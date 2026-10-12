import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/invitations/presentation/invite_screen.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester, {CaseDetail? created}) {
    useMobileSurface(tester);
    return tester.pumpWidget(
      harness(
        child: InviteScreen(caseId: 'case-1', created: created),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
  }

  testWidgets('shows the one-time summons link', (tester) async {
    await pump(tester, created: buildDetail());
    await tester.pumpAndSettle();

    expect(
      find.text('https://court.test/invite/inv_test_token'),
      findsOneWidget,
    );
    expect(find.text('Share the summons'), findsOneWidget);
    expect(find.text('Copy the summons link'), findsOneWidget);
  });

  testWidgets('hands out the jury link alongside the summons', (tester) async {
    await pump(tester, created: buildDetail());
    await tester.pumpAndSettle();

    expect(find.text('https://court.test/jury/jry_test_token'), findsOneWidget);
    expect(find.text('Share the jury summons'), findsOneWidget);
    // The two links are for different audiences, and the screen says so.
    expect(find.textContaining('For the accused only'), findsOneWidget);
    expect(find.textContaining('group chat'), findsOneWidget);
  });

  testWidgets('shows only the summons when no jury link came back', (
    tester,
  ) async {
    await pump(tester, created: buildDetail(juryToken: null));
    await tester.pumpAndSettle();

    expect(find.text('Share the summons'), findsOneWidget);
    expect(find.text('Share the jury summons'), findsNothing);
  });

  testWidgets('the share sheet carries the title and the invite link', (
    tester,
  ) async {
    final shares = captureShares();
    await pump(tester, created: buildDetail());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share the summons'));
    await tester.pumpAndSettle();

    expect(shares.single['text'], contains('The Last Pizza Slice'));
    expect(
      shares.single['text'],
      contains('https://court.test/invite/inv_test_token'),
    );
  });

  testWidgets('the jury share carries the jury link, not the summons', (
    tester,
  ) async {
    final shares = captureShares();
    await pump(tester, created: buildDetail());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share the jury summons'));
    await tester.pumpAndSettle();

    expect(
      shares.single['text'],
      contains('https://court.test/jury/jry_test_token'),
    );
    expect(
      shares.single['text'],
      isNot(contains('https://court.test/invite/')),
    );
  });

  testWidgets('explains the one-time link when it is not available', (
    tester,
  ) async {
    // Reached by deep link or after a restart: the token is unrecoverable.
    await pump(tester, created: null);
    await tester.pumpAndSettle();

    expect(find.text('This summons link is gone'), findsOneWidget);
    expect(find.textContaining('shown only once'), findsOneWidget);
    expect(find.text('Share the summons'), findsNothing);
  });
}
