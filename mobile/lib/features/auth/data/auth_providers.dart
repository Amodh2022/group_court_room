import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/env.dart';
import '../../../core/models.dart';

const _sessionKey = 'gcc.session';

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(baseUrl: Env.apiBaseUrl),
);

/// Current sign-in. `null` means signed out.
class AuthController extends StateNotifier<AsyncValue<Session?>> {
  AuthController(this._api) : super(const AsyncValue.loading()) {
    _restore();
  }

  final ApiClient _api;

  /// Session restore must never be able to hang. If storage is slow or a
  /// platform channel is wedged, we start signed out rather than leaving the
  /// app stuck in an indeterminate state behind the gate.
  static const restoreTimeout = Duration(seconds: 5);

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        restoreTimeout,
      );
      final raw = prefs.getString(_sessionKey);
      if (raw == null) {
        state = const AsyncValue.data(null);
        return;
      }
      final session = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _api.token = session.accessToken;
      state = AsyncValue.data(session);
    } catch (_) {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> signIn(String email, String password) =>
      _authenticate(() => _api.login(email.trim(), password));

  Future<void> register(String email, String password, String displayName) =>
      _authenticate(
        () => _api.register(email.trim(), password, displayName.trim()),
      );

  Future<void> _authenticate(Future<Session> Function() call) async {
    state = const AsyncValue.loading();
    try {
      final session = await call();
      _api.token = session.accessToken;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
      state = AsyncValue.data(session);
    } on ApiException catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    _api.token = null;
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<Session?>>(
      (ref) => AuthController(ref.watch(apiClientProvider)),
    );

/// True once the stored session has been checked, whatever the outcome.
final authResolvedProvider = Provider<bool>(
  (ref) => !ref.watch(authControllerProvider).isLoading,
);

final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).valueOrNull != null,
);
