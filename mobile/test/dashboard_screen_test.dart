import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/core/widgets/court_widgets.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/cases/presentation/dashboard_screen.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) {
    useMobileSurface(tester);
    return tester.pumpWidget(
      harness(
        child: const DashboardScreen(),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
  }

  group('dashboard states', () {
    testWidgets('shows a skeleton while the docket loads', (tester) async {
      final gate = Completer<void>();
      api.listGate = gate;
      await pump(tester);
      await tester.pump();

      expect(find.byType(CourtSkeleton), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CourtSkeleton), findsNothing);
    });

    testWidgets('invites the user to file when the docket is empty', (
      tester,
    ) async {
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('The docket is empty'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'File a case'), findsOneWidget);
    });

    testWidgets('renders a card per case', (tester) async {
      api.cases = [
        buildSummary(id: 'a', title: 'The Last Pizza Slice'),
        buildSummary(id: 'b', title: 'Reply Guy Of The Year'),
      ];
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('The Last Pizza Slice'), findsOneWidget);
      expect(find.text('Reply Guy Of The Year'), findsOneWidget);
    });

    testWidgets('offers a retry when the docket cannot be loaded', (
      tester,
    ) async {
      api.listError = ApiException(
        0,
        'network_error',
        'Could not reach the courthouse.',
      );
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the courthouse.'), findsOneWidget);

      api.listError = null;
      api.cases = [buildSummary()];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('The Last Pizza Slice'), findsOneWidget);
    });
  });

  group('dashboard status rendering', () {
    Future<void> pumpWithStatus(WidgetTester tester, CaseStatus status) async {
      api.cases = [buildSummary(status: status)];
      await pump(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('labels a case awaiting a defense', (tester) async {
      await pumpWithStatus(tester, CaseStatus.awaitingDefense);
      expect(find.text('Awaiting defense'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    });

    testWidgets('labels a case ready for a verdict', (tester) async {
      await pumpWithStatus(tester, CaseStatus.ready);
      expect(find.text('Ready for verdict'), findsOneWidget);
      expect(find.byIcon(Icons.gavel), findsWidgets);
    });

    testWidgets('labels a case in deliberation', (tester) async {
      await pumpWithStatus(tester, CaseStatus.generating);
      expect(find.text('In deliberation'), findsOneWidget);
    });

    testWidgets('labels a completed case', (tester) async {
      await pumpWithStatus(tester, CaseStatus.completed);
      expect(find.text('Verdict in'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
    });

    testWidgets('labels a failed case as retryable', (tester) async {
      await pumpWithStatus(tester, CaseStatus.failed);
      expect(find.text('Needs a retry'), findsOneWidget);
    });

    testWidgets('labels an expired case', (tester) async {
      await pumpWithStatus(tester, CaseStatus.expired);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('marks a publicly shared case', (tester) async {
      api.cases = [
        buildSummary(status: CaseStatus.completed, shareEnabled: true),
      ];
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.public), findsOneWidget);
    });

    testWidgets('does not mark an unshared case as public', (tester) async {
      await pumpWithStatus(tester, CaseStatus.completed);
      expect(find.byIcon(Icons.public), findsNothing);
    });
  });

  group('the docket cards', () {
    testWidgets('never cast a shadow from a box with no fill', (tester) async {
      // A BoxShadow on a transparent box shows through its own middle as a grey
      // wash. Every shadowed box on this screen must carry its own fill.
      api.cases = [buildSummary(status: CaseStatus.completed)];
      await pump(tester);
      await tester.pumpAndSettle();

      final shadowed = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.boxShadow != null && d.boxShadow!.isNotEmpty);

      expect(shadowed, isNotEmpty, reason: 'the card should be floating');
      for (final decoration in shadowed) {
        expect(
          decoration.color,
          isNotNull,
          reason: 'a shadow needs a fill behind it',
        );
      }
    });

    testWidgets('read like the reference: trial number and a pill', (
      tester,
    ) async {
      api.cases = [buildSummary(id: 'abcde-1234')];
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Court Trial · ABCDE'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('offer the verdict pill once a ruling exists', (tester) async {
      api.cases = [buildSummary(status: CaseStatus.completed)];
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Verdict'), findsOneWidget);
    });
  });
}
