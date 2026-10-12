/// Routing and deep links, driven through the real GoRouter the app ships.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:group_chat_court/core/courtroom.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/core/router.dart';
import 'package:group_chat_court/core/theme.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient();
    SharedPreferences.setMockInitialValues({});
  });

  Future<GoRouter> pumpApp(WidgetTester tester, {bool signedIn = false}) async {
    useMobileSurface(tester);
    if (signedIn) {
      SharedPreferences.setMockInitialValues({
        'gcc.session':
            '{"access_token":"t","user_id":"u","display_name":"Alex"}',
        'gcc.subject': 'dev|test',
      });
    }
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        courtroomConnectorProvider.overrideWithValue(FakeRooms().connect),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: courtLightTheme(),
          routerConfig: router,
          // Staged animations off, as harness() does: navigation tests assert
          // where you landed, not how the courtroom got you there.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  group('auth routing', () {
    testWidgets('a signed-out user lands on sign-in', (tester) async {
      final router = await pumpApp(tester);
      expect(router.state.matchedLocation, '/sign-in');
      expect(find.text('Settle it in court.'), findsOneWidget);
    });

    testWidgets('a restored session lands on the dashboard', (tester) async {
      final router = await pumpApp(tester, signedIn: true);
      expect(router.state.matchedLocation, '/');
      expect(find.text('Sue Me'), findsWidgets);
    });

    testWidgets('signing in moves the user to the dashboard', (tester) async {
      final router = await pumpApp(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'alex@example.com');
      await tester.enterText(fields.at(1), 'correct-horse');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/');
    });

    testWidgets('a signed-out user cannot deep-link past the gate', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      router.go('/cases/case-1');
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/sign-in');
    });
  });

  group('deep links for a signed-in user', () {
    testWidgets('opens a case file directly', (tester) async {
      api.detail = buildDetail();
      final router = await pumpApp(tester, signedIn: true);

      router.go('/cases/case-1');
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/cases/case-1');
      expect(find.text('Case file'), findsOneWidget);
    });

    testWidgets('opens the verdict screen directly', (tester) async {
      api.detail = buildDetail(status: CaseStatus.completed);
      api.verdict = const VerdictState(
        status: CaseStatus.completed,
        verdict: testVerdict,
      );
      final router = await pumpApp(tester, signedIn: true);

      router.go('/cases/case-1/verdict');
      await tester.pumpAndSettle();

      expect(find.text('The verdict'), findsOneWidget);
      expect(find.byKey(const Key('verdict-stamp')), findsOneWidget);
    });

    testWidgets('opens settings and privacy', (tester) async {
      final router = await pumpApp(tester, signedIn: true);
      router.go('/settings');
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Nothing is public by default'), findsOneWidget);
    });

    testWidgets('an unknown route shows a recoverable error page', (
      tester,
    ) async {
      final router = await pumpApp(tester, signedIn: true);
      router.go('/not-a-courtroom');
      await tester.pumpAndSettle();

      expect(find.text('Lost in the courthouse'), findsOneWidget);

      await tester.tap(find.text('Back to the docket'));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/');
    });

    testWidgets(
      'an invite screen opened without its one-time token explains why',
      (tester) async {
        final router = await pumpApp(tester, signedIn: true);
        // No `extra`: exactly what happens on a cold deep link or app restart.
        router.go('/cases/case-1/invite');
        await tester.pumpAndSettle();

        expect(find.text('This summons link is gone'), findsOneWidget);
        expect(find.text('Open the case'), findsOneWidget);
      },
    );

    testWidgets('signing out returns to the sign-in gate', (tester) async {
      final router = await pumpApp(tester, signedIn: true);
      router.go('/settings');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/sign-in');
    });
  });
}
