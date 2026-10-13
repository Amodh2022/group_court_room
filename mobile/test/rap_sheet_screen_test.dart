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
    expect(find.text('Repeat Offender'), findsOneWidget);
    expect(find.text('Clean Record'), findsOneWidget);
    // The number one is wanted, and their count is on their plinth.
    expect(find.text('WANTED'), findsOneWidget);
    expect(find.text('4 guilty'), findsOneWidget);
  });

  testWidgets('everyone past the podium gets a row with their record', (
    tester,
  ) async {
    api.records = [
      for (var i = 1; i <= 4; i++)
        buildRecord(
          id: 'offender-$i',
          displayName: 'Person $i',
          rank: i,
          convictions: 5 - i,
        ),
    ];
    await pump(tester);
    await tester.pumpAndSettle();

    // Ranks one to three are on plinths; rank four is the first list row.
    expect(find.text('4'), findsWidgets);
    expect(find.text('Person 4'), findsOneWidget);
    expect(find.text('GUILTY'), findsOneWidget);
    expect(find.text('Mistrial'), findsOneWidget);
  });

  testWidgets('the stage totals the court, not one person', (tester) async {
    api.records = [
      buildRecord(displayName: 'Streaky', rank: 1, longestStreak: 3),
      buildRecord(id: 'offender-2', displayName: 'Occasional', rank: 2),
    ];
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Longest streak'), findsOneWidget);
    expect(find.text('Conviction rate'), findsOneWidget);
    expect(find.text('Cases tried'), findsOneWidget);
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
}
