import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../cases/data/case_providers.dart';

/// Standings in this court. The reason case #5 is funnier than case #1.
///
/// Drawn to the "Rap sheet" artboard: a lit stage with the top three on
/// plinths, then everyone else as a plain list with their record as a bar.
class RapSheetScreen extends ConsumerWidget {
  const RapSheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheet = ref.watch(rapSheetProvider);
    final rows = sheet.valueOrNull ?? const <RapSheetEntry>[];
    final cases = rows.fold<int>(0, (n, r) => n + r.casesTotal);

    return CourtScaffold(
      title: 'Rap sheet',
      header: ScreenHeader(
        title: 'Rap Sheet',
        eyebrowWidget: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CourtColors.greenFill,
                border: Border.all(color: context.palette.border, width: 2),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'EVERY COURT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: context.palette.inkDim,
                ),
              ),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        trailing: [
          if (rows.isNotEmpty)
            CourtPill(
              label: '$cases ${cases == 1 ? 'case' : 'cases'}',
              glyph: CourtGlyph.doc,
              raised: true,
              fontSize: 14,
            ),
          RoundIconButton(
            glyph: CourtGlyph.share,
            label: 'Share rap sheet',
            onTap: rows.isEmpty ? null : () => _share(rows),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(rapSheetProvider.future),
        child: sheet.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, courtNavBottomInset),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => CourtSkeleton(height: i == 0 ? 240 : 68),
          ),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: CourtErrorView(
                  message: error is ApiException
                      ? error.message
                      : 'Could not pull the records.',
                  onRetry: () => ref.invalidate(rapSheetProvider),
                ),
              ),
            ],
          ),
          data: (rows) => rows.isEmpty
              ? ListView(
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.6,
                      child: CourtNotice(
                        icon: Icons.folder_open,
                        title: 'No convictions yet',
                        message:
                            'Suspiciously clean, this group. Every verdict '
                            'the court hands down lands on somebody\'s record.',
                        action: CourtKey(
                          label: 'File a case',
                          glyph: CourtGlyph.gavel,
                          onPressed: () => context.push('/cases/new'),
                        ),
                      ),
                    ),
                  ],
                )
              : _Sheet(rows: rows),
        ),
      ),
    );
  }

  void _share(List<RapSheetEntry> rows) {
    final lines = rows
        .take(5)
        .map((r) => '#${r.rank} ${r.displayName} — ${r.convictions} guilty')
        .join('\n');
    SharePlus.instance.share(
      ShareParams(
        text: 'The rap sheet so far:\n$lines',
        subject: 'Sue Me — the rap sheet',
      ),
    );
  }
}

class _Sheet extends ConsumerWidget {
  const _Sheet({required this.rows});

  final List<RapSheetEntry> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull?.userId;
    final rest = rows.length > 3 ? rows.sublist(3) : const <RapSheetEntry>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, courtNavBottomInset),
      children: [
        _MostWanted(rows: rows),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 16),
          _EveryoneElse(rows: rows, rest: rest, me: me),
        ],
        const SizedBox(height: 16),
        const _Legend(),
      ],
    );
  }
}

/// The lit stage: the top three on plinths, and three numbers under them.
class _MostWanted extends StatelessWidget {
  const _MostWanted({required this.rows});

  final List<RapSheetEntry> rows;

  @override
  Widget build(BuildContext context) {
    final top = rows.take(3).toList();
    // Second, first, third — so the tallest plinth is centred.
    const arrangement = [1, 0, 2];
    const spec = [
      _PlinthSpec(
        block: 78,
        avatar: 58,
        name: 16,
        rank: 30,
        color: CourtColors.pink,
      ),
      _PlinthSpec(
        block: 112,
        avatar: 86,
        name: 20,
        rank: 40,
        color: CourtColors.yellow,
      ),
      _PlinthSpec(
        block: 58,
        avatar: 58,
        name: 16,
        rank: 30,
        color: CourtColors.blue,
        onColor: Colors.white,
      ),
    ];

    final tried = rows.fold<int>(0, (n, r) => n + r.casesTotal);
    final guilty = rows.fold<int>(0, (n, r) => n + r.convictions);
    final streak = rows.fold<int>(
      0,
      (n, r) => r.longestStreak > n ? r.longestStreak : n,
    );
    final rate = tried == 0 ? 0 : (guilty / tried * 100).round();

    return StagePanel(
      semanticLabel: top.isEmpty
          ? 'Most wanted'
          : 'Most wanted. Number one: ${top.first.displayName}, '
                '${top.first.convictions} guilty.',
      spot: CourtColors.yellow,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'MOST WANTED',
                  style: TextStyle(
                    fontFamily: courtDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 2.5,
                    color: CourtColors.yellow,
                  ),
                ),
              ),
              const Text(
                'All-time',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: CourtColors.stageDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              // Three equal columns with an 8px gutter. The champion's avatar
              // is capped to the column so a narrow phone never overflows it.
              final column = (box.maxWidth - 16) / 3;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < arrangement.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    SizedBox(
                      width: column,
                      child: arrangement[i] < top.length
                          ? _Plinth(
                              entry: top[arrangement[i]],
                              spec: spec[i],
                              maxAvatar: column - 10,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              );
            },
          ),
          // The stat row tucks into the plinths, as on the canvas.
          Transform.translate(
            offset: const Offset(0, -10),
            // IntrinsicHeight, not plain stretch: inside a list this Row has
            // unbounded height, and stretch would force an infinite one.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StageStat(
                      value: '$streak',
                      label: 'Longest streak',
                      leading: const CourtIcon(
                        CourtGlyph.flame,
                        size: 16,
                        color: CourtColors.yellow,
                        fill: CourtColors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StageStat(
                      value: '$rate%',
                      label: 'Conviction rate',
                      valueColor: CourtColors.redOnStage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StageStat(value: '$tried', label: 'Cases tried'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Size and colour of one plinth, by podium position.
class _PlinthSpec {
  const _PlinthSpec({
    required this.block,
    required this.avatar,
    required this.name,
    required this.rank,
    required this.color,
    this.onColor = CourtColors.lightInk,
  });

  final double block;
  final double avatar;
  final double name;
  final double rank;
  final Color color;
  final Color onColor;
}

class _Plinth extends StatelessWidget {
  const _Plinth({
    required this.entry,
    required this.spec,
    required this.maxAvatar,
  });

  final RapSheetEntry entry;
  final _PlinthSpec spec;
  final double maxAvatar;

  @override
  Widget build(BuildContext context) {
    final champion = entry.rank == 1;
    final size = spec.avatar > maxAvatar ? maxAvatar : spec.avatar;
    final tint = tintFor(entry.displayName);
    final letter = entry.displayName.trim().isEmpty
        ? '?'
        : entry.displayName.trim()[0].toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint,
                border: Border.all(color: tint, width: 4),
                boxShadow: const [
                  BoxShadow(color: Colors.black, offset: Offset(0, 4)),
                ],
              ),
              child: Text(
                letter,
                style: TextStyle(
                  fontFamily: courtDisplayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.42,
                  height: 1,
                  color: CourtColors.lightInk,
                ),
              ),
            ),
            if (champion)
              Transform.translate(
                offset: const Offset(0, -12),
                child: Transform.rotate(
                  angle: -0.07,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CourtColors.red,
                      borderRadius: BorderRadius.circular(courtRadiusPill),
                      border: Border.all(
                        color: CourtColors.stageLight,
                        width: 3,
                      ),
                    ),
                    child: const Text(
                      'WANTED',
                      style: TextStyle(
                        fontFamily: courtDisplayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 1.5,
                        height: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: champion ? 0 : 6),
        Text(
          entry.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: courtDisplayFont,
            fontWeight: FontWeight.w600,
            fontSize: spec.name,
            height: 1.1,
            color: CourtColors.stageInk,
          ),
        ),
        Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: CourtColors.stageDim,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: spec.block,
          width: double.infinity,
          decoration: BoxDecoration(
            color: spec.color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: const Border(
              top: BorderSide(color: Colors.black, width: 3),
              left: BorderSide(color: Colors.black, width: 3),
              right: BorderSide(color: Colors.black, width: 3),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          alignment: Alignment.topCenter,
          // The shortest plinth is only 58px tall, and a large text scale
          // would push the number and its caption past it. Scale the pair
          // down rather than clip them — a plinth that overflows is a bug
          // the user sees as a striped bar.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.rank}',
                  style: TextStyle(
                    fontFamily: courtDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: spec.rank,
                    height: 1,
                    color: spec.onColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.convictions} guilty',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: spec.onColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Rank four and down: one row each, with the whole record as a bar.
class _EveryoneElse extends StatelessWidget {
  const _EveryoneElse({required this.rows, required this.rest, this.me});

  final List<RapSheetEntry> rows;
  final List<RapSheetEntry> rest;
  final String? me;

  @override
  Widget build(BuildContext context) => Container(
    decoration: courtChunk(context, radius: courtRadiusLg),
    padding: const EdgeInsets.all(6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in rest)
          _RecordRow(
            entry: entry,
            isYou: me != null && entry.id == me,
            // Who is directly above them, for the "one more and you pass X"
            // nudge. Null at the top of the list.
            above: rows.where((r) => r.rank == entry.rank - 1).firstOrNull,
          ),
      ],
    ),
  );
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.entry, required this.isYou, this.above});

  final RapSheetEntry entry;
  final bool isYou;
  final RapSheetEntry? above;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clean = entry.convictions == 0;
    final gap = above == null ? 0 : above!.convictions - entry.convictions + 1;
    final nudge = isYou && gap > 0 && gap <= 3 && above != null
        ? '$gap more guilty and you pass ${above!.displayName}'
        : null;

    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isYou ? palette.surfaceAlt : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isYou ? palette.border : Colors.transparent,
          width: courtBorderThin,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: courtDisplayFont,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: palette.inkDim,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tintFor(entry.displayName),
              border: Border.all(
                color: palette.border,
                width: courtBorderWidth,
              ),
            ),
            child: Text(
              entry.displayName.trim().isEmpty
                  ? '?'
                  : entry.displayName.trim()[0].toUpperCase(),
              style: const TextStyle(
                fontFamily: courtDisplayFont,
                fontWeight: FontWeight.w700,
                fontSize: 19,
                height: 1,
                color: CourtColors.lightInk,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (isYou) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.stage,
                          borderRadius: BorderRadius.circular(courtRadiusPill),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: CourtColors.yellow,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: clean ? palette.successText : palette.inkDim,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                RecordBar(entry: entry),
                if (nudge != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    nudge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: palette.inkDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${entry.convictions}',
                style: const TextStyle(
                  fontFamily: courtDisplayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  height: 1,
                ),
              ),
              Text(
                'GUILTY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: palette.inkDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A whole record as one 10px bar: guilty, cleared, mistrial, in that order.
///
/// The segments are flex rather than fixed widths, so the bar fills whatever
/// room the row has and can never overflow it.
class RecordBar extends StatelessWidget {
  const RecordBar({super.key, required this.entry});

  final RapSheetEntry entry;

  @override
  Widget build(BuildContext context) {
    final total = entry.casesTotal == 0
        ? entry.convictions + entry.acquittals + entry.mistrials
        : entry.casesTotal;
    if (total == 0) {
      return SizedBox(
        height: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.palette.lineSoft,
            borderRadius: BorderRadius.circular(3),
          ),
          child: const SizedBox(width: double.infinity),
        ),
      );
    }

    Widget seg(int n, Color color) => n == 0
        ? const SizedBox.shrink()
        : Expanded(
            flex: n,
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          );

    return Semantics(
      label:
          '${entry.convictions} guilty, ${entry.acquittals} not guilty, '
          '${entry.mistrials} mistrial',
      child: SizedBox(
        height: 10,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            seg(entry.convictions, CourtColors.red),
            seg(entry.acquittals, context.palette.successText),
            seg(entry.mistrials, context.palette.mistrial),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget key(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: context.palette.inkDim,
          ),
        ),
      ],
    );

    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 8,
        children: [
          key(CourtColors.red, 'Guilty'),
          key(context.palette.successText, 'Not guilty'),
          key(context.palette.mistrial, 'Mistrial'),
        ],
      ),
    );
  }
}
