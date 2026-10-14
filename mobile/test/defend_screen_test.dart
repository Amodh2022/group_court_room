import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/invitations/presentation/defend_screen.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) {
    useMobileSurface(tester);
    return tester.pumpWidget(
      harness(
        child: const DefendScreen(token: 'inv_abc12345'),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
  }

  group('the summons', () {
    testWidgets('shows the charge and who brought it', (tester) async {
      api.invite = buildInvitePreview(
        caseTitle: 'The Last Pizza Slice',
        accusation: 'They ate it right after saying they were full.',
        plaintiffName: 'Alex',
      );
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('The Last Pizza Slice'), findsOneWidget);
      expect(
        find.text('They ate it right after saying they were full.'),
        findsOneWidget,
      );
      expect(find.textContaining('Alex'), findsWidgets);
    });

    testWidgets('a link the server rejects says so without saying why', (
      tester,
    ) async {
      api.inviteError = ApiException(404, 'invalid_link', 'Invalid link.');
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('This summons is no longer valid'), findsOneWidget);
      // The reason is deliberately not leaked: expired, revoked and never
      // existed are one answer.
      expect(find.textContaining('expired, been revoked'), findsOneWidget);
    });

    testWidgets('a connection failure offers a retry instead', (tester) async {
      api.inviteError = ApiException(0, 'network_error', 'offline');
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('one already answered cannot be answered again', (
      tester,
    ) async {
      api.invite = buildInvitePreview(alreadySubmitted: true);
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('This defence is already in'), findsOneWidget);
      expect(find.text('ENTER MY DEFENCE'), findsNothing);
    });
  });

  group('writing a defence', () {
    testWidgets('sends the trimmed name and body', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Sam'),
        '  Sam  ',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Tell the court what really happened.',
        ),
        '  Nobody claimed it, so I assumed it was abandoned.  ',
      );
      await tester.tap(find.text('ENTER MY DEFENCE'));
      await tester.pumpAndSettle();

      expect(api.lastDefense, {
        'token': 'inv_abc12345',
        'nickname': 'Sam',
        'body': 'Nobody claimed it, so I assumed it was abandoned.',
      });
    });

    testWidgets('refuses a defence that says almost nothing', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Sam'), 'Sam');
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Tell the court what really happened.',
        ),
        'no',
      );
      await tester.tap(find.text('ENTER MY DEFENCE'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least'), findsOneWidget);
      expect(api.lastDefense, isNull);
    });

    testWidgets('confirms once the defence is on the record', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Sam'), 'Sam');
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Tell the court what really happened.',
        ),
        'Nobody claimed it, so I assumed it was abandoned.',
      );
      await tester.tap(find.text('ENTER MY DEFENCE'));
      await tester.pumpAndSettle();

      expect(find.text('Your defence is on the record'), findsOneWidget);
    });

    testWidgets('shows the server message when the court refuses it', (
      tester,
    ) async {
      api.defenseError = ApiException(
        409,
        'conflict',
        'This case is no longer accepting a defense.',
      );
      await pump(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Sam'), 'Sam');
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Tell the court what really happened.',
        ),
        'Nobody claimed it, so I assumed it was abandoned.',
      );
      await tester.tap(find.text('ENTER MY DEFENCE'));
      await tester.pumpAndSettle();

      expect(
        find.text('This case is no longer accepting a defense.'),
        findsOneWidget,
      );
    });
  });

  group('the route a summons links to', () {
    testWidgets('a boss case opens the defence in the app, not an error page', (
      tester,
    ) async {
      // The bug this screen exists to fix: every "DEFEND" in the app pushed
      // /invite/<token>, which no route matched, so it landed on the
      // "Lost in the courthouse" page.
      const shared = SharedCase(
        caseId: 'case-1',
        title: 'The Last Pizza Slice',
        category: 'food',
        status: 'awaiting_defense',
        role: 'accused',
        creatorName: 'Alex',
        linkKind: 'invite',
        token: 'inv_abc12345',
      );
      expect(shared.path, '/invite/inv_abc12345');

      useMobileSurface(tester);
      final router = GoRouter(
        initialLocation: shared.path,
        routes: [
          GoRoute(
            path: '/invite/:token',
            builder: (_, state) =>
                DefendScreen(token: state.pathParameters['token']!),
          ),
        ],
        errorBuilder: (_, __) => const Text('Lost in the courthouse'),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        harnessWithRouter(
          router: router,
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lost in the courthouse'), findsNothing);
      expect(find.text('Your defence'), findsOneWidget);
    });
  });
}
