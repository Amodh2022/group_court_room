import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import 'court_stage.dart';

/// One line of courtroom theatre.
class _Beat {
  const _Beat(this.line, {this.sub, this.gavel = false, required this.ms});

  final String line;
  final String? sub;
  final bool gavel;
  final int ms;
}

/// The verdict as theatre: a few beats of anticipation, then the ruling.
///
/// The content is identical either way — the sequence only controls when it
/// arrives. Skipping, or a device that asks for reduced motion, goes straight
/// to [child].
class VerdictReveal extends StatefulWidget {
  const VerdictReveal({
    super.key,
    required this.verdict,
    required this.tally,
    required this.child,
    this.onStage,
  });

  final Verdict verdict;
  final JuryTally? tally;

  /// Fires with [CourtScene.rise] while the beats play and [CourtScene.verdict]
  /// once the ruling lands, so a stage above can move the camera in step with
  /// the theatre.
  final ValueChanged<CourtScene>? onStage;

  /// The full ruling, shown once the sequence finishes.
  final Widget child;

  @override
  State<VerdictReveal> createState() => _VerdictRevealState();
}

class _VerdictRevealState extends State<VerdictReveal> {
  late final List<_Beat> _beats = _build();
  int _index = 0;
  Timer? _timer;
  bool _started = false;

  List<_Beat> _build() {
    final tally = widget.tally;
    return [
      const _Beat('All rise.', gavel: true, ms: 1500),
      _Beat(
        'The court has reached a decision.',
        sub: widget.verdict.caseTitle,
        ms: 2000,
      ),
      if (tally != null && !tally.isEmpty)
        _Beat(tally.summary, sub: 'The judge is not bound by it.', ms: 2000),
      _Beat(
        'Judge Byte will now deliver the verdict.',
        sub: widget.verdict.charge,
        ms: 1800,
      ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // A device set to reduce motion gets the ruling, not the performance.
    if (MediaQuery.disableAnimationsOf(context)) {
      _index = _beats.length;
    } else {
      _schedule();
    }
    _announce();
  }

  /// Told after the frame, never during build: the listener above is a parent,
  /// and setting its state mid-build is an error.
  void _announce() {
    final done = _index >= _beats.length;
    if (done) _landed();
    final notify = widget.onStage;
    if (notify == null) return;
    final stage = done ? CourtScene.verdict : CourtScene.rise;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notify(stage);
    });
  }

  bool _hasLanded = false;

  /// The ruling arriving, in the hand. The gavel strike itself belongs to the
  /// stage — this is the stamp coming down after it, and it fires once however
  /// the sequence ended, skipped or played in full.
  void _landed() {
    if (_hasLanded) return;
    _hasLanded = true;
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;

    final overruled = widget.verdict.verdict.overrules(widget.tally);
    if (!overruled) {
      HapticFeedback.mediumImpact();
      return;
    }
    // The best outcome in the game gets its own rhythm, so a player learns to
    // recognise it before they have read a word: strike, beat, strike.
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) HapticFeedback.heavyImpact();
    });
  }

  void _schedule() {
    _timer?.cancel();
    if (_index >= _beats.length) return;
    _timer = Timer(Duration(milliseconds: _beats[_index].ms), () {
      if (!mounted) return;
      setState(() => _index++);
      _announce();
      _schedule();
    });
  }

  void _skip() {
    _timer?.cancel();
    setState(() => _index = _beats.length);
    _announce();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= _beats.length) return widget.child;

    final beat = _beats[_index];
    return Center(
      key: const Key('verdict-reveal'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (beat.gavel)
              const _SwingingGavel()
            else
              Icon(Icons.more_horiz, size: 42, color: context.palette.accent),
            const SizedBox(height: 26),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Column(
                key: ValueKey(_index),
                children: [
                  Text(
                    beat.line,
                    textAlign: TextAlign.center,
                    style: context.text.headlineMedium,
                  ),
                  if (beat.sub != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      beat.sub!,
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(
                        color: context.palette.inkDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 34),
            TextButton(
              onPressed: _skip,
              child: const Text('Skip to the verdict'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwingingGavel extends StatefulWidget {
  const _SwingingGavel();

  @override
  State<_SwingingGavel> createState() => _SwingingGavelState();
}

class _SwingingGavelState extends State<_SwingingGavel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      // Wind up, strike, settle — then hold still for the rest of the loop.
      final t = _controller.value;
      final angle = t < 0.25
          ? -0.45 * (t / 0.25)
          : t < 0.4
          ? -0.45 + 0.55 * ((t - 0.25) / 0.15)
          : t < 0.6
          ? 0.10 * (1 - (t - 0.4) / 0.2)
          : 0.0;
      return Transform.rotate(
        angle: angle,
        alignment: Alignment.bottomRight,
        child: child,
      );
    },
    child: const Text('🔨', style: TextStyle(fontSize: 64)),
  );
}
