import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'court_icons.dart';

/// Pieces of chrome shared by every screen, drawn to the design canvas.
///
/// The canvas has no app bar anywhere: each screen opens with its own header
/// row, and navigation is a floating dark pill with a raised violet key in the
/// middle. Both live here so a change lands on all six screens at once.

/// A 44x44 round button: surface fill, 3px ink rim, 3px hard shadow.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
    this.size = 44,
    this.fill,
    this.foreground,
    this.badge,
  });

  final CourtGlyph glyph;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final Color? fill;
  final Color? foreground;

  /// A count to pin to the top-right corner, as on the dashboard bell.
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final button = Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill ?? context.colors.surfaceContainerHighest,
              border: Border.all(
                color: palette.border,
                width: courtBorderWidth,
              ),
              boxShadow: courtHardShadow(context, dy: 3),
            ),
            alignment: Alignment.center,
            child: CourtIcon(
              glyph,
              size: size * 0.45,
              color: foreground ?? context.colors.onSurface,
            ),
          ),
        ),
      ),
    );

    if (badge == null || badge == 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CourtColors.red,
              borderRadius: BorderRadius.circular(courtRadiusPill),
              border: Border.all(color: palette.border, width: 2),
            ),
            child: Text(
              badge! > 99 ? '99+' : '$badge',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small pill: a count, a countdown, a rank. [raised] gives it the rim and
/// the hard shadow; without it the pill is flat, the way chips inside a card
/// are drawn on the canvas.
class CourtPill extends StatelessWidget {
  const CourtPill({
    super.key,
    required this.label,
    this.glyph,
    this.fill,
    this.foreground,
    this.raised = false,
    this.fontSize = 13,
    this.bordered = false,
  });

  final String label;
  final CourtGlyph? glyph;
  final Color? fill;
  final Color? foreground;
  final bool raised;
  final bool bordered;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? context.colors.onSurface;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: glyph == null ? 10 : 12,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: fill ?? context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(courtRadiusPill),
        border: raised || bordered
            ? Border.all(
                color: context.palette.border,
                width: raised ? courtBorderWidth : courtBorderThin,
              )
            : null,
        boxShadow: raised ? courtHardShadow(context, dy: 3) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            CourtIcon(glyph!, size: fontSize + 3, color: fg, strokeWidth: 2.8),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary action: a violet key with its own darker shadow, so it reads as
/// something you press rather than something that floats.
class CourtKey extends StatelessWidget {
  const CourtKey({
    super.key,
    required this.label,
    required this.onPressed,
    this.glyph,
    this.fill,
    this.foreground,
    this.shadowInk,
    this.height = 58,
    this.radius = courtRadiusPill,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final CourtGlyph? glyph;
  final Color? fill;
  final Color? foreground;
  final Color? shadowInk;
  final double height;
  final double radius;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final bg = fill ?? context.palette.accent;
    final fg = foreground ?? Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: context.palette.border,
            width: courtBorderWidth,
          ),
          boxShadow: courtHardShadow(
            context,
            ink: shadowInk ?? context.palette.accentInk,
            dy: 5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: fg,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (glyph != null) ...[
                            CourtIcon(glyph!, size: 22, color: fg),
                            const SizedBox(width: 9),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: courtDisplayFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 19,
                                color: fg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dark panel that carries the one loud thing on a screen, with the
/// canvas's radial spotlight behind it.
class StagePanel extends StatelessWidget {
  const StagePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.spot,
    this.spotAlignment = const Alignment(0, -1.6),
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// The colour of the glow behind the content. Null draws no glow.
  final Color? spot;
  final Alignment spotAlignment;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        color: context.palette.stage,
        borderRadius: BorderRadius.circular(courtRadiusXl),
        border: Border.all(
          color: context.palette.border,
          width: courtBorderWidth,
        ),
        boxShadow: courtHardShadow(context, dy: courtShadowOffsetLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (spot != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: spotAlignment,
                      radius: 1.1,
                      colors: [
                        spot!.withValues(alpha: 0.38),
                        spot!.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: padding,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: CourtColors.stageInk),
              child: child,
            ),
          ),
        ],
      ),
    );
    return semanticLabel == null
        ? body
        : Semantics(container: true, label: semanticLabel, child: body);
  }
}

/// One quiet tile inside a [StagePanel]: a number and what it counts.
class StageStat extends StatelessWidget {
  const StageStat({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.leading,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: context.palette.stageChip,
      borderRadius: BorderRadius.circular(courtRadiusSm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 4)],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontFamily: courtDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    height: 1,
                    color: valueColor ?? CourtColors.stageInk,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: CourtColors.stageDim,
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}

/// The header row every screen opens with: an optional round leading button, a
/// title block, and up to a couple of trailing controls.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.eyebrowWidget,
    this.leading,
    this.trailing = const [],
    this.titleSize = 36,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 12),
  });

  final String title;
  final String? eyebrow;
  final Widget? eyebrowWidget;
  final Widget? leading;
  final List<Widget> trailing;
  final double titleSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrowWidget != null)
                eyebrowWidget!
              else if (eyebrow != null)
                Text(
                  eyebrow!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.palette.inkDim,
                  ),
                ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: courtDisplayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: titleSize,
                  height: 1.05,
                  letterSpacing: -0.5,
                  color: context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        for (final widget in trailing) ...[const SizedBox(width: 10), widget],
      ],
    ),
  );
}

/// The sticky panel the canvas puts at the foot of the case file and the
/// filing form: a surface with a 3px top rim and big top corners.
class BottomDock extends StatelessWidget {
  const BottomDock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHighest,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(courtRadiusXl),
      ),
      border: Border(
        top: BorderSide(color: context.palette.border, width: courtBorderWidth),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: child,
      ),
    ),
  );
}

/// Where a top-level screen sits in the main navigation. The canvas shows five
/// slots; the middle one is the filing key, which is an action rather than a
/// destination, so it is not a tab.
enum CourtTab {
  home('/', CourtGlyph.home, 'Home'),
  courts('/courts', CourtGlyph.courts, 'Courts'),
  record('/rap-sheet', CourtGlyph.trophy, 'Rap sheet'),
  settings('/settings', CourtGlyph.person, 'Profile');

  const CourtTab(this.path, this.glyph, this.label);
  final String path;
  final CourtGlyph glyph;
  final String label;
}

/// The floating navigation pill: dark in both modes, the current tab a yellow
/// disc, and the filing key raised through the top edge.
///
/// Built once, by the navigation shell — never by a screen. [onSelect] is the
/// shell's `goBranch`, which keeps each tab's own navigation stack alive
/// instead of rebuilding the destination from scratch.
class CourtNavBar extends StatelessWidget {
  const CourtNavBar({super.key, required this.current, this.onSelect});

  final CourtTab? current;

  /// Called with the tab's index. Null falls back to a plain `go`, for the
  /// rare screen that is outside the shell.
  final ValueChanged<int>? onSelect;

  static const _order = [
    CourtTab.home,
    CourtTab.courts,
    null, // the filing key
    CourtTab.record,
    CourtTab.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      // As a Scaffold's bottomNavigationBar this is the outermost widget in
      // that slot, and nothing above it is a Material — without this every
      // InkWell in the pill would assert instead of rippling.
      type: MaterialType.transparency,
      child: Padding(
        // 34 of head-room so the raised key is inside this widget's own bounds
        // and never gets clipped by the bottom-bar slot.
        padding: const EdgeInsets.fromLTRB(16, 34, 16, 0),
        child: SizedBox(
          height: courtNavHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.nav,
                    borderRadius: BorderRadius.circular(courtRadiusPill),
                    border: Border.all(
                      color: palette.border,
                      width: courtBorderWidth,
                    ),
                    boxShadow: courtHardShadow(context),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (final tab in _order)
                        if (tab == null)
                          _FilingKey(key: const Key('nav-file'))
                        else
                          _NavSlot(
                            tab: tab,
                            selected: tab == current,
                            onSelect: onSelect,
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

class _NavSlot extends StatelessWidget {
  const _NavSlot({required this.tab, required this.selected, this.onSelect});

  final CourtTab tab;
  final bool selected;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: tab.label,
    child: Tooltip(
      message: tab.label,
      child: InkWell(
        customBorder: const CircleBorder(),
        // Tapping the tab you are on returns it to its own root, which is what
        // every tab bar does; `goBranch` handles that for us.
        onTap: () =>
            onSelect == null ? context.go(tab.path) : onSelect!(tab.index),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? CourtColors.yellow : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: CourtIcon(
            tab.glyph,
            size: tab == CourtTab.record ? 22 : 24,
            color: selected ? CourtColors.lightInk : CourtColors.stageDim,
            strokeWidth: tab == CourtTab.record ? 2.8 : 2.6,
          ),
        ),
      ),
    ),
  );
}

/// The violet key in the middle of the pill, raised 34px through its top edge.
///
/// The Transform wraps the *whole* interactive subtree, not just the circle.
/// With it inside the InkWell the key painted 34px above the box that took
/// taps: the top half of the key did nothing, and the dead strip below it did.
class _FilingKey extends StatelessWidget {
  const _FilingKey({super.key});

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: const Offset(0, -34),
    child: Semantics(
      button: true,
      label: 'File a case',
      child: Tooltip(
        message: 'File a case',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.push('/cases/new'),
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CourtColors.violet,
              border: Border.all(
                color: context.palette.border,
                width: courtBorderWidth,
              ),
              boxShadow: const [
                BoxShadow(color: CourtColors.violetInk, offset: Offset(0, 5)),
              ],
            ),
            alignment: Alignment.center,
            child: const CourtIcon(
              CourtGlyph.gavel,
              size: 30,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}
