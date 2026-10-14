import 'package:flutter/material.dart';

import '../theme.dart';
import 'court_icons.dart';

/// Building blocks drawn from the "Sue Me — App Screens" canvas. Every one of
/// them takes its colours from [CourtPalette] so light and dark both work.

/// Accent colour families used for avatars, pills and tints.
enum SueTone { blue, orange, teal, gold, gray }

extension SueToneColors on SueTone {
  /// Foreground (text / icon / ring) colour for this tone.
  Color fg(BuildContext context) {
    final dark = context.isDark;
    switch (this) {
      case SueTone.blue:
        return dark ? CourtColors.blueDark : CourtColors.blue;
      case SueTone.orange:
        return dark ? CourtColors.redOnStage : CourtColors.orange;
      case SueTone.teal:
        return dark ? CourtColors.darkGreenText : CourtColors.notGuilty;
      case SueTone.gold:
        return dark ? CourtColors.gold : const Color(0xFFC98A0A);
      case SueTone.gray:
        return context.palette.inkDim;
    }
  }

  /// Soft background tint for this tone.
  Color tint(BuildContext context) {
    final dark = context.isDark;
    switch (this) {
      case SueTone.blue:
        return dark ? CourtColors.blueTintDark : CourtColors.blueTintLight;
      case SueTone.orange:
        return dark ? CourtColors.orangeTintDark : CourtColors.orangeTintLight;
      case SueTone.teal:
        return dark ? CourtColors.tealTintDark : CourtColors.tealTintLight;
      case SueTone.gold:
        return dark ? CourtColors.goldTintDark : CourtColors.goldTintLight;
      case SueTone.gray:
        return context.palette.surfaceAlt;
    }
  }

  /// Solid button fill (slightly deeper than [fg] so white text passes AA).
  Color solid(BuildContext context) {
    switch (this) {
      case SueTone.orange:
        return context.isDark ? CourtColors.redInk : CourtColors.red;
      case SueTone.teal:
        return context.isDark ? const Color(0xFF17857F) : CourtColors.greenDeep;
      default:
        return fg(context);
    }
  }
}

/// Stable tone for a person's name, so a face keeps its colour everywhere.
SueTone toneFor(String key) {
  const order = [SueTone.blue, SueTone.orange, SueTone.teal];
  var h = 0;
  for (final c in key.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return order[h % order.length];
}

/// A raised white card: radius 24, soft shadow, no border.
class SueCard extends StatelessWidget {
  const SueCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 24,
    this.color,
    this.small = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool small;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: courtHardShadow(context, dy: small ? 4 : 10),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// A round initial. [ring] draws the 3px accent ring the podium uses.
class SueAvatar extends StatelessWidget {
  const SueAvatar({
    super.key,
    required this.name,
    this.size = 34,
    this.tone,
    this.ring,
    this.fontSize,
    this.borderColor,
  });

  final String name;
  final double size;
  final SueTone? tone;
  final Color? ring;
  final double? fontSize;

  /// Draws a separating border (the overlapped pair on a feed card).
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? toneFor(name);
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Tints are translucent in dark mode; lay them on the card colour so
        // nothing behind the avatar (a ring, the other face) shows through.
        color: Color.alphaBlend(
          t.tint(context),
          context.colors.surfaceContainerHighest,
        ),
        border: ring != null
            ? Border.all(color: ring!, width: 3)
            : borderColor != null
            ? Border.all(color: borderColor!, width: 3)
            : null,
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: fontSize ?? size * 0.41,
          height: 1,
          color: t.fg(context),
        ),
      ),
    );
  }
}

/// Two faces overlapping by 10px: the plaintiff and the accused.
class SuePair extends StatelessWidget {
  const SuePair({super.key, required this.a, required this.b});

  final String a;
  final String b;

  @override
  Widget build(BuildContext context) {
    final card = context.colors.surfaceContainerHighest;
    return SizedBox(
      width: 58,
      height: 34,
      child: Stack(
        children: [
          SueAvatar(name: a, tone: SueTone.blue, borderColor: card),
          Positioned(
            left: 24,
            child: SueAvatar(name: b, tone: SueTone.orange, borderColor: card),
          ),
        ],
      ),
    );
  }
}

/// A small tinted pill: "JURY LIVE", "GUILTY", "BOSS CASE".
class SuePill extends StatelessWidget {
  const SuePill(
    this.label, {
    super.key,
    this.tone = SueTone.orange,
    this.dot = false,
    this.round = true,
  });

  final String label;
  final SueTone tone;

  /// A leading pulsing-style dot, for "live" states.
  final bool dot;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final fg = tone.fg(context);
    return Container(
      height: round ? 26 : null,
      padding: EdgeInsets.symmetric(
        horizontal: round ? 10 : 9,
        vertical: round ? 0 : 5,
      ),
      decoration: BoxDecoration(
        color: tone.tint(context),
        borderRadius: BorderRadius.circular(round ? 999 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .9,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// The three-up segmented control under the stories row.
class SueTabs extends StatelessWidget {
  const SueTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.isDark ? p.surfaceAlt : p.surfaceAlt2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index
                          ? context.colors.surfaceContainerHighest
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: i == index
                          ? courtHardShadow(context, dy: 4)
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: i == index ? context.colors.onSurface : p.inkDim,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A story-style round with a gradient ring (live) or a flat grey one (seen).
class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.label,
    required this.initial,
    this.live = false,
    this.tone = SueTone.blue,
    this.onTap,
  });

  final String label;
  final String initial;
  final bool live;
  final SueTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: live
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF0643C), Color(0xFFFFB347)],
                      )
                    : null,
                color: live ? null : context.palette.inkFaint,
              ),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.alphaBlend(tone.tint(context), bg),
                  border: Border.all(color: bg, width: 3),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: tone.fg(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashed "+" first item of the stories row.
class AddStory extends StatelessWidget {
  const AddStory({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 62,
      child: Column(
        children: [
          CustomPaint(
            painter: _DashedCircle(context.palette.inkFaint),
            child: SizedBox(
              width: 62,
              height: 62,
              child: Center(
                child: CourtIcon(
                  CourtGlyph.plus,
                  size: 22,
                  color: context.palette.accent,
                  strokeWidth: 2.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = (size.shortestSide - 2) / 2;
    final c = size.center(Offset.zero);
    const dashes = 24;
    for (var i = 0; i < dashes; i++) {
      final a = i * 2 * 3.141592653589793 / dashes;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        a,
        2 * 3.141592653589793 / dashes * .55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// Guilty vs not-guilty split: a label row over two rounded segments.
/// Shows only real counts; renders a neutral track when nobody has voted.
class VoteBar extends StatelessWidget {
  const VoteBar({super.key, required this.guilty, required this.notGuilty});

  final int guilty;
  final int notGuilty;

  @override
  Widget build(BuildContext context) {
    final total = guilty + notGuilty;
    final gPct = total == 0 ? 0 : (guilty * 100 / total).round();
    final nPct = total == 0 ? 0 : 100 - gPct;
    final dim = context.palette.inkDim;
    return Column(
      children: [
        Row(
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Guilty $gPct%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SueTone.orange.fg(context),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                total == 0 ? 'No votes yet' : '$total voted',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: dim,
                ),
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Not guilty $nPct%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SueTone.teal.fg(context),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 10,
          child: total == 0
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const SizedBox.expand(),
                )
              : Row(
                  children: [
                    if (guilty > 0)
                      Expanded(
                        flex: guilty,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: SueTone.orange.fg(context),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    if (guilty > 0 && notGuilty > 0) const SizedBox(width: 3),
                    if (notGuilty > 0)
                      Expanded(
                        flex: notGuilty,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: SueTone.teal.fg(context),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A thin progress track with a filled, rounded bar.
class SueProgress extends StatelessWidget {
  const SueProgress({
    super.key,
    required this.value,
    this.height = 8,
    this.color,
    this.track,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: track ?? context.palette.surfaceAlt),
          ),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color ?? context.palette.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The squarish solid vote / CTA button: 48 high, 14 radius, tracked caps.
class SueButton extends StatelessWidget {
  const SueButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = SueTone.blue,
    this.height = 48,
    this.busy = false,
    this.radius = 14,
    this.glyph,
  });

  final String label;
  final VoidCallback? onPressed;
  final SueTone tone;
  final double height;
  final bool busy;
  final double radius;

  /// A trailing glyph, as the artboard's "GET OTP" key carries an arrow.
  final CourtGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final fill = tone.solid(context);
    final fg = context.isDark && tone == SueTone.blue
        ? const Color(0xFF0F121B)
        : Colors.white;
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: busy ? null : onPressed,
          child: SizedBox(
            height: height,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: fg,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                              color: fg,
                            ),
                          ),
                        ),
                        if (glyph != null) ...[
                          const SizedBox(width: 8),
                          CourtIcon(
                            glyph!,
                            size: 18,
                            color: fg,
                            strokeWidth: 2.6,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The illustrated band the canvas puts above the verdict and over the
/// sign-in: a calm stage with a gavel coming down on its block.
class SueStage extends StatelessWidget {
  const SueStage({super.key, required this.tone, this.height = 176});

  final SueTone tone;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF161B2A)
            : const Color(0xFFE6ECFA),
        borderRadius: BorderRadius.circular(26),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _SueStagePainter(
          line: context.isDark
              ? const Color(0xFF3A4C80)
              : const Color(0xFF8FA6E6),
          accent: context.palette.accent,
          hit: tone.fg(context),
        ),
        size: Size.infinite,
      ),
    ),
  );
}

class _SueStagePainter extends CustomPainter {
  const _SueStagePainter({
    required this.line,
    required this.accent,
    required this.hit,
  });

  final Color line;
  final Color accent;
  final Color hit;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final base = size.height - 34;
    // Soft discs behind the scene.
    canvas.drawCircle(
      Offset(cx + 90, size.height * .75),
      80,
      Paint()..color = Colors.white.withValues(alpha: .10),
    );
    canvas.drawCircle(
      Offset(cx - 110, 30),
      46,
      Paint()..color = Colors.white.withValues(alpha: .08),
    );
    // The sound block.
    final block = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, base), width: 120, height: 22),
      const Radius.circular(8),
    );
    canvas.drawRRect(block, Paint()..color = accent);
    // The gavel: a head and a handle, tilted down toward the block.
    canvas.save();
    canvas.translate(cx + 6, base - 52);
    canvas.rotate(-.5);
    final handle = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-5, -6, 10, 78),
      const Radius.circular(5),
    );
    canvas.drawRRect(handle, Paint()..color = line);
    final head = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-34, -30, 68, 30),
      const Radius.circular(10),
    );
    canvas.drawRRect(head, Paint()..color = accent);
    canvas.restore();
    // The impact marks.
    final p = Paint()
      ..color = hit
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final o = Offset(cx - 52, base - 12);
    canvas.drawLine(o + const Offset(-6, -8), o + const Offset(-18, -22), p);
    canvas.drawLine(o + const Offset(-10, 2), o + const Offset(-26, 2), p);
    canvas.drawLine(o + const Offset(-6, 12), o + const Offset(-18, 24), p);
  }

  @override
  bool shouldRepaint(_SueStagePainter old) =>
      old.line != line || old.accent != accent || old.hit != hit;
}

/// The player's face inside a ring that fills as they level up, with the level
/// on a pill through the bottom edge. The artboard's conic gradient, drawn as
/// an arc because Flutter has no conic gradient on a circle border.
class LevelRing extends StatelessWidget {
  const LevelRing({
    super.key,
    required this.name,
    required this.level,
    required this.fraction,
    this.size = 60,
  });

  final String name;
  final int level;

  /// How far through this level, 0..1.
  final double fraction;
  final double size;

  @override
  Widget build(BuildContext context) {
    final card = context.colors.surfaceContainerHighest;
    return SizedBox(
      width: size,
      height: size + 10,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              fraction: fraction.clamp(0, 1),
              track: context.palette.surfaceAlt,
              fill: CourtColors.blue,
            ),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: SueAvatar(
                  // The ring has to stay visible around the face: the avatar
                  // draws its own 3px rim, so it sits 14 inside the ring
                  // rather than 10.
                  name: name,
                  size: size - 14,
                  tone: SueTone.blue,
                  borderColor: card,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 36,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CourtColors.blue,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: card, width: 2),
              ),
              child: Text(
                'LV $level',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
  });

  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawCircle(rect.center, size.width / 2, Paint()..color = track);
    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -3.14159 / 2,
      6.28318 * fraction,
      true,
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
}

/// A badge: the artboard's hexagon, tinted when earned and faded when not.
class HexBadge extends StatelessWidget {
  const HexBadge({
    super.key,
    required this.glyph,
    required this.label,
    required this.earned,
    this.tone = SueTone.blue,
    this.width = 58,
  });

  final String glyph;
  final String label;
  final bool earned;
  final SueTone tone;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colour = earned ? tone.fg(context) : context.palette.inkDim;
    final fill = earned ? tone.tint(context) : context.palette.surfaceAlt;
    return Opacity(
      opacity: earned ? 1 : .45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            height: width * 64 / 58,
            child: CustomPaint(
              painter: _HexPainter(fill: fill, stroke: colour),
              child: Center(
                child: Text(
                  glyph,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colour,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // The artboard's hexagon on its own 58x64 grid, scaled to fit.
    final sx = size.width / 58, sy = size.height / 64;
    final path = Path()
      ..moveTo(29 * sx, 2 * sy)
      ..lineTo(54 * sx, 16 * sy)
      ..lineTo(54 * sx, 48 * sy)
      ..lineTo(29 * sx, 62 * sy)
      ..lineTo(4 * sx, 48 * sy)
      ..lineTo(4 * sx, 16 * sy)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HexPainter old) =>
      old.fill != fill || old.stroke != stroke;
}

/// A small tinted tile carrying one number: the streak, the coins, the badges.
class SueStatTile extends StatelessWidget {
  const SueStatTile({
    super.key,
    required this.value,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String value;
  final String label;
  final SueTone tone;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: tone.tint(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 8)],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: context.palette.inkDim),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A coin, as the artboard draws it: a gold disc with a darker inner rim.
class SueCoin extends StatelessWidget {
  const SueCoin({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: const _CoinPainter()),
  );
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, size.width / 2, Paint()..color = CourtColors.gold);
    canvas.drawCircle(
      c,
      size.width * 0.27,
      Paint()
        ..color = CourtColors.goldDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.085,
    );
  }

  @override
  bool shouldRepaint(_CoinPainter old) => false;
}
