import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Where the camera is standing. The same names the web app uses, so a change
/// to the choreography can be made in both places from one description.
enum CourtScene {
  arrival,
  charge,
  defense,
  deliberation,
  ballot,
  rise,
  verdict,
  record,
}

/// A camera position, and how the room looks from it.
///
/// [z] is a scale rather than a translation — the stage is flat layers, so
/// pushing in means growing the backdrop while the content holds still.
/// [heat] slides the backdrop from courthouse-cold to judgment-hot.
@immutable
class CourtShot {
  const CourtShot({
    required this.z,
    required this.y,
    required this.heat,
    required this.sway,
    required this.ms,
  });

  final double z;
  final double y;
  final double heat;

  /// How far the gaze parallax may push a layer, in logical pixels.
  final double sway;

  /// The move *into* this shot.
  final int ms;

  static const _shots = <CourtScene, CourtShot>{
    CourtScene.arrival: CourtShot(
      z: 1.14,
      y: 10,
      heat: 0.15,
      sway: 22,
      ms: 900,
    ),
    CourtScene.charge: CourtShot(z: 1.0, y: 0, heat: 0.35, sway: 16, ms: 700),
    CourtScene.defense: CourtShot(
      z: 1.02,
      y: -6,
      heat: 0.30,
      sway: 16,
      ms: 700,
    ),
    CourtScene.deliberation: CourtShot(
      z: 0.96,
      y: 0,
      heat: 0.45,
      sway: 10,
      ms: 700,
    ),
    CourtScene.ballot: CourtShot(z: 1.08, y: 4, heat: 0.55, sway: 8, ms: 600),
    // The one shot that moves fast and hard. Everything else is a drift.
    CourtScene.rise: CourtShot(z: 1.34, y: -34, heat: 0.95, sway: 4, ms: 420),
    CourtScene.verdict: CourtShot(z: 1.0, y: 0, heat: 0.80, sway: 14, ms: 900),
    CourtScene.record: CourtShot(z: 0.94, y: 0, heat: 0.25, sway: 18, ms: 700),
  };

  static CourtShot of(CourtScene scene) =>
      _shots[scene] ?? _shots[CourtScene.charge]!;
}

/// The room. One widget, kept alive for the whole case, with the backdrop, the
/// dust and the bench surviving every scene change — that persistence is the
/// point. Only [child] swaps, and it cross-fades rather than pushing a route.
///
/// There is no accelerometer here on purpose: the app does not carry a sensor
/// package, and asking for motion permission to tilt a gradient is not a trade
/// worth making. The gaze comes from where the finger is.
///
/// The room never stops moving. The dust drifts, the camera breathes and the
/// bench glow pulses on a single perpetual clock, because a backdrop that only
/// reacts to your thumb is a hover effect, not an animation — sit still and it
/// would be a photograph.
///
/// That clock is gated on [MediaQuery.disableAnimationsOf]. It has to be: a
/// controller that repeats forever keeps a frame permanently scheduled, so
/// `pumpAndSettle` would never return and the GPU would never idle. Widget
/// tests run with animations disabled, and so does a phone whose owner asked
/// for less motion — both get a still room and a settling test.
class CourtStage extends StatefulWidget {
  const CourtStage({
    super.key,
    required this.scene,
    required this.child,
    this.hud,
  });

  final CourtScene scene;
  final Widget child;
  final Widget? hud;

  @override
  State<CourtStage> createState() => _CourtStageState();
}

class _CourtStageState extends State<CourtStage> with TickerProviderStateMixin {
  /// The clock everything ambient runs on. One controller for the whole room:
  /// seventy specks with seventy controllers would be seventy tickers.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  /// The gavel landing. Short and violent on purpose — it is the only moment
  /// in the app that hits rather than eases.
  late final AnimationController _impact = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  /// -1..1 from the centre of the stage.
  Offset _gaze = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ambient.isAnimating) {
      _ambient.stop();
    } else if (!still && !_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  @override
  void didUpdateWidget(CourtStage old) {
    super.didUpdateWidget(old);
    if (old.scene == widget.scene) return;
    // One scene is a strike, not a move. The room takes the hit and the phone
    // reports it — a gavel you only see is a picture of a gavel.
    if (widget.scene == CourtScene.rise &&
        !MediaQuery.disableAnimationsOf(context)) {
      _impact.forward(from: 0);
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    _impact.dispose();
    super.dispose();
  }

  void _track(Offset local, Size size) {
    if (size.isEmpty) return;
    setState(() {
      _gaze = Offset(
        (local.dx / size.width) * 2 - 1,
        (local.dy / size.height) * 2 - 1,
      ).clampToUnit();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shot = CourtShot.of(widget.scene);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final ms = reduced ? 0 : shot.ms;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          // Listener, not GestureDetector: the gaze must never compete with the
          // scroll, the chat or a button for the gesture arena.
          behavior: HitTestBehavior.translucent,
          onPointerMove: (event) => _track(event.localPosition, size),
          onPointerHover: (event) => _track(event.localPosition, size),
          child: AnimatedBuilder(
            animation: Listenable.merge([_ambient, _impact]),
            builder: (context, _) {
              // The breath. Three different periods, so the room never
              // visibly repeats, and amplitudes small enough to read as
              // "alive" rather than "the page is sliding about".
              final t = _ambient.value * 2 * math.pi;
              final breath = reduced
                  ? Offset.zero
                  : Offset(
                      math.sin(t) * 0.26 + math.sin(t * 2.3) * 0.10,
                      math.cos(t * 0.7) * 0.18,
                    );
              final gaze = reduced
                  ? Offset.zero
                  : (_gaze + breath).clampToUnit();
              final swell = reduced ? 1.0 : 1 + math.sin(t * 1.3) * 0.012;

              // A damped rattle: three fast swings that die to nothing, so the
              // room settles rather than wobbling.
              final hit = _impact.isAnimating || _impact.value > 0
                  ? math.sin(_impact.value * math.pi * 6) *
                        (1 - _impact.value) *
                        9
                  : 0.0;

              return Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedContainer(
                    duration: Duration(milliseconds: ms),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.identity()
                      ..translateByDouble(hit, hit * 0.6, 0.0, 1.0)
                      ..translateByDouble(0.0, reduced ? 0.0 : shot.y, 0.0, 1.0)
                      ..scaleByDouble(
                        reduced ? 1.0 : shot.z * swell,
                        reduced ? 1.0 : shot.z * swell,
                        1.0,
                        1.0,
                      ),
                    transformAlignment: Alignment.center,
                    child: Transform.scale(
                      // Bleed: a shot that pulls back (z < 1) would otherwise
                      // expose the scaffold at the edges of the room.
                      scale: 1.16,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _Layer(
                            gaze: gaze,
                            sway: shot.sway,
                            depth: 0.9,
                            child: _Sky(heat: shot.heat, ms: ms),
                          ),
                          _Layer(
                            gaze: gaze,
                            sway: shot.sway,
                            depth: 0.55,
                            child: _Dust(t: _ambient.value, heat: shot.heat),
                          ),
                          _Layer(
                            gaze: gaze,
                            sway: shot.sway,
                            depth: 0.30,
                            child: _Bench(
                              pulse: reduced ? 0.0 : _ambient.value,
                            ),
                          ),
                          // Negative depth: the haze rides *with* the finger,
                          // which is what sells it sitting in front of your face.
                          _Layer(
                            gaze: gaze,
                            sway: shot.sway,
                            depth: -0.25,
                            child: _Haze(heat: shot.heat, ms: ms),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // The content cross-fades. Keyed on the scene so two scenes
                  // that happen to render the same widget still transition.
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: reduced ? 0 : 420),
                    switchInCurve: Curves.easeOutCubic,
                    child: KeyedSubtree(
                      key: ValueKey(widget.scene),
                      child: widget.child,
                    ),
                  ),

                  // Outside the camera: the HUD must not move when the room
                  // does, because it is how you leave.
                  if (widget.hud != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(bottom: false, child: widget.hud!),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

extension on Offset {
  Offset clampToUnit() => Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
}

class _Layer extends StatelessWidget {
  const _Layer({
    required this.gaze,
    required this.sway,
    required this.depth,
    required this.child,
  });

  final Offset gaze;
  final double sway;
  final double depth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(-gaze.dx * sway * depth, -gaze.dy * sway * depth),
    child: child,
  );
}

class _Sky extends StatelessWidget {
  const _Sky({required this.heat, required this.ms});

  final double heat;
  final int ms;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      AnimatedContainer(
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(CourtColors.yellow, CourtColors.orange, heat * 0.5)!,
              CourtColors.heroPink,
              CourtColors.heroViolet,
              Color.lerp(CourtColors.heroBlue, CourtColors.blue, heat * 0.4)!,
            ],
            stops: const [0.0, 0.36, 0.70, 1.0],
          ),
        ),
      ),
      // The glow off the bench, which is what warms the room as the case
      // heats up. Separate from the ramp above so the two can be read — and
      // tuned — independently, exactly as they are on the web.
      AnimatedContainer(
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, 0.7 - heat * 0.6),
            radius: 0.95,
            colors: [
              CourtColors.orange.withValues(alpha: 0.22 + heat * 0.38),
              CourtColors.orange.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    ],
  );
}

/// The dust in the light. Painted rather than built: seventy positioned
/// widgets would be seventy render objects re-laid-out every frame, and this
/// field never stops moving.
class _Dust extends StatelessWidget {
  const _Dust({required this.t, required this.heat});

  /// The ambient clock, 0..1, wrapping.
  final double t;
  final double heat;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DustPainter(t: t, heat: heat),
    isComplex: true,
  );
}

class _DustPainter extends CustomPainter {
  _DustPainter({required this.t, required this.heat});

  final double t;
  final double heat;

  static const _count = 64;

  /// Deterministic per-speck constants. A real RNG re-rolled each frame would
  /// make the field flicker; seeding from the index keeps every speck on its
  /// own fixed path forever.
  static double _hash(int i, int salt) {
    final x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < _count; i++) {
      final column = _hash(i, 1);
      final radius = 0.7 + _hash(i, 2) * 2.4;
      final rise = 0.05 + _hash(i, 3) * 0.22;
      final sway = 3 + _hash(i, 4) * 20;
      final speed = 0.6 + _hash(i, 5) * 2.4;
      final alpha = 0.16 + _hash(i, 6) * 0.46;

      // Each speck climbs at its own rate and wraps, offset by its own phase so
      // the field never pulses in unison.
      final climb = (t * rise * 10 + _hash(i, 7)) % 1.0;
      final y = (1.05 - climb) * size.height;
      final x =
          column * size.width +
          math.sin((t * speed + column) * 2 * math.pi) * sway;

      // The hotter the room, the more of the dust catches the bench light.
      final ember = radius > 2.2 && heat > 0.5;
      paint.color = ember
          ? const Color(0xFFFFC478).withValues(alpha: alpha * heat)
          : Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => old.t != t || old.heat != heat;
}

/// The bench. The one persistent object in the room — it is what the camera
/// pushes toward on [CourtScene.rise], so it must never be rebuilt from
/// scratch between scenes.
class _Bench extends StatelessWidget {
  const _Bench({required this.pulse});

  /// The ambient clock, 0..1. Drives the glow's heartbeat.
  final double pulse;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth * 0.64, 520.0);
        // A slow heartbeat, so the room has a pulse even in a scene where
        // nothing at all is happening.
        final beat = 0.5 + 0.5 * math.sin(pulse * 2 * math.pi * 4.4);

        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: -constraints.maxHeight * 0.06,
              child: IgnorePointer(
                child: Container(
                  width: math.min(constraints.maxWidth * 0.96, 760.0),
                  height: constraints.maxHeight * 0.46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        CourtColors.orange.withValues(
                          alpha: 0.18 + beat * 0.22,
                        ),
                        CourtColors.orange.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: constraints.maxHeight * 0.04,
              child: Opacity(
                opacity: 0.55,
                child: Container(
                  width: width,
                  height: width,
                  decoration: BoxDecoration(
                    color: scheme.onInverseSurface.withValues(alpha: 0.70),
                    border: Border.all(color: palette.line, width: 3),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(width / 2),
                      bottom: const Radius.circular(28),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: math.min(constraints.maxWidth * 0.84, 680.0),
              height: constraints.maxHeight * 0.16,
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                border: Border(
                  top: BorderSide(color: palette.line, width: 3),
                  left: BorderSide(color: palette.line, width: 3),
                  right: BorderSide(color: palette.line, width: 3),
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Opacity(
                  opacity: 0.18,
                  child: Text(
                    '§',
                    style: context.text.displaySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Haze extends StatelessWidget {
  const _Haze({required this.heat, required this.ms});

  final double heat;
  final int ms;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedContainer(
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [
            Colors.transparent,
            Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.18 + heat * 0.22),
          ],
          stops: const [0.38, 1.0],
        ),
      ),
    ),
  );
}

/// A screen that *is* the room: the stage, plus the only chrome allowed to
/// float above it — the way back, where you are, and any actions that belong
/// to the case rather than to the scene.
///
/// There is no app bar on purpose. An opaque bar across the top cuts the
/// backdrop in half and undoes the illusion the stage exists to create.
class CourtStageScaffold extends StatelessWidget {
  const CourtStageScaffold({
    super.key,
    required this.scene,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final CourtScene scene;
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: CourtStage(
      scene: scene,
      hud: _StageHud(title: title, actions: actions),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            // Clears the HUD, which floats rather than reserving space.
            child: Padding(
              padding: const EdgeInsets.only(top: 52),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class _StageHud extends StatelessWidget {
  const _StageHud({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            IconButton.filledTonal(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.88),
                border: Border.all(color: palette.line, width: 2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelLarge,
              ),
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// How far the *case* has got — not how far the reader has scrolled. A readout,
/// never a control: a player does not advance a case, the parties do.
class CourtProgress extends StatelessWidget {
  const CourtProgress({super.key, required this.step, required this.labels});

  /// 1-based. 0 means the case has not started.
  final int step;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final here = step >= 1 && step <= labels.length ? labels[step - 1] : null;
    return Semantics(
      label: here == null
          ? 'Step $step of ${labels.length}'
          : '$here, step $step of ${labels.length}',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < labels.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 26,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i < step - 1
                        ? palette.line
                        : i == step - 1
                        ? palette.accent
                        : Colors.transparent,
                    border: Border.all(color: palette.line, width: 2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
          if (here != null) ...[
            const SizedBox(height: 6),
            Text(
              '${here.toUpperCase()} · STEP $step OF ${labels.length}',
              style: context.text.labelSmall?.copyWith(
                color: palette.inkDim,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
