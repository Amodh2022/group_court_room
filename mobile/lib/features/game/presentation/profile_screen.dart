import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/widgets/sue_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../cases/data/case_providers.dart';
import '../../courts/data/court_providers.dart';
import '../data/game_providers.dart';

/// Home for the player, drawn to the "Dashboard" artboard: the player card
/// with the level ring and the day's numbers, the case that wants answering,
/// today's quests, and the badge wall.
///
/// Every number here is the server's. A player who has done nothing sees
/// zeros and empty rings, which is the honest version of this screen.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameStateProvider);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final shared = ref.watch(sharedCasesProvider).valueOrNull ?? const [];
    final boss = shared.where((s) => s.linkKind != 'jury').toList();

    final gear = RoundIconButton(
      glyph: CourtGlyph.key,
      label: 'Settings',
      onTap: () => context.push('/settings'),
    );

    Widget body(GameState state) => _Body(
      state: state,
      boss: boss,
      onRefresh: () async {
        ref.invalidate(gameStateProvider);
        await ref.read(gameStateProvider.future);
      },
    );

    return CourtScaffold(
      title: 'Profile',
      maxWidth: 640,
      tablet: SueTabletPage(
        header: SueTabletHeader(
          title: session == null ? 'Profile' : 'Hi, ${session.displayName}',
          subtitle: game.valueOrNull == null
              ? null
              : _streakLine(game.value!.player),
          trailing: gear,
        ),
        child: game.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => CourtErrorView(
            message: e is ApiException
                ? e.message
                : 'Could not load your card.',
            onRetry: () => ref.invalidate(gameStateProvider),
          ),
          data: (state) => ListView(
            padding: EdgeInsets.zero,
            children: [
              SueColumns(
                start: [
                  _PlayerCard(player: state.player),
                  _BadgeWall(badges: state.badges),
                ],
                end: [
                  for (final item in boss) _BossCase(item: item),
                  _Quests(quests: state.quests),
                ],
              ),
            ],
          ),
        ),
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                session == null ? 'Profile' : 'Hi, ${session.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
            ),
            gear,
          ],
        ),
      ),
      body: game.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => CourtErrorView(
          message: e is ApiException ? e.message : 'Could not load your card.',
          onRetry: () => ref.invalidate(gameStateProvider),
        ),
        data: body,
      ),
    );
  }

  static String _streakLine(Player p) =>
      p.streakDays == 0 ? 'No streak yet' : '${p.streakDays}-day streak';
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.boss,
    required this.onRefresh,
  });

  final GameState state;
  final List<SharedCase> boss;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, courtNavBottomInset),
      children: [
        _PlayerCard(player: state.player),
        const SizedBox(height: 14),
        for (final item in boss) ...[
          _BossCase(item: item),
          const SizedBox(height: 14),
        ],
        _Quests(quests: state.quests),
        const SizedBox(height: 14),
        _BadgeWall(badges: state.badges),
      ],
    ),
  );
}

/// The card at the top: who you are, how far through this level, and the three
/// numbers the day turns on.
class _PlayerCard extends ConsumerWidget {
  const _PlayerCard({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(courtsProvider).valueOrNull ?? const <Court>[];
    final sheet = ref.watch(rapSheetProvider).valueOrNull;
    final me = ref.watch(authControllerProvider).valueOrNull;
    final entry = me == null || sheet == null
        ? null
        : sheet.where((r) => r.id == me.userId).firstOrNull;

    // The line under the name is only drawn from a record that exists. With no
    // standing yet it says so rather than inventing a rank.
    final standing = entry == null
        ? (courts.isEmpty
              ? 'No court yet'
              : 'No record in ${courts.first.name}')
        : '${entry.title}'
              '${courts.isEmpty ? '' : ' · #${entry.rank} in ${courts.first.name}'}';

    return SueCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LevelRing(
                name: player.displayName,
                level: player.level,
                fraction: player.levelFraction,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      standing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.inkDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  '${player.xpIntoLevel} / ${player.xpPerLevel} XP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${player.xpToNextLevel} XP to level ${player.level + 1}',
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.inkDim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _XpBar(fraction: player.levelFraction),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SueStatTile(
                  value: '${player.streakDays}',
                  label: 'day streak',
                  tone: SueTone.orange,
                  icon: const CourtIcon(
                    CourtGlyph.flame,
                    size: 18,
                    color: CourtColors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SueStatTile(
                  value: '${player.coins}',
                  label: 'coins',
                  tone: SueTone.gold,
                  icon: const SueCoin(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SueStatTile(
                  value: '${player.badgesEarned}/${player.badgesTotal}',
                  label: 'badges',
                  tone: SueTone.teal,
                  icon: Icon(
                    Icons.shield,
                    size: 16,
                    color: SueTone.teal.fg(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The artboard's gradient XP bar.
class _XpBar extends StatelessWidget {
  const _XpBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: SizedBox(
      height: 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.palette.surfaceAlt),
          // heightFactor as well as widthFactor: in a stack the fill would
          // otherwise lay out at zero height and never be seen.
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0, 1),
            heightFactor: 1,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [CourtColors.blue, CourtColors.blueSoft],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// "BOSS CASE": somebody is suing you and the clock is running.
class _BossCase extends StatelessWidget {
  const _BossCase({required this.item});

  final SharedCase item;

  @override
  Widget build(BuildContext context) => Material(
    color: CourtColors.red,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => context.push(item.path),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BOSS CASE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Colors.white.withValues(alpha: .85),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.creatorName.isEmpty ? 'Someone' : item.creatorName} is suing you',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: .9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'DEFEND',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: CourtColors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Today's quests. The list the server opened this morning — never a list the
/// app made up, so a quest that is not offered today is simply not here.
class _Quests extends StatelessWidget {
  const _Quests({required this.quests});

  final List<Quest> quests;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Expanded(
            child: Text(
              'Daily quests',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            quests.isEmpty
                ? ''
                : quests.every((q) => q.done)
                ? 'All done today'
                : '${quests.where((q) => q.done).length}/${quests.length} done',
            style: TextStyle(fontSize: 12, color: context.palette.inkDim),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (quests.isEmpty)
        SueCard(
          small: true,
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: Text(
            'No quests today.',
            style: TextStyle(fontSize: 14, color: context.palette.inkDim),
          ),
        )
      else
        for (final q in quests) ...[
          _QuestRow(quest: q),
          if (q != quests.last) const SizedBox(height: 10),
        ],
    ],
  );
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.quest});

  final Quest quest;

  @override
  Widget build(BuildContext context) {
    final done = quest.done;
    final teal = SueTone.teal.fg(context);
    return SueCard(
      small: true,
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? teal : Colors.transparent,
              border: done
                  ? null
                  : Border.all(color: context.palette.inkFaint, width: 2),
            ),
            child: done
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quest.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? context.palette.inkDim : null,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: quest.fraction,
                          minHeight: 6,
                          backgroundColor: context.palette.surfaceAlt,
                          valueColor: AlwaysStoppedAnimation(
                            done ? teal : context.palette.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${quest.progress}/${quest.target}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.palette.inkDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SuePill('+${quest.xp} XP', tone: SueTone.blue, round: false),
        ],
      ),
    );
  }
}

/// Every badge in the catalogue, earned ones lit.
class _BadgeWall extends StatelessWidget {
  const _BadgeWall({required this.badges});

  final List<GameBadge> badges;

  static const _tones = [
    SueTone.orange,
    SueTone.blue,
    SueTone.teal,
    SueTone.gold,
  ];

  @override
  Widget build(BuildContext context) {
    final earned = badges.where((b) => b.earned).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Badges',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$earned of ${badges.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.palette.inkDim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            // Four across on a phone, more as the column widens.
            final columns = (c.maxWidth / 86).floor().clamp(3, 6);
            return Wrap(
              spacing: 10,
              runSpacing: 14,
              children: [
                for (var i = 0; i < badges.length; i++)
                  SizedBox(
                    width: (c.maxWidth - (columns - 1) * 10) / columns,
                    child: Tooltip(
                      message: badges[i].hint,
                      child: HexBadge(
                        glyph: badges[i].glyph,
                        label: badges[i].name,
                        earned: badges[i].earned,
                        tone: _tones[i % _tones.length],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
