import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/sue_widgets.dart';
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
    final me =
        ref.watch(authControllerProvider).valueOrNull?.displayName ?? 'You';

    final back = RoundIconButton(
      glyph: CourtGlyph.back,
      label: 'Back',
      onTap: () => context.canPop() ? context.pop() : context.go('/'),
    );

    return CourtScaffold(
      title: 'Case file',
      tablet: _TabletCase(
        caseId: caseId,
        detail: detail,
        me: me,
        back: back,
        onDelete: () => _confirmDelete(context, ref),
      ),
      header: ScreenHeader(
        title: data == null
            ? 'Case file'
            : '$me v. ${data.defendantNickname ?? 'the accused'}',
        eyebrow: data == null
            ? null
            : '${_caseNumber(data.id)} · '
                  '${CaseCategory.byId(data.category).label.toUpperCase()}',
        titleSize: 24,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        leading: back,
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

/// The case file as the tablet artboards draw it: the title row, the charge
/// and the statements down the main column, and the case's progress, the jury
/// and the seats beside them once the window is landscape-wide.
class _TabletCase extends ConsumerWidget {
  const _TabletCase({
    required this.caseId,
    required this.detail,
    required this.me,
    required this.back,
    required this.onDelete,
  });

  final String caseId;
  final AsyncValue<CaseDetail> detail;
  final String me;
  final Widget back;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = detail.valueOrNull;

    return Column(
      children: [
        Expanded(
          child: SueTabletPage(
            header: Row(
              children: [
                back,
                const SizedBox(width: 14),
                Expanded(
                  child: SueTabletHeader(
                    title: data == null
                        ? 'Case file'
                        : '$me v. ${data.defendantNickname ?? 'the accused'}',
                    subtitle: data == null
                        ? null
                        : '${CaseDetailScreen._caseNumber(data.id)} · '
                              '${CaseCategory.byId(data.category).label.toUpperCase()}',
                  ),
                ),
                if (data != null) ...[
                  _Countdown(expiresAt: data.expiresAt),
                  const SizedBox(width: 10),
                  RoundIconButton(
                    glyph: CourtGlyph.trash,
                    label: 'Delete case',
                    onTap: onDelete,
                  ),
                ],
              ],
            ),
            child: detail.when(
              loading: () => const _DetailSkeleton(),
              error: (error, _) => CourtErrorView(
                message: error is ApiException
                    ? error.message
                    : 'Could not open this case file.',
                onRetry: () => ref.invalidate(caseDetailProvider(caseId)),
              ),
              data: (data) => RefreshIndicator(
                onRefresh: () async =>
                    ref.refresh(caseDetailProvider(caseId).future),
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SueColumns(
                      start: [
                        _Versus(
                          plaintiff: me,
                          accused: data.defendantNickname ?? 'The accused',
                          charge: data.title,
                        ),
                        _Statement(
                          label: 'PLAINTIFF · ${me.toUpperCase()}',
                          tone: SueTone.blue,
                          body: data.accusation,
                        ),
                        _Defense(
                          accused: data.defendantNickname ?? 'The accused',
                          defended: data.defenseSubmitted,
                        ),
                        CourtroomPanel(caseId: data.id),
                      ],
                      end: [
                        _Progress(step: CaseDetailScreen._stepFor(data.status)),
                        _StatusPanel(detail: data),
                        _JuryTray(detail: data),
                        if (data.juryTally != null && !data.juryTally!.isEmpty)
                          _JuryPanel(tally: data.juryTally!),
                        _SeatPanel(detail: data),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (data != null) _ActionDock(detail: data),
      ],
    );
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
      return const SuePill('CLOSED', tone: SueTone.gray);
    }
    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);
    return SuePill(
      hours > 0 ? '${hours}H ${minutes}M LEFT' : '${minutes}M LEFT',
      tone: SueTone.orange,
      round: false,
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        _Versus(plaintiff: me, accused: accused, charge: detail.title),
        const SizedBox(height: 12),
        _Progress(step: CaseDetailScreen._stepFor(detail.status)),
        const SizedBox(height: 12),
        // What the court is waiting for sits high: it is the first thing the
        // creator opens the file to find out.
        _StatusPanel(detail: detail),
        const SizedBox(height: 12),
        const Text(
          'Statements',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        _Statement(
          label: 'PLAINTIFF · ${me.toUpperCase()}',
          tone: SueTone.blue,
          body: detail.accusation,
        ),
        const SizedBox(height: 10),
        _Defense(accused: accused, defended: detail.defenseSubmitted),
        const SizedBox(height: 12),
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

/// The charge card: who is suing whom, and what over.
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
  Widget build(BuildContext context) => Semantics(
    label: '$plaintiff versus $accused',
    child: SueCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 70,
                height: 40,
                child: Stack(
                  children: [
                    SueAvatar(
                      name: plaintiff,
                      size: 40,
                      tone: SueTone.blue,
                      borderColor: context.colors.surfaceContainerHighest,
                    ),
                    Positioned(
                      left: 30,
                      child: SueAvatar(
                        name: accused,
                        size: 40,
                        tone: SueTone.orange,
                        borderColor: context.colors.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: plaintiff == 'You'
                        ? 'You are suing '
                        : '$plaintiff is suing ',
                    children: [
                      TextSpan(
                        text: accused,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: context.colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 13, color: context.palette.inkDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'THE CHARGE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            charge,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    ),
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
    final blue = palette.accent;
    final card = context.colors.surfaceContainerHighest;
    return Semantics(
      label: 'Step $step of ${_caseStages.length}: ${_caseStages[step - 1]}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _caseStages.length; i++)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        // The line to the next step, behind the dots.
                        if (i < _caseStages.length - 1)
                          Positioned(
                            top: 9,
                            left: box.maxWidth / 2,
                            width: box.maxWidth,
                            height: 2,
                            child: ColoredBox(
                              color: i + 1 < step ? blue : palette.surfaceAlt2,
                            ),
                          ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i + 1 < step ? blue : card,
                                border: i + 1 < step
                                    ? null
                                    : Border.all(
                                        color: i + 1 == step
                                            ? blue
                                            : palette.inkFaint,
                                        width: i + 1 == step ? 5 : 2,
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
                                fontWeight: FontWeight.w500,
                                color: i + 1 > step
                                    ? palette.inkDim
                                    : context.colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
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

/// A statement card: tracked label in the speaker's colour, then their words.
class _Statement extends StatelessWidget {
  const _Statement({
    required this.label,
    required this.tone,
    required this.body,
    this.muted = false,
  });

  final String label;
  final SueTone tone;
  final String body;
  final bool muted;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SueCard(
      small: true,
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
              color: tone.fg(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: muted ? context.palette.inkDim : context.colors.onSurface,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Defense extends StatelessWidget {
  const _Defense({required this.accused, required this.defended});

  final String accused;
  final bool defended;

  @override
  Widget build(BuildContext context) => _Statement(
    label: 'DEFENCE · ${accused.toUpperCase()}',
    tone: SueTone.orange,
    body: defended
        ? 'Filed. Sealed until the judge rules — the court does not hand '
              'the defense to the plaintiff.'
        : 'Nothing on the record yet. The court is waiting.',
    muted: !defended,
  );
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
    final shown = seated.clamp(0, 4);
    final bg = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          SizedBox(
            width: shown == 0 ? 0 : 30.0 + 22 * (shown - 1),
            height: 30,
            child: Stack(
              children: [
                for (var i = 0; i < shown; i++)
                  Positioned(
                    left: i * 22.0,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < voted
                            ? Color.alphaBlend(SueTone.teal.tint(context), bg)
                            : context.palette.surfaceAlt2,
                        border: Border.all(color: bg, width: 2),
                      ),
                      child: i < voted
                          ? CourtIcon(
                              CourtGlyph.check,
                              size: 14,
                              color: SueTone.teal.fg(context),
                              strokeWidth: 3.2,
                            )
                          : Text(
                              '?',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.palette.inkDim,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          if (seated > 0) const SizedBox(width: 14),
          Expanded(
            child: seated == 0
                ? Text(
                    'No jurors seated yet · votes stay sealed until the judge rules',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.palette.inkDim,
                    ),
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$voted of $seated',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: context.colors.onSurface,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' ${seated == 1 ? 'juror has' : 'jurors have'} voted · sealed until the ruling',
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.palette.inkDim,
                    ),
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
      CaseStatus.draft ||
      CaseStatus.awaitingDefense => 'Has the defendant answered?',
      CaseStatus.ready => 'Both sides are in.',
      CaseStatus.generating => 'The judge is deliberating.',
      CaseStatus.completed => 'The court has ruled.',
      CaseStatus.failed => 'The court could not reach a verdict.',
      CaseStatus.expired => 'This case has closed.',
    };

    final (label, _, action) = switch (detail.status) {
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
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 15,
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 12),
          SueButton(label: label, height: 56, onPressed: action),
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
                // Wide enough for the glyph and the label at the tracked
                // weight the key sets; at 160 both read as "Add a jur…".
                width: 186,
                child: CourtKey(
                  label: 'Add a juror',
                  glyph: CourtGlyph.person,
                  height: 48,
                  onPressed: _busy || completed ? null : () => _seat('juror'),
                ),
              ),
              if (!widget.detail.defenseSubmitted)
                SizedBox(
                  width: 224,
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

    return SizedBox(
      width: double.infinity,
      child: SueCard(
        small: true,
        radius: 18,
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
