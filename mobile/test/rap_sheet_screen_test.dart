import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/records/presentation/rap_sheet_screen.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) {
    useMobileSurface(tester);
    return tester.pumpWidget(
      harness(
        child: const RapSheetScreen(),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
  }

  testWidgets('puts the top three on the podium with their count', (
    tester,
  ) async {
    api.records = [
      buildRecord(displayName: 'SliceBandit', rank: 1, convictions: 4),
      buildRecord(
        id: 'offender-2',
        displayName: 'Alex',
        rank: 2,
        title: 'Clean Record',
        convictions: 0,
        acquittals: 2,
        currentStreak: 0,
      ),
    ];
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('SliceBandit'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    // Each podium place shows the person's real conviction count.
    expect(find.text('4 guilty'), findsOneWidget);
    expect(find.text('0 guilty'), findsOneWidget);
  });

  testWidgets('everyone past the podium gets a row with title and pill', (
    tester,
  ) async {
    api.records = [
      for (var i = 1; i <= 5; i++)
        buildRecord(
          id: 'offender-$i',
          displayName: 'Person $i',
          rank: i,
          title: 'Title $i',
          convictions: i == 5 ? 0 : 5 - i,
        ),
    ];
    await pump(tester);
    await tester.pumpAndSettle();

    // Ranks one to three are on the podium; four and five are list rows.
    expect(find.text('Person 4'), findsOneWidget);
    expect(find.text('Title 4'), findsOneWidget);
    expect(find.text('1 GUILTY'), findsOneWidget);
    // Nobody convicted reads as clean, not as "0 guilty".
    expect(find.text('CLEAN'), findsOneWidget);
  });

  testWidgets('the header totals the court, not one person', (tester) async {
    api.records = [
      buildRecord(displayName: 'Streaky', rank: 1), // 3 + 1 = 4 cases
      buildRecord(id: 'offender-2', displayName: 'Occasional', rank: 2),
    ];
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('ALL-TIME · 8 CASES'), findsOneWidget);
  });

  testWidgets('an empty sheet invites a first case', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('No convictions yet'), findsOneWidget);
    expect(find.text('File a case'), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    api.rapSheetError = ApiException(
      500,
      'server_error',
      'The archive is on fire.',
    );
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('The archive is on fire.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  group('where you stand', () {
    testWidgets('names the gap to the rank above', (tester) async {
      api.records = [
        buildRecord(displayName: 'Dev', rank: 1, convictions: 11),
        buildRecord(id: 'o-2', displayName: 'Maya', rank: 2, convictions: 8),
        buildRecord(id: 'o-3', displayName: 'Priya', rank: 3, convictions: 7),
        buildRecord(id: 'o-4', displayName: 'Arjun', rank: 4, convictions: 5),
        buildRecord(id: 'o-5', displayName: 'You', rank: 5, convictions: 4,
            isYou: true),
      ];
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('1 more guilty verdict'), findsOneWidget);
      expect(find.textContaining('Arjun'), findsWidgets);
    });

    testWidgets('stays hidden when the court has no record of you', (
      tester,
    ) async {
      // A row carries a record id, never an account id, so the client cannot
      // work this out itself — an unmarked sheet draws no band.
      api.records = [
        buildRecord(displayName: 'Dev', rank: 1, convictions: 11),
        buildRecord(id: 'o-2', displayName: 'Maya', rank: 2, convictions: 8),
      ];
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('to overtake'), findsNothing);
      expect(find.textContaining('Top of the sheet'), findsNothing);
    });
  });
}
