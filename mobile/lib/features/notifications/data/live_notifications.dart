import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/env.dart';
import '../../auth/data/auth_providers.dart';
import '../../courts/data/court_providers.dart';

Uri notificationsSocketUri([String base = Env.apiBaseUrl]) {
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return Uri.parse(
    '${root.replaceFirst(RegExp('^http'), 'ws')}/api/v1/ws/notifications',
  );
}

/// Keeps a socket open while signed in and refetches the bell the moment the
/// server says something changed. Reconnects with backoff; failures are
/// silent because pull-to-refresh still works.
class LiveNotifications extends ConsumerStatefulWidget {
  const LiveNotifications({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LiveNotifications> createState() => _LiveNotificationsState();
}

class _LiveNotificationsState extends ConsumerState<LiveNotifications> {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  String? _token;

  void _connect(String token) {
    _disconnect();
    _token = token;
    try {
      final channel = WebSocketChannel.connect(notificationsSocketUri());
      _channel = channel;
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _sub = channel.stream.listen(
        (data) {
          try {
            final frame = jsonDecode(data as String) as Map<String, dynamic>;
            if (frame['type'] == 'notifications') {
              _attempt = 0;
              ref.invalidate(notificationsProvider);
            } else if (frame['type'] == 'error') {
              _token = null; // bad token: wait for the next sign-in
            }
          } catch (_) {}
        },
        onDone: _reconnect,
        onError: (_) => _reconnect(),
      );
    } catch (e) {
      debugPrint('live notifications unavailable: $e');
      _reconnect();
    }
  }

  void _reconnect() {
    final token = _token;
    if (!mounted || token == null) return;
    final seconds = (1 << _attempt).clamp(1, 15);
    _attempt = (_attempt + 1).clamp(0, 4);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), () {
      if (mounted && _token == token) _connect(token);
    });
  }

  void _disconnect() {
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  @override
  void dispose() {
    _token = null;
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(authControllerProvider).valueOrNull?.accessToken;
    if (token == null) {
      if (_token != null) {
        _token = null;
        _disconnect();
      }
    } else if (token != _token) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect(token);
      });
    }
    return widget.child;
  }
}
