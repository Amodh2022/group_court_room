import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/sue_widgets.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../courts/data/court_providers.dart';
import '../../cases/data/case_providers.dart';

/// Standings, drawn to the "Leaderboard" artboard (Most Wanted): the top three
/// on a podium, then everyone else as a row with their title and conviction
/// count. Every number is the court's own record.
class RapSheetScreen extends ConsumerWidget {
  const RapSheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheet = ref.watch(rapSheetProvider);
    final rows = sheet.valueOrNull ?? const <RapSheetEntry>[];
    final cases = rows.fold<int>(0, (n, r) => n + r.casesTotal);

    return CourtScaffold(
      title: 'Most Wanted',
      maxWidth: 640,
      tablet: _TabletSheet(
        sheet: sheet,
        onShare: rows.isEmpty ? null : () => _share(rows),
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rows.isEmpty
                        ? 'ALL-TIME'
                        : 'ALL-TIME · $cases ${cases == 1 ? 'CASE' : 'CASES'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.5,
                      color: context.palette.inkDim,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Most Wanted',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            RoundIconButton(
              glyph: CourtGlyph.share,
              label: 'Share rap sheet',
              onTap: rows.isEmpty ? null : () => _share(rows),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(rapSheetProvider.future),
        child: sheet.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, courtNavBottomInset),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => CourtSkeleton(height: i == 0 ? 240 : 62),
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

/// The rap sheet as the tablet artboards draw it: the loud title row, the
/// podium, and the standings beside it once the window is landscape-wide.
class _TabletSheet extends ConsumerWidget {
  const _TabletSheet({required this.sheet, required this.onShare});

  final AsyncValue<List<RapSheetEntry>> sheet;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(courtsProvider).valueOrNull ?? const <Court>[];
    final rows = sheet.valueOrNull ?? const <RapSheetEntry>[];
    final rest = rows.length > 3 ? rows.sublist(3) : const <RapSheetEntry>[];

    return SueTabletPage(
      header: SueTabletHeader(
        title: 'Rap sheet',
        subtitle: courts.isEmpty ? null : courts.first.name,
        trailing: RoundIconButton(
          glyph: CourtGlyph.share,
          label: 'Share rap sheet',
          onTap: onShare,
        ),
      ),
      child: sheet.when(
        loading: () => ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => CourtSkeleton(height: i == 0 ? 240 : 62),
        ),
        error: (error, _) => CourtErrorView(
          message: error is ApiException
              ? error.message
              : 'Could not pull the records.',
          onRetry: () => ref.invalidate(rapSheetProvider),
        ),
        data: (rows) => rows.isEmpty
            ? CourtNotice(
                icon: Icons.folder_open,
                title: 'No convictions yet',
                message:
                    'Suspiciously clean, this group. Every verdict the court '
                    'hands down lands on somebody\'s record.',
                action: CourtKey(
                  label: 'File a case',
                  glyph: CourtGlyph.gavel,
                  onPressed: () => context.push('/cases/new'),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.refresh(rapSheetProvider.future),
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SueColumns(
                      start: [_Podium(top: rows.take(3).toList())],
                      end: [
                        _YourPosition(rows: rows),
                        for (final r in rest) _Row(entry: r),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.rows});

  final List<RapSheetEntry> rows;

  @override
  Widget build(BuildContext context) {
    final rest = rows.length > 3 ? rows.sublist(3) : const <RapSheetEntry>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, courtNavBottomInset),
      children: [
        _Podium(top: rows.take(3).toList()),
        const SizedBox(height: 14),
        _YourPosition(rows: rows),
        for (final r in rest) ...[const SizedBox(height: 10), _Row(entry: r)],
      ],
    );
  }
}

/// The blue band on the artboard: where you stand, and how far off the rank
/// above you are. Drawn only once the court's record actually names you.
class _YourPosition extends StatelessWidget {
  const _YourPosition({required this.rows});

  final List<RapSheetEntry> rows;

  @override
  Widget build(BuildContext context) {
    // The server marks the row: a rap sheet entry carries a record id, and a
    // record is keyed by nickname, so it never equals an account id.
    final index = rows.indexWhere((r) => r.isYou);
    if (index < 0) return const SizedBox.shrink();

    final mine = rows[index];
    final above = index > 0 ? rows[index - 1] : null;
    final gap = above == null ? 0 : above.convictions - mine.convictions;
    // How far along the stretch between me and the rank above. No one above:
    // the bar is full, because there is nowhere further to go.
    final progress = above == null || above.convictions == 0
        ? 1.0
        : (mine.convictions / above.convictions).clamp(0.0, 1.0);

    final line = above == null
        ? 'Top of the sheet. Everyone else is working on it.'
        : gap <= 0
        ? 'Level with ${above.displayName} — the next verdict breaks the tie.'
        : '$gap more guilty verdict${gap == 1 ? '' : 's'} to overtake '
              '${above.displayName}';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: CourtColors.blue,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: CourtColors.blue.withValues(alpha: .3),
            offset: const Offset(0, 12),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .18),
                ),
                child: Text(
                  mine.displayName.trim().isEmpty
                      ? '?'
                      : mine.displayName.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "You're #${mine.rank} · ${mine.title}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${mine.convictions}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Progress to the rank above',
            value: '${(progress * 100).round()}%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: .22),
                valueColor: const AlwaysStoppedAnimation(CourtColors.gold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Second, first, third — first tallest, with the gold crown over them.
class _Podium extends StatelessWidget {
  const _Podium({required this.top});

  final List<RapSheetEntry> top;

  @override
  Widget build(BuildContext context) {
    // Heights and sizes straight off the artboard, indexed by finishing place.
    const avatars = [74.0, 56.0, 56.0];
    const blocks = [104.0, 70.0, 52.0];
    const numbers = [36.0, 26.0, 26.0];
    const delays = [0, 150, 300];
    // Display order: 2nd, 1st, 3rd (whoever exists).
    final order = [if (top.length > 1) 1, 0, if (top.length > 2) 2];
    final calm = MediaQuery.disableAnimationsOf(context);
    return SueCard(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Semantics(
        label:
            'Podium: ${top.map((e) => '${e.rank} ${e.displayName}').join(', ')}',
        child: ClipRRect(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final i in order)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _Place(
                      entry: top[i],
                      place: i,
                      avatar: avatars[i],
                      block: blocks[i],
                      numberSize: numbers[i],
                      delay: calm
                          ? Duration.zero
                          : Duration(milliseconds: delays[i]),
                      animate: !calm,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({
    required this.entry,
    required this.place,
    required this.avatar,
    required this.block,
    required this.numberSize,
    required this.delay,
    required this.animate,
  });

  final RapSheetEntry entry;
  final int place;
  final double avatar;
  final double block;
  final double numberSize;
  final Duration delay;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    // 1st is gold, 2nd blue, 3rd orange.
    final ring = switch (place) {
      0 => CourtColors.gold,
      1 => SueTone.blue.fg(context),
      _ => SueTone.orange.fg(context),
    };
    final tint = switch (place) {
      0 => SueTone.gold.tint(context),
      1 => SueTone.blue.tint(context),
      _ => SueTone.orange.tint(context),
    };
    final letterTone = switch (place) {
      0 => SueTone.gold,
      1 => SueTone.blue,
      _ => SueTone.orange,
    };
    final rank = place + 1;
    final bar = Container(
      width: double.infinity,
      height: block,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: numberSize,
          fontWeight: FontWeight.w800,
          color: ring.withValues(alpha: .9),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (place == 0)
          Transform.rotate(
            angle: -.14,
            child: const CustomPaint(
              size: Size(34, 26),
              painter: _CrownPainter(),
            ),
          ),
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            SueAvatar(
              name: entry.displayName,
              size: avatar,
              tone: letterTone,
              ring: ring,
              fontSize: avatar * .38,
            ),
            Positioned(
              bottom: -10,
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ring,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: context.colors.surfaceContainerHighest,
                    width: 2,
                  ),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          entry.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        Text(
          '${entry.convictions} guilty',
          style: TextStyle(fontSize: 12, color: context.palette.inkDim),
        ),
        const SizedBox(height: 6),
        if (animate)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700) + delay,
            curve: Interval(
              delay.inMilliseconds / (700 + delay.inMilliseconds),
              1,
              curve: Curves.easeOutBack,
            ),
            builder: (_, v, child) => Align(
              alignment: Alignment.bottomCenter,
              heightFactor: v.clamp(0.0, 1.2),
              child: child,
            ),
            child: bar,
          )
        else
          bar,
      ],
    );
  }
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 34;
    final sy = size.height / 26;
    final path = Path()
      ..moveTo(3 * sx, 22 * sy)
      ..lineTo(5 * sx, 6 * sy)
      ..lineTo(12 * sx, 13 * sy)
      ..lineTo(17 * sx, 3 * sy)
      ..lineTo(22 * sx, 13 * sy)
      ..lineTo(29 * sx, 6 * sy)
      ..lineTo(31 * sx, 22 * sy)
      ..close();
    canvas.drawPath(path, Paint()..color = CourtColors.gold);
    canvas.drawPath(
      path,
      Paint()
        ..color = CourtColors.goldDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      Offset(17 * sx, 3 * sy),
      2.5 * sx,
      Paint()..color = const Color(0xFFF0643C),
    );
  }

  @override
  bool shouldRepaint(_CrownPainter old) => false;
}

/// Rank 4 and below: number, face, name + title, and a pill.
class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final RapSheetEntry entry;

  @override
  Widget build(BuildContext context) {
    final clean = entry.convictions == 0;
    final tone = clean ? SueTone.teal : SueTone.blue;
    return SueCard(
      small: true,
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.palette.inkFaint,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SueAvatar(
              name: entry.displayName,
              size: 38,
              tone: tone,
              fontSize: 15,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.shield,
                        size: 12,
                        color: clean
                            ? tone.fg(context)
                            : context.palette.inkFaint,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.inkDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SuePill(
              clean ? 'CLEAN' : '${entry.convictions} GUILTY',
              tone: clean ? SueTone.teal : SueTone.gray,
              round: false,
            ),
          ],
        ),
      ),
    );
  }
}
