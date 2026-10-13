import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/env.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../courts/data/court_providers.dart';
import '../data/case_providers.dart';

/// Home, drawn to the "Dashboard" artboard: who you are and what you have
/// done, then the two or three things that are actually waiting on you.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cases = ref.watch(casesProvider);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final unread = ref.watch(notificationsProvider).valueOrNull?.unread ?? 0;
    final name = session?.displayName;

    return CourtScaffold(
      title: 'Sue Me',
      maxWidth: 1000,
      header: ScreenHeader(
        title: name == null || name.isEmpty ? 'Welcome' : name,
        eyebrow: '${_greeting()},',
        titleSize: 28,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        leading: _HeaderAvatar(name: name),
        trailing: [
          RoundIconButton(
            glyph: CourtGlyph.bell,
            label: unread > 0 ? 'Notifications, $unread new' : 'Notifications',
            badge: unread,
            onTap: () => context.push('/notifications'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sharedCasesProvider);
          ref.invalidate(notificationsProvider);
          ref.invalidate(rapSheetProvider);
          ref.invalidate(casesProvider);
          await ref.read(casesProvider.future);
        },
        child: cases.when(
          loading: () => const _DashboardSkeleton(),
          error: (error, _) => ListView(
            // A scrollable is required for pull-to-refresh to work in an
            // error state, which is exactly when a user wants to retry.
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: CourtErrorView(
                  message: error is ApiException
                      ? error.message
                      : 'Could not load your docket.',
                  onRetry: () => ref.invalidate(casesProvider),
                ),
              ),
            ],
          ),
          data: (items) => _Docket(items: items),
        ),
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final letter = (name ?? '').trim().isEmpty
        ? '?'
        : name!.trim()[0].toUpperCase();
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tintFor(name ?? ''),
        border: Border.all(
          color: context.palette.border,
          width: courtBorderWidth,
        ),
        boxShadow: courtHardShadow(context, dy: 3),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontFamily: courtDisplayFont,
          fontWeight: FontWeight.w700,
          fontSize: 22,
          height: 1,
          color: CourtColors.lightInk,
        ),
      ),
    );
  }
}

class _Docket extends ConsumerWidget {
  const _Docket({required this.items});

  final List<CaseSummary> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(sharedCasesProvider).valueOrNull ?? const [];
    final wide = MediaQuery.sizeOf(context).width >= courtWideBreakpoint;

    // The most recent case the court has actually ruled on, for the one-line
    // "new ruling" tray at the foot of the screen.
    final ruled = items.where((c) => c.verdictReady).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    Widget cards() => wide
        ? LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final summary in items)
                  SizedBox(
                    width: (c.maxWidth - 12) / 2,
                    child: _CaseCard(summary: summary),
                  ),
              ],
            ),
          )
        : Column(
            children: [
              for (final summary in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CaseCard(summary: summary),
                ),
            ],
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, courtNavBottomInset),
      children: [
        const _RecordStage(),
        if (shared.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionHeading(
            title: 'Needs you',
            trailing: '${shared.length} waiting',
          ),
          const SizedBox(height: 12),
          for (final item in shared)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: item.role == 'accused'
                  ? _SuedCard(item: item)
                  : _JuryDutyCard(item: item),
            ),
        ],
        if (ruled.isNotEmpty) ...[
          const SizedBox(height: 2),
          _RulingTray(summary: ruled.first),
        ],
        const SizedBox(height: 18),
        _SectionHeading(
          title: 'My cases',
          trailing: items.isEmpty ? null : '${items.length}',
        ),
        const SizedBox(height: 12),
        if (items.isEmpty) const _EmptyDocketCard() else cards(),
        const SizedBox(height: 12),
        DashedAddTile(
          label: 'File a new case',
          onTap: () => context.push('/cases/new'),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: courtDisplayFont,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              height: 1.1,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: context.palette.inkDim,
            ),
          ),
      ],
    ),
  );
}

/// The lit panel: your conviction rate as a dial, the title you have earned,
/// and the four numbers behind it.
class _RecordStage extends ConsumerWidget {
  const _RecordStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final sheet = ref.watch(rapSheetProvider).valueOrNull;
    final courts = ref.watch(courtsProvider).valueOrNull ?? const <Court>[];
    final entry = me == null || sheet == null
        ? null
        : sheet.where((r) => r.id == me.userId).firstOrNull;

    final rate = entry == null ? 0.0 : entry.convictionRate.clamp(0.0, 1.0);
    final pct = (rate * 100).round();

    return StagePanel(
      spot: CourtColors.pink,
      spotAlignment: const Alignment(1.3, -1.3),
      padding: const EdgeInsets.all(18),
      semanticLabel: entry == null
          ? 'Your record: nothing on it yet'
          : 'Your record: ${entry.title}, conviction rate $pct percent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RateDial(rate: rate, label: '$pct%'),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'YOUR TITLE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: CourtColors.yellow,
                      ),
                    ),
                    Text(
                      entry?.title.isNotEmpty == true
                          ? entry!.title
                          : 'No record yet',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: courtDisplayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                        height: 1.05,
                        color: CourtColors.stageInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (entry != null)
                          CourtPill(
                            label: '#${entry.rank} on the rap sheet',
                            fill: CourtColors.yellow,
                            foreground: CourtColors.lightInk,
                            fontSize: 12,
                          ),
                        if (courts.isNotEmpty)
                          CourtPill(
                            label:
                                '${courts.length} '
                                '${courts.length == 1 ? 'court' : 'courts'}',
                            fill: CourtColors.stageChipLight,
                            foreground: CourtColors.stageInk,
                            fontSize: 12,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // IntrinsicHeight, not CrossAxisAlignment.stretch: inside a list the
          // Row has unbounded height, and stretch would hand its children an
          // infinite constraint.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StageStat(
                    value: '${entry?.casesTotal ?? 0}',
                    label: 'Cases',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StageStat(
                    value: '${entry?.convictions ?? 0}',
                    label: 'Guilty',
                    valueColor: CourtColors.redOnStage,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StageStat(
                    value: '${entry?.acquittals ?? 0}',
                    label: 'Cleared',
                    valueColor: CourtColors.greenFill,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StageStat(
                    value: '${entry?.mistrials ?? 0}',
                    label: 'Mistrial',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The conviction-rate dial from the canvas: a red arc on a plum track, with
/// the number punched out of the middle.
class _RateDial extends StatelessWidget {
  const _RateDial({required this.rate, required this.label});

  final double rate;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    height: 104,
    child: CustomPaint(
      painter: _DialPainter(
        rate: rate,
        track: CourtColors.darkTray2,
        rim: Colors.black,
        hole: context.palette.stage,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: courtDisplayFont,
                fontWeight: FontWeight.w700,
                fontSize: 26,
                height: 1,
                color: CourtColors.stageInk,
              ),
            ),
            const Text(
              'guilty',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: CourtColors.stageDim,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.rate,
    required this.track,
    required this.rim,
    required this.hole,
  });

  final double rate;
  final Color track;
  final Color rim;
  final Color hole;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = size.width / 2;

    canvas.drawCircle(centre, radius - 1.5, Paint()..color = track);
    if (rate > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius - 1.5),
        -math.pi / 2,
        2 * math.pi * rate,
        true,
        Paint()..color = CourtColors.red,
      );
    }
    canvas.drawCircle(centre, (size.width - 28) / 2, Paint()..color = hole);
    canvas.drawCircle(
      centre,
      radius - 1.5,
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.rate != rate || old.track != track || old.hole != hole;
}

/// "You've been sued": the one card that is allowed to shout.
class _SuedCard extends StatelessWidget {
  const _SuedCard({required this.item});

  final SharedCase item;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: CourtColors.red,
      borderRadius: BorderRadius.circular(courtRadiusLg),
      border: Border.all(
        color: context.palette.border,
        width: courtBorderWidth,
      ),
      boxShadow: courtHardShadow(context, dy: 5),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(courtRadiusPill),
                  border: Border.all(color: CourtColors.lightInk, width: 2),
                ),
                child: const Text(
                  "YOU'VE BEEN SUED",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: courtDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1,
                    color: CourtColors.redInk,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Your move',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tintFor(item.creatorName),
                border: Border.all(
                  color: CourtColors.lightInk,
                  width: courtBorderWidth,
                ),
              ),
              child: Text(
                item.creatorName.trim().isEmpty
                    ? '?'
                    : item.creatorName.trim()[0].toUpperCase(),
                style: const TextStyle(
                  fontFamily: courtDisplayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  height: 1,
                  color: CourtColors.lightInk,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.creatorName} v. you',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: courtDisplayFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      height: 1.15,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CourtKey(
          label: 'Defend yourself',
          glyph: CourtGlyph.arrowRight,
          height: 52,
          onPressed: () => showSharedCase(context, item),
        ),
      ],
    ),
  );
}

/// Jury duty: the charge, and the two buttons that put your name to a side.
///
/// The vote is real — it posts to the jury endpoint with the signed-in user
/// id as the voter key, which is what the web app does with its browser key.
class _JuryDutyCard extends ConsumerStatefulWidget {
  const _JuryDutyCard({required this.item});

  final SharedCase item;

  @override
  ConsumerState<_JuryDutyCard> createState() => _JuryDutyCardState();
}

class _JuryDutyCardState extends ConsumerState<_JuryDutyCard> {
  bool _busy = false;

  Future<void> _vote(String vote) async {
    setState(() => _busy = true);
    try {
      await ref.read(juryVoteProvider)(widget.item.token, vote);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your vote is on the record. It stays sealed.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final room = ref.watch(juryRoomProvider(widget.item.token)).valueOrNull;
    final voted = room?.yourVote;
    final charge = room?.accusation.isNotEmpty == true
        ? room!.accusation
        : widget.item.title;

    return Container(
      decoration: courtChunk(context, radius: courtRadiusLg),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CourtPill(
                label: 'JURY DUTY',
                fill: CourtColors.blue,
                foreground: Colors.white,
                fontSize: 12,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  room == null
                      ? widget.item.creatorName
                      : '${room.plaintiffName} v. ${room.defendantName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: palette.inkDim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            charge,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: courtDisplayFont,
              fontWeight: FontWeight.w600,
              fontSize: 19,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          if (voted != null)
            _VotedNote(vote: voted)
          else
            Row(
              children: [
                Expanded(
                  child: _VoteButton(
                    label: 'Guilty',
                    fill: palette.guiltyBg,
                    foreground: palette.guiltyFg,
                    onPressed: _busy ? null : () => _vote('guilty'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _VoteButton(
                    label: 'Not guilty',
                    fill: palette.innocentBg,
                    foreground: palette.innocentFg,
                    onPressed: _busy ? null : () => _vote('not_guilty'),
                  ),
                ),
              ],
            ),
          // The whole file lives on the web; a juror who wants to read it
          // before committing should not have to vote first.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => showSharedCase(context, widget.item),
              child: const Text('Open the summons'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.label,
    required this.fill,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color fill;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? 0.6 : 1,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(courtRadiusSm + 2),
        border: Border.all(
          color: context.palette.border,
          width: courtBorderWidth,
        ),
        boxShadow: courtHardShadow(context, dy: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: courtDisplayFont,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _VotedNote extends StatelessWidget {
  const _VotedNote({required this.vote});

  final String vote;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CourtIcon(CourtGlyph.check, size: 18, color: context.palette.successText),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'You voted ${vote == 'guilty' ? 'guilty' : 'not guilty'}. '
          'It stays sealed until the judge rules.',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: context.palette.inkDim,
          ),
        ),
      ),
    ],
  );
}

/// The one-line tray at the foot: the court's latest ruling.
class _RulingTray extends StatelessWidget {
  const _RulingTray({required this.summary});

  final CaseSummary summary;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.surfaceAlt,
    borderRadius: BorderRadius.circular(courtRadius),
    child: InkWell(
      borderRadius: BorderRadius.circular(courtRadius),
      onTap: () => context.push('/cases/${summary.id}/verdict'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CourtColors.yellow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.palette.border,
                  width: courtBorderWidth,
                ),
              ),
              child: const CourtIcon(
                CourtGlyph.gavel,
                size: 20,
                color: CourtColors.lightInk,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Latest ruling: ${summary.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'The court has handed it down',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.palette.inkDim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CourtIcon(
              CourtGlyph.chevronRight,
              size: 18,
              color: context.colors.onSurface,
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Jury duty and summonses are answered in the browser; hand over the link.
void showSharedCase(BuildContext context, SharedCase item) => showAnswerLink(
  context,
  heading: item.title,
  message:
      '${item.creatorName} added you as '
      '${item.role == 'accused' ? 'the accused' : 'a juror'}.',
  path: item.path,
);

/// The sheet behind a summons or jury notice: [path] is the web route
/// (`/invite/<token>` for the defense, `/jury/<token>` for jurors).
void showAnswerLink(
  BuildContext context, {
  required String heading,
  required String message,
  required String path,
}) {
  final link = '${Env.webBaseUrl}$path';
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: context.text.headlineSmall),
          const SizedBox(height: 6),
          Text(
            message,
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(link, style: context.text.bodySmall),
          const SizedBox(height: 16),
          CourtKey(
            label: 'Copy link to answer in browser',
            glyph: CourtGlyph.share,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Link copied')));
            },
          ),
        ],
      ),
    ),
  );
}

class _EmptyDocketCard extends StatelessWidget {
  const _EmptyDocketCard();

  @override
  Widget build(BuildContext context) => CourtCard(
    child: Column(
      children: [
        CourtIcon(
          CourtGlyph.doc,
          size: 40,
          color: context.palette.inkFaint,
          strokeWidth: 2,
        ),
        const SizedBox(height: 10),
        Text('The docket is empty', style: context.text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'File your first case and summon a friend to defend themselves.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.inkDim,
          ),
        ),
        const SizedBox(height: 16),
        CourtKey(
          label: 'File a case',
          glyph: CourtGlyph.gavel,
          onPressed: () => context.push('/cases/new'),
        ),
      ],
    ),
  );
}

/// One of my cases: who it is against, where it has got to, and a pill that
/// says whether there is anything to read.
class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.summary});

  final CaseSummary summary;

  @override
  Widget build(BuildContext context) {
    final statusColor = summary.status.color(context);
    final number = summary.id.length >= 5
        ? summary.id.substring(0, 5).toUpperCase()
        : summary.id.toUpperCase();

    return Container(
      decoration: courtChunk(context, radius: courtRadiusLg),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => context.push('/cases/${summary.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        CourtColors.tints[number.hashCode.abs() %
                            CourtColors.tints.length],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: context.palette.border,
                      width: courtBorderWidth,
                    ),
                  ),
                  child: const CourtIcon(
                    CourtGlyph.doc,
                    size: 22,
                    color: CourtColors.lightInk,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        summary.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: courtDisplayFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            flex: 3,
                            child: Text(
                              summary.status.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: context.palette.inkDim,
                              ),
                            ),
                          ),
                          if (summary.defendantNickname != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              flex: 2,
                              child: Text(
                                'v. ${summary.defendantNickname}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.palette.inkFaint,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (summary.juryCount > 0 || summary.shareEnabled) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (summary.juryCount > 0)
                              CourtPill(
                                label: '${summary.juryCount} jurors',
                                fill: context.palette.surfaceAlt,
                                fontSize: 11,
                              ),
                            if (summary.shareEnabled) ...[
                              const SizedBox(width: 6),
                              CourtPill(
                                label: 'Public',
                                fill: context.palette.surfaceAlt,
                                fontSize: 11,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CourtPill(
                  label: summary.verdictReady ? 'Verdict' : 'Open',
                  fill: summary.verdictReady
                      ? CourtColors.yellow
                      : context.palette.accent,
                  foreground: summary.verdictReady
                      ? CourtColors.lightInk
                      : Colors.white,
                  bordered: true,
                  fontSize: 12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, courtNavBottomInset),
    children: const [
      CourtSkeleton(height: 210),
      SizedBox(height: 18),
      CourtSkeleton(height: 22, width: 140),
      SizedBox(height: 14),
      CourtSkeleton(height: 150),
      SizedBox(height: 12),
      CourtSkeleton(height: 120),
      SizedBox(height: 12),
      CourtSkeleton(height: 92),
    ],
  );
}
