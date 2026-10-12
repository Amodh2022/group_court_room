import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/courtroom.dart';
import '../../auth/data/auth_providers.dart';
import '../data/case_providers.dart';
import 'courtroom_panel.dart';

class CaseDetailScreen extends ConsumerWidget {
  const CaseDetailScreen({super.key, required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(caseDetailProvider(caseId));

    return CourtScaffold(
      title: 'Case file',
      actions: [
        if (detail.hasValue)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete case',
            onPressed: () => _confirmDelete(context, ref),
          ),
      ],
      body: detail.when(
        loading: () => const _DetailSkeleton(),
        error: (error, _) => CourtErrorView(
          message: error is ApiException
              ? error.message
              : 'Could not open this case file.',
          onRetry: () => ref.invalidate(caseDetailProvider(caseId)),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.refresh(caseDetailProvider(caseId).future),
          child: _CaseBody(detail: data),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dismiss this case?'),
        content: const Text(
          'The case, the defense and the verdict are deleted, and every link '
          'you have shared stops working immediately. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CourtColors.guilty),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(caseActionsProvider).delete(caseId);
      if (!context.mounted) return;
      context.go('/');
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _CaseBody extends ConsumerWidget {
  const _CaseBody({required this.detail});

  final CaseDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = CaseCategory.byId(detail.category);

    // The room hears about the defense, the votes and the verdict first; refresh
    // the case file the moment it says the status moved.
    ref.listen(courtroomProvider(detail.id), (prev, next) {
      final status = next.caseStatus;
      if (status != null && status != detail.status) {
        ref.invalidate(caseDetailProvider(detail.id));
      }
    });

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        PageTitle(
          label: '${category.emoji}  ${category.label}',
          title: detail.title,
          subtitle: 'Filed ${DateFormat.yMMMd().format(detail.createdAt)}',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (detail.defendantNickname != null)
                CourtChip('v. ${detail.defendantNickname}'),
              if (detail.juryCount > 0)
                CourtChip(
                  '${detail.juryCount} juror${detail.juryCount == 1 ? '' : 's'}',
                  color: context.palette.accent,
                  icon: Icons.groups_outlined,
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PartyTrays(
            plaintiff:
                ref.watch(authControllerProvider).valueOrNull?.displayName ??
                'You',
            defendant: detail.defendantNickname ?? 'The accused',
            defended: detail.defenseSubmitted,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border(
                left: BorderSide(color: context.palette.accent, width: 4),
              ),
            ),
            child: Text(
              '“${detail.accusation}”',
              style: context.text.bodyLarge,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: CourtroomPanel(caseId: detail.id),
        ),
        const SizedBox(height: 16),
        if (detail.juryTally != null && !detail.juryTally!.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _JuryPanel(tally: detail.juryTally!),
          ),
          const SizedBox(height: 16),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _StatusPanel(detail: detail),
        ),
      ],
    );
  }
}

/// The running count, which the creator may see at any time: they are not a
/// juror, so knowing the split cannot spoil a vote of their own.
class _JuryPanel extends StatelessWidget {
  const _JuryPanel({required this.tally});

  final JuryTally tally;

  @override
  Widget build(BuildContext context) => CourtCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.groups_outlined,
              size: 18,
              color: context.palette.accent,
            ),
            const SizedBox(width: 8),
            const Expanded(child: SectionLabel('The jury so far')),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          tally.summary,
          style: context.text.bodyMedium?.copyWith(
            color: context.palette.inkDim,
          ),
        ),
        const SizedBox(height: 14),
        JuryTallyBar(tally: tally),
      ],
    ),
  );
}

/// Explains, per status, exactly what the court is waiting for and what the
/// creator can do about it. Every control here does something real.
class _StatusPanel extends ConsumerWidget {
  const _StatusPanel({required this.detail});

  final CaseDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = detail.status.color(context);

    return CourtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(detail.status.icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                detail.status.label,
                style: context.text.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _explanation(detail),
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 18),
          ..._actions(context, ref),
        ],
      ),
    );
  }

  String _explanation(CaseDetail detail) => switch (detail.status) {
    CaseStatus.draft || CaseStatus.awaitingDefense =>
      'The summons has been issued. Nothing happens until '
          '${detail.defendantNickname ?? 'the defendant'} files a defense '
          '— but the jury can start voting right now.',
    CaseStatus.ready =>
      '${detail.defendantNickname ?? 'The defendant'} has filed a defense. '
          'Both sides are in — the court is ready to rule.',
    CaseStatus.generating =>
      'The judge is deliberating. This usually takes a few seconds.',
    CaseStatus.completed =>
      'The verdict has been handed down. Read it, then decide whether the '
          'world deserves to see it.',
    CaseStatus.failed =>
      'The court could not reach a verdict${detail.failureReason == null ? '' : ' (${detail.failureReason})'}. '
          'You can safely ask it to try again.',
    CaseStatus.expired =>
      'This case expired before a defense arrived. File a fresh one if it '
          'still matters.',
  };

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    switch (detail.status) {
      case CaseStatus.draft:
      case CaseStatus.awaitingDefense:
        return [
          OutlinedButton.icon(
            onPressed: () => ref.invalidate(caseDetailProvider(detail.id)),
            icon: const Icon(Icons.refresh),
            label: const Text('Check for a defense'),
          ),
        ];
      case CaseStatus.ready:
      case CaseStatus.failed:
        return [
          FilledButton.icon(
            onPressed: () => context.push('/cases/${detail.id}/verdict'),
            icon: const Icon(Icons.gavel),
            label: Text(
              detail.status == CaseStatus.failed
                  ? 'Try the verdict again'
                  : 'Call the court to order',
            ),
          ),
        ];
      case CaseStatus.generating:
      case CaseStatus.completed:
        return [
          FilledButton.icon(
            onPressed: () => context.push('/cases/${detail.id}/verdict'),
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              detail.status == CaseStatus.completed
                  ? 'Read the verdict'
                  : 'Watch the deliberation',
            ),
          ),
        ];
      case CaseStatus.expired:
        return [
          OutlinedButton.icon(
            onPressed: () => context.push('/cases/new'),
            icon: const Icon(Icons.gavel),
            label: const Text('File a new case'),
          ),
        ];
    }
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
    children: const [
      CourtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CourtSkeleton(height: 12, width: 110),
            SizedBox(height: 14),
            CourtSkeleton(height: 26, width: 220),
            SizedBox(height: 18),
            CourtSkeleton(height: 84),
          ],
        ),
      ),
      SizedBox(height: 16),
      CourtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CourtSkeleton(height: 18, width: 150),
            SizedBox(height: 12),
            CourtSkeleton(height: 40),
          ],
        ),
      ),
    ],
  );
}
