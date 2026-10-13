import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/courtroom.dart';
import '../../auth/data/auth_providers.dart';
import '../../courts/presentation/user_search_sheet.dart';
import '../data/case_providers.dart';
import 'courtroom_panel.dart';

/// The case file, drawn to the "Case file" artboard: the two sides on a lit
/// stage with the charge between them, how far the case has got, what each
/// side has said, and one key at the foot for whatever happens next.
class CaseDetailScreen extends ConsumerWidget {
  const CaseDetailScreen({super.key, required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(caseDetailProvider(caseId));
    final data = detail.valueOrNull;

    return CourtScaffold(
      title: 'Case file',
      header: ScreenHeader(
        title: data?.title ?? 'Case file',
        eyebrow: data == null
            ? null
            : '${_caseNumber(data.id)} · '
                  '${CaseCategory.byId(data.category).label.toUpperCase()}',
        titleSize: 26,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        leading: RoundIconButton(
          glyph: CourtGlyph.back,
          label: 'Back',
          onTap: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        trailing: [
          if (data != null) _Countdown(expiresAt: data.expiresAt),
          if (data != null)
            RoundIconButton(
              glyph: CourtGlyph.trash,
              label: 'Delete case',
              onTap: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      bottom: data == null ? null : _ActionDock(detail: data),
      body: detail.when(
        loading: () => const _DetailSkeleton(),
        error: (error, _) => CourtErrorView(
          message: error is ApiException
              ? error.message
              : 'Could not open this case file.',
          onRetry: () => ref.invalidate(caseDetailProvider(caseId)),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.refresh(caseDetailProvider(caseId).future),
          child: _CaseBody(detail: data),
        ),
      ),
    );
  }

  static String _caseNumber(String id) {
    final digits = id.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final tail = digits.length >= 4
        ? digits.substring(digits.length - 4)
        : digits.padLeft(4, '0');
    return 'CASE #${tail.toUpperCase()}';
  }

  /// 1-based, matching [_caseStages].
  static int _stepFor(CaseStatus status) => switch (status) {
    CaseStatus.draft || CaseStatus.awaitingDefense => 1,
    CaseStatus.ready => 2,
    CaseStatus.generating => 3,
    CaseStatus.completed => 4,
    CaseStatus.failed || CaseStatus.expired => 4,
  };

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dismiss this case?'),
        content: const Text(
          'The case, the defense and the verdict are deleted, and every link '
          'you have shared stops working immediately. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CourtColors.guilty),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(caseActionsProvider).delete(caseId);
      if (!context.mounted) return;
      context.go('/');
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// The yellow countdown chip. Shows nothing at all when the case has no
/// deadline left to run — an empty clock is worse than no clock.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.expiresAt});

  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    if (expiresAt == null) return const SizedBox.shrink();
    final left = expiresAt!.difference(DateTime.now());
    if (left.isNegative) {
      return const CourtPill(
        label: 'Closed',
        glyph: CourtGlyph.clock,
        fill: CourtColors.lightMistrial,
        foreground: CourtColors.lightInk,
        bordered: true,
      );
    }
    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);
    return CourtPill(
      label: hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m',
      glyph: CourtGlyph.clock,
      fill: CourtColors.yellow,
      foreground: CourtColors.lightInk,
      bordered: true,
    );
  }
}

class _CaseBody extends ConsumerWidget {
  const _CaseBody({required this.detail});

  final CaseDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me =
        ref.watch(authControllerProvider).valueOrNull?.displayName ?? 'You';
    final accused = detail.defendantNickname ?? 'The accused';

    // The room hears about the defense, the votes and the verdict first; refresh
    // the case file the moment it says the status moved.
    ref.listen(courtroomProvider(detail.id), (prev, next) {
      final status = next.caseStatus;
      if (status != null && status != detail.status) {
        ref.invalidate(caseDetailProvider(detail.id));
      }
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _Versus(plaintiff: me, accused: accused, charge: detail.accusation),
        const SizedBox(height: 14),
        _Progress(step: CaseDetailScreen._stepFor(detail.status)),
        const SizedBox(height: 14),
        // What the court is waiting for sits high: it is the first thing the
        // creator opens the file to find out.
        _StatusPanel(detail: detail),
        const SizedBox(height: 14),
        _Defense(accused: accused, defended: detail.defenseSubmitted),
        const SizedBox(height: 14),
        _JuryTray(detail: detail),
        const SizedBox(height: 14),
        CourtroomPanel(caseId: detail.id),
        const SizedBox(height: 14),
        if (detail.juryTally != null && !detail.juryTally!.isEmpty) ...[
          _JuryPanel(tally: detail.juryTally!),
          const SizedBox(height: 14),
        ],
        _SeatPanel(detail: detail),
      ],
    );
  }
}

/// The lit stage: who is suing whom, and what over.
class _Versus extends StatelessWidget {
  const _Versus({
    required this.plaintiff,
    required this.accused,
    required this.charge,
  });

  final String plaintiff;
  final String accused;
  final String charge;

  @override
  Widget build(BuildContext context) => StagePanel(
    semanticLabel: '$plaintiff versus $accused',
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _Party(
                name: plaintiff,
                role: 'PLAINTIFF',
                roleColor: CourtColors.yellow,
              ),
            ),
            Transform.rotate(
              angle: -0.105,
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CourtColors.red,
                  border: Border.all(color: Colors.black, width: courtBorderWidth),
                ),
                child: const Text(
                  'VS',
                  style: TextStyle(
                    fontFamily: courtDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _Party(
                name: accused,
                role: 'ACCUSED',
                roleColor: CourtColors.pink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: CourtColors.lightBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black, width: courtBorderWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'THE CHARGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: CourtColors.redInk,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                charge,
                style: const TextStyle(
                  fontFamily: courtDisplayFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 21,
                  height: 1.15,
                  color: CourtColors.lightInk,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Party extends StatelessWidget {
  const _Party({
    required this.name,
    required this.role,
    required this.roleColor,
  });

  final String name;
  final String role;
  final Color roleColor;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tintFor(name),
          border: Border.all(color: CourtColors.stageInk, width: 4),
        ),
        child: Text(
          name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
          style: const TextStyle(
            fontFamily: courtDisplayFont,
            fontWeight: FontWeight.w700,
            fontSize: 30,
            height: 1,
            color: CourtColors.lightInk,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: courtDisplayFont,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            height: 1,
            color: CourtColors.stageInk,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        role,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          color: roleColor,
        ),
      ),
    ],
  );
}

/// What a case passes through, in order. A readout, never a control: a player
/// does not advance a case, the parties do.
const _caseStages = ['Filed', 'Defense', 'Jury', 'Ruling'];

class _Progress extends StatelessWidget {
  const _Progress({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Step $step of ${_caseStages.length}: ${_caseStages[step - 1]}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < _caseStages.length; i++)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i + 1 < step)
                      _Dot(
                        fill: context.colors.onSurface,
                        child: CourtIcon(
                          CourtGlyph.check,
                          size: 16,
                          color: context.colors.surface,
                          strokeWidth: 3.4,
                        ),
                      )
                    else if (i + 1 == step)
                      _Dot(
                        fill: CourtColors.yellow,
                        border: palette.border,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontFamily: courtDisplayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1,
                            color: CourtColors.lightInk,
                          ),
                        ),
                      )
                    else
                      _Dot(
                        fill: Colors.transparent,
                        border: palette.inkDim,
                        dashed: true,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontFamily: courtDisplayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1,
                            color: palette.inkDim,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      _caseStages[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i + 1 == step
                            ? FontWeight.w900
                            : FontWeight.w800,
                        color: i + 1 > step
                            ? palette.inkDim
                            : context.colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.fill,
    required this.child,
    this.border,
    this.dashed = false,
  });

  final Color fill;
  final Widget child;
  final Color? border;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      border: border == null
          ? null
          : Border.all(color: border!, width: dashed ? 2 : courtBorderWidth),
    ),
    child: child,
  );
}

/// What the other side has put on the record. The charge itself is already
/// the loudest thing on the stage, so only the answer gets a bubble.
class _Defense extends StatelessWidget {
  const _Defense({required this.accused, required this.defended});

  final String accused;
  final bool defended;

  @override
  Widget build(BuildContext context) => _Bubble(
    name: accused,
    label: 'DEFENSE',
    body: defended
        ? 'Filed. Sealed until the judge rules — the court does not hand '
              'the defense to the plaintiff.'
        : 'Nothing on the record yet. The court is waiting.',
    mine: false,
    muted: !defended,
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.name,
    required this.label,
    required this.body,
    required this.mine,
    this.muted = false,
  });

  final String name;
  final String label;
  final String body;
  final bool mine;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final avatar = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tintFor(name),
        border: Border.all(color: palette.border, width: courtBorderThin),
      ),
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: const TextStyle(
          fontFamily: courtDisplayFont,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          height: 1,
          color: CourtColors.lightInk,
        ),
      ),
    );

    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? context.colors.surfaceContainerHighest
              : palette.bubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 6 : 20),
            bottomRight: Radius.circular(mine ? 20 : 6),
          ),
          border: Border.all(color: palette.border, width: courtBorderWidth),
          boxShadow: courtHardShadow(context, dy: 3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: palette.inkDim,
              ),
            ),
            Text(
              body,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: muted ? palette.inkDim : context.colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      textDirection: mine ? TextDirection.ltr : TextDirection.rtl,
      children: [avatar, const SizedBox(width: 8), bubble],
    );
  }
}

/// How full the jury box is. Counts only — the court never says who voted
/// which way, and neither does this.
class _JuryTray extends StatelessWidget {
  const _JuryTray({required this.detail});

  final CaseDetail detail;

  @override
  Widget build(BuildContext context) {
    final seated = detail.juryCount;
    final voted = detail.juryTally?.total ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(courtRadius),
      ),
      child: Row(
        children: [
          SizedBox(
            width: seated == 0 ? 0 : 34.0 + 26 * (seated.clamp(1, 4) - 1),
            height: 34,
            child: Stack(
              children: [
                for (var i = 0; i < seated.clamp(0, 4); i++)
                  Positioned(
                    left: i * 26.0,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < voted
                            ? CourtColors.tints[i % CourtColors.tints.length]
                            : context.palette.surfaceAlt2,
                        border: Border.all(
                          color: context.palette.border,
                          width: courtBorderThin,
                        ),
                      ),
                      child: i < voted
                          ? CourtIcon(
                              CourtGlyph.check,
                              size: 16,
                              color: CourtColors.lightInk,
                              strokeWidth: 3.4,
                            )
                          : Text(
                              '?',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: context.palette.inkDim,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          if (seated > 0) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seated == 0
                      ? 'No jurors seated yet'
                      : '$voted of $seated ${seated == 1 ? 'juror has' : 'jurors have'} voted',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Votes stay sealed until the judge rules',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
}

/// The one key at the foot of the file: whatever the case is waiting for.
class _ActionDock extends ConsumerWidget {
  const _ActionDock({required this.detail});

  final CaseDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The prompt above the key is a question, as on the canvas — not the
    // status again. The status panel higher up already says that.
    final prompt = switch (detail.status) {
      CaseStatus.draft || CaseStatus.awaitingDefense =>
        'Has the defendant answered?',
      CaseStatus.ready => 'Both sides are in.',
      CaseStatus.generating => 'The judge is deliberating.',
      CaseStatus.completed => 'The court has ruled.',
      CaseStatus.failed => 'The court could not reach a verdict.',
      CaseStatus.expired => 'This case has closed.',
    };

    final (label, glyph, action) = switch (detail.status) {
      CaseStatus.draft || CaseStatus.awaitingDefense => (
        'Check for a defense',
        CourtGlyph.refresh,
        () => ref.invalidate(caseDetailProvider(detail.id)),
      ),
      CaseStatus.ready => (
        'Call the court to order',
        CourtGlyph.gavel,
        () => context.push('/cases/${detail.id}/verdict'),
      ),
      CaseStatus.generating => (
        'Watch the deliberation',
        CourtGlyph.clock,
        () => context.push('/cases/${detail.id}/verdict'),
      ),
      CaseStatus.completed => (
        'Read the verdict',
        CourtGlyph.gavel,
        () => context.push('/cases/${detail.id}/verdict'),
      ),
      CaseStatus.failed => (
        'Try the verdict again',
        CourtGlyph.refresh,
        () => context.push('/cases/${detail.id}/verdict'),
      ),
      CaseStatus.expired => (
        'File a new case',
        CourtGlyph.gavel,
        () => context.push('/cases/new'),
      ),
    };

    return BottomDock(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            prompt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: courtDisplayFont,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          CourtKey(label: label, glyph: glyph, onPressed: action),
        ],
      ),
    );
  }
}

/// Seat a friend on this case.
class _SeatPanel extends ConsumerStatefulWidget {
  const _SeatPanel({required this.detail});

  final CaseDetail detail;

  @override
  ConsumerState<_SeatPanel> createState() => _SeatPanelState();
}

class _SeatPanelState extends ConsumerState<_SeatPanel> {
  bool _busy = false;

  Future<void> _seat(String role) async {
    final friend = await pickUser(
      context,
      title: role == 'accused' ? 'Who is the accused?' : 'Who joins the jury?',
    );
    if (friend == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(caseActionsProvider)
          .addMember(widget.detail.id, friend.userId, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${friend.displayName} has been notified.')),
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
    final completed = widget.detail.status == CaseStatus.completed;
    return CourtCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Summon somebody'),
          const SizedBox(height: 8),
          Text(
            completed
                ? 'This case has been ruled on. The jury is closed.'
                : 'Pick a friend and they are told straight away. Someone '
                      'added by nickname only gets the link you send them.',
            style: context.text.bodySmall?.copyWith(
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 160,
                child: CourtKey(
                  label: 'Add a juror',
                  glyph: CourtGlyph.person,
                  height: 48,
                  onPressed: _busy || completed ? null : () => _seat('juror'),
                ),
              ),
              if (!widget.detail.defenseSubmitted)
                SizedBox(
                  width: 180,
                  child: CourtKey(
                    label: 'Name the accused',
                    glyph: CourtGlyph.plus,
                    height: 48,
                    fill: context.colors.surfaceContainerHighest,
                    foreground: context.colors.onSurface,
                    shadowInk: context.palette.shadowInk,
                    onPressed: _busy || completed
                        ? null
                        : () => _seat('accused'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The running count, which the creator may see at any time: they are not a
/// juror, so knowing the split cannot spoil a vote of their own.
class _JuryPanel extends StatelessWidget {
  const _JuryPanel({required this.tally});

  final JuryTally tally;

  @override
  Widget build(BuildContext context) => CourtCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('The jury so far'),
        const SizedBox(height: 10),
        Text(
          tally.summary,
          style: context.text.bodyMedium?.copyWith(
            color: context.palette.inkDim,
          ),
        ),
        const SizedBox(height: 14),
        JuryTallyBar(tally: tally),
      ],
    ),
  );
}

/// Explains, per status, exactly what the court is waiting for.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.detail});

  final CaseDetail detail;

  @override
  Widget build(BuildContext context) {
    final color = detail.status.color(context);

    return CourtCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detail.status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _explanation(detail),
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.inkDim,
            ),
          ),
        ],
      ),
    );
  }

  String _explanation(CaseDetail detail) => switch (detail.status) {
    CaseStatus.draft || CaseStatus.awaitingDefense =>
      'The summons has been issued. Nothing happens until '
          '${detail.defendantNickname ?? 'the defendant'} files a defense '
          '— but the jury can start voting right now.',
    CaseStatus.ready =>
      '${detail.defendantNickname ?? 'The defendant'} has filed a defense. '
          'Both sides are in — the court is ready to rule.',
    CaseStatus.generating =>
      'The judge is deliberating. This usually takes a few seconds.',
    CaseStatus.completed =>
      'The verdict has been handed down. Read it, then decide whether the '
          'world deserves to see it.',
    CaseStatus.failed =>
      'The court could not reach a verdict${detail.failureReason == null ? '' : ' (${detail.failureReason})'}. '
          'You can safely ask it to try again.',
    CaseStatus.expired =>
      'This case expired before a defense arrived. File a fresh one if it '
          'still matters.',
  };
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
    children: const [
      CourtSkeleton(height: 230),
      SizedBox(height: 16),
      CourtSkeleton(height: 54),
      SizedBox(height: 16),
      CourtSkeleton(height: 90),
      SizedBox(height: 12),
      CourtSkeleton(height: 90),
    ],
  );
}
