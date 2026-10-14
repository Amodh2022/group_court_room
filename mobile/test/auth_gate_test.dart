/// The sign-in gate, under realistic and hostile timing.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/splash.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  Future<void> pumpApp(
    WidgetTester tester, {
    bool primeStorage = true,
    Map<String, Object> storage = const {},
  }) {
    useMobileSurface(tester);
    if (!primeStorage) {
      _unprimeStorage();
    } else if (storage.isNotEmpty) {
      SharedPreferences.setMockInitialValues(storage);
    }
    return tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const GroupChatCourtApp(),
      ),
    );
  }

  testWidgets('holds on a splash until the stored session has been read', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // The very first frame, before the restore future has had a chance to run.
    await pumpApp(tester);
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets(
    'never calls the API from a protected screen before auth resolves',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpApp(tester);
      await tester.pump();

      // The dashboard must not have mounted and fired an unauthenticated
      // request — that is what produced a spurious "invalid credentials" error.
      expect(api.listCalls, 0);

      await tester.pumpAndSettle();
      expect(
        api.listCalls,
        0,
        reason: 'a signed-out user never loads a docket',
      );
    },
  );

  testWidgets('a restored session goes straight to the dashboard', (
    tester,
  ) async {
    api.cases = [buildSummary()];

    await pumpApp(
      tester,
      storage: {
        'gcc.session':
            '{"access_token":"t","user_id":"u","display_name":"Alex"}',
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('The Last Pizza Slice'), findsOneWidget);
  });

  testWidgets('falls back to signed out when storage never answers', (
    tester,
  ) async {
    // A wedged platform channel: the store never answers. The in-memory store
    // must be off (primeStorage: false), or it would bypass the channel and
    // nothing would hang.
    const channel = MethodChannel(
      'plugins.flutter.io/shared_preferences_android',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) => Completer<Map<String, Object>>().future,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await pumpApp(tester, primeStorage: false);
    expect(find.byType(SplashScreen), findsOneWidget);

    // Past the restore timeout, the app resolves rather than hanging.
    await tester.pump(
      AuthController.restoreTimeout + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SplashScreen), findsNothing);
  });
}

/// Drops the in-memory store so reads go to the platform channel.
void _unprimeStorage() {
  const channel = MethodChannel(
    'plugins.flutter.io/shared_preferences_android',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        channel,
        (_) => Completer<Map<String, Object>>().future,
      );
}
