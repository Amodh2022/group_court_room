import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/widgets/verdict_reveal.dart';
import '../../cases/data/case_providers.dart';

class VerdictScreen extends ConsumerWidget {
  const VerdictScreen({super.key, required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(verdictControllerProvider(caseId));
    final controller = ref.read(verdictControllerProvider(caseId).notifier);
    // The jury's split is part of the case, not the verdict payload.
    final caseDetail = ref.watch(caseDetailProvider(caseId));
    final tally = caseDetail.valueOrNull?.juryTally;

    return CourtScaffold(
      title: 'The verdict',
      body: state.when(
        loading: () => const _Deliberating(),
        error: (error, _) => CourtErrorView(
          message: error is ApiException
              ? error.message
              : 'The court is unavailable.',
          onRetry: controller.refresh,
        ),
        data: (data) => switch (data.status) {
          // Wait for the case the first time: the reveal fixes its beats
          // when it mounts, so starting without the jury would drop it from
          // the sequence for good. A later refresh keeps the last value, so
          // this never re-blanks a verdict the user is already reading.
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
            ),
          ),
          CaseStatus.generating => _Deliberating(
            timedOut: controller.timedOut,
            onRetry: controller.refresh,
          ),
          CaseStatus.ready => CourtNotice(
            icon: Icons.gavel,
            title: 'Both sides are in',
            message:
                'The defense has been filed. Call the court to order '
                'and the judge will rule.',
            action: FilledButton(
              onPressed: controller.requestVerdict,
              child: const Text('Call the court to order'),
            ),
          ),
          CaseStatus.failed => CourtNotice(
            icon: Icons.error_outline,
            title: 'A mistrial',
            message:
                'The court could not reach a verdict. Nothing is lost '
                '— you can safely ask it to try again.',
            action: FilledButton(
              onPressed: controller.requestVerdict,
              child: const Text('Retry the verdict'),
            ),
          ),
          CaseStatus.expired => const CourtNotice(
            icon: Icons.lock_clock,
            title: 'This case expired',
            message: 'It closed before both sides were heard.',
          ),
          _ => const CourtNotice(
            icon: Icons.hourglass_top,
            title: 'Still awaiting a defense',
            message:
                'The court cannot rule until the defendant has had their say.',
          ),
        },
      ),
    );
  }
}

class _Deliberating extends StatelessWidget {
  const _Deliberating({this.timedOut = false, this.onRetry});

  final bool timedOut;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (timedOut) {
      return CourtNotice(
        icon: Icons.schedule,
        title: 'The judge is taking their time',
        message:
            'Deliberation is still running. The verdict is not lost — '
            'check again in a moment.',
        action: onRetry == null
            ? null
            : FilledButton(
                onPressed: onRetry,
                child: const Text('Check again'),
              ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: context.palette.accent,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'The court is in deliberation',
            style: context.text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Both sides have been heard. The judge is weighing the evidence, '
              'such as it is.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: context.palette.inkDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictView extends ConsumerStatefulWidget {
  const _VerdictView({required this.caseId, required this.verdict, this.tally});

  final String caseId;
  final Verdict verdict;
  final JuryTally? tally;

  @override
  ConsumerState<_VerdictView> createState() => _VerdictViewState();
}

class _VerdictViewState extends ConsumerState<_VerdictView> {
  ShareLink? _shareLink;
  bool _busy = false;

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        CourtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('In the matter of'),
              const SizedBox(height: 8),
              Text(v.caseTitle, style: context.text.headlineMedium),
              const SizedBox(height: 6),
              Text(
                v.charge,
                style: context.text.bodyMedium?.copyWith(
                  color: context.palette.inkDim,
                ),
              ),
              const SizedBox(height: 28),
              VerdictStamp(verdict: v.verdict, animate: true),
              const SizedBox(height: 28),
              if (widget.tally != null && !widget.tally!.isEmpty) ...[
                const SectionLabel('The jury'),
                const SizedBox(height: 6),
                Text(
                  widget.tally!.summary,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.palette.inkDim,
                  ),
                ),
                const SizedBox(height: 12),
                JuryTallyBar(tally: widget.tally!),
                if (v.verdict.overrules(widget.tally))
                  OverruledBanner(
                    note: v.juryNote.isNotEmpty
                        ? v.juryNote
                        : 'The court thanks the jury for its time, and disagrees.',
                  ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        CourtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Section(label: 'Prosecution', body: v.prosecutionSummary),
              _Section(label: 'Defense', body: v.defenseSummary),
              _Section(label: 'Reasoning', body: v.reasoning),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CourtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Sentence'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.palette.line,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Text(v.sentence, style: context.text.bodyLarge),
              ),
              const SizedBox(height: 18),
              const SectionLabel('The judge adds'),
              const SizedBox(height: 8),
              Text(
                '“${v.judgeRoast}”',
                style: context.text.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: context.palette.inkDim,
                ),
              ),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  v.closingLine,
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium?.copyWith(
                    fontFamily: courtDisplayFont,
                    color: context.palette.inkDim,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_shareLink == null)
          FilledButton.icon(
            onPressed: _busy ? null : _enableShare,
            icon: const Icon(Icons.ios_share),
            label: const Text('Publish and share the verdict'),
          )
        else ...[
          CourtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.public, size: 18, color: context.palette.accent),
                    const SizedBox(width: 8),
                    const Expanded(child: SectionLabel('Public link is live')),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _shareLink!.url,
                  style: context.text.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _shareLink!.url),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied.')),
                          );
                        },
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _revokeShare,
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('Revoke'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: '${v.shareCaption} ${_shareLink!.url}'),
            ),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share again'),
          ),
        ],
        const CourtDisclaimer(
          text:
              'Publishing is opt-in and reversible. The public page shows only '
              'the verdict — never the raw accusation or defense.',
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: 6),
        Text(body, style: context.text.bodyMedium),
      ],
    ),
  );
}
