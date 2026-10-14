import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/api_client.dart';
import 'package:group_chat_court/core/widgets/sue_widgets.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/game/presentation/profile_screen.dart';

import 'support/fakes.dart';

Future<FakeApiClient> pumpProfile(
  WidgetTester tester, {
  FakeApiClient? api,
  Size size = const Size(430, 1800),
}) async {
  final client = api ?? FakeApiClient();
  useMobileSurface(tester, size: size);

  await tester.pumpWidget(
    harness(
      child: const ProfileScreen(),
      overrides: [apiClientProvider.overrideWithValue(client)],
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

void main() {
  group('the player card', () {
    testWidgets('a player who has done nothing is shown zeros, not guesses', (
      tester,
    ) async {
      await pumpProfile(tester);

      // The opening balance is real; everything earned is still zero.
      expect(find.text('0'), findsWidgets);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('0 / 1000 XP'), findsOneWidget);
      expect(find.text('1000 XP to level 2'), findsOneWidget);
    });

    testWidgets('the level, XP and coins come from the server', (tester) async {
      await pumpProfile(
        tester,
        api: FakeApiClient()
          ..game = buildGameState(
            level: 7,
            xp: 6640,
            xpIntoLevel: 640,
            coins: 320,
            streakDays: 4,
          ),
      );

      expect(find.text('LV 7'), findsOneWidget);
      expect(find.text('640 / 1000 XP'), findsOneWidget);
      expect(find.text('360 XP to level 8'), findsOneWidget);
      expect(find.text('320'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('the XP bar reaches exactly as far as the level does', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        api: FakeApiClient()..game = buildGameState(xpIntoLevel: 250),
      );

      final ring = tester.widget<LevelRing>(find.byType(LevelRing));
      expect(ring.fraction, closeTo(0.25, 0.001));
    });
  });

  group('daily quests', () {
    testWidgets('are the ones the server opened, and no others', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        api: FakeApiClient()
          ..game = buildGameState(
            quests: [
              buildQuest(
                code: 'vote_jury',
                text: 'Vote on 2 jury cases',
                progress: 1,
                target: 2,
                xp: 30,
              ),
            ],
          ),
      );

      expect(find.text('Vote on 2 jury cases'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('+30 XP'), findsOneWidget);
      // Nothing the server did not send.
      expect(find.text('File a new case'), findsNothing);
    });

    testWidgets('a day with no quests says so rather than inventing any', (
      tester,
    ) async {
      await pumpProfile(tester);
      expect(find.text('No quests today.'), findsOneWidget);
    });

    testWidgets('a finished quest is struck through', (tester) async {
      await pumpProfile(
        tester,
        api: FakeApiClient()
          ..game = buildGameState(
            quests: [buildQuest(progress: 1, target: 1, done: true)],
          ),
      );

      final text = tester.widget<Text>(find.text('File a new case'));
      expect(text.style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('badges', () {
    testWidgets('show the whole catalogue, earned ones lit', (tester) async {
      await pumpProfile(
        tester,
        api: FakeApiClient()
          ..game = buildGameState(
            badges: [
              buildBadge(earned: true),
              buildBadge(code: 'kingpin', name: 'Kingpin', glyph: 'K'),
            ],
          ),
      );

      expect(find.text('First blood'), findsOneWidget);
      expect(find.text('Kingpin'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);

      final badges = tester
          .widgetList<HexBadge>(find.byType(HexBadge))
          .toList();
      expect(badges.map((b) => b.earned), [true, false]);
    });
  });

  group('when the server cannot be reached', () {
    testWidgets('the card says so and offers a retry', (tester) async {
      await pumpProfile(
        tester,
        api: FakeApiClient()
          ..gameError = ApiException(0, 'network_error', 'No courthouse.'),
      );

      expect(find.text('No courthouse.'), findsOneWidget);
    });
  });
}
