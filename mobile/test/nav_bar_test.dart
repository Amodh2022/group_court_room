/// The navigation pill: built once, laid out inside its own bounds, and big
/// enough to hit. Every one of these pins a bug this screen actually had.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:group_chat_court/core/courtroom.dart';
import 'package:group_chat_court/core/router.dart';
import 'package:group_chat_court/core/theme.dart';
import 'package:group_chat_court/core/widgets/court_chrome.dart';
import 'package:group_chat_court/core/widgets/court_icons.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient(cases: [buildSummary()]);
    SharedPreferences.setMockInitialValues({
      'gcc.session':
          '{"access_token":"t","user_id":"user-1","display_name":"Alex"}',
    });
  });

  Future<GoRouter> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        courtroomConnectorProvider.overrideWithValue(FakeRooms().connect),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: courtLightTheme(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  const phone = Size(393, 851);

  testWidgets('has five slots: four tabs and the filing key', (tester) async {
    await pumpApp(tester, phone);
    for (final tab in CourtTab.values) {
      expect(find.byTooltip(tab.label), findsOneWidget, reason: tab.label);
    }
    expect(find.byTooltip('File a case'), findsOneWidget);
  });

  testWidgets('the raised filing key stays inside the bar it belongs to', (
    tester,
  ) async {
    await pumpApp(tester, phone);
    // The key is translated 34px up through the pill's top edge. If the bar
    // does not reserve that head-room the key is clipped by the bottom-bar
    // slot and its top half stops taking taps.
    final bar = tester.getRect(find.byType(CourtNavBar));
    final key = tester.getRect(find.byTooltip('File a case'));
    expect(key.top, greaterThanOrEqualTo(bar.top));
    expect(key.bottom, lessThanOrEqualTo(bar.bottom));
  });

  testWidgets('the filing key answers a tap where it is drawn', (
    tester,
  ) async {
    final router = await pumpApp(tester, phone);
    // Tap the gavel itself, not the slot's bounding box. The key is painted
    // 34px above its slot, and with the Transform inside the InkWell those
    // two came apart: the visible key was dead and a blank strip of pill
    // below it opened the filing screen instead.
    final gavel = find.descendant(
      of: find.byTooltip('File a case'),
      matching: find.byType(CourtIcon),
    );
    await tester.tapAt(tester.getCenter(gavel));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/cases/new');
  });

  testWidgets('every slot clears the 44px touch target', (tester) async {
    await pumpApp(tester, phone);
    for (final label in [
      ...CourtTab.values.map((t) => t.label),
      'File a case',
    ]) {
      final box = tester.getRect(find.byTooltip(label));
      expect(box.width, greaterThanOrEqualTo(44), reason: label);
      expect(box.height, greaterThanOrEqualTo(44), reason: label);
    }
  });

  testWidgets('the slots do not overlap each other', (tester) async {
    await pumpApp(tester, phone);
    final boxes = [
      for (final label in [
        CourtTab.home.label,
        CourtTab.courts.label,
        'File a case',
        CourtTab.record.label,
        CourtTab.settings.label,
      ])
        tester.getRect(find.byTooltip(label)),
    ];
    for (var i = 1; i < boxes.length; i++) {
      expect(
        boxes[i - 1].right,
        lessThanOrEqualTo(boxes[i].left),
        reason: 'slot $i overlaps the one before it',
      );
    }
  });

  testWidgets('it sits above the gesture inset, not under it', (tester) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        courtroomConnectorProvider.overrideWithValue(FakeRooms().connect),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: courtLightTheme(),
          routerConfig: container.read(routerProvider),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pill = tester.getRect(find.byTooltip(CourtTab.home.label));
    expect(
      pill.bottom,
      lessThanOrEqualTo(phone.height - 48),
      reason: 'the pill must clear the system gesture bar',
    );
  });

  testWidgets('it stands down while the keyboard is up', (tester) async {
    await pumpApp(tester, phone);
    expect(find.byType(CourtNavBar), findsOneWidget);

    // A bottom bar is pushed up by the keyboard; the pill would sit on top of
    // the keys, over tabs nobody is reaching for.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(find.byType(CourtNavBar), findsNothing);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.byType(CourtNavBar), findsOneWidget);
  });

  group('android back', () {
    testWidgets('inside a tab, pops that tab before leaving it', (
      tester,
    ) async {
      final router = await pumpApp(tester, phone);
      router.go('/courts/court-1');
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/courts');
    });

    testWidgets('at a tab root, returns to Home rather than exiting', (
      tester,
    ) async {
      final router = await pumpApp(tester, phone);
      await tester.tap(find.byTooltip(CourtTab.record.label));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/rap-sheet');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/');
    });
  });

  testWidgets('a wide window gets the rail instead, never both', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1000, 800));
    expect(find.byType(CourtNavBar), findsNothing);
    expect(find.byTooltip(CourtTab.courts.label), findsOneWidget);
    expect(tester.getCenter(find.byTooltip(CourtTab.courts.label)).dx,
        lessThan(120));
  });

  testWidgets('switching tabs does not stack a second bar', (tester) async {
    await pumpApp(tester, phone);
    for (final tab in CourtTab.values) {
      await tester.tap(find.byTooltip(tab.label));
      await tester.pumpAndSettle();
      expect(find.byType(CourtNavBar), findsOneWidget, reason: tab.label);
    }
  });

  testWidgets('the current tab is the only one marked selected', (
    tester,
  ) async {
    await pumpApp(tester, phone);
    await tester.tap(find.byTooltip(CourtTab.record.label));
    await tester.pumpAndSettle();

    final selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.selected == true)
        .length;
    expect(selected, 1);
  });
}
