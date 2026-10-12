import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router.dart';
import '../../auth/data/auth_providers.dart';
import '../../courts/data/court_providers.dart';

/// Registers this phone for push once somebody is signed in.
///
/// Lives only in `main()`, so tests (which have no Firebase) never touch it.
/// Every failure is swallowed: push is a nicety, and the app must still work
/// when permission is denied, Play Services is missing, or the server has no
/// `/devices` endpoint yet.
class PushBootstrap extends ConsumerStatefulWidget {
  const PushBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushBootstrap> createState() => _PushBootstrapState();
}

class _PushBootstrapState extends ConsumerState<PushBootstrap> {
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(isSignedInProvider)) _start();
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await _register(token);
      _refresh = messaging.onTokenRefresh.listen(_register);
      // A push while the app is open just refreshes the bell.
      _foreground = FirebaseMessaging.onMessage.listen(
        (_) => ref.invalidate(notificationsProvider),
      );
      _opened = FirebaseMessaging.onMessageOpenedApp.listen((_) {
        ref.invalidate(notificationsProvider);
        ref.read(routerProvider).go('/notifications');
      });
    } catch (e) {
      debugPrint('push disabled: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await ref.read(apiClientProvider).registerDevice(token);
    } catch (e) {
      debugPrint('device registration failed: $e');
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _foreground?.cancel();
    _opened?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isSignedInProvider, (_, signedIn) {
      if (signedIn) _start();
    });
    return widget.child;
  }
}

/// Starts Firebase. Returns false (and the app carries on) if it is not set up.
Future<bool> initFirebase() async {
  try {
    await Firebase.initializeApp();
    return true;
  } catch (e) {
    debugPrint('firebase unavailable: $e');
    return false;
  }
}
