import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/courtroom.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/core/theme.dart';
import 'package:group_chat_court/core/widgets/court_people.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/cases/presentation/case_detail_screen.dart';
import 'package:group_chat_court/features/cases/presentation/courtroom_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

final _auth = {'kind': 'creator', 'case_id': 'case-1', 'token': 'jwt-secret'};

CourtroomController _room(FakeRooms rooms, {Map<String, dynamic>? auth}) =>
    CourtroomController(
      connector: rooms.connect,
      uri: courtroomUri('http://api.test'),
      auth: auth ?? _auth,
    );

void main() {
  late FakeRooms rooms;

  setUp(() => rooms = FakeRooms());

  group('connecting', () {
    test('authenticates in its first frame, so no token sits in the URL', () {
      final room = _room(rooms);
      addTearDown(room.dispose);

      expect(rooms.sent.first, {'type': 'auth', ..._auth});
      expect(rooms.uris.single.toString(), 'ws://api.test/api/v1/ws/room');
      expect(rooms.uris.single.toString(), isNot(contains('jwt-secret')));
    });

    test('uses wss for an https API', () {
      expect(
        courtroomUri('https://api.test/').toString(),
        'wss://api.test/api/v1/ws/room',
      );
    });

    test('opens nothing without a credential', () {
      final room = CourtroomController(
        connector: rooms.connect,
        uri: courtroomUri('http://api.test'),
        auth: null,
      );
      addTearDown(room.dispose);
      expect(rooms.connections, 0);
    });

    test('goes live on welcome and keeps history in the server\'s order', () {
      final room = _room(rooms);
      addTearDown(room.dispose);
      expect(room.state.conn, ConnState.connecting);

      rooms.welcome(messages: [chatJson(2), chatJson(1)]);

      expect(room.state.conn, ConnState.live);
      expect(room.state.seatRole, 'plaintiff');
      expect(room.state.messages.map((m) => m.n), [1, 2]);
    });

    test('tracks who is here and when the case moves on', () {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome();

      rooms.push({'type': 'presence', 'online': 4});
      rooms.push({'type': 'case', 'status': 'completed'});

      expect(room.state.online, 4);
      expect(room.state.caseStatus, CaseStatus.completed);
    });

    test('ignores junk instead of crashing', () {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome();

      rooms.controllers.last.local.sink.add('not json at all');
      rooms.controllers.last.local.sink.add(jsonEncode([1, 2, 3]));
      rooms.push({'type': 'something-new'});

      expect(room.state.conn, ConnState.live);
    });
  });

  group('a dead link', () {
    testWidgets('is final: it is not retried', (tester) async {
      final room = _room(rooms);
      addTearDown(room.dispose);

      rooms.push({
        'type': 'error',
        'code': 'invalid_link',
        'message': 'invalid',
      });
      await rooms.drop();
      await tester.pump(const Duration(seconds: 60));

      expect(room.state.conn, ConnState.refused);
      expect(rooms.connections, 1);
    });
  });

  group('a dropped connection', () {
    testWidgets('reconnects, and replayed history does not double the log', (
      tester,
    ) async {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome(messages: [chatJson(1), chatJson(2)]);

      await rooms.drop();
      expect(room.state.conn, ConnState.reconnecting);
      await tester.pump(const Duration(seconds: 1));
      expect(rooms.connections, 2);

      rooms.welcome(messages: [chatJson(1), chatJson(2), chatJson(3)]);
      expect(room.state.messages, hasLength(3));
      expect(room.state.conn, ConnState.live);
      // It authenticated again on the new connection.
      expect(rooms.sent.where((f) => f['type'] == 'auth'), hasLength(2));
    });

    testWidgets('backs off further each time it fails', (tester) async {
      final room = _room(rooms);
      addTearDown(room.dispose);

      await rooms.drop();
      await tester.pump(const Duration(milliseconds: 999));
      expect(rooms.connections, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(rooms.connections, 2);

      await rooms.drop();
      await tester.pump(const Duration(milliseconds: 1999));
      expect(rooms.connections, 2);
      await tester.pump(const Duration(milliseconds: 1));
      expect(rooms.connections, 3);
    });

    testWidgets('stops reconnecting once it is disposed', (tester) async {
      final room = _room(rooms);
      await rooms.drop();
      room.dispose();
      await tester.pump(const Duration(seconds: 30));
      expect(rooms.connections, 1);
    });
  });

  group('speaking', () {
    test('cannot say anything until the court has let you in', () {
      final room = _room(rooms);
      addTearDown(room.dispose);

      expect(room.say('hello'), isFalse);
      expect(room.objectNow(), isFalse);
      expect(rooms.sent.where((f) => f['type'] == 'say'), isEmpty);
    });

    test('sends say, object and hide frames once live', () {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome();

      expect(room.say('the aisle seat is a war crime'), isTrue);
      expect(room.objectNow(), isTrue);
      expect(room.hide('m1'), isTrue);

      expect(rooms.sent.skip(1), [
        {'type': 'say', 'body': 'the aisle seat is a war crime'},
        {'type': 'object'},
        {'type': 'hide', 'id': 'm1'},
      ]);
    });

    testWidgets('shows a refusal briefly, then lets it go', (tester) async {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome();

      rooms.push({'type': 'error', 'code': 'blocked', 'message': 'Not here.'});
      expect(room.state.notice, 'Not here.');
      await tester.pump(const Duration(seconds: 5));
      expect(room.state.notice, isNull);
    });
  });

  group('what arrives', () {
    test('puts a new message in position, whatever order it arrives in', () {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome(messages: [chatJson(1)]);

      rooms.push({'type': 'message', 'message': chatJson(3)});
      rooms.push({'type': 'message', 'message': chatJson(2)});

      expect(room.state.messages.map((m) => m.n), [1, 2, 3]);
    });

    test('removes a message the plaintiff cleared', () {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome(messages: [chatJson(1), chatJson(2)]);

      rooms.push({'type': 'hidden', 'id': 'm1'});
      expect(room.state.messages.map((m) => m.id), ['m2']);
    });
  });

  test('mergeMessages is idempotent and lets a later copy win', () {
    final a = ChatMessage.fromJson(chatJson(1, body: 'old'));
    final b = ChatMessage.fromJson(chatJson(1, body: 'new'));
    final c = ChatMessage.fromJson(chatJson(2));

    final merged = mergeMessages([c, a], [b]);
    expect(merged.map((m) => m.n), [1, 2]);
    expect(merged.first.body, 'new');
    expect(mergeMessages(merged, merged).length, 2);
  });

  // --- the panel -----------------------------------------------------------

  group('the courtroom panel', () {
    late FakeApiClient api;

    setUp(() => api = FakeApiClient());

    Future<void> pump(WidgetTester tester, {double height = 440}) async {
      useMobileSurface(tester);
      SharedPreferences.setMockInitialValues({
        'gcc.session':
            '{"access_token":"jwt-secret","user_id":"u","display_name":"Alex"}',
      });
      await tester.pumpWidget(
        harness(
          rooms: rooms,
          child: Scaffold(
            body: SingleChildScrollView(
              child: CourtroomPanel(caseId: 'case-1', height: height),
            ),
          ),
          overrides: [apiClientProvider.overrideWithValue(api)],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('connects as the plaintiff with the signed-in token', (
      tester,
    ) async {
      await pump(tester);
      expect(rooms.sent.first, {
        'type': 'auth',
        'kind': 'creator',
        'case_id': 'case-1',
        'token': 'jwt-secret',
      });
    });

    testWidgets('cannot send until the court lets you in', (tester) async {
      await pump(tester);
      expect(
        tester.widget<TextField>(find.byKey(const Key('chat-input'))).enabled,
        isFalse,
      );
      expect(find.text('Connecting…'), findsWidgets);
    });

    testWidgets('renders the trial: statements, judge, objections, chatter', (
      tester,
    ) async {
      // Tall enough to build every row: the log is lazy and follows the newest.
      await pump(tester, height: 2400);
      rooms.welcome(
        messages: [
          chatJson(
            1,
            kind: 'system',
            body: 'Court is now in session.',
            ref: 'system',
          ),
          chatJson(
            2,
            kind: 'plaintiff',
            author: 'Alex',
            ref: 'ref-me',
            body: 'They ate it.',
            meta: {'statement': 'opening'},
          ),
          chatJson(
            3,
            kind: 'defendant',
            author: 'Sam',
            ref: 'ref-def',
            body: 'It was abandoned.',
            meta: {'statement': 'defense'},
          ),
          chatJson(
            4,
            kind: 'judge',
            author: 'Judge Byte',
            ref: 'judge',
            body: 'Order in the court.',
          ),
          chatJson(5, author: 'Mia', ref: 'ref-mia', body: 'honestly guilty'),
          chatJson(
            6,
            author: 'Dev',
            ref: 'ref-dev',
            body: 'OBJECTION!',
            meta: {'objection': true},
          ),
          chatJson(
            7,
            kind: 'judge',
            author: 'Judge Byte',
            ref: 'judge',
            body: 'Overruled. Sit down.',
            meta: {'ruling': 'overruled', 'on': 'm6'},
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Court is now in session.'), findsOneWidget);
      expect(find.byKey(const Key('chat-statement-opening')), findsOneWidget);
      expect(find.byKey(const Key('chat-statement-defense')), findsOneWidget);
      expect(find.text('Order in the court.'), findsOneWidget);
      expect(find.text('honestly guilty'), findsOneWidget);
      expect(find.byKey(const Key('chat-objection')), findsOneWidget);
      expect(find.text('OVERRULED'), findsOneWidget);
      expect(
        find.text('1 here now').evaluate().isEmpty,
        isTrue,
      ); // no presence yet
    });

    testWidgets('sends what you type and clears the box', (tester) async {
      await pump(tester);
      rooms.welcome();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('chat-input')),
        '  that was about restaurants  ',
      );
      await tester.tap(find.byKey(const Key('chat-send')));
      await tester.pump();

      expect(rooms.sent.last, {
        'type': 'say',
        'body': 'that was about restaurants',
      });
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat-input')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('does not send an empty line', (tester) async {
      await pump(tester);
      rooms.welcome();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat-send')));
      await tester.pump();
      expect(rooms.sent.where((f) => f['type'] == 'say'), isEmpty);
    });

    testWidgets('sends an objection', (tester) async {
      await pump(tester);
      rooms.welcome();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Objection!'));
      await tester.pump();
      expect(rooms.sent.last, {'type': 'object'});
    });

    testWidgets('lets the plaintiff clear a juror\'s line, and only that', (
      tester,
    ) async {
      await pump(tester);
      rooms.welcome(
        messages: [
          chatJson(
            1,
            kind: 'plaintiff',
            author: 'Alex',
            ref: 'ref-me',
            meta: {'statement': 'opening'},
          ),
          chatJson(2, kind: 'judge', author: 'Judge Byte', ref: 'judge'),
          chatJson(3, author: 'Mia', ref: 'ref-mia', body: 'rude'),
        ],
      );
      await tester.pumpAndSettle();

      // Exactly one thing on this screen can be cleared: the juror's line.
      expect(find.text('clear'), findsOneWidget);
      await tester.tap(find.text('clear'));
      await tester.pump();
      expect(rooms.sent.last, {'type': 'hide', 'id': 'm3'});

      rooms.push({'type': 'hidden', 'id': 'm3'});
      await tester.pumpAndSettle();
      expect(find.text('rude'), findsNothing);
    });

    testWidgets('lets you mute a person, but never the judge', (tester) async {
      await pump(tester);
      rooms.welcome(
        messages: [
          chatJson(1, author: 'Mia', ref: 'ref-mia', body: 'annoying thing'),
          chatJson(
            2,
            kind: 'judge',
            author: 'Judge Byte',
            ref: 'judge',
            body: 'Order.',
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('mute'));
      await tester.pumpAndSettle();

      expect(find.text('annoying thing'), findsNothing);
      expect(find.text('Order.'), findsOneWidget);
    });

    testWidgets('shows a refusal under the composer', (tester) async {
      await pump(tester);
      rooms.welcome();
      await tester.pumpAndSettle();

      rooms.push({
        'type': 'error',
        'code': 'slow_down',
        'message': 'Slow down.',
      });
      await tester.pump();
      expect(find.byKey(const Key('chat-notice')), findsOneWidget);
      expect(find.text('Slow down.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('says plainly when the courtroom is closed', (tester) async {
      await pump(tester);
      rooms.push({
        'type': 'error',
        'code': 'invalid_link',
        'message': 'invalid',
      });
      await tester.pumpAndSettle();
      expect(find.text('The courtroom is closed'), findsOneWidget);
    });

    testWidgets('marks your own lines as yours (no name above them)', (
      tester,
    ) async {
      await pump(tester);
      rooms.welcome(
        messages: [
          chatJson(1, author: 'Alex', ref: 'ref-me', body: 'mine'),
          chatJson(2, author: 'Mia', ref: 'ref-mia', body: 'theirs'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Mia'), findsOneWidget);
      expect(find.text('Alex'), findsNothing);
    });
  });

  group('on the case file', () {
    testWidgets(
      'sits on the case file and refreshes it when the room reports a change',
      (tester) async {
        final api = FakeApiClient()
          ..detail = buildDetail(status: CaseStatus.awaitingDefense);
        useMobileSurface(tester);
        SharedPreferences.setMockInitialValues({
          'gcc.session':
              '{"access_token":"jwt-secret","user_id":"u","display_name":"Alex"}',
        });
        await tester.pumpWidget(
          harness(
            rooms: rooms,
            child: const CaseDetailScreen(caseId: 'case-1'),
            overrides: [apiClientProvider.overrideWithValue(api)],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CourtroomPanel), findsOneWidget);
        final before = api.detailCalls;

        rooms.welcome();
        rooms.push({'type': 'case', 'status': 'ready'});
        await tester.pumpAndSettle();

        expect(api.detailCalls, greaterThan(before));
      },
    );
  });

  group('the jury box', () {
    final seats = [
      {'ref': 'r1', 'name': 'Alex', 'role': 'plaintiff', 'voted': false},
      {'ref': 'r2', 'name': 'Priya', 'role': 'defendant', 'voted': false},
      {'ref': 'r3', 'name': 'Dev', 'role': 'juror', 'voted': true},
      {'ref': 'r4', 'name': 'Mia', 'role': 'juror', 'voted': false},
    ];

    test('follows people in and out, in the server\'s order', () {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome();

      rooms.push({'type': 'roster', 'seats': seats});
      expect(room.state.roster.map((s) => s.name), [
        'Alex',
        'Priya',
        'Dev',
        'Mia',
      ]);

      rooms.push({'type': 'roster', 'seats': seats.take(2).toList()});
      expect(room.state.roster, hasLength(2));
    });

    test('carries who has voted and nothing about which way', () {
      final room = _room(rooms);
      addTearDown(room.dispose);
      rooms.welcome();
      rooms.push({'type': 'roster', 'seats': seats});

      expect(room.state.roster.where((s) => s.voted).map((s) => s.name), [
        'Dev',
      ]);
    });

    testWidgets('shows everyone, with a role under each name', (tester) async {
      useMobileSurface(tester);
      await tester.pumpWidget(
        harness(
          child: Scaffold(
            body: JuryStrip(
              seats: [for (final s in seats) RosterSeat.fromJson(s)],
            ),
          ),
          overrides: const [],
        ),
      );

      expect(find.byKey(const Key('jury-box')), findsOneWidget);
      for (final name in ['Alex', 'Priya', 'Dev', 'Mia']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Plaintiff'), findsOneWidget);
      expect(find.text('Defense'), findsOneWidget);
      expect(find.text('Voted'), findsOneWidget);
    });

    testWidgets('is absent until the room has said who is here', (
      tester,
    ) async {
      useMobileSurface(tester);
      await tester.pumpWidget(
        harness(
          child: const Scaffold(body: JuryStrip(seats: [])),
          overrides: const [],
        ),
      );
      expect(find.byKey(const Key('jury-box')), findsNothing);
    });
  });

  group('the parties', () {
    testWidgets('introduces both sides and whether the accused has answered', (
      tester,
    ) async {
      useMobileSurface(tester);
      Widget build(bool defended) => harness(
        child: Scaffold(
          body: PartyTrays(
            plaintiff: 'Alex',
            defendant: 'Priya',
            defended: defended,
          ),
        ),
        overrides: const [],
      );

      await tester.pumpWidget(build(false));
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Awaiting a defense'), findsOneWidget);

      await tester.pumpWidget(build(true));
      expect(find.text('Has answered'), findsOneWidget);
    });
  });

  test('a person keeps one colour wherever they appear', () {
    expect(tintFor('Priya'), tintFor('Priya'));
    expect(CourtColors.tints, contains(tintFor('Priya')));
  });
}
