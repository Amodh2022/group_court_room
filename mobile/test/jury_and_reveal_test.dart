import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/core/widgets/court_widgets.dart';
import 'package:group_chat_court/core/widgets/verdict_reveal.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/cases/presentation/case_detail_screen.dart';
import 'package:group_chat_court/features/verdicts/presentation/verdict_screen.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  // --- the jury's split, wherever it is shown ------------------------------

  group('the jury on the case file', () {
    Future<void> pump(WidgetTester tester) {
      useMobileSurface(tester);
      return tester.pumpWidget(
        harness(
          child: const CaseDetailScreen(caseId: 'case-1'),
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );
    }

    testWidgets('shows the creator the running count', (tester) async {
      api.detail = buildDetail(juryTally: buildTally(guilty: 3, notGuilty: 1));
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('The jury voted 3–1 for guilty.'), findsOneWidget);
      expect(find.byKey(const Key('jury-tally')), findsOneWidget);
    });

    testWidgets('says nothing about a jury nobody has joined', (tester) async {
      api.detail = buildDetail(juryTally: buildTally(guilty: 0, notGuilty: 0));
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('jury-tally')), findsNothing);
    });

    testWidgets('points at the jury while the defense is outstanding', (
      tester,
    ) async {
      api.detail = buildDetail(status: CaseStatus.awaitingDefense);
      await pump(tester);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('jury can start voting right now'),
        findsOneWidget,
      );
    });
  });

  group('the jury on the verdict', () {
    Future<void> pump(WidgetTester tester) {
      useMobileSurface(tester);
      return tester.pumpWidget(
        harness(
          child: const VerdictScreen(caseId: 'case-1'),
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );
    }

    testWidgets('flags a ruling that went against the jury', (tester) async {
      // testVerdict is BOTH GUILTY; a jury that voted not guilty is overruled.
      api.detail = buildDetail(
        status: CaseStatus.completed,
        juryTally: buildTally(guilty: 1, notGuilty: 4),
      );
      api.verdict = const VerdictState(
        status: CaseStatus.completed,
        verdict: testVerdict,
      );
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('overruled')), findsOneWidget);
      expect(find.textContaining('JUDGE OVERRULED'), findsOneWidget);
    });

    testWidgets('says nothing when the judge agreed with the jury', (
      tester,
    ) async {
      api.detail = buildDetail(
        status: CaseStatus.completed,
        juryTally: buildTally(guilty: 4, notGuilty: 1),
      );
      api.verdict = const VerdictState(
        status: CaseStatus.completed,
        verdict: testVerdict,
      );
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('jury-tally')), findsOneWidget);
      expect(find.byKey(const Key('overruled')), findsNothing);
    });

    testWidgets('holds the curtain until the jury is known', (tester) async {
      // The reveal fixes its beats on mount. If the verdict lands before the
      // case file does, performing immediately would drop the jury from the
      // sequence permanently — so the screen waits.
      final gate = Completer<void>();
      api.detailGate = gate;
      api.detail = buildDetail(
        status: CaseStatus.completed,
        juryTally: buildTally(guilty: 3, notGuilty: 1),
      );
      api.verdict = const VerdictState(
        status: CaseStatus.completed,
        verdict: testVerdict,
      );

      useMobileSurface(tester);
      await tester.pumpWidget(
        harness(
          animated: true,
          child: const VerdictScreen(caseId: 'case-1'),
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('The court is in deliberation'), findsOneWidget);
      expect(find.byKey(const Key('verdict-reveal')), findsNothing);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('verdict-reveal')), findsOneWidget);
      expect(find.text('All rise.'), findsOneWidget);
    });

    testWidgets('a deadlocked jury is never overruled', (tester) async {
      api.detail = buildDetail(
        status: CaseStatus.completed,
        juryTally: buildTally(guilty: 2, notGuilty: 2),
      );
      api.verdict = const VerdictState(
        status: CaseStatus.completed,
        verdict: testVerdict,
      );
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('overruled')), findsNothing);
    });
  });

  group('the tally bar', () {
    Future<void> pumpBar(WidgetTester tester, JuryTally tally) {
      useMobileSurface(tester);
      return tester.pumpWidget(
        harness(
          child: Scaffold(
            body: Center(child: JuryTallyBar(tally: tally)),
          ),
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );
    }

    testWidgets('actually paints both segments at full height', (tester) async {
      // A find-by-key assertion is not enough here: the bar can be present in
      // the tree and still paint nothing if its segments collapse to zero
      // height, which is exactly what a loose-constrained Row causes.
      await pumpBar(tester, buildTally(guilty: 3, notGuilty: 1));
      await tester.pumpAndSettle();

      final bar = tester.getSize(find.byKey(const Key('jury-tally')));
      expect(bar.height, 14);
      expect(bar.width, greaterThan(0));

      final segments = find.descendant(
        of: find.byKey(const Key('jury-tally')),
        matching: find.byType(ColoredBox),
      );
      expect(segments, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(segments.at(i));
        expect(size.height, 14, reason: 'segment $i collapsed vertically');
        expect(size.width, greaterThan(0), reason: 'segment $i has no width');
      }

      // 3 guilty to 1 not guilty: three times the width.
      final guilty = tester.getSize(segments.at(0)).width;
      final notGuilty = tester.getSize(segments.at(1)).width;
      expect(guilty, closeTo(notGuilty * 3, 0.5));
    });

    testWidgets('a one-sided jury fills the bar with one colour', (
      tester,
    ) async {
      await pumpBar(tester, buildTally(guilty: 4, notGuilty: 0));
      await tester.pumpAndSettle();

      final segments = find.descendant(
        of: find.byKey(const Key('jury-tally')),
        matching: find.byType(ColoredBox),
      );
      expect(segments, findsOneWidget);
      expect(tester.getSize(segments).height, 14);
    });
  });

  // --- the reveal ----------------------------------------------------------

  group('the reveal', () {
    testWidgets('plays before the ruling, and can be skipped', (tester) async {
      useMobileSurface(tester);
      await tester.pumpWidget(
        harness(
          animated: true,
          child: VerdictReveal(
            verdict: testVerdict,
            tally: buildTally(),
            child: const Text('THE RULING'),
          ),
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('verdict-reveal')), findsOneWidget);
      expect(find.text('All rise.'), findsOneWidget);
      expect(find.text('THE RULING'), findsNothing);

      await tester.tap(find.text('Skip to the verdict'));
      await tester.pumpAndSettle();

      expect(find.text('THE RULING'), findsOneWidget);
      expect(find.byKey(const Key('verdict-reveal')), findsNothing);
    });

    testWidgets('reads the jury out as one of the beats', (tester) async {
      useMobileSurface(tester);
      await tester.pumpWidget(
        harness(
          animated: true,
          child: VerdictReveal(
            verdict: testVerdict,
            tally: buildTally(guilty: 3, notGuilty: 1),
            child: const Text('THE RULING'),
          ),
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 2100));

      expect(find.text('The jury voted 3–1 for guilty.'), findsOneWidget);
      expect(find.text('The judge is not bound by it.'), findsOneWidget);
    });

    testWidgets('goes straight to the ruling when motion is reduced', (
      tester,
    ) async {
      useMobileSurface(tester);
      await tester.pumpWidget(
        harness(
          // harness() disables animations, exactly as the OS setting would.
          child: VerdictReveal(
            verdict: testVerdict,
            tally: buildTally(),
            child: const Text('THE RULING'),
          ),
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );
      await tester.pump();

      expect(find.text('THE RULING'), findsOneWidget);
      expect(find.byKey(const Key('verdict-reveal')), findsNothing);
    });
  });
}
