import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/core/widgets/court_layout.dart';
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

  testWidgets('lists the records this court has accumulated', (tester) async {
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
    // Convictions are the headline number on the person's own card...
    final card = find.ancestor(
      of: find.text('SliceBandit'),
      matching: find.byType(SpineCard),
    );
    expect(find.descendant(of: card, matching: find.text('4')), findsOneWidget);
    // ...and the standings strip totals them across the court.
    expect(find.text('Convictions'), findsOneWidget);
  });

  testWidgets('shows a streak only once it is worth mentioning', (
    tester,
  ) async {
    api.records = [
      buildRecord(displayName: 'Streaky', rank: 1, currentStreak: 3),
      buildRecord(
        id: 'offender-2',
        displayName: 'Occasional',
        rank: 2,
        currentStreak: 1,
      ),
    ];
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('3-case streak'), findsOneWidget);
    expect(find.text('1-case streak'), findsNothing);
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
