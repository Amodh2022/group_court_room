/// Responsive layout (phone, tablet, landscape) and the social features:
/// courts, user search, shared cases and notifications.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:group_chat_court/core/courtroom.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/core/router.dart';
import 'package:group_chat_court/core/theme.dart';
import 'package:group_chat_court/core/widgets/court_chrome.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _alex = UserRef(userId: 'user-1', handle: 'alex', displayName: 'Alex');
const _sam = UserRef(userId: 'user-2', handle: 'sam', displayName: 'Sam');
// A court with one member never stacks its faces, and the stack is where the
// layout actually bites: overlapping avatars drawn with a negative margin
// throw on layout, which a single-member fixture can never catch.
const _crowd = [
  _alex,
  UserRef(userId: 'user-3', handle: 'priya', displayName: 'Priya'),
  UserRef(userId: 'user-4', handle: 'dev', displayName: 'Dev'),
  UserRef(userId: 'user-5', handle: 'arjun', displayName: 'Arjun'),
  UserRef(userId: 'user-6', handle: 'maya', displayName: 'Maya'),
];

final searchField = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Handle or exact email',
);

void main() {
  late FakeApiClient api;

  setUp(() {
    api =
        FakeApiClient(
            cases: [
              buildSummary(id: 'a1234', title: 'The Last Pizza Slice'),
              buildSummary(id: 'b1234', title: 'Reply Guy Of The Year'),
            ],
          )
          ..people = [_sam]
          ..courts = [
            const Court(
              id: 'court-1',
              name: 'The Brunch Crew With A Very Long Name Indeed',
              inviteCode: 'ABCD1234',
              ownerId: 'user-1',
              members: _crowd,
            ),
          ]
          ..shared = [
            const SharedCase(
              caseId: 'c1',
              title: 'Who Left The Group',
              category: 'group_chat',
              status: 'ready',
              role: 'juror',
              creatorName: 'Sam',
              linkKind: 'jury',
              token: 'tok123',
            ),
          ]
          ..feed = NotificationFeed(
            unread: 2,
            items: [
              const AppNotification(
                id: 'n1',
                kind: 'added_to_court',
                text: 'Sam added you to The Brunch Crew',
                createdAt: null,
                read: false,
              ),
            ],
          );
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

  group('responsive: no overflow on any main screen', () {
    const sizes = <String, Size>{
      'small phone 320x568': Size(320, 568),
      'phone 360x800': Size(360, 800),
      'phone landscape 800x360': Size(800, 360),
      'tablet 800x1280': Size(800, 1280),
      'tablet landscape 1280x800': Size(1280, 800),
      'desktop 1200x900': Size(1200, 900),
    };
    const routes = [
      '/',
      '/courts',
      '/courts/court-1',
      '/rap-sheet',
      '/settings',
      '/cases/new',
      '/notifications',
    ];

    for (final entry in sizes.entries) {
      testWidgets(entry.key, (tester) async {
        final router = await pumpApp(tester, entry.value);
        for (final route in routes) {
          router.go(route);
          await tester.pumpAndSettle();
          final error = tester.takeException();
          expect(error, isNull, reason: '$route at ${entry.key}: $error');
        }
      });
    }
  });

  group('navigation shell', () {
    testWidgets('phone gets a floating bar along the bottom', (tester) async {
      await pumpApp(tester, const Size(360, 800));
      expect(find.byTooltip('Courts'), findsOneWidget);
      expect(tester.getCenter(find.byTooltip('Courts')).dy, greaterThan(600));
    });

    testWidgets('content stops above the bar, never under it', (tester) async {
      await pumpApp(tester, const Size(360, 800));
      // The bar is a real bottomNavigationBar, so Scaffold lays the body out
      // above it. This pins that. It used to be a Stack overlay with a faked
      // MediaQuery inset, which only covered widgets that read the inset —
      // non-scrolling content and the FAB were clipped behind the pill.
      expect(
        tester.getRect(find.byType(RefreshIndicator)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('Courts')).top),
        reason: 'the docket must end above the nav pill',
      );
    });

    testWidgets('tablet gets a rail down the left edge', (tester) async {
      await pumpApp(tester, const Size(1000, 800));
      expect(
        tester.getCenter(find.byTooltip('Courts')).dx,
        lessThan(120),
        reason: 'rail runs down the left edge',
      );
    });

    testWidgets('content is held to a readable width on wide screens', (
      tester,
    ) async {
      await pumpApp(tester, const Size(1200, 900));
      final card = find.text('The Last Pizza Slice');
      expect(card, findsOneWidget);
      final box = tester.getRect(find.byType(ListView).first);
      expect(box.width, lessThanOrEqualTo(1000));
    });

    testWidgets('tabs switch screens', (tester) async {
      await pumpApp(tester, const Size(360, 800));
      await tester.tap(find.byTooltip('Courts'));
      await tester.pumpAndSettle();
      expect(find.text('Courts'), findsOneWidget);
    });

    testWidgets('the pill is built once, not once per screen', (tester) async {
      await pumpApp(tester, const Size(360, 800));
      expect(find.byType(CourtNavBar), findsOneWidget);

      // The same element, not an equal one: the shell keeps the bar mounted
      // across a tab change. When every screen drew its own, this came back
      // as a different element each time and the pill visibly blinked.
      final before = tester.element(find.byType(CourtNavBar));
      await tester.tap(find.byTooltip('Rap sheet'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Courts'));
      await tester.pumpAndSettle();

      expect(find.byType(CourtNavBar), findsOneWidget);
      expect(identical(tester.element(find.byType(CourtNavBar)), before), isTrue);
    });

    testWidgets('each tab keeps its own place', (tester) async {
      final router = await pumpApp(tester, const Size(360, 800));
      router.go('/courts/court-1');
      await tester.pumpAndSettle();
      expect(find.text('INVITE CODE'), findsOneWidget);

      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      expect(find.text('INVITE CODE'), findsNothing);

      // Back to Courts: still inside the court we opened, not reset to the
      // list. That is the whole point of a branch per tab.
      await tester.tap(find.byTooltip('Courts'));
      await tester.pumpAndSettle();
      expect(find.text('INVITE CODE'), findsOneWidget);
      expect(router.state.matchedLocation, '/courts/court-1');
    });

    testWidgets('a takeover screen covers the pill', (tester) async {
      final router = await pumpApp(tester, const Size(360, 800));
      expect(find.byType(CourtNavBar), findsOneWidget);

      // Filing, a case file and a ruling are full-screen on the canvas.
      router.push('/cases/new');
      await tester.pumpAndSettle();
      expect(find.byType(CourtNavBar), findsNothing);
    });
  });

  group('courts', () {
    testWidgets('lists my courts and opens one', (tester) async {
      final router = await pumpApp(tester, const Size(360, 800));
      router.go('/courts');
      await tester.pumpAndSettle();
      expect(find.textContaining('The Brunch Crew'), findsOneWidget);
      await tester.tap(find.textContaining('The Brunch Crew'));
      await tester.pumpAndSettle();
      expect(find.text('ABCD1234'), findsOneWidget);
      expect(find.text('@alex · owner · you'), findsOneWidget);
    });

    testWidgets('adds a friend by searching their handle', (tester) async {
      final router = await pumpApp(tester, const Size(360, 800));
      router.go('/courts/court-1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a friend'));
      await tester.pumpAndSettle();
      await tester.enterText(searchField, 'sa');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('@sam'));
      await tester.pumpAndSettle();

      expect(api.courts.first.members.map((m) => m.handle), [
        'alex',
        'priya',
        'dev',
        'arjun',
        'maya',
        'sam',
      ]);
      expect(find.text('Sam'), findsOneWidget);
    });

    testWidgets('create-case sends the chosen court and accused', (
      tester,
    ) async {
      final router = await pumpApp(tester, const Size(360, 1600));
      router.go('/cases/new?court=court-1');
      await tester.pumpAndSettle();

      // Addressed by what each box says: the canvas puts the accused above
      // the charge, so a positional index would point at the wrong one.
      Finder fieldWithHint(String hint) => find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == hint,
        ),
        matching: find.byType(TextFormField),
      );

      await tester.enterText(
        fieldWithHint('The Last Pizza Slice'),
        'The Last Pizza Slice',
      );
      await tester.enterText(
        fieldWithHint('State the crime. Be dramatic.'),
        'They ate the last slice right after saying they were full.',
      );
      await tester.ensureVisible(find.text('Search'));
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(searchField, 'sa');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('@sam'));
      await tester.pumpAndSettle();

      // Once the court can name the accused, the key names them too.
      await tester.ensureVisible(find.text('Sue Sam'));
      await tester.tap(find.text('Sue Sam'));
      await tester.pumpAndSettle();

      expect(api.lastCreate?['court_id'], 'court-1');
      expect(api.lastCreate?['accused_user_id'], 'user-2');
    });
  });

  group('shared cases and notifications', () {
    testWidgets('dashboard lists cases shared with me', (tester) async {
      await pumpApp(tester, const Size(360, 800));
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('JURY DUTY'), findsOneWidget);
      await tester.tap(find.text('Open the summons'));
      await tester.pumpAndSettle();
      expect(find.textContaining('/jury/tok123'), findsOneWidget);
    });

    testWidgets('the bell shows the unread count and opens the list', (
      tester,
    ) async {
      await pumpApp(tester, const Size(360, 800));
      // The bell draws its own badge rather than Material's.
      expect(find.text('2'), findsWidgets);
      await tester.tap(find.bySemanticsLabel('Notifications, 2 new').first);
      await tester.pumpAndSettle();
      expect(find.text('Sam added you to The Brunch Crew'), findsOneWidget);
      expect(api.readAllCalls, 1);
    });
  });
}
