import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/cases/presentation/case_detail_screen.dart';

import 'support/fakes.dart';

void main() {
  _seatingTests();
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester, {CaseDetail? detail}) {
    api.detail = detail ?? buildDetail();
    useMobileSurface(tester);
    return tester.pumpWidget(
      harness(
        child: const CaseDetailScreen(caseId: 'case-1'),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
  }

  testWidgets('shows the case and its accusation', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('The Last Pizza Slice'), findsOneWidget);
    expect(find.textContaining('ate the last pizza slice'), findsOneWidget);
  });

  group('status panel explains what the court is waiting for', () {
    testWidgets('awaiting a defense', (tester) async {
      await pump(
        tester,
        detail: buildDetail(status: CaseStatus.awaitingDefense),
      );
      await tester.pumpAndSettle();

      expect(find.text('Awaiting defense'), findsOneWidget);
      expect(find.textContaining('Nothing happens until'), findsOneWidget);
      expect(find.text('Check for a defense'), findsOneWidget);
    });

    testWidgets('ready for a verdict', (tester) async {
      await pump(tester, detail: buildDetail(status: CaseStatus.ready));
      await tester.pumpAndSettle();

      expect(find.text('Call the court to order'), findsOneWidget);
    });

    testWidgets('failed, offering a safe retry', (tester) async {
      await pump(
        tester,
        detail: buildDetail(
          status: CaseStatus.failed,
          failureReason: 'LLMTimeoutError',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('LLMTimeoutError'), findsOneWidget);
      expect(find.text('Try the verdict again'), findsOneWidget);
    });

    testWidgets('completed, offering to read the verdict', (tester) async {
      await pump(tester, detail: buildDetail(status: CaseStatus.completed));
      await tester.pumpAndSettle();

      expect(find.text('Read the verdict'), findsOneWidget);
    });

    testWidgets('expired, offering a fresh case', (tester) async {
      await pump(tester, detail: buildDetail(status: CaseStatus.expired));
      await tester.pumpAndSettle();

      expect(find.textContaining('expired before a defense'), findsOneWidget);
      expect(find.text('File a new case'), findsOneWidget);
    });
  });

  testWidgets('deleting asks for confirmation and warns about links', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();

    // The chrome draws its own glyphs rather than Material icons, so the
    // button is addressed the way a screen reader addresses it.
    await tester.tap(find.bySemanticsLabel('Delete case'));
    await tester.pumpAndSettle();

    expect(find.text('Dismiss this case?'), findsOneWidget);
    expect(find.textContaining('stops working immediately'), findsOneWidget);

    // Backing out must not delete anything.
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(api.deleteCalls, 0);
  });

  testWidgets('surfaces a load failure with a retry', (tester) async {
    api.detailError = ApiException(404, 'not_found', 'Case not found.');
    useMobileSurface(tester);
    await tester.pumpWidget(
      harness(
        child: const CaseDetailScreen(caseId: 'case-1'),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Case not found.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

void _seatingTests() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  testWidgets('seating a friend on a live case notifies them', (tester) async {
    // The endpoint and the client method both existed; no screen called them,
    // so the only way to involve a friend was to pick one while filing.
    api.detail = buildDetail();
    api.people = const [
      UserRef(userId: 'user-9', displayName: 'Priya', handle: 'priya'),
    ];
    useMobileSurface(tester);
    await tester.pumpWidget(
      harness(
        child: const CaseDetailScreen(caseId: 'case-1'),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Add a juror'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a juror'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.hintText == 'Handle or exact email',
      ),
      'priya',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@priya'));
    await tester.pumpAndSettle();

    expect(api.seated, [('case-1', 'user-9', 'juror')]);
    expect(find.textContaining('has been notified'), findsOneWidget);
  });
}
