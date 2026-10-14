import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/core/courtroom.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/core/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';

/// An in-memory courtroom server.
///
/// Hands the app a channel instead of a socket. Tests push frames at it exactly
/// as the server would, and read back what the app sent.
class FakeRooms {
  final controllers = <StreamChannelController<dynamic>>[];
  final uris = <Uri>[];

  /// Every frame the app has sent, across all connections, in order.
  final sent = <Map<String, dynamic>>[];

  StreamChannel<dynamic> connect(Uri uri) {
    final controller = StreamChannelController<dynamic>(sync: true);
    controllers.add(controller);
    uris.add(uri);
    controller.local.stream.listen(
      (raw) => sent.add(jsonDecode(raw as String) as Map<String, dynamic>),
    );
    return controller.foreign;
  }

  int get connections => controllers.length;

  /// The server sends a frame on the newest connection.
  void push(Map<String, dynamic> frame) =>
      controllers.last.local.sink.add(jsonEncode(frame));

  /// The connection drops without the app asking.
  Future<void> drop() => controllers.last.local.sink.close();

  /// Open the room as `role`, with `messages` already in the log.
  void welcome({
    String role = 'plaintiff',
    String ref = 'ref-me',
    List<Map<String, dynamic>> messages = const [],
  }) => push({
    'type': 'welcome',
    'seat': {'role': role, 'name': 'Alex', 'ref': ref},
    'messages': messages,
  });
}

Map<String, dynamic> chatJson(
  int n, {
  String kind = 'juror',
  String author = 'Sam',
  String ref = 'ref-sam',
  String? body,
  Map<String, dynamic> meta = const {},
}) => {
  'id': 'm$n',
  'n': n,
  'kind': kind,
  'author': author,
  'ref': ref,
  'body': body ?? 'message $n',
  'meta': meta,
  'at': '2026-10-12T12:00:00Z',
};

/// In-memory stand-in for the API. Every method can be told to fail, so error
/// paths are exercised through the same client the screens use in production.
class FakeApiClient implements ApiClient {
  FakeApiClient({this.cases = const [], this.detail, this.verdict});

  List<CaseSummary> cases;
  CaseDetail? detail;
  VerdictState? verdict;

  ApiException? listError;
  ApiException? detailError;
  ApiException? createError;
  ApiException? verdictError;
  ApiException? rapSheetError;

  List<RapSheetEntry> records = const [];

  /// Complete this to release a pending `listCases`, so a test can observe
  /// the loading state instead of racing past it.
  Completer<void>? listGate;

  /// The same trick for `getCase`, so a test can hold the case file in flight
  /// while the verdict has already arrived.
  Completer<void>? detailGate;

  int listCalls = 0;
  int detailCalls = 0;
  int verdictRequests = 0;
  int deleteCalls = 0;
  int shareCalls = 0;
  int revokeCalls = 0;
  Map<String, dynamic>? lastCreate;

  @override
  set token(String? value) {}

  @override
  Future<Session> devLogin(String subject, String displayName) async => Session(
    accessToken: 'test-token',
    userId: 'user-1',
    displayName: displayName,
  );

  @override
  Future<Session> login(String email, String password) async => Session(
    accessToken: 'test-token',
    userId: 'user-1',
    displayName: 'Alex',
    email: email,
  );

  @override
  Future<Session> register(
    String email,
    String password,
    String displayName,
  ) async => Session(
    accessToken: 'test-token',
    userId: 'user-1',
    displayName: displayName,
    email: email,
  );

  List<Court> courts = const [];
  List<SharedCase> shared = const [];

  /// The game state the server would return. Defaults to a player who has
  /// done nothing, which is what a fresh account actually looks like.
  GameState game = buildGameState();
  CaseRewards rewards = const CaseRewards(totalXp: 0, totalCoins: 0, items: []);
  ApiException? gameError;

  /// The summons the accused is answering, and what the server said when
  /// they did.
  InvitePreview? invite;
  ApiException? inviteError;
  ApiException? defenseError;
  Map<String, String>? lastDefense;

  @override
  Future<InvitePreview> invitePreview(String token) async {
    if (inviteError != null) throw inviteError!;
    return invite ?? buildInvitePreview();
  }

  @override
  Future<DefenseAccepted> submitDefense(
    String token, {
    required String nickname,
    required String body,
  }) async {
    lastDefense = {'token': token, 'nickname': nickname, 'body': body};
    if (defenseError != null) throw defenseError!;
    return DefenseAccepted(
      caseTitle: (invite ?? buildInvitePreview()).caseTitle,
      nickname: nickname,
    );
  }

  @override
  Future<GameState> gameState() async {
    if (gameError != null) throw gameError!;
    return game;
  }

  @override
  Future<CaseRewards> caseRewards(String caseId) async => rewards;
  List<UserRef> people = const [];
  NotificationFeed feed = const NotificationFeed(unread: 0, items: []);
  int readAllCalls = 0;

  /// (caseId, userId, role) for every seat taken through the app.
  final List<(String, String, String)> seated = [];

  @override
  Future<List<UserRef>> searchUsers(String query) async =>
      people.where((u) => u.handle.startsWith(query.toLowerCase())).toList();

  @override
  Future<List<Court>> listCourts() async => courts;

  @override
  Future<Court> createCourt(String name) async {
    final court = Court(
      id: 'court-${courts.length + 1}',
      name: name,
      inviteCode: 'CODE1234',
      ownerId: 'user-1',
      members: const [
        UserRef(userId: 'user-1', handle: 'alex', displayName: 'Alex'),
      ],
    );
    courts = [...courts, court];
    return court;
  }

  @override
  Future<Court> addCourtMember(String courtId, String userId) async {
    final user = people.firstWhere((u) => u.userId == userId);
    courts = [
      for (final c in courts)
        if (c.id == courtId)
          Court(
            id: c.id,
            name: c.name,
            inviteCode: c.inviteCode,
            ownerId: c.ownerId,
            members: [...c.members, user],
          )
        else
          c,
    ];
    return courts.firstWhere((c) => c.id == courtId);
  }

  @override
  Future<Court> joinCourt(String inviteCode) async => courts.first;

  @override
  Future<void> removeCourtMember(String courtId, String userId) async {}

  @override
  Future<void> addCaseMember(String caseId, String userId, String role) async {
    seated.add((caseId, userId, role));
  }

  /// The jury box. `rooms` is keyed by jury token; a token with no entry
  /// behaves like a summons the court has not opened yet.
  Map<String, JuryRoom> rooms = {};

  /// (token, vote, voterKey) for every ballot cast through the app.
  final List<(String, String, String)> ballots = [];
  ApiException? voteError;

  @override
  Future<JuryRoom> juryRoom(String token, {required String voterKey}) async =>
      rooms[token] ??
      const JuryRoom(
        caseTitle: 'A case',
        accusation: 'Something petty happened.',
        defense: null,
        plaintiffName: 'Alex',
        defendantName: 'Sam',
        juryOpen: true,
        verdictReady: false,
        yourVote: null,
        tally: null,
      );

  @override
  Future<JuryTally> castVote(
    String token, {
    required String vote,
    required String voterKey,
    String? jurorName,
  }) async {
    if (voteError != null) throw voteError!;
    ballots.add((token, vote, voterKey));
    final existing = rooms[token];
    rooms = {
      ...rooms,
      token: JuryRoom(
        caseTitle: existing?.caseTitle ?? 'A case',
        accusation: existing?.accusation ?? 'Something petty happened.',
        defense: existing?.defense,
        plaintiffName: existing?.plaintiffName ?? 'Alex',
        defendantName: existing?.defendantName ?? 'Sam',
        juryOpen: true,
        verdictReady: false,
        yourVote: vote,
        tally: null,
      ),
    };
    return JuryTally(
      guilty: vote == 'guilty' ? 1 : 0,
      notGuilty: vote == 'guilty' ? 0 : 1,
      total: 1,
      majority: vote,
      summary: 'One juror has voted.',
    );
  }

  @override
  Future<List<SharedCase>> sharedCases() async => shared;

  String? registeredDevice;

  @override
  Future<void> registerDevice(
    String token, {
    String platform = 'android',
  }) async => registeredDevice = token;

  @override
  Future<NotificationFeed> notifications() async => feed;

  @override
  Future<void> markNotificationsRead() async => readAllCalls++;

  @override
  Future<List<CaseSummary>> listCases() async {
    listCalls++;
    if (listGate != null) await listGate!.future;
    if (listError != null) throw listError!;
    return cases;
  }

  @override
  Future<CaseDetail> createCase({
    required String title,
    required String category,
    required String accusation,
    String? defendantNickname,
    String? courtId,
    String? accusedUserId,
    int pettyLevel = 1,
  }) async {
    lastCreate = {
      'court_id': courtId,
      'accused_user_id': accusedUserId,
      'title': title,
      'category': category,
      'accusation': accusation,
      'defendant_nickname': defendantNickname,
      'petty_level': pettyLevel,
    };
    if (createError != null) throw createError!;
    return detail ??= buildDetail(title: title, category: category);
  }

  @override
  Future<CaseDetail> getCase(String id) async {
    detailCalls++;
    if (detailGate != null) await detailGate!.future;
    if (detailError != null) throw detailError!;
    return detail ?? buildDetail();
  }

  @override
  Future<void> deleteCase(String id) async => deleteCalls++;

  @override
  Future<VerdictState> requestVerdict(String id) async {
    verdictRequests++;
    if (verdictError != null) throw verdictError!;
    return verdict ??= const VerdictState(status: CaseStatus.generating);
  }

  @override
  Future<VerdictState> getVerdict(String id) async {
    if (verdictError != null) throw verdictError!;
    return verdict ?? const VerdictState(status: CaseStatus.ready);
  }

  @override
  Future<ShareLink> enableShare(String id) async {
    shareCalls++;
    return const ShareLink(
      token: 'shr_test',
      url: 'https://court.test/verdict/shr_test',
    );
  }

  @override
  Future<void> revokeShare(String id) async => revokeCalls++;

  @override
  Future<List<RapSheetEntry>> rapSheet() async {
    if (rapSheetError != null) throw rapSheetError!;
    return records;
  }
}

// --- fixtures --------------------------------------------------------------

CaseSummary buildSummary({
  String id = 'case-1',
  String title = 'The Last Pizza Slice',
  CaseStatus status = CaseStatus.awaitingDefense,
  bool defenseSubmitted = false,
  bool shareEnabled = false,
  int juryCount = 0,
}) => CaseSummary(
  id: id,
  title: title,
  category: 'food',
  status: status,
  createdAt: DateTime(2026, 10, 9),
  expiresAt: DateTime(2026, 10, 12),
  defendantNickname: 'SliceBandit',
  defenseSubmitted: defenseSubmitted,
  verdictReady: status == CaseStatus.completed,
  shareEnabled: shareEnabled,
  juryCount: juryCount,
);

CaseDetail buildDetail({
  String id = 'case-1',
  String title = 'The Last Pizza Slice',
  String category = 'food',
  CaseStatus status = CaseStatus.awaitingDefense,
  String? inviteToken = 'inv_test_token',
  String? juryToken = 'jry_test_token',
  JuryTally? juryTally,
  String? failureReason,
}) => CaseDetail(
  id: id,
  title: title,
  category: category,
  status: status,
  createdAt: DateTime(2026, 10, 9),
  expiresAt: DateTime(2026, 10, 12),
  defendantNickname: 'SliceBandit',
  defenseSubmitted: status != CaseStatus.awaitingDefense,
  verdictReady: status == CaseStatus.completed,
  shareEnabled: false,
  accusation: 'My friend ate the last pizza slice after saying they were full.',
  failureReason: failureReason,
  inviteToken: inviteToken,
  inviteUrl: inviteToken == null
      ? null
      : 'https://court.test/invite/$inviteToken',
  juryToken: juryToken,
  juryUrl: juryToken == null ? null : 'https://court.test/jury/$juryToken',
  juryTally: juryTally,
  juryCount: juryTally?.total ?? 0,
);

JuryTally buildTally({int guilty = 3, int notGuilty = 1}) {
  final majority = guilty == notGuilty
      ? null
      : (guilty > notGuilty ? 'guilty' : 'not_guilty');
  final high = guilty > notGuilty ? guilty : notGuilty;
  final low = guilty > notGuilty ? notGuilty : guilty;
  return JuryTally(
    guilty: guilty,
    notGuilty: notGuilty,
    total: guilty + notGuilty,
    majority: majority,
    summary: majority == null
        ? 'The jury deadlocked $guilty–$notGuilty.'
        : 'The jury voted $high–$low for '
              '${majority == 'guilty' ? 'guilty' : 'not guilty'}.',
  );
}

RapSheetEntry buildRecord({
  String id = 'offender-1',
  String displayName = 'SliceBandit',
  int rank = 1,
  String title = 'Repeat Offender',
  int convictions = 3,
  int acquittals = 1,
  int currentStreak = 2,
  int? longestStreak,
  bool isYou = false,
}) => RapSheetEntry(
  id: id,
  displayName: displayName,
  rank: rank,
  title: title,
  casesTotal: convictions + acquittals,
  convictions: convictions,
  acquittals: acquittals,
  mistrials: 0,
  currentStreak: currentStreak,
  longestStreak: longestStreak ?? currentStreak,
  convictionRate: 0.75,
  isYou: isYou,
);

const testVerdict = Verdict(
  caseTitle: 'The Last Pizza Slice',
  charge: 'Alleged food misconduct',
  prosecutionSummary:
      'Alex brings a food complaint and wants it on the record.',
  defenseSummary: 'Sam disputes the framing and calls the slice abandoned.',
  verdict: VerdictKind.bothGuilty,
  reasoning: 'Neither party produced receipts, which is on brand.',
  sentence: 'Establish a formal last-slice policy before your next order.',
  judgeRoast: 'You had a whole defense ready, which is rarely a good sign.',
  closingLine: 'This court is adjourned. Go outside.',
  shareCaption: 'The court has ruled: both guilty.',
);

// --- harness ---------------------------------------------------------------

/// Pumps a screen behind a real GoRouter, so navigation assertions are
/// meaningful rather than mocked away.
/// A test app around one screen.
///
/// [animated] defaults to false, which switches off the courtroom's staged
/// animations the same way an accessibility setting would. Tests then assert
/// on content without racing a timed sequence; the sequence itself is covered
/// directly in verdict_reveal_test.dart.
Widget harness({
  required Widget child,
  required List<Override> overrides,
  List<GoRoute> extraRoutes = const [],
  bool animated = false,
  FakeRooms? rooms,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      ...extraRoutes,
    ],
  );
  return ProviderScope(
    overrides: [
      // No test ever opens a real socket.
      courtroomConnectorProvider.overrideWithValue(
        (rooms ?? FakeRooms()).connect,
      ),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: courtLightTheme(),
      darkTheme: courtDarkTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: !animated),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

/// The same harness around a router a test built itself, for asserting on the
/// routes a screen links to rather than only on the screen.
Widget harnessWithRouter({
  required GoRouter router,
  required List<Override> overrides,
  bool animated = false,
  FakeRooms? rooms,
}) => ProviderScope(
  overrides: [
    courtroomConnectorProvider.overrideWithValue(
      (rooms ?? FakeRooms()).connect,
    ),
    ...overrides,
  ],
  child: MaterialApp.router(
    theme: courtLightTheme(),
    darkTheme: courtDarkTheme(),
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: !animated),
      child: child ?? const SizedBox.shrink(),
    ),
  ),
);

/// Standard setup for a widget test: a realistic phone viewport and a working
/// key-value store.
///
/// The viewport matters because the default 800x600 surface puts a form's
/// submit button below the fold, and a widget inside an un-scrolled ListView is
/// never built — so a tap on it fails for reasons unrelated to the code under
/// test.
///
/// The store matters because any screen that touches auth constructs
/// AuthController, which reads SharedPreferences. Without an in-memory store
/// that read goes to a platform channel that never answers in a test.
void useMobileSurface(
  WidgetTester tester, {
  Size size = const Size(430, 1800),
}) {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

/// Stubs the share_plus platform channel.
///
/// Without this, tapping a share button throws MissingPluginException in a
/// widget test — the sheet is native and there is no platform side here.
/// Returns the list of share payloads the screen asked for.
List<Map<Object?, Object?>> captureShares() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final shares = <Map<Object?, Object?>>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        shares.add(Map<Object?, Object?>.from(call.arguments as Map));
        return 'dev.fluttercommunity.plus/share/success';
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  return shares;
}

/// Scrolls a target into view before interacting with it. In a tall ListView
/// the widget may not be built at all, so a bare tap finds nothing.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// A player card for tests. Everything is zero unless a test says otherwise,
/// because that is what the server returns for an account that has done
/// nothing.
GameState buildGameState({
  String name = 'Alex',
  int level = 1,
  int xp = 0,
  int xpIntoLevel = 0,
  int coins = 100,
  int streakDays = 0,
  List<Quest> quests = const [],
  List<GameBadge> badges = const [],
}) => GameState(
  player: Player(
    displayName: name,
    level: level,
    xp: xp,
    xpIntoLevel: xpIntoLevel,
    xpPerLevel: 1000,
    xpToNextLevel: 1000 - xpIntoLevel,
    coins: coins,
    streakDays: streakDays,
    longestStreakDays: streakDays,
    badgesEarned: badges.where((b) => b.earned).length,
    badgesTotal: badges.isEmpty ? 12 : badges.length,
  ),
  quests: quests,
  badges: badges,
);

Quest buildQuest({
  String code = 'file_case',
  String text = 'File a new case',
  int progress = 0,
  int target = 1,
  int xp = 50,
  bool done = false,
}) => Quest(
  code: code,
  text: text,
  progress: progress,
  target: target,
  xp: xp,
  done: done,
);

GameBadge buildBadge({
  String code = 'first_blood',
  String name = 'First blood',
  String glyph = '1',
  String hint = 'File your first case',
  bool earned = false,
}) =>
    GameBadge(code: code, name: name, glyph: glyph, hint: hint, earned: earned);

/// A summons, as the server would preview it.
InvitePreview buildInvitePreview({
  String caseTitle = 'The Last Pizza Slice',
  String accusation = 'They ate it right after saying they were full.',
  String plaintiffName = 'Alex',
  String? defendantNickname = 'SliceBandit',
  bool alreadySubmitted = false,
  bool verdictReady = false,
  int juryCount = 0,
  DateTime? expiresAt,
}) => InvitePreview(
  caseTitle: caseTitle,
  category: 'food',
  accusation: accusation,
  plaintiffName: plaintiffName,
  defendantNickname: defendantNickname,
  expiresAt: expiresAt,
  alreadySubmitted: alreadySubmitted,
  verdictReady: verdictReady,
  juryCount: juryCount,
);
