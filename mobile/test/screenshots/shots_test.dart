// Renders real screens to PNG so layout can be compared with the design canvas.
//   flutter test test/screenshots --dart-define=SHOT_DIR=/some/dir
// It only writes files; nothing here is an assertion about pixels.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_chat_court/core/models.dart';
import 'package:group_chat_court/core/theme.dart';
import 'package:group_chat_court/core/widgets/court_chrome.dart';
import 'package:group_chat_court/core/widgets/sue_tablet.dart';
import 'package:group_chat_court/features/auth/data/auth_providers.dart';
import 'package:group_chat_court/features/cases/presentation/case_detail_screen.dart';
import 'package:group_chat_court/features/cases/presentation/create_case_screen.dart';
import 'package:group_chat_court/features/courts/presentation/courts_screen.dart';
import 'package:group_chat_court/features/verdicts/presentation/verdict_screen.dart';
import 'package:group_chat_court/features/feed/presentation/feed_screen.dart';
import 'package:group_chat_court/features/auth/presentation/sign_in_screen.dart';
import 'package:group_chat_court/features/records/presentation/rap_sheet_screen.dart';
import 'package:group_chat_court/features/game/presentation/profile_screen.dart';
import 'package:group_chat_court/features/invitations/presentation/defend_screen.dart';

import '../support/fakes.dart';

const _dir = String.fromEnvironment('SHOT_DIR', defaultValue: '/tmp/shots');

Future<void> _loadFont() async {
  final loader = FontLoader('Outfit')
    ..addFont(rootBundle.load('assets/fonts/Outfit.ttf'));
  await loader.load();
}

/// Every frame the canvas draws a screen at: the phone artboard, and the two
/// tablet ones. The rail replaces the bottom bar from 600 up, exactly as the
/// app does.
const _frames = <String, Size>{
  '': Size(430, 932),
  '_tabletp': Size(820, 1180),
  '_tabletl': Size(1180, 820),
};

/// One screen, in both modes, at each frame.
void _screen(
  String name,
  Widget Function() screen, {
  required FakeApiClient Function() api,
  CourtTab? tab,
}) {
  for (final frame in _frames.entries) {
    _shot(name + frame.key, screen, api: api, tab: tab, size: frame.value);
  }
}

void _shot(
  String name,
  Widget Function() screen, {
  required FakeApiClient Function() api,
  CourtTab? tab,
  Size size = const Size(430, 932),
}) {
  final rail = size.width >= 600;
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('$name $mode', (tester) async {
      // The test binding draws shadows as solid shapes unless told otherwise.
      final shadowsWere = debugDisableShadows;
      debugDisableShadows = false;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        harness(
          child: RepaintBoundary(
            key: const Key('shot'),
            child: ColoredBox(
              color: dark ? CourtColors.darkBg : CourtColors.lightBg,
              child: rail
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (tab != null)
                          SueNavRail(current: tab, onSelect: (_) {}),
                        Expanded(child: screen()),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: screen()),
                        if (tab != null)
                          CourtNavBar(current: tab, onSelect: (_) {}),
                      ],
                    ),
            ),
          ),
          overrides: [apiClientProvider.overrideWithValue(api())],
        ),
      );
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('shot')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(_dir).createSync(recursive: true);
        File(
          '$_dir/${name}_$mode.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      debugDisableShadows = shadowsWere;
    });
  }
}

void main() {
  setUpAll(_loadFont);

  _screen(
    'feed',
    () => const FeedScreen(),
    tab: CourtTab.home,
    api: () => FakeApiClient()
      ..cases = [
        buildSummary(
          id: 'a',
          title: 'Borrowed my hoodie in August. It is now October.',
        ),
        buildSummary(
          id: 'b',
          title: 'Left the last samosa and a note saying sorry',
        ),
      ]
      ..shared = const [
        SharedCase(
          caseId: 'c1',
          title: 'Owes me 450 rupees for pizza since the World Cup final',
          category: 'money',
          status: 'awaiting_defense',
          role: 'accused',
          creatorName: 'Priya',
          linkKind: 'invite',
          token: 't1',
        ),
      ],
  );

  _screen(
    'leaderboard',
    () => const RapSheetScreen(),
    tab: CourtTab.record,
    api: () => FakeApiClient()
      ..records = [
        buildRecord(
          id: '1',
          displayName: 'Priya',
          rank: 1,
          title: 'Kingpin',
          convictions: 7,
        ),
        buildRecord(
          id: '2',
          displayName: 'Dev',
          rank: 2,
          title: 'Known associate',
          convictions: 5,
        ),
        buildRecord(
          id: '3',
          displayName: 'Arjun',
          rank: 3,
          title: 'Flight risk',
          convictions: 4,
        ),
        buildRecord(
          id: '4',
          displayName: 'Maya',
          rank: 4,
          title: 'Suspect',
          convictions: 2,
          // The viewer, so the shot includes the "where you stand" band.
          isYou: true,
        ),
        buildRecord(
          id: '5',
          displayName: 'Sam',
          rank: 5,
          title: 'Clean record',
          convictions: 0,
        ),
      ],
  );

  const faces = [
    UserRef(userId: 'u1', handle: 'priya', displayName: 'Priya'),
    UserRef(userId: 'u2', handle: 'dev', displayName: 'Dev'),
    UserRef(userId: 'u3', handle: 'arjun', displayName: 'Arjun'),
    UserRef(userId: 'u4', handle: 'maya', displayName: 'Maya'),
    UserRef(userId: 'u5', handle: 'sam', displayName: 'Sam'),
  ];
  _screen(
    'courts',
    () => const CourtsScreen(),
    tab: CourtTab.courts,
    api: () => FakeApiClient()
      ..courts = const [
        Court(
          id: 'c1',
          name: 'The Flat 4B',
          inviteCode: 'AAAA1111',
          ownerId: 'user-1',
          members: faces,
        ),
        Court(
          id: 'c2',
          name: 'Office Lunch Crew',
          inviteCode: 'BBBB2222',
          ownerId: 'x',
          members: faces,
        ),
        Court(
          id: 'c3',
          name: "Goa Trip '25",
          inviteCode: 'CCCC3333',
          ownerId: 'x',
          members: faces,
        ),
        Court(
          id: 'c4',
          name: 'Family Group',
          inviteCode: 'DDDD4444',
          ownerId: 'x',
          members: faces,
        ),
      ],
  );

  _screen(
    'filecase',
    () => const CreateCaseScreen(),
    api: () => FakeApiClient()
      ..courts = const [
        Court(
          id: 'c1',
          name: 'The Flat 4B',
          inviteCode: 'A',
          ownerId: 'x',
          members: faces,
        ),
      ],
  );
  _screen(
    'case',
    () => const CaseDetailScreen(caseId: 'case-1'),
    api: () => FakeApiClient(
      detail: buildDetail(
        title: 'Borrowed my hoodie in August. It is now October.',
      ),
    ),
  );
  _screen(
    'verdict',
    () => const VerdictScreen(caseId: 'case-1'),
    api: () => FakeApiClient()
      ..verdict = const VerdictState(
        status: CaseStatus.completed,
        verdict: testVerdict,
      )
      ..rewards = const CaseRewards(
        totalXp: 50,
        totalCoins: 15,
        levelReached: 8,
        items: [
          Reward(
            kind: 'jury_first',
            detail: 'First juror to vote · 2×',
            xp: 50,
            coins: 5,
          ),
          Reward(
            kind: 'badge',
            detail: 'Hung jury',
            xp: 0,
            coins: 15,
            badgeCode: 'hung_jury',
            badgeName: 'Hung jury',
          ),
        ],
      ),
  );
  _screen('signin', () => const SignInScreen(), api: FakeApiClient.new);
  _screen(
    'profile',
    () => const ProfileScreen(),
    tab: CourtTab.settings,
    api: () => FakeApiClient()
      ..game = buildGameState(
        level: 7,
        xp: 6640,
        xpIntoLevel: 640,
        coins: 320,
        streakDays: 4,
        quests: [
          buildQuest(
            code: 'vote_jury',
            text: 'Vote on 2 jury cases',
            progress: 1,
            target: 2,
            xp: 30,
          ),
          buildQuest(),
          buildQuest(
            code: 'show_up',
            text: 'Open the app 1 day in a row',
            progress: 1,
            xp: 10,
            done: true,
          ),
        ],
        badges: [
          buildBadge(earned: true),
          buildBadge(
            code: 'first_win',
            name: 'First win',
            glyph: 'W',
            earned: true,
          ),
          buildBadge(
            code: 'hung_jury',
            name: 'Hung jury',
            glyph: '?',
            earned: true,
          ),
          buildBadge(code: 'clean_sweep', name: 'Clean sweep', glyph: '3'),
          buildBadge(code: 'kingpin', name: 'Kingpin', glyph: 'K'),
          buildBadge(code: 'overruled', name: 'Overruled', glyph: '!'),
          buildBadge(code: 'jury_duty', name: 'Jury duty', glyph: 'J'),
          buildBadge(code: 'oracle', name: 'Oracle', glyph: 'O'),
        ],
      ),
  );
  _screen(
    'defend',
    () => const DefendScreen(token: 'inv_abc12345'),
    api: () => FakeApiClient()
      ..invite = buildInvitePreview(
        caseTitle: 'Borrowed my hoodie in August. It is now October.',
        accusation:
            'It was "just for the bus ride". She has worn it to three '
            'parties. I have photos.',
        plaintiffName: 'Dev',
        defendantNickname: 'Maya',
        juryCount: 4,
      ),
  );
}
