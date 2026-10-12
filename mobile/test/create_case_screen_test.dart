import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/cases/presentation/create_case_screen.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) {
    useMobileSurface(tester);
    return tester.pumpWidget(
      harness(
        child: const CreateCaseScreen(),
        overrides: [apiClientProvider.overrideWithValue(api)],
      ),
    );
  }

  group('create-case form validation', () {
    testWidgets('rejects an empty form and does not call the API', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('File the case'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Give the case a name'), findsOneWidget);
      expect(find.textContaining('needs to hear the charge'), findsOneWidget);
      expect(api.lastCreate, isNull);
    });

    testWidgets('rejects a title that is too short', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextFormField).first, 'ab');
      await tester.tap(find.text('File the case'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 3 characters'), findsOneWidget);
      expect(api.lastCreate, isNull);
    });

    testWidgets('rejects an accusation that is too short', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'The Last Pizza Slice',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'too short');
      await tester.tap(find.text('File the case'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 10 characters'), findsOneWidget);
      expect(api.lastCreate, isNull);
    });

    testWidgets('submits trimmed values with the chosen category', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        '  The Last Pizza Slice  ',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '  They ate the last slice right after saying they were full.  ',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'SliceBandit');

      await tester.tap(find.text('💬  Group chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File the case'));
      await tester.pumpAndSettle();

      expect(api.lastCreate, {
        'title': 'The Last Pizza Slice',
        'category': 'group_chat',
        'accusation':
            'They ate the last slice right after saying they were full.',
        'defendant_nickname': 'SliceBandit',
        'court_id': null,
        'accused_user_id': null,
      });
    });

    testWidgets('counts down the characters left in the accusation', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('1000 characters left'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), 'abcde');
      await tester.pump();
      expect(find.text('995 characters left'), findsOneWidget);
    });
  });

  group('create-case error states', () {
    testWidgets('shows the server message when filing is rejected', (
      tester,
    ) async {
      api.createError = ApiException(
        409,
        'conflict',
        'You have too many open cases.',
      );
      await pump(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'The Last Pizza Slice',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'They ate the last slice after saying they were full.',
      );
      await tester.tap(find.text('File the case'));
      await tester.pumpAndSettle();

      expect(find.text('You have too many open cases.'), findsOneWidget);
    });

    testWidgets('shows a network failure without losing typed input', (
      tester,
    ) async {
      api.createError = ApiException(
        0,
        'network_error',
        'Could not reach the courthouse. Check your connection.',
      );
      await pump(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'The Last Pizza Slice',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'They ate the last slice after saying they were full.',
      );
      await tester.tap(find.text('File the case'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not reach the courthouse'),
        findsOneWidget,
      );
      // The typed title survives the failure, so a retry costs no re-typing.
      final title = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField).first,
          matching: find.byType(TextField),
        ),
      );
      expect(title.controller?.text, 'The Last Pizza Slice');
    });

    testWidgets('disables the button while a filing is in flight', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'The Last Pizza Slice',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'They ate the last slice after saying they were full.',
      );

      await tester.tap(find.text('File the case'));
      await tester.pump(); // submitting, not yet resolved

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
