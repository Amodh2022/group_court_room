import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_chrome.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/widgets/verdict_reveal.dart';
import '../../cases/data/case_providers.dart';

/// The ruling, drawn to the "Verdict" artboard: a dark room with the light
/// behind the bench, the stamp slammed down on it, and the judge's words
/// underneath.
///
/// The room is the same colour in light mode and dark mode. A verdict is a
/// moment, not a page, and the canvas gives it one set of colours.
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

/// The room itself: ink-plum, the rays behind the bench, and the one piece of
/// chrome allowed over it — the way out.
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
  Widget build(BuildContext context) => Theme(
    // The room is dark whatever the app's mode, so the widgets inside it read
    // their own colours from a dark theme rather than second-guessing.
    data: courtDarkTheme().copyWith(
      scaffoldBackgroundColor: CourtColors.stageLight,
    ),
    child: Scaffold(
      backgroundColor: CourtColors.stageLight,
      body: Stack(
        children: [
          const Positioned.fill(child: _Rays()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      _CloseButton(onTap: onClose),
                      Expanded(
                        child: Text(
                          caseLabel,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: CourtColors.stageDim,
                          ),
                        ),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CourtColors.stageChipLight,
            border: Border.all(color: Colors.black, width: courtBorderWidth),
          ),
          child: const CourtIcon(
            CourtGlyph.close,
            size: 18,
            color: CourtColors.stageInk,
            strokeWidth: 3,
          ),
        ),
      ),
    ),
  );
}

/// The light behind the bench: a slow wheel of red rays, faded out into the
/// room so it never touches the text.
class _Rays extends StatefulWidget {
  const _Rays();

  @override
  State<_Rays> createState() => _RaysState();
}

class _RaysState extends State<_Rays> with SingleTickerProviderStateMixin {
  AnimationController? _spin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A controller that repeats forever keeps a frame permanently scheduled,
    // so `pumpAndSettle` would never return and the GPU would never idle.
    // Widget tests run with animations disabled, and so does a phone whose
    // owner asked for less motion — both get a still room.
    final wants = !MediaQuery.disableAnimationsOf(context);
    if (wants && _spin == null) {
      _spin = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 40),
      )..repeat();
    } else if (!wants && _spin != null) {
      _spin!.dispose();
      _spin = null;
    }
  }

  @override
  void dispose() {
    _spin?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _spin == null
        ? const CustomPaint(painter: _RaysPainter(0))
        : AnimatedBuilder(
            animation: _spin!,
            builder: (_, __) =>
                CustomPaint(painter: _RaysPainter(_spin!.value)),
          );
    return ExcludeSemantics(
      child: SizedBox.expand(child: RepaintBoundary(child: painter)),
    );
  }
}

class _RaysPainter extends CustomPainter {
  const _RaysPainter(this.turn);

  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, 240);
    final radius = size.longestSide * 1.2;
    final paint = Paint()..color = const Color(0x47FF3B52);

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(turn * 2 * math.pi);
    const wedges = 18;
    for (var i = 0; i < wedges; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        i * 2 * math.pi / wedges,
        math.pi / wedges,
        true,
        paint,
      );
    }
    canvas.restore();

    // Fade the wheel back into the room, so the rays are a glow behind the
    // bench rather than a pattern across the text.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(0, (240 / size.height) * 2 - 1),
          radius: 460 / size.shortestSide,
          colors: const [
            Color(0x00171023),
            Color(0x00171023),
            CourtColors.stageLight,
          ],
          stops: const [0, 0.3, 1],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.turn != turn;
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
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: CourtColors.yellow,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'The court is in deliberation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: courtDisplayFont,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: CourtColors.stageInk,
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Both sides have been heard. The judge is weighing the '
              'evidence, such as it is.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: CourtColors.stageDim,
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
          const CourtIcon(
            CourtGlyph.gavel,
            size: 44,
            color: CourtColors.yellow,
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: courtDisplayFont,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: CourtColors.stageInk,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: CourtColors.stageDim,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: CourtKey(label: actionLabel!, onPressed: onAction),
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
    // After a ruling the defendant's record has moved; show where it landed
    // rather than inventing a delta.
    final sheet = ref.watch(rapSheetProvider).valueOrNull;
    final record = sheet
        ?.where((r) => r.displayName.toLowerCase() == name.toLowerCase())
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Center(
          child: Text(
            'THE COURT FINDS',
            style: TextStyle(
              fontFamily: courtDisplayFont,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: 4,
              color: CourtColors.yellow,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Column(
            children: [
              Container(
                width: 136,
                height: 136,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tintFor(name),
                  border: Border.all(color: CourtColors.stageInk, width: 5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, offset: Offset(0, 6)),
                  ],
                ),
                child: Text(
                  name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: courtDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 58,
                    height: 1,
                    color: CourtColors.lightInk,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: courtDisplayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 32,
                  height: 1,
                  color: CourtColors.stageInk,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(child: VerdictStamp(verdict: v.verdict, animate: true)),
        if (overruled) ...[
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: CourtColors.orange,
                borderRadius: BorderRadius.circular(courtRadiusPill),
                border: Border.all(color: Colors.black, width: courtBorderWidth),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CourtIcon(
                    CourtGlyph.warn,
                    size: 16,
                    color: CourtColors.lightInk,
                    strokeWidth: 3,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.tally == null
                          ? 'JUDGE OVERRULED THE JURY'
                          : 'JUDGE OVERRULED THE JURY · '
                                '${widget.tally!.guilty}–${widget.tally!.notGuilty}',
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: CourtColors.lightInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _RulingCard(verdict: v),
        if (record != null) ...[
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StageTile(
                    label: 'RAP SHEET',
                    value: '${record.convictions} guilty',
                    valueColor: CourtColors.redOnStage,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StageTile(
                    label: 'THEIR TITLE',
                    value: record.title,
                    valueColor: CourtColors.yellow,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.tally != null && !widget.tally!.isEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CourtColors.stageChipLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'THE JURY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: CourtColors.stageDim,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.tally!.summary,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CourtColors.stageInk,
                  ),
                ),
                const SizedBox(height: 12),
                JuryTallyBar(tally: widget.tally!),
                if (overruled)
                  OverruledBanner(
                    note: v.juryNote.isNotEmpty
                        ? v.juryNote
                        : 'The court thanks the jury for its time, and disagrees.',
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _WorkingToggle(
          open: _showWorking,
          onToggle: () => setState(() => _showWorking = !_showWorking),
        ),
        if (_showWorking) ...[
          const SizedBox(height: 10),
          _Working(verdict: v),
        ],
        const SizedBox(height: 20),
        if (_shareLink == null)
          CourtKey(
            label: 'Post to the group chat',
            glyph: CourtGlyph.share,
            onPressed: _busy ? null : _enableShare,
            busy: _busy,
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CourtColors.stageChipLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PUBLIC LINK IS LIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: CourtColors.yellow,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  _shareLink!.url,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: CourtColors.stageInk,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CourtKey(
                        label: 'Copy',
                        height: 46,
                        fill: CourtColors.stageLight,
                        foreground: CourtColors.stageInk,
                        shadowInk: Colors.black,
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
                      child: CourtKey(
                        label: 'Revoke',
                        height: 46,
                        fill: CourtColors.stageLight,
                        foreground: CourtColors.redOnStage,
                        shadowInk: Colors.black,
                        onPressed: _busy ? null : _revokeShare,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CourtKey(
            label: 'Share again',
            glyph: CourtGlyph.share,
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: '${v.shareCaption} ${_shareLink!.url}'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        CourtKey(
          label: 'See the rap sheet',
          height: 50,
          fill: Colors.transparent,
          foreground: CourtColors.stageInk,
          shadowInk: Colors.transparent,
          onPressed: () => context.go('/rap-sheet'),
        ),
        const CourtDisclaimer(
          text:
              'Publishing is opt-in and reversible. The public page shows only '
              'the verdict — never the raw accusation or defense.',
        ),
      ],
    );
  }
}

/// The judge's own words, on cream so they read as the document they are.
class _RulingCard extends StatelessWidget {
  const _RulingCard({required this.verdict});

  final Verdict verdict;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: CourtColors.lightBg,
      borderRadius: BorderRadius.circular(courtRadiusLg),
      border: Border.all(color: Colors.black, width: courtBorderWidth),
      boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(0, 5))],
    ),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CourtColors.yellow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CourtColors.lightInk,
                  width: courtBorderWidth,
                ),
              ),
              child: const CourtIcon(
                CourtGlyph.gavel,
                size: 20,
                color: CourtColors.lightInk,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'The Honourable Judge Byte',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: courtDisplayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: CourtColors.lightInk,
                ),
              ),
            ),
          ],
        ),
        if (verdict.charge.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            verdict.charge,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: CourtColors.lightInkDim,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '“${verdict.judgeRoast.isEmpty ? verdict.reasoning : verdict.judgeRoast}”',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.4,
            color: CourtColors.lightInk,
          ),
        ),
        if (verdict.sentence.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: CourtColors.lightTray2,
              borderRadius: BorderRadius.circular(courtRadiusSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SENTENCE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: CourtColors.redText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  verdict.sentence,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                    color: CourtColors.lightInk,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (verdict.closingLine.isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              verdict.closingLine,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: courtDisplayFont,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: CourtColors.lightInkDim,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: CourtColors.stageChipLight,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: CourtColors.stageDim,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: courtDisplayFont,
            fontWeight: FontWeight.w700,
            fontSize: 19,
            height: 1.1,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
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
      borderRadius: BorderRadius.circular(courtRadiusPill),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                open ? 'Hide the working' : 'How the court got there',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: CourtColors.stageDim,
                ),
              ),
            ),
            CourtIcon(
              open ? CourtGlyph.chevronDown : CourtGlyph.chevronRight,
              size: 18,
              color: CourtColors.stageDim,
              strokeWidth: 3,
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CourtColors.stageChipLight,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(label: 'PROSECUTION', body: verdict.prosecutionSummary),
        _Section(label: 'DEFENSE', body: verdict.defenseSummary),
        _Section(label: 'REASONING', body: verdict.reasoning, last: true),
      ],
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
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: CourtColors.stageDim,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.45,
            color: CourtColors.stageInk,
          ),
        ),
      ],
    ),
  );
}
