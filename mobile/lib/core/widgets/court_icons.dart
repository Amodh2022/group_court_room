import 'package:flutter/material.dart';

/// The canvas's own icons, redrawn as paths.
///
/// Material's outlined set is a thinner, rounder family: next to a 3px border
/// and a 900-weight label it reads as a different app. These are the exact
/// geometries from the design, stroked at the weight the design uses, so the
/// chrome matches the artboards rather than approximating them.
enum CourtGlyph {
  home,
  courts,
  gavel,
  trophy,
  person,
  bell,
  share,
  back,
  close,
  check,
  cross,
  arrowRight,
  chevronRight,
  chevronDown,
  plus,
  clock,
  doc,
  warn,
  camera,
  key,
  trash,
  refresh,
  /// Solid, not stroked — the petty-level flame.
  flame,
}

/// A stroked icon drawn on the design's 24x24 grid (22x22 for [CourtGlyph.flame]).
class CourtIcon extends StatelessWidget {
  const CourtIcon(
    this.glyph, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 2.6,
    this.fill,
  });

  final CourtGlyph glyph;
  final double size;
  final Color? color;
  final double strokeWidth;

  /// Only [CourtGlyph.flame] is filled; this is its interior colour.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(
          glyph: glyph,
          color: tone,
          strokeWidth: strokeWidth,
          fill: fill,
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.glyph,
    required this.color,
    required this.strokeWidth,
    this.fill,
  });

  final CourtGlyph glyph;
  final Color color;
  final double strokeWidth;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    // Every path below is authored on the design's own grid, then scaled to
    // whatever box the caller asked for. Stroke width is scaled with it, so an
    // icon keeps its weight at any size.
    final grid = glyph == CourtGlyph.flame ? const Size(18, 22) : const Size(24, 24);
    final scale = size.width / grid.width;
    canvas.save();
    canvas.scale(scale);

    final path = _path(glyph);

    if (glyph == CourtGlyph.flame) {
      canvas.drawPath(path, Paint()..color = fill ?? color);
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          // Authored in grid units, so the weight scales with the icon the
          // way an SVG stroke does.
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }

  Path _path(CourtGlyph g) {
    final p = Path();
    switch (g) {
      case CourtGlyph.home:
        p.moveTo(3, 11);
        p.lineTo(12, 4);
        p.lineTo(21, 11);
        p.moveTo(5, 10);
        p.lineTo(5, 20);
        p.lineTo(19, 20);
        p.lineTo(19, 10);
      case CourtGlyph.courts:
        p.moveTo(3, 9);
        p.lineTo(12, 4);
        p.lineTo(21, 9);
        for (final x in const [5.0, 10.0, 14.0, 19.0]) {
          p.moveTo(x, 9);
          p.lineTo(x, 18);
        }
        p.moveTo(3, 20);
        p.lineTo(21, 20);
      case CourtGlyph.gavel:
        p.moveTo(14, 4);
        p.lineTo(20, 10);
        p.moveTo(11, 7);
        p.lineTo(17, 13);
        p.moveTo(12.5, 5.5);
        p.lineTo(7.5, 10.5);
        p.lineTo(11.5, 14.5);
        p.lineTo(16.5, 9.5);
        p.moveTo(9.5, 12.5);
        p.lineTo(3, 19);
        p.moveTo(13, 21);
        p.lineTo(21, 21);
      case CourtGlyph.trophy:
        p.moveTo(8, 21);
        p.lineTo(16, 21);
        p.moveTo(12, 17);
        p.lineTo(12, 21);
        p.moveTo(7, 4);
        p.lineTo(17, 4);
        p.lineTo(17, 9);
        p.arcToPoint(const Offset(7, 9), radius: const Radius.circular(5));
        p.close();
        p.moveTo(17, 6);
        p.lineTo(20, 6);
        p.lineTo(20, 8);
        p.arcToPoint(const Offset(17, 11), radius: const Radius.circular(3));
        p.moveTo(7, 6);
        p.lineTo(4, 6);
        p.lineTo(4, 8);
        p.arcToPoint(
          const Offset(7, 11),
          radius: const Radius.circular(3),
          clockwise: false,
        );
      case CourtGlyph.person:
        p.addOval(Rect.fromCircle(center: const Offset(12, 8), radius: 4));
        p.moveTo(4, 21);
        p.cubicTo(5, 17, 8, 15, 12, 15);
        p.cubicTo(16, 15, 19, 17, 20, 21);
      case CourtGlyph.bell:
        p.moveTo(6, 8);
        p.arcToPoint(const Offset(18, 8), radius: const Radius.circular(6));
        p.cubicTo(18, 15, 21, 17, 21, 17);
        p.lineTo(3, 17);
        p.cubicTo(3, 17, 6, 15, 6, 8);
        p.moveTo(10, 21);
        p.lineTo(14, 21);
      case CourtGlyph.share:
        p.moveTo(12, 3);
        p.lineTo(12, 16);
        p.moveTo(7, 8);
        p.lineTo(12, 3);
        p.lineTo(17, 8);
        p.moveTo(5, 14);
        p.lineTo(5, 19);
        p.arcToPoint(
          const Offset(7, 21),
          radius: const Radius.circular(2),
          clockwise: false,
        );
        p.lineTo(17, 21);
        p.arcToPoint(const Offset(19, 19), radius: const Radius.circular(2),
            clockwise: false);
        p.lineTo(19, 14);
      case CourtGlyph.back:
        p.moveTo(15, 18);
        p.lineTo(9, 12);
        p.lineTo(15, 6);
      case CourtGlyph.close:
      case CourtGlyph.cross:
        p.moveTo(6, 6);
        p.lineTo(18, 18);
        p.moveTo(18, 6);
        p.lineTo(6, 18);
      case CourtGlyph.check:
        p.moveTo(5, 12);
        p.lineTo(10, 17);
        p.lineTo(19, 7);
      case CourtGlyph.arrowRight:
        p.moveTo(5, 12);
        p.lineTo(19, 12);
        p.moveTo(13, 6);
        p.lineTo(19, 12);
        p.lineTo(13, 18);
      case CourtGlyph.chevronRight:
        p.moveTo(9, 6);
        p.lineTo(15, 12);
        p.lineTo(9, 18);
      case CourtGlyph.chevronDown:
        p.moveTo(6, 9);
        p.lineTo(12, 15);
        p.lineTo(18, 9);
      case CourtGlyph.plus:
        p.moveTo(12, 5);
        p.lineTo(12, 19);
        p.moveTo(5, 12);
        p.lineTo(19, 12);
      case CourtGlyph.clock:
        p.addOval(Rect.fromCircle(center: const Offset(12, 13), radius: 8));
        p.moveTo(12, 9);
        p.lineTo(12, 13);
        p.lineTo(14, 15);
        p.moveTo(9, 2);
        p.lineTo(15, 2);
      case CourtGlyph.doc:
        p.addRRect(
          RRect.fromLTRBR(6, 3, 18, 21, const Radius.circular(1.5)),
        );
        p.moveTo(9, 8);
        p.lineTo(15, 8);
        p.moveTo(9, 12);
        p.lineTo(15, 12);
        p.moveTo(9, 16);
        p.lineTo(12, 16);
      case CourtGlyph.warn:
        p.moveTo(12, 3);
        p.lineTo(21, 19);
        p.lineTo(3, 19);
        p.close();
        p.moveTo(12, 10);
        p.lineTo(12, 14);
        p.moveTo(12, 16.8);
        p.lineTo(12, 17.3);
      case CourtGlyph.camera:
        p.addRRect(RRect.fromLTRBR(3, 4, 21, 20, const Radius.circular(3)));
        p.addOval(Rect.fromCircle(center: const Offset(9, 10), radius: 2));
        p.moveTo(21, 16);
        p.lineTo(16, 11);
        p.lineTo(7, 20);
      case CourtGlyph.key:
        p.addOval(Rect.fromCircle(center: const Offset(8, 12), radius: 4));
        p.moveTo(12, 12);
        p.lineTo(21, 12);
        p.moveTo(18, 12);
        p.lineTo(18, 16);
        p.moveTo(21, 12);
        p.lineTo(21, 15);
      case CourtGlyph.trash:
        p.moveTo(4, 7);
        p.lineTo(20, 7);
        p.moveTo(9, 7);
        p.lineTo(9, 4);
        p.lineTo(15, 4);
        p.lineTo(15, 7);
        p.moveTo(6, 7);
        p.lineTo(7, 21);
        p.lineTo(17, 21);
        p.lineTo(18, 7);
      case CourtGlyph.refresh:
        p.addArc(
          Rect.fromCircle(center: const Offset(12, 12), radius: 8),
          -0.6,
          5.0,
        );
        p.moveTo(18.6, 7.6);
        p.lineTo(19.6, 3.6);
        p.moveTo(18.6, 7.6);
        p.lineTo(14.6, 6.6);
      case CourtGlyph.flame:
        p.moveTo(9, 1);
        p.cubicTo(10, 5, 15, 7, 15, 13);
        p.arcToPoint(const Offset(3, 13), radius: const Radius.circular(6));
        p.cubicTo(3, 10, 5, 8, 6, 7);
        p.cubicTo(6, 9, 7, 10, 8, 10);
        p.cubicTo(8, 6, 7, 4, 9, 1);
        p.close();
    }
    return p;
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.fill != fill;
}
