import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'court_chrome.dart';
import 'sue_tablet.dart';

// The nav pill, the stage panel and the header row live in court_chrome.dart.
// Re-exported so the screens keep one import for "the shell".
export 'court_chrome.dart';
export 'sue_tablet.dart';

/// Widest a column of content gets. Past this the screen centres it.
const courtContentWidth = 720.0;

/// Breakpoints. Below [courtRailBreakpoint] the nav floats at the bottom; from
/// there up it becomes the canvas's 104px rail. From [courtWideBreakpoint]
/// lists become two columns.
const courtRailBreakpoint = sueTabletBreakpoint;
const courtWideBreakpoint = 840.0;

/// The soft grey canvas behind every screen. With [hero] it adds the pastel
/// pink/violet/blue wash from the reference (sign-in).
class CourtBackground extends StatelessWidget {
  const CourtBackground({super.key, required this.child, this.hero = false});

  final Widget child;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surface;
    if (!hero) return ColoredBox(color: base, child: child);
    final dark = context.isDark;
    return ColoredBox(
      color: base,
      child: Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.topCenter,
              heightFactor: 0.62,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    // A quiet blue wash that fades into the page; the canvas
                    // has no sign-in screen, so it borrows its one accent.
                    colors: [
                      CourtColors.blue.withValues(alpha: dark ? 0.28 : 0.16),
                      CourtColors.blue.withValues(alpha: dark ? 0.14 : 0.07),
                      base.withValues(alpha: 0),
                      base.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.35, 0.7, 1],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A round icon button with a small label under it, as in the reference.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.palette.surfaceAlt,
              ),
              child: Icon(icon, size: 22, color: context.colors.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.palette.inkDim,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A dashed-outline "add" tile.
class DashedAddTile extends StatelessWidget {
  const DashedAddTile({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 84,
  });

  final String label;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: CustomPaint(
      painter: _DashedRRect(context.palette.inkFaint),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: context.palette.inkDim),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium?.copyWith(
                  color: context.palette.inkDim,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DashedRRect extends CustomPainter {
  _DashedRRect(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color;
}

/// The navigation shell: the page, the nav, and whichever tab is showing.
///
/// Built once by the router, not by each screen. A screen that drew its own
/// nav bar tore it down and rebuilt it on every tab change — the pill blinked,
/// and each tab lost its scroll position and its own back stack. With
/// [StatefulNavigationShell] the four branches stay alive side by side and
/// only the visible one changes.
class CourtShell extends StatelessWidget {
  const CourtShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final rail = width >= courtRailBreakpoint;
    // A bottom bar is pushed up by the keyboard, so the pill would float on
    // top of it — covering the row of keys and pointing at tabs the user is
    // not trying to reach. While something is being typed, it stands down.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final current = CourtTab.values[navigationShell.currentIndex];

    void go(int index) => navigationShell.goBranch(
      index,
      // Tapping the tab you are already on pops it back to its own root.
      initialLocation: index == navigationShell.currentIndex,
    );

    return PopScope(
      // Android back inside a tab: pop that tab's own stack first, then fall
      // back to Home, and only leave the app from Home itself. Without this,
      // back from any tab closed the app outright.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
        } else if (navigationShell.currentIndex != 0) {
          go(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: CourtBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          // A real bottom bar, not an overlay. Flutter reserves the space, so
          // nothing — scrolling or not — can end up underneath it.
          bottomNavigationBar: rail || typing
              ? null
              : SafeArea(
                  top: false,
                  minimum: EdgeInsets.zero,
                  child: CourtNavBar(current: current, onSelect: go),
                ),
          body: rail
              ? Row(
                  children: [
                    SueNavRail(current: current, onSelect: go),
                    Expanded(child: navigationShell),
                  ],
                )
              : navigationShell,
        ),
      ),
    );
  }
}

/// A screen: the warm page, the screen's own header, content held to a
/// readable width.
///
/// The canvas has no app bar anywhere, so a screen that passes [header] gets
/// its own row instead. [title] is still required: it is what the back button
/// and the route announce, and screens outside the canvas (settings, invites,
/// a court's page) fall back to a plain transparent bar.
///
/// Navigation is **not** drawn here — [CourtShell] owns it.
class CourtScaffold extends StatelessWidget {
  const CourtScaffold({
    super.key,
    required this.title,
    required this.body,
    this.header,
    this.actions,
    this.leading,
    this.bottom,
    this.floatingActionButton,
    this.automaticallyImplyLeading = true,
    this.hero = false,
    this.maxWidth = courtContentWidth,
    this.tablet,
  });

  final String title;
  final Widget body;

  /// The screen's own header row, drawn in place of an app bar.
  final Widget? header;

  final List<Widget>? actions;
  final Widget? leading;

  /// A docked panel pinned under the body.
  final Widget? bottom;

  final Widget? floatingActionButton;
  final bool automaticallyImplyLeading;
  final bool hero;
  final double maxWidth;

  /// The screen as the canvas's tablet artboard draws it: its own 28px page,
  /// its own loud title row, its own columns. Used whole — [header], [body]
  /// and [bottom] are the phone frame and stand down — from
  /// [sueTabletBreakpoint] up. A screen that has no tablet artboard leaves
  /// this null and keeps the phone layout, centred, at any width.
  final Widget? tablet;

  @override
  Widget build(BuildContext context) {
    final wide = tablet != null && context.isTablet;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) header!,
        Expanded(child: body),
        if (bottom != null) bottom!,
      ],
    );

    final content = wide
        ? tablet!
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: column,
            ),
          );

    return CourtBackground(
      hero: hero,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: header != null || wide
            ? null
            : AppBar(
                title: Text(title),
                actions: actions,
                leading: leading,
                automaticallyImplyLeading: automaticallyImplyLeading,
              ),
        floatingActionButton: floatingActionButton,
        // The tablet page lays out its own safe area so a side panel can run
        // to the edge of the glass.
        body: wide ? content : SafeArea(bottom: bottom == null, child: content),
      ),
    );
  }
}

/// A big display heading inside the body, in the court's voice.
///
/// Deliberately not the app bar title: the bar says which room you are in,
/// this says what the room is about, and it can be much louder.
class PageTitle extends StatelessWidget {
  const PageTitle({
    super.key,
    required this.label,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String label;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.inkDim,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: context.text.displaySmall)),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.inkDim,
            ),
          ),
        ],
      ],
    ),
  );
}

/// One number worth knowing at a glance.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.color,
  });

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: courtShadow(context),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: context.text.headlineSmall?.copyWith(
              color: color ?? context.palette.accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.palette.inkDim,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A row of [StatTile]s with consistent spacing.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          tiles[i],
        ],
      ],
    ),
  );
}

/// A tappable surface with a coloured spine down its left edge.
///
/// The spine is the status: you can read a docket at arm's length by colour
/// before you read a word of it.
class SpineCard extends StatelessWidget {
  const SpineCard({
    super.key,
    required this.spine,
    required this.child,
    this.onTap,
  });

  final Color spine;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: courtShadow(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: spine,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
