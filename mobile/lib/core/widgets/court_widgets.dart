import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Small quiet-grey all-caps heading used throughout the court's documents.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.text.titleMedium);
}

/// A white card that floats on the page, like the reference's panels: a broad,
/// soft shadow and a hairline edge instead of a heavy border.
class CourtCard extends StatelessWidget {
  const CourtCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(24),
      boxShadow: courtShadow(context),
    ),
    child: Padding(padding: padding ?? const EdgeInsets.all(20), child: child),
  );
}

/// The verdict stamp, slammed down on reveal.
class VerdictStamp extends StatelessWidget {
  const VerdictStamp({super.key, required this.verdict, this.animate = false});

  final VerdictKind verdict;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final isLong = verdict == VerdictKind.insufficientEvidence;
    final stamp = Transform.rotate(
      angle: -0.061, // ~3.5 degrees, as on the web card
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: verdict.color, width: 4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          verdict.label,
          key: const Key('verdict-stamp'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: courtDisplayFont,
            fontWeight: FontWeight.w800,
            fontSize: isLong ? 20 : 32,
            letterSpacing: 2,
            color: verdict.color,
          ),
        ),
      ),
    );

    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      return Center(child: stamp);
    }

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 2.4 - 1.4 * t, child: child),
        ),
        child: stamp,
      ),
    );
  }
}

/// Full-screen empty / error / success state.
class CourtNotice extends StatelessWidget {
  const CourtNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 52, color: context.palette.accent),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: context.text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.palette.inkDim,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 26),
                  SizedBox(width: double.infinity, child: action),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shimmering placeholder used while a list or card loads.
class CourtSkeleton extends StatefulWidget {
  const CourtSkeleton({super.key, this.height = 16, this.width});

  final double height;
  final double? width;

  @override
  State<CourtSkeleton> createState() => _CourtSkeletonState();
}

class _CourtSkeletonState extends State<CourtSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.palette.surfaceAlt;
    final highlight = Color.alphaBlend(
      context.palette.accent.withValues(alpha: 0.10),
      base,
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment(-1 - 2 * _controller.value, 0),
            end: Alignment(1 - 2 * _controller.value, 0),
            colors: [base, highlight, base],
          ),
        ),
      ),
    );
  }
}

class CourtErrorView extends StatelessWidget {
  const CourtErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => CourtNotice(
    icon: Icons.gavel_outlined,
    title: 'Order in the court',
    message: message,
    action: onRetry == null
        ? null
        : FilledButton(onPressed: onRetry, child: const Text('Try again')),
  );
}

/// Inline, dismissible error for a form submission.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CourtColors.guilty.withValues(alpha: 0.12),
      border: Border.all(color: CourtColors.guilty),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: CourtColors.guilty, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: context.text.bodyMedium)),
      ],
    ),
  );
}

class CourtDisclaimer extends StatelessWidget {
  const CourtDisclaimer({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
    child: Text(
      text ??
          'Group Chat Court is a comedy game. Verdicts are entertainment — '
              'not a finding of fact, and not legal advice.',
      textAlign: TextAlign.center,
      style: context.text.bodySmall?.copyWith(color: context.palette.inkDim),
    ),
  );
}

/// A small status pill. The court's answer to a badge.
class CourtChip extends StatelessWidget {
  const CourtChip(this.label, {super.key, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? context.palette.inkDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: context.text.bodySmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// How the room voted, as a split bar. Counts only — the API never says who
/// voted which way, and neither does this.
class JuryTallyBar extends StatelessWidget {
  const JuryTallyBar({super.key, required this.tally, this.animate = true});

  final JuryTally tally;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final guiltyFlex = tally.isEmpty ? 1 : tally.guilty;
    final notGuiltyFlex = tally.isEmpty ? 1 : tally.notGuilty;

    return Semantics(
      label: 'Jury: ${tally.guilty} guilty, ${tally.notGuilty} not guilty',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              key: const Key('jury-tally'),
              height: 14,
              child: Row(
                // Without `stretch`, a Row hands its children loose vertical
                // constraints and a childless ColoredBox takes the smallest
                // size it is offered — which is zero. The bar then exists,
                // passes a find-by-key test, and paints nothing.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (guiltyFlex > 0)
                    Expanded(
                      flex: guiltyFlex,
                      child: const ColoredBox(color: CourtColors.guilty),
                    ),
                  if (notGuiltyFlex > 0)
                    Expanded(
                      flex: notGuiltyFlex,
                      child: const ColoredBox(color: CourtColors.greenFill),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${tally.guilty} guilty',
                style: context.text.bodySmall?.copyWith(
                  color: CourtColors.guilty,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${tally.notGuilty} not guilty',
                style: context.text.bodySmall?.copyWith(
                  color: context.palette.successText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The banner for the best outcome in the game: the judge siding against the
/// room. Shown only when the jury actually reached a majority.
class OverruledBanner extends StatelessWidget {
  const OverruledBanner({super.key, required this.note});

  final String note;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('overruled'),
    width: double.infinity,
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.palette.accent.withValues(alpha: 0.12),
      border: Border.all(color: context.palette.accent.withValues(alpha: 0.45)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Text(
          'The jury has been overruled.',
          textAlign: TextAlign.center,
          style: context.text.titleMedium?.copyWith(
            fontFamily: courtDisplayFont,
            fontWeight: FontWeight.w700,
            color: context.palette.accent,
          ),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            note,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.inkDim,
            ),
          ),
        ],
      ],
    ),
  );
}

/// A copyable link the user is meant to send to someone.
class ShareableLink extends StatelessWidget {
  const ShareableLink({
    super.key,
    required this.label,
    required this.url,
    required this.hint,
    required this.onShare,
  });

  final String label;
  final String url;
  final String hint;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionLabel(label),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.palette.line),
        ),
        child: SelectableText(
          url,
          style: context.text.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        hint,
        style: context.text.bodySmall?.copyWith(color: context.palette.inkDim),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: onShare,
        icon: const Icon(Icons.ios_share, size: 18),
        label: Text('Share the ${label.toLowerCase()}'),
      ),
    ],
  );
}
