import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/sue_tablet.dart';
import '../../../core/widgets/sue_widgets.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/widgets/verdict_reveal.dart';
import '../../cases/data/case_providers.dart';
import '../../game/data/game_providers.dart';

/// The ruling, drawn to the "Verdict" artboard: a stage band with the gavel,
/// the verdict as one huge word, the judge's words, and a share button.
class VerdictScreen extends ConsumerStatefulWidget {
  const VerdictScreen({super.key, required this.caseId});

  final String caseId;

  @override
  ConsumerState<VerdictScreen> createState() => _VerdictScreenState();
}

class _VerdictScreenState extends ConsumerState<VerdictScreen> {
  @override
  Widget build(BuildContext context) {
    final caseId = widget.caseId;
    final state = ref.watch(verdictControllerProvider(caseId));
    final controller = ref.read(verdictControllerProvider(caseId).notifier);
    // The jury's split is part of the case, not the verdict payload.
    final caseDetail = ref.watch(caseDetailProvider(caseId));
    final tally = caseDetail.valueOrNull?.juryTally;
    final accused = caseDetail.valueOrNull?.defendantNickname;

    final body = state.when(
      loading: () => const _Deliberating(),
      error: (error, _) => _Notice(
        title: 'Order in the court',
        message: error is ApiException
            ? error.message
            : 'The court is unavailable.',
        actionLabel: 'Try again',
        onAction: controller.refresh,
      ),
      data: (data) => switch (data.status) {
        // Wait for the case the first time: the reveal fixes its beats when it
        // mounts, so starting without the jury would drop it from the sequence
        // for good. A later refresh keeps the last value, so this never
        // re-blanks a verdict the user is already reading.
        CaseStatus.completed
            when data.verdict != null && !caseDetail.hasValue =>
          const _Deliberating(),
        CaseStatus.completed when data.verdict != null => VerdictReveal(
          verdict: data.verdict!,
          tally: tally,
          child: _VerdictView(
            caseId: caseId,
            verdict: data.verdict!,
            tally: tally,
            accused: accused,
          ),
        ),
        CaseStatus.generating => _Deliberating(
          timedOut: controller.timedOut,
          onRetry: controller.refresh,
        ),
        CaseStatus.ready => _Notice(
          title: 'Both sides are in',
          message:
              'The defense has been filed. Call the court to order '
              'and the judge will rule.',
          actionLabel: 'Call the court to order',
          onAction: controller.requestVerdict,
        ),
        CaseStatus.failed => _Notice(
          title: 'A mistrial',
          message:
              'The court could not reach a verdict. Nothing is lost '
              '— you can safely ask it to try again.',
          actionLabel: 'Retry the verdict',
          onAction: controller.requestVerdict,
        ),
        CaseStatus.expired => const _Notice(
          title: 'This case expired',
          message: 'It closed before both sides were heard.',
        ),
        _ => const _Notice(
          title: 'Still awaiting a defense',
          message:
              'The court cannot rule until the defendant has had their say.',
        ),
      },
    );

    final ruled = state.valueOrNull?.verdict;
    return _VerdictRoom(
      caseLabel: ruled?.caseTitle.isNotEmpty == true
          ? ruled!.caseTitle
          : caseDetail.valueOrNull?.title ?? 'The verdict',
      onClose: () =>
          context.canPop() ? context.pop() : context.go('/cases/$caseId'),
      child: body,
    );
  }
}

/// The page: a close button, the case label, and whatever the state is.
class _VerdictRoom extends StatelessWidget {
  const _VerdictRoom({
    required this.caseLabel,
    required this.onClose,
    required this.child,
  });

  final String caseLabel;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The tablet artboard opens the ruling with the same loud title row every
    // other tablet screen uses, inside the canvas's 28px page.
    if (context.isTablet) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        body: SueTabletPage(
          header: Row(
            children: [
              _CloseButton(onTap: onClose),
              const SizedBox(width: 14),
              Expanded(
                child: SueTabletHeader(title: 'Verdict', subtitle: caseLabel),
              ),
            ],
          ),
          child: child,
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  _CloseButton(onTap: onClose),
                  Expanded(
                    child: Text(
                      caseLabel.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                        color: context.palette.inkDim,
                      ),
                    ),
                  ),
                  const SizedBox(width: 46),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Close',
    child: Tooltip(
      message: 'Close',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.surfaceContainerHighest,
            boxShadow: courtHardShadow(context),
          ),
          child: const CourtIcon(CourtGlyph.close, size: 18, strokeWidth: 2.6),
        ),
      ),
    ),
  );
}

class _Deliberating extends StatelessWidget {
  const _Deliberating({this.timedOut = false, this.onRetry});

  final bool timedOut;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (timedOut) {
      return _Notice(
        title: 'The judge is taking their time',
        message:
            'Deliberation is still running. The verdict is not lost — '
            'check again in a moment.',
        actionLabel: onRetry == null ? null : 'Check again',
        onAction: onRetry,
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          const Text(
            'The court is in deliberation',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Both sides have been heard. The judge is weighing the '
              'evidence, such as it is.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: context.palette.inkDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every non-verdict state of the room, in one shape.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CourtIcon(CourtGlyph.gavel, size: 44, color: context.palette.accent),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: context.palette.inkDim,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: SueButton(
                label: actionLabel!,
                height: 54,
                onPressed: onAction,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _VerdictView extends ConsumerStatefulWidget {
  const _VerdictView({
    required this.caseId,
    required this.verdict,
    this.tally,
    this.accused,
  });

  final String caseId;
  final Verdict verdict;
  final JuryTally? tally;
  final String? accused;

  @override
  ConsumerState<_VerdictView> createState() => _VerdictViewState();
}

class _VerdictViewState extends ConsumerState<_VerdictView> {
  ShareLink? _shareLink;
  bool _busy = false;
  bool _showWorking = false;

  Future<void> _enableShare() async {
    setState(() => _busy = true);
    try {
      final link = await ref
          .read(caseActionsProvider)
          .enableShare(widget.caseId);
      if (!mounted) return;
      setState(() => _shareLink = link);
      await SharePlus.instance.share(
        ShareParams(
          text: '${widget.verdict.shareCaption} ${link.url}',
          subject: 'Sue Me — the verdict is in',
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

  Future<void> _revokeShare() async {
    setState(() => _busy = true);
    try {
      await ref.read(caseActionsProvider).revokeShare(widget.caseId);
      if (!mounted) return;
      setState(() => _shareLink = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Public link revoked. It no longer opens.'),
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
    final v = widget.verdict;
    final name = widget.accused ?? 'The accused';
    final overruled = v.verdict.overrules(widget.tally);
    final palette = context.palette;
    // After a ruling the defendant's record has moved; show where it landed
    // rather than inventing a delta.
    final sheet = ref.watch(rapSheetProvider).valueOrNull;
    final record = sheet
        ?.where((r) => r.displayName.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    final tone = switch (v.verdict) {
      VerdictKind.notGuilty => SueTone.teal,
      VerdictKind.insufficientEvidence => SueTone.gray,
      _ => SueTone.orange,
    };
    // 60px is the artboard's; the longer rulings step down to stay on one line.
    final wordSize = v.verdict.label.length > 10 ? 40.0 : 60.0;

    // The finding — the stage, the line and the word — and everything the
    // court said after it. On a landscape tablet the artboard sets the two
    // side by side; everywhere else they run one after the other.
    final finding = <Widget>[
      SueStage(tone: tone),
      const SizedBox(height: 16),
      Text(
        'THE COURT FINDS ${name.toUpperCase()}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.5,
          color: palette.inkDim,
        ),
      ),
      const SizedBox(height: 2),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(
            _title(v.verdict),
            key: const Key('verdict-stamp'),
            style: TextStyle(
              fontSize: wordSize,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -1,
              color: tone.fg(context),
            ),
          ),
          if (overruled)
            Container(
              key: const Key('overruled'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: SueTone.blue.tint(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.tally == null
                    ? 'JUDGE OVERRULED\nTHE JURY'
                    : 'JUDGE OVERRULED\nJURY SAID ${widget.tally!.guilty}–${widget.tally!.notGuilty}'
                          ' ${widget.tally!.guilty > widget.tally!.notGuilty ? 'GUILTY' : 'NOT GUILTY'}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  height: 1.3,
                  color: SueTone.blue.fg(context),
                ),
              ),
            ),
        ],
      ),
    ];

    final ruling = <Widget>[
      _RulingCard(verdict: v),
      const SizedBox(height: 12),
      _RewardsCard(caseId: widget.caseId),
      if (record != null) ...[
        const SizedBox(height: 12),
        SueCard(
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RAP SHEET',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                        color: palette.inkDim,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.convictions} guilty',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: SueTone.orange.fg(context),
                      ),
                    ),
                  ],
                ),
              ),
              SuePill(
                record.title.toUpperCase(),
                tone: SueTone.gold,
                round: false,
              ),
            ],
          ),
        ),
      ],
      if (widget.tally != null && !widget.tally!.isEmpty) ...[
        const SizedBox(height: 12),
        SueCard(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THE JURY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                  color: palette.inkDim,
                ),
              ),
              const SizedBox(height: 10),
              VoteBar(
                key: const Key('jury-tally'),
                guilty: widget.tally!.guilty,
                notGuilty: widget.tally!.notGuilty,
              ),
              if (overruled) ...[
                const SizedBox(height: 12),
                Text(
                  v.juryNote.isNotEmpty
                      ? v.juryNote
                      : 'The court thanks the jury for its time, and disagrees.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.inkDim,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 8),
      _WorkingToggle(
        open: _showWorking,
        onToggle: () => setState(() => _showWorking = !_showWorking),
      ),
      if (_showWorking) ...[const SizedBox(height: 6), _Working(verdict: v)],
      const SizedBox(height: 14),
      if (_shareLink == null)
        SueButton(
          label: 'SHARE THE VERDICT',
          height: 56,
          busy: _busy,
          onPressed: _busy ? null : _enableShare,
        )
      else ...[
        SueCard(
          radius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PUBLIC LINK IS LIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: SueTone.teal.fg(context),
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                _shareLink!.url,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SueButton(
                      label: 'COPY',
                      height: 46,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _shareLink!.url),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied.')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SueButton(
                      label: 'REVOKE',
                      height: 46,
                      tone: SueTone.orange,
                      onPressed: _busy ? null : _revokeShare,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SueButton(
          label: 'SHARE AGAIN',
          height: 56,
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: '${v.shareCaption} ${_shareLink!.url}'),
          ),
        ),
      ],
      const SizedBox(height: 6),
      Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.go('/rap-sheet'),
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                'See the rap sheet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ),
      ),
      const CourtDisclaimer(
        text:
            'Publishing is opt-in and reversible. The public page shows only '
            'the verdict — never the raw accusation or defense.',
      ),
    ];

    Widget stack(List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: items,
    );

    if (context.isWideTablet) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          SueColumns(start: [stack(finding)], end: [stack(ruling)]),
        ],
      );
    }

    return ListView(
      padding: context.isTablet
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [stack(finding), const SizedBox(height: 12), stack(ruling)],
    );
  }

  /// "Guilty", "Not guilty": the artboard sets the word in sentence case.
  static String _title(VerdictKind k) {
    final l = k.label.toLowerCase();
    return l[0].toUpperCase() + l.substring(1);
  }
}

/// The judge's own words, then the sentence.
class _RulingCard extends StatelessWidget {
  const _RulingCard({required this.verdict});

  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: double.infinity,
      child: SueCard(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'JUDGE BYTE RULES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
                color: palette.inkDim,
              ),
            ),
            if (verdict.charge.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                verdict.charge,
                style: TextStyle(fontSize: 13, color: palette.inkDim),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '“${verdict.judgeRoast.isEmpty ? verdict.reasoning : verdict.judgeRoast}”',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            if (verdict.sentence.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: palette.surfaceAlt)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SuePill('SENTENCE', round: false),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        verdict.sentence,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (verdict.closingLine.isNotEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  verdict.closingLine,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: palette.inkDim),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkingToggle extends StatelessWidget {
  const _WorkingToggle({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: open,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                open ? 'Hide the working' : 'How the court got there',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: context.palette.inkDim,
                ),
              ),
            ),
            CourtIcon(
              open ? CourtGlyph.chevronDown : CourtGlyph.chevronRight,
              size: 18,
              color: context.palette.inkDim,
              strokeWidth: 2.6,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Working extends StatelessWidget {
  const _Working({required this.verdict});

  final Verdict verdict;

  @override
  Widget build(BuildContext context) => SueCard(
    radius: 20,
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(label: 'PROSECUTION', body: verdict.prosecutionSummary),
          _Section(label: 'DEFENSE', body: verdict.defenseSummary),
          _Section(label: 'REASONING', body: verdict.reasoning, last: true),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.body, this.last = false});

  final String label;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
            color: context.palette.inkDim,
          ),
        ),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(fontSize: 15, height: 1.45)),
      ],
    ),
  );
}

/// "YOUR REWARDS": what this ruling paid you.
///
/// Drawn only when the case actually paid this player something. A case you
/// were not part of, or one the judge has not ruled on, has no rows — and an
/// empty rewards card would be a lie dressed as a reward.
class _RewardsCard extends ConsumerWidget {
  const _RewardsCard({required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewards = ref.watch(caseRewardsProvider(caseId)).valueOrNull;
    if (rewards == null || rewards.isEmpty) return const SizedBox.shrink();

    final palette = context.palette;
    final badges = rewards.items.where((r) => r.badgeCode != null).toList();
    final lines = rewards.items.where((r) => r.xp != 0).toList();

    return SueCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'YOUR REWARDS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: palette.inkDim,
                  ),
                ),
              ),
              if (rewards.levelReached != null)
                Container(
                  key: const Key('level-up'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: CourtColors.gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'LEVEL UP · LV ${rewards.levelReached}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: CourtColors.lightInk,
                    ),
                  ),
                ),
            ],
          ),
          for (final line in lines) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.detail,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '+${line.xp} XP',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.accent,
                  ),
                ),
              ],
            ),
          ],
          for (final badge in badges) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.lineSoft)),
              ),
              child: Row(
                children: [
                  HexBadge(
                    // The badge's own initial: Outfit has no star, and a
                    // missing glyph draws as an empty box.
                    glyph: (badge.badgeName ?? badge.detail).isEmpty
                        ? '?'
                        : (badge.badgeName ?? badge.detail)[0].toUpperCase(),
                    label: '',
                    earned: true,
                    tone: SueTone.orange,
                    width: 30,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Badge unlocked: ',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: badge.badgeName ?? badge.detail),
                        ],
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  if (badge.coins > 0) ...[
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SueCoin(size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '+${badge.coins}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
