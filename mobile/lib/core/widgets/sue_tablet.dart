import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'court_chrome.dart';
import 'court_icons.dart';

/// The tablet half of the "Sue Me — App Screens" canvas.
///
/// The tablet artboards (820×1180 portrait, 1180×820 landscape) keep every
/// colour, radius and type size of the phone screens and change only the
/// frame: the floating bottom pill becomes a 104px rail down the left edge,
/// each screen opens with a big title row instead of its phone header, and the
/// body spreads into columns with a 16px gutter inside 28px of page padding.
///
/// Everything here is that frame. The cards themselves come from
/// `sue_widgets.dart`, unchanged, so a tablet shows the same components the
/// phone does — which is the point.

/// From here up the nav is a rail, not a bottom pill. 600 is the short side of
/// the smallest tablet the canvas draws.
const sueTabletBreakpoint = 600.0;

/// From here up a screen can carry a side panel beside its main column. The
/// portrait tablet artboard is 820 wide and does exactly that.
const sueAsideBreakpoint = 820.0;

/// From here up the landscape artboards split the body into two columns.
const sueWideBreakpoint = 1000.0;

/// Page padding and gutter, straight off the tablet artboards.
const suePagePad = 28.0;
const sueGutter = 16.0;

/// Width of the rail, and of the side panel beside the main column.
const sueRailWidth = 104.0;
const sueAsideWidth = 280.0;

extension SueMetrics on BuildContext {
  /// A rail-width window: the tablet frame applies.
  bool get isTablet => MediaQuery.sizeOf(this).width >= sueTabletBreakpoint;

  /// Wide enough for a side panel next to the main column.
  bool get hasAside => MediaQuery.sizeOf(this).width >= sueAsideBreakpoint;

  /// Wide enough to split the body into two columns (landscape tablet).
  bool get isWideTablet => MediaQuery.sizeOf(this).width >= sueWideBreakpoint;
}

/// The nav rail: 104px of card, five slots, the filing key between Courts and
/// the rap sheet so the order matches the phone pill exactly.
class SueNavRail extends StatelessWidget {
  const SueNavRail({super.key, required this.current, this.onSelect});

  final CourtTab? current;
  final ValueChanged<int>? onSelect;

  /// The rail spells its destinations out; the pill only has room for glyphs.
  static String _label(CourtTab tab) => switch (tab) {
    CourtTab.home => 'Home',
    CourtTab.courts => 'Courts',
    CourtTab.record => 'Rap sheet',
    CourtTab.settings => 'Profile',
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: sueRailWidth,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest,
          boxShadow: [
            BoxShadow(
              color: context.isDark
                  ? const Color(0x4D000000)
                  : const Color(0x0F1E2235),
              offset: const Offset(8, 0),
              blurRadius: 24,
            ),
          ],
        ),
        // In a short landscape window five slots are taller than the rail;
        // a nav is never a reason to overflow.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tab in CourtTab.values) ...[
                _RailSlot(
                  label: _label(tab),
                  tooltip: tab.label,
                  selected: tab == current,
                  onTap: () => onSelect == null
                      ? context.go(tab.path)
                      : onSelect!(tab.index),
                ),
                const SizedBox(height: 6),
                if (tab == CourtTab.courts) ...[
                  const _RailKey(),
                  const SizedBox(height: 6),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RailSlot extends StatelessWidget {
  const _RailSlot({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: tooltip,
    child: Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 68,
          // 44 minimum touch target: 9px of padding either side of a 12px
          // line that lays out at 26px.
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (context.isDark
                      ? CourtColors.blueTintDark
                      : CourtColors.blueTintLight)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? context.palette.accent : context.palette.inkDim,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The blue filing key in the middle of the rail.
class _RailKey extends StatelessWidget {
  const _RailKey();

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'File a case',
    child: Tooltip(
      message: 'File a case',
      child: InkWell(
        key: const Key('rail-file'),
        customBorder: const CircleBorder(),
        onTap: () => context.push('/cases/new'),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CourtColors.blue,
            boxShadow: [
              BoxShadow(
                color: CourtColors.blue.withValues(alpha: .4),
                offset: const Offset(0, 8),
                blurRadius: 18,
              ),
            ],
          ),
          child: const CourtIcon(
            CourtGlyph.plus,
            size: 24,
            color: Colors.white,
            strokeWidth: 2.8,
          ),
        ),
      ),
    ),
  );
}

/// A tablet screen's opening row: the title, loud, with a quiet line of
/// context on the same baseline.
class SueTabletHeader extends StatelessWidget {
  const SueTabletHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
            height: 1.1,
          ),
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: context.palette.inkDim),
          ),
        ),
      ],
      if (trailing != null) ...[const Spacer(), trailing!],
    ],
  );
}

/// A small tracked caps label over a block inside a tablet card.
class SueSectionLabel extends StatelessWidget {
  const SueSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.4,
      color: color ?? context.palette.inkDim,
    ),
  );
}

/// The body of a tablet screen: 28px of page padding, a header row, and
/// whatever columns the artboard calls for under it.
///
/// [aside] is only drawn when the window is wide enough for it
/// ([sueAsideBreakpoint]); below that its children fall to the end of the main
/// column so nothing is lost on the narrower frame.
class SueTabletPage extends StatelessWidget {
  const SueTabletPage({
    super.key,
    required this.header,
    required this.child,
    this.aside,
    this.padding = const EdgeInsets.all(suePagePad),
  });

  final Widget header;
  final Widget child;

  /// The right-hand panel of the tablet feed artboards.
  final List<Widget>? aside;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final side = aside;
    final withAside = side != null && side.isNotEmpty && context.hasAside;

    return SafeArea(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: sueGutter),
            Expanded(
              child: withAside
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: child),
                        const SizedBox(width: sueGutter + 8),
                        SizedBox(
                          width: sueAsideWidth,
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              for (var i = 0; i < side.length; i++) ...[
                                if (i > 0) const SizedBox(height: sueGutter),
                                side[i],
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Two columns with the canvas's gutter, for the landscape artboards. Below
/// [sueWideBreakpoint] the two stack, which is what the portrait boards do.
class SueColumns extends StatelessWidget {
  const SueColumns({
    super.key,
    required this.start,
    required this.end,
    this.startFlex = 1,
    this.endFlex = 1,
  });

  final List<Widget> start;
  final List<Widget> end;
  final int startFlex;
  final int endFlex;

  static Widget _stack(List<Widget> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: sueGutter),
        items[i],
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!context.isWideTablet) return _stack([...start, ...end]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: startFlex, child: _stack(start)),
        const SizedBox(width: sueGutter),
        Expanded(flex: endFlex, child: _stack(end)),
      ],
    );
  }
}
