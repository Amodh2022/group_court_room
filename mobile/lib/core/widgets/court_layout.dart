import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';

/// Widest a column of content gets. Past this the screen centres it.
const courtContentWidth = 720.0;

/// Breakpoints. Below [courtRailBreakpoint] the nav floats at the bottom; from
/// there up it becomes a rail down the side. From [courtWideBreakpoint] lists
/// become two columns.
const courtRailBreakpoint = 600.0;
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
                    colors: [
                      CourtColors.heroBlue.withValues(alpha: dark ? 0.5 : 0.9),
                      CourtColors.heroPink.withValues(alpha: dark ? 0.5 : 0.85),
                      CourtColors.heroViolet.withValues(
                        alpha: dark ? 0.4 : 0.55,
                      ),
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

/// Where a top-level screen sits in the main navigation.
enum CourtTab {
  home('/', Icons.home_outlined, Icons.home_rounded, 'Home'),
  courts('/courts', Icons.groups_outlined, Icons.groups_rounded, 'Courts'),
  record('/rap-sheet', Icons.fingerprint, Icons.fingerprint, 'Rap sheet'),
  settings(
    '/settings',
    Icons.settings_outlined,
    Icons.settings_rounded,
    'Settings',
  );

  const CourtTab(this.path, this.icon, this.activeIcon, this.label);
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
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

/// The floating bottom bar: round buttons, the current one filled black.
class _FloatingNav extends StatelessWidget {
  const _FloatingNav({required this.current});

  final CourtTab current;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(40),
      boxShadow: courtShadow(context),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tab in CourtTab.values)
          Semantics(
            button: true,
            selected: tab == current,
            label: tab.label,
            child: Tooltip(
              message: tab.label,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => tab == current ? null : context.go(tab.path),
                child: Container(
                  width: 52,
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tab == current
                        ? context.colors.onSurface
                        : Colors.transparent,
                  ),
                  child: Icon(
                    tab == current ? tab.activeIcon : tab.icon,
                    color: tab == current
                        ? context.colors.surface
                        : context.colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A screen: soft grey canvas, a transparent app bar, content held to a
/// readable width, and (for top-level screens) the main navigation: a floating
/// bar on phones, a rail on tablets and in landscape.
class CourtScaffold extends StatelessWidget {
  const CourtScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.automaticallyImplyLeading = true,
    this.tab,
    this.hero = false,
    this.maxWidth = courtContentWidth,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final bool automaticallyImplyLeading;
  final CourtTab? tab;
  final bool hero;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final rail = tab != null && width >= courtRailBreakpoint;
    final bar = tab != null && !rail;
    // Leave room under scrolling content for the floating bar.
    final content = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: MediaQuery.paddingOf(context).copyWith(
          bottom: MediaQuery.paddingOf(context).bottom + (bar ? 84 : 0),
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: body,
        ),
      ),
    );

    return CourtBackground(
      hero: hero,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(title),
          actions: actions,
          leading: leading,
          automaticallyImplyLeading: automaticallyImplyLeading && tab == null,
        ),
        floatingActionButton: floatingActionButton == null
            ? null
            : Padding(
                padding: EdgeInsets.only(bottom: bar ? 76 : 0),
                child: floatingActionButton,
              ),
        bottomNavigationBar: null,
        body: Stack(
          children: [
            SafeArea(
              child: rail
                  ? Row(
                      children: [
                        _Rail(current: tab!),
                        Expanded(child: content),
                      ],
                    )
                  : content,
            ),
            if (bar)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  minimum: const EdgeInsets.only(bottom: 12),
                  child: Center(child: _FloatingNav(current: tab!)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.current});

  final CourtTab current;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
    child: Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(40),
        boxShadow: courtShadow(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tab in CourtTab.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Semantics(
                button: true,
                selected: tab == current,
                label: tab.label,
                child: Tooltip(
                  message: tab.label,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => tab == current ? null : context.go(tab.path),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tab == current
                            ? context.colors.onSurface
                            : Colors.transparent,
                      ),
                      child: Icon(
                        tab == current ? tab.activeIcon : tab.icon,
                        color: tab == current
                            ? context.colors.surface
                            : context.colors.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
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
