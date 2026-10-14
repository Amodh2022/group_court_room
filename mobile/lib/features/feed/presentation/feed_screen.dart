import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/widgets/sue_widgets.dart';
import '../../../core/widgets/court_layout.dart';
import '../../auth/data/auth_providers.dart';
import '../../cases/data/case_providers.dart';
import '../../courts/data/court_providers.dart';

/// Home, drawn to the "Feed" artboard: the app name and court switcher, a row
/// of live cases, three tabs, and a scroll of case cards.
///
/// Only real data is shown. "My courts" is built from the account's own cases
/// and the cases it was summoned to; Nearby and Trending say so until the
/// server can rank them.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  int _tab = 0;

  Future<void> _refresh() async {
    ref.invalidate(sharedCasesProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(casesProvider);
    await ref.read(casesProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final cases = ref.watch(casesProvider);
    final shared = ref.watch(sharedCasesProvider).valueOrNull ?? const [];
    final unread = ref.watch(notificationsProvider).valueOrNull?.unread ?? 0;
    final courts = ref.watch(courtsProvider).valueOrNull ?? const [];

    final bell = RoundIconButton(
      glyph: CourtGlyph.bell,
      label: unread > 0 ? 'Notifications, $unread new' : 'Notifications',
      badge: unread,
      onTap: () => context.push('/notifications'),
    );

    return CourtScaffold(
      title: 'Sue Me',
      maxWidth: 640,
      tablet: _TabletFeed(
        cases: cases,
        shared: shared,
        courts: courts,
        bell: bell,
        tab: _tab,
        onTab: (i) => setState(() => _tab = i),
        onRefresh: _refresh,
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
        child: Row(
          children: [
            const Text(
              'Sue Me',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: courts.isEmpty
                    ? const SizedBox.shrink()
                    : _CourtChip(
                        name: courts.first.name,
                        onTap: () => context.go('/courts'),
                      ),
              ),
            ),
            bell,
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: cases.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * .6,
                child: CourtErrorView(
                  message: error is ApiException
                      ? error.message
                      : 'Could not load the feed.',
                  onRetry: () => ref.invalidate(casesProvider),
                ),
              ),
            ],
          ),
          data: (mine) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, courtNavBottomInset),
            children: [
              _Stories(mine: mine, shared: shared),
              const SizedBox(height: 10),
              SueTabs(
                labels: const ['My courts', 'Nearby', 'Trending'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 14),
              if (_tab != 0)
                _SoonCard(
                  title: _tab == 1 ? 'Nearby is coming' : 'Trending is coming',
                  body: _tab == 1
                      ? 'Public cases from people close to you will show up here once you opt in to location.'
                      : 'The cases everyone is voting on will show up here.',
                )
              else ...[
                for (final s in shared)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: s.linkKind == 'jury'
                        ? _JuryCard(item: s)
                        : _SuedCard(item: s),
                  ),
                for (final c in mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _MyCaseCard(summary: c),
                  ),
                if (mine.isEmpty && shared.isEmpty)
                  const _SoonCard(
                    title: 'Nothing on the docket',
                    body:
                        'File a case with the + button, or join a court to see its cases here.',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CourtChip extends StatelessWidget {
  const _CourtChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Switch court',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          boxShadow: courtHardShadow(context, dy: 4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: SueTone.teal.fg(context),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const CourtIcon(CourtGlyph.chevronDown, size: 12, strokeWidth: 3),
          ],
        ),
      ),
    ),
  );
}

/// The row under the header: "Add clip" plus every case that is live now.
class _Stories extends StatelessWidget {
  const _Stories({required this.mine, required this.shared});

  final List<CaseSummary> mine;
  final List<SharedCase> shared;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      AddStory(label: 'File case', onTap: () => context.push('/cases/new')),
      for (final s in shared)
        StoryRing(
          label: _short(s.title),
          initial: s.creatorName.isEmpty ? '?' : s.creatorName[0].toUpperCase(),
          live: true,
          tone: toneFor(s.creatorName),
          onTap: () => context.push(s.path),
        ),
      for (final c
          in mine
              .where(
                (c) =>
                    c.status != CaseStatus.completed &&
                    c.status != CaseStatus.expired,
              )
              .take(6))
        StoryRing(
          label: _short(c.title),
          initial: c.title.isEmpty ? '?' : c.title[0].toUpperCase(),
          live: c.status == CaseStatus.awaitingDefense,
          tone: toneFor(c.title),
          onTap: () => context.push('/cases/${c.id}'),
        ),
    ];
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => items[i],
      ),
    );
  }

  static String _short(String t) =>
      t.length <= 10 ? t : '${t.substring(0, 9)}…';
}

class _SoonCard extends StatelessWidget {
  const _SoonCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => SueCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: context.palette.inkDim,
          ),
        ),
      ],
    ),
  );
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// A case I filed.
class _MyCaseCard extends StatelessWidget {
  const _MyCaseCard({required this.summary});

  final CaseSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = summary;
    final accused = c.defendantNickname ?? 'Unnamed';
    final (pill, tone) = switch (c.status) {
      CaseStatus.awaitingDefense => ('AWAITING DEFENCE', SueTone.orange),
      CaseStatus.generating => ('DELIBERATING', SueTone.blue),
      CaseStatus.completed => ('RULED', SueTone.teal),
      CaseStatus.ready => ('READY', SueTone.blue),
      CaseStatus.failed => ('FAILED', SueTone.orange),
      CaseStatus.expired => ('EXPIRED', SueTone.gray),
      CaseStatus.draft => ('DRAFT', SueTone.gray),
    };
    return SueCard(
      onTap: () => context.push(
        c.verdictReady ? '/cases/${c.id}/verdict' : '/cases/${c.id}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SuePair(a: 'You', b: accused),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You v. $accused',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _ago(c.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.inkDim,
                      ),
                    ),
                  ],
                ),
              ),
              SuePill(
                pill,
                tone: tone,
                round: c.status != CaseStatus.completed,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            c.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (c.juryCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${c.juryCount} on the jury',
              style: TextStyle(fontSize: 12, color: context.palette.inkDim),
            ),
          ],
        ],
      ),
    );
  }
}

/// Somebody is suing me: the boss-case card.
class _SuedCard extends StatelessWidget {
  const _SuedCard({required this.item});

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

/// A case I have been summoned to judge: live tally and two vote buttons.
class _JuryCard extends ConsumerStatefulWidget {
  const _JuryCard({required this.item});

  final SharedCase item;

  @override
  ConsumerState<_JuryCard> createState() => _JuryCardState();
}

class _JuryCardState extends ConsumerState<_JuryCard> {
  bool _busy = false;

  Future<void> _vote(String vote) async {
    setState(() => _busy = true);
    try {
      await ref.read(juryVoteProvider)(widget.item.token, vote);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final room = ref.watch(juryRoomProvider(item.token)).valueOrNull;
    final tally = room?.tally;
    final open = room?.juryOpen ?? true;
    final voted = room?.hasVoted ?? false;
    final plaintiff = room?.plaintiffName.isNotEmpty == true
        ? room!.plaintiffName
        : item.creatorName;
    final defendant = room?.defendantName ?? '';
    return SueCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SuePair(a: plaintiff, b: defendant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      defendant.isEmpty
                          ? plaintiff
                          : '$plaintiff v. $defendant',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'You are on the jury',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.inkDim,
                      ),
                    ),
                  ],
                ),
              ),
              if (open) const SuePill('JURY LIVE', dot: true),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (tally != null) ...[
            const SizedBox(height: 14),
            VoteBar(guilty: tally.guilty, notGuilty: tally.notGuilty),
          ],
          if (!voted && open) ...[
            const SizedBox(height: 14),
            const _JuryStake(),
          ],
          const SizedBox(height: 14),
          if (voted)
            Text(
              'You voted ${room!.yourVote == 'guilty' ? 'guilty' : 'not guilty'}.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.inkDim,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: SueButton(
                    label: 'GUILTY',
                    tone: SueTone.orange,
                    busy: _busy,
                    onPressed: open ? () => _vote('guilty') : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SueButton(
                    label: 'NOT GUILTY',
                    tone: SueTone.teal,
                    busy: _busy,
                    onPressed: open ? () => _vote('not_guilty') : null,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Home as the tablet artboards draw it: the court's name across the top, the
/// three feed tabs and the case cards down the main column, and — once the
/// window is wide enough — a side panel carrying where you stand, the cases
/// running right now, and anything you have been summoned to answer.
///
/// The cards are the phone's own; only the frame changes.
class _TabletFeed extends ConsumerWidget {
  const _TabletFeed({
    required this.cases,
    required this.shared,
    required this.courts,
    required this.bell,
    required this.tab,
    required this.onTab,
    required this.onRefresh,
  });

  final AsyncValue<List<CaseSummary>> cases;
  final List<SharedCase> shared;
  final List<Court> courts;
  final Widget bell;
  final int tab;
  final ValueChanged<int> onTab;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = cases.valueOrNull ?? const <CaseSummary>[];
    final boss = shared.where((s) => s.linkKind != 'jury').toList();
    final jury = shared.where((s) => s.linkKind == 'jury').toList();
    final live = mine
        .where(
          (c) =>
              c.status != CaseStatus.completed &&
              c.status != CaseStatus.expired,
        )
        .toList();

    // Below the aside breakpoint SueTabletPage drops the panel, so the boss
    // cards have to stay in the main column or they would vanish.
    final panelled = context.hasAside;

    return SueTabletPage(
      header: SueTabletHeader(
        title: courts.isEmpty ? 'Sue Me' : courts.first.name,
        subtitle: courts.isEmpty ? null : 'Sue Me',
        trailing: bell,
      ),
      aside: [
        const _PositionPanel(),
        if (live.isNotEmpty || jury.isNotEmpty)
          _LivePanel(mine: live, jury: jury),
        for (final item in boss) _SuedCard(item: item),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SueTabs(
            labels: const ['My courts', 'Nearby', 'Trending'],
            index: tab,
            onChanged: onTab,
          ),
          const SizedBox(height: sueGutter),
          Expanded(
            child: cases.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => CourtErrorView(
                message: error is ApiException
                    ? error.message
                    : 'Could not load the feed.',
                onRetry: () => ref.invalidate(casesProvider),
              ),
              data: (mine) => RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (tab != 0)
                      _SoonCard(
                        title: tab == 1
                            ? 'Nearby is coming'
                            : 'Trending is coming',
                        body: tab == 1
                            ? 'Public cases from people close to you will show up here once you opt in to location.'
                            : 'The cases everyone is voting on will show up here.',
                      )
                    else ...[
                      if (!panelled)
                        for (final item in boss)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _SuedCard(item: item),
                          ),
                      for (final s in jury)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _JuryCard(item: s),
                        ),
                      for (final c in mine)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _MyCaseCard(summary: c),
                        ),
                      if (mine.isEmpty && shared.isEmpty)
                        const _SoonCard(
                          title: 'Nothing on the docket',
                          body:
                              'File a case with the + button, or join a court to see its cases here.',
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "YOUR POSITION": your rank in the court's own record. Nothing is shown
/// until the rap sheet names you.
class _PositionPanel extends ConsumerWidget {
  const _PositionPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final rows = ref.watch(rapSheetProvider).valueOrNull ?? const [];
    final index = me == null ? -1 : rows.indexWhere((r) => r.id == me.userId);
    if (index < 0) return const SizedBox.shrink();
    final mine = rows[index];
    final above = index > 0 ? rows[index - 1] : null;

    return SueCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SueSectionLabel('YOUR POSITION'),
          const SizedBox(height: 8),
          Text(
            '#${mine.rank} · ${mine.title}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            above == null
                ? 'Top of the sheet.'
                : 'Behind ${above.displayName} by '
                      '${above.convictions - mine.convictions} guilty',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: context.palette.inkDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// "LIVE CASES": everything still open, as a short list you can tap into.
class _LivePanel extends StatelessWidget {
  const _LivePanel({required this.mine, required this.jury});

  final List<CaseSummary> mine;
  final List<SharedCase> jury;

  @override
  Widget build(BuildContext context) => SueCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SueSectionLabel('LIVE CASES'),
        const SizedBox(height: 10),
        for (final s in jury.take(4))
          _LiveRow(
            name: s.creatorName,
            title: s.title,
            onTap: () => context.push(s.path),
          ),
        for (final c in mine.take(4))
          _LiveRow(
            name: c.defendantNickname ?? c.title,
            title: c.title,
            onTap: () => context.push('/cases/${c.id}'),
          ),
      ],
    ),
  );
}

class _LiveRow extends StatelessWidget {
  const _LiveRow({
    required this.name,
    required this.title,
    required this.onTap,
  });

  final String name;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SueAvatar(name: name, size: 30, fontSize: 12),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

/// "Call it like the judge": what a juror is playing for.
///
/// The numbers are the server's own rules, quoted so a juror knows the stake
/// before they commit. Nothing is credited here — the payout happens when the
/// judge rules, and only if they called it right.
class _JuryStake extends StatelessWidget {
  const _JuryStake();

  /// Kept in step with the server's jury rules.
  static const correctXp = 25;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: SueTone.gold.tint(context),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const SueCoin(size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Call it like the judge',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Match the final ruling for '),
                    TextSpan(
                      text: '+$correctXp XP',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.colors.onSurface,
                      ),
                    ),
                    const TextSpan(text: '. First to vote gets 2×.'),
                  ],
                ),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: context.palette.inkDim,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
