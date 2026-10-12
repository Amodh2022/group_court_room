import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../features/auth/data/auth_providers.dart';
import 'env.dart';
import 'models.dart';

enum ChatKind {
  plaintiff,
  defendant,
  juror,
  judge,
  system;

  static ChatKind parse(String value) => ChatKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => ChatKind.system,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.n,
    required this.kind,
    required this.author,
    required this.ref,
    required this.body,
    required this.meta,
    required this.at,
  });

  final String id;

  /// Position in the room. The server's order is the only order.
  final int n;
  final ChatKind kind;
  final String author;
  final String ref;
  final String body;
  final Map<String, dynamic> meta;
  final DateTime? at;

  bool get isObjection => meta['objection'] == true;
  String? get statement => meta['statement'] as String?;
  String? get ruling => meta['ruling'] as String?;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    n: json['n'] as int,
    kind: ChatKind.parse(json['kind'] as String? ?? ''),
    author: json['author'] as String? ?? '',
    ref: json['ref'] as String? ?? '',
    body: json['body'] as String? ?? '',
    meta: (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
    at: json['at'] == null
        ? null
        : DateTime.tryParse(json['at'] as String)?.toLocal(),
  );
}

/// One seat in the jury box. `voted` says a ballot exists, never which way.
class RosterSeat {
  const RosterSeat({
    required this.ref,
    required this.name,
    required this.role,
    required this.voted,
  });

  final String ref;
  final String name;
  final String role;
  final bool voted;

  factory RosterSeat.fromJson(Map<String, dynamic> json) => RosterSeat(
    ref: json['ref'] as String? ?? '',
    name: json['name'] as String? ?? '',
    role: json['role'] as String? ?? 'juror',
    voted: json['voted'] as bool? ?? false,
  );
}

enum ConnState { connecting, live, reconnecting, refused }

class CourtroomState {
  const CourtroomState({
    this.conn = ConnState.connecting,
    this.seatRef,
    this.seatRole,
    this.messages = const [],
    this.online = 0,
    this.roster = const [],
    this.caseStatus,
    this.notice,
  });

  final ConnState conn;
  final String? seatRef;
  final String? seatRole;
  final List<ChatMessage> messages;
  final int online;
  final List<RosterSeat> roster;
  final CaseStatus? caseStatus;

  /// The last refusal, shown briefly under the composer.
  final String? notice;

  bool get isLive => conn == ConnState.live;

  CourtroomState copyWith({
    ConnState? conn,
    String? seatRef,
    String? seatRole,
    List<ChatMessage>? messages,
    int? online,
    List<RosterSeat>? roster,
    CaseStatus? caseStatus,
    String? notice,
    bool clearNotice = false,
  }) => CourtroomState(
    conn: conn ?? this.conn,
    seatRef: seatRef ?? this.seatRef,
    seatRole: seatRole ?? this.seatRole,
    messages: messages ?? this.messages,
    online: online ?? this.online,
    roster: roster ?? this.roster,
    caseStatus: caseStatus ?? this.caseStatus,
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}

/// One message per id, in the server's order. A reconnect replays history, so
/// merging has to be idempotent or every dropped connection would double the
/// transcript.
List<ChatMessage> mergeMessages(
  List<ChatMessage> current,
  Iterable<ChatMessage> incoming,
) {
  final byId = {for (final m in current) m.id: m};
  for (final m in incoming) {
    byId[m.id] = m;
  }
  return byId.values.toList()..sort((a, b) => a.n.compareTo(b.n));
}

/// Opens a socket. Replaced in tests with an in-memory channel.
typedef CourtroomConnector = StreamChannel<dynamic> Function(Uri uri);

final courtroomConnectorProvider = Provider<CourtroomConnector>(
  (ref) =>
      (uri) => WebSocketChannel.connect(uri),
);

Uri courtroomUri([String base = Env.apiBaseUrl]) {
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final ws = root.replaceFirst(RegExp('^http'), 'ws');
  return Uri.parse('$ws/api/v1/ws/room');
}

/// Keeps the plaintiff connected to their case's courtroom.
///
/// Authenticates in its first frame so no token ever sits in a URL. A refusal
/// (dead link) is final; a dropped connection is retried with backoff and
/// resumes from the server's history rather than from memory.
class CourtroomController extends StateNotifier<CourtroomState> {
  CourtroomController({
    required CourtroomConnector connector,
    required Uri uri,
    required Map<String, dynamic>? auth,
    this.backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
    this.noticeFor = const Duration(seconds: 5),
  }) : _connector = connector,
       _uri = uri,
       _auth = auth,
       super(const CourtroomState()) {
    if (auth != null) _connect();
  }

  final CourtroomConnector _connector;
  final Uri _uri;
  final Map<String, dynamic>? _auth;
  final List<Duration> backoff;
  final Duration noticeFor;

  StreamChannel<dynamic>? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _noticeTimer;
  int _attempt = 0;
  bool _refused = false;
  bool _closed = false;

  void _connect() {
    if (_closed) return;
    state = state.copyWith(
      conn: _attempt == 0 ? ConnState.connecting : ConnState.reconnecting,
    );
    final channel = _connector(_uri);
    _channel = channel;
    channel.sink.add(jsonEncode({'type': 'auth', ..._auth!}));
    _sub = channel.stream.listen(
      _onFrame,
      onDone: () => _onLost(channel),
      onError: (_) => _onLost(channel),
      cancelOnError: true,
    );
  }

  void _onLost(StreamChannel<dynamic> channel) {
    // A stale channel closing after we moved on must not schedule a second
    // reconnect.
    if (_closed || _refused || !identical(channel, _channel)) return;
    final wait = backoff[_attempt.clamp(0, backoff.length - 1)];
    _attempt++;
    state = state.copyWith(conn: ConnState.reconnecting);
    _retry = Timer(wait, _connect);
  }

  void _onFrame(dynamic raw) {
    if (_closed) return;
    final Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map<String, dynamic>) return;
      frame = decoded;
    } catch (_) {
      return;
    }

    switch (frame['type']) {
      case 'welcome':
        _attempt = 0;
        final seat = frame['seat'] as Map<String, dynamic>;
        state = state.copyWith(
          conn: ConnState.live,
          seatRef: seat['ref'] as String?,
          seatRole: seat['role'] as String?,
          messages: mergeMessages(state.messages, _parse(frame['messages'])),
        );
      case 'message':
        state = state.copyWith(
          messages: mergeMessages(state.messages, [
            ChatMessage.fromJson(frame['message'] as Map<String, dynamic>),
          ]),
        );
      case 'hidden':
        state = state.copyWith(
          messages: state.messages.where((m) => m.id != frame['id']).toList(),
        );
      case 'presence':
        state = state.copyWith(online: (frame['online'] as num?)?.toInt() ?? 0);
      case 'roster':
        state = state.copyWith(
          roster: (frame['seats'] as List<dynamic>)
              .map((e) => RosterSeat.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'case':
        state = state.copyWith(
          caseStatus: CaseStatus.parse(frame['status'] as String? ?? ''),
        );
      case 'error':
        if (frame['code'] == 'invalid_link') {
          _refused = true;
          state = state.copyWith(conn: ConnState.refused);
        } else {
          _flash(frame['message'] as String? ?? 'The court did not like that.');
        }
    }
  }

  Iterable<ChatMessage> _parse(dynamic list) => (list as List<dynamic>).map(
    (e) => ChatMessage.fromJson(e as Map<String, dynamic>),
  );

  void _flash(String text) {
    state = state.copyWith(notice: text);
    _noticeTimer?.cancel();
    _noticeTimer = Timer(noticeFor, () {
      if (!_closed) state = state.copyWith(clearNotice: true);
    });
  }

  bool _send(Map<String, dynamic> frame) {
    final channel = _channel;
    if (channel == null || !state.isLive) return false;
    channel.sink.add(jsonEncode(frame));
    return true;
  }

  bool say(String body) => _send({'type': 'say', 'body': body});
  bool objectNow() => _send({'type': 'object'});
  bool hide(String id) => _send({'type': 'hide', 'id': id});

  @override
  void dispose() {
    _closed = true;
    _retry?.cancel();
    _noticeTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}

/// The plaintiff's seat in one case's courtroom.
final courtroomProvider = StateNotifierProvider.autoDispose
    .family<CourtroomController, CourtroomState, String>((ref, caseId) {
      final token = ref.watch(authControllerProvider).valueOrNull?.accessToken;
      return CourtroomController(
        connector: ref.watch(courtroomConnectorProvider),
        uri: courtroomUri(),
        auth: token == null
            ? null
            : {'kind': 'creator', 'case_id': caseId, 'token': token},
      );
    });
