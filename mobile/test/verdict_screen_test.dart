import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/verdicts/presentation/verdict_screen.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) {
    useMobileSurface(tester);
    return tester.pumpWidget(
      harness(
        child: const VerdictScreen(caseId: 'case-1'),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
  }

  group('verdict rendering', () {
    setUp(
      () => api.verdict = const VerdictState(
        status: CaseStatus.completed,
        verdict: testVerdict,
      ),
    );

    testWidgets('renders every section of the verdict', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('The Last Pizza Slice'), findsOneWidget);
      expect(find.text('Alleged food misconduct'), findsOneWidget);
      expect(find.text(testVerdict.prosecutionSummary), findsOneWidget);
      expect(find.text(testVerdict.defenseSummary), findsOneWidget);
      expect(find.text(testVerdict.reasoning), findsOneWidget);
      expect(find.text(testVerdict.sentence), findsOneWidget);
      expect(find.text('“${testVerdict.judgeRoast}”'), findsOneWidget);
      expect(find.text(testVerdict.closingLine), findsOneWidget);
    });

    testWidgets('stamps the verdict', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      final stamp = find.byKey(const Key('verdict-stamp'));
      expect(stamp, findsOneWidget);
      expect(tester.widget<Text>(stamp).data, 'BOTH GUILTY');
    });

    for (final (kind, label) in <(VerdictKind, String)>[
      (VerdictKind.guilty, 'GUILTY'),
      (VerdictKind.notGuilty, 'NOT GUILTY'),
      (VerdictKind.bothGuilty, 'BOTH GUILTY'),
      (VerdictKind.insufficientEvidence, 'INSUFFICIENT EVIDENCE'),
    ]) {
      testWidgets('stamps $label', (tester) async {
        api.verdict = VerdictState(
          status: CaseStatus.completed,
          verdict: Verdict(
            caseTitle: 'T',
            charge: 'C',
            prosecutionSummary: 'P',
            defenseSummary: 'D',
            verdict: kind,
            reasoning: 'R',
            sentence: 'S',
            judgeRoast: 'J',
            closingLine: 'L',
            shareCaption: 'Cap',
          ),
        );
        await pump(tester);
        await tester.pumpAndSettle();

        expect(
          tester.widget<Text>(find.byKey(const Key('verdict-stamp'))).data,
          label,
        );
      });
    }

    testWidgets('publishing is opt-in and reveals a revocable link', (
      tester,
    ) async {
      final shares = captureShares();
      await pump(tester);
      await tester.pumpAndSettle();

      // Nothing is public until the creator asks for it.
      expect(find.textContaining('court.test/verdict'), findsNothing);
      expect(api.shareCalls, 0);

      await scrollTo(tester, find.text('Publish and share the verdict'));
      await tester.tap(find.text('Publish and share the verdict'));
      await tester.pumpAndSettle();

      expect(api.shareCalls, 1);
      expect(find.text('Public link is live'), findsOneWidget);
      expect(find.text('https://court.test/verdict/shr_test'), findsOneWidget);
      // The share sheet got the caption and the public URL, nothing private.
      expect(
        shares.single['text'],
        contains('https://court.test/verdict/shr_test'),
      );
      expect(shares.single['text'], contains(testVerdict.shareCaption));

      await scrollTo(tester, find.text('Revoke'));
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();

      expect(api.revokeCalls, 1);
      expect(find.text('Publish and share the verdict'), findsOneWidget);
    });
  });

  group('verdict lifecycle states', () {
    testWidgets('offers to call the court when both sides are in', (
      tester,
    ) async {
      api.verdict = const VerdictState(status: CaseStatus.ready);
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Both sides are in'), findsOneWidget);

      await tester.tap(find.text('Call the court to order'));
      await tester.pump();
      expect(api.verdictRequests, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('shows a deliberation state while generating', (tester) async {
      api.verdict = const VerdictState(status: CaseStatus.generating);
      await pump(tester);
      await tester.pump();

      expect(find.text('The court is in deliberation'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('offers a safe retry after a mistrial', (tester) async {
      api.verdict = const VerdictState(status: CaseStatus.failed);
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('A mistrial'), findsOneWidget);

      await tester.tap(find.text('Retry the verdict'));
      await tester.pump();
      expect(api.verdictRequests, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('explains that a defense is still outstanding', (tester) async {
      api.verdict = const VerdictState(status: CaseStatus.awaitingDefense);
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Still awaiting a defense'), findsOneWidget);
    });

    testWidgets('reports an expired case', (tester) async {
      api.verdict = const VerdictState(status: CaseStatus.expired);
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('This case expired'), findsOneWidget);
    });

    testWidgets('surfaces an API failure with a retry', (tester) async {
      api.verdictError = ApiException(
        0,
        'network_error',
        'Could not reach the courthouse.',
      );
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the courthouse.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
