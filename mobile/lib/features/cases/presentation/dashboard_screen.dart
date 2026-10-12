import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/env.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../courts/data/court_providers.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../data/case_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cases = ref.watch(casesProvider);
    final name = ref.watch(authControllerProvider).valueOrNull?.displayName;

    return CourtScaffold(
      title: 'Group Chat Court',
      tab: CourtTab.home,
      maxWidth: 1000,
      actions: const [NotificationBell()],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sharedCasesProvider);
          ref.invalidate(notificationsProvider);
          ref.invalidate(casesProvider);
          await ref.read(casesProvider.future);
        },
        child: cases.when(
          loading: () => const _DashboardSkeleton(),
          error: (error, _) => ListView(
            // A scrollable is required for pull-to-refresh to work in an
            // error state, which is exactly when a user wants to retry.
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: CourtErrorView(
                  message: error is ApiException
                      ? error.message
                      : 'Could not load your docket.',
                  onRetry: () => ref.invalidate(casesProvider),
                ),
              ),
            ],
          ),
          data: (items) => _Docket(items: items, name: name),
        ),
      ),
    );
  }
}

class _Docket extends ConsumerWidget {
  const _Docket({required this.items, this.name});

  final List<CaseSummary> items;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = items
        .where((c) => !c.verdictReady && c.status != CaseStatus.expired)
        .length;
    final ruled = items.where((c) => c.verdictReady).length;
    final jurors = items.fold<int>(0, (sum, c) => sum + c.juryCount);
    final shared = ref.watch(sharedCasesProvider).valueOrNull ?? const [];
    final wide = MediaQuery.sizeOf(context).width >= courtWideBreakpoint;

    Widget cards() => wide
        ? LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final summary in items)
                  SizedBox(
                    width: (c.maxWidth - 12) / 2,
                    child: _CaseCard(summary: summary),
                  ),
              ],
            ),
          )
        : Column(
            children: [
              for (final summary in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CaseCard(summary: summary),
                ),
            ],
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(
          name == null ? 'Hello' : 'Hello $name',
          style: context.text.displaySmall,
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('EEEE, d MMMM').format(DateTime.now()),
          style: context.text.bodySmall?.copyWith(
            color: context.palette.inkDim,
          ),
        ),
        const SizedBox(height: 18),
        CourtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Stat(value: '$open', label: 'Open cases'),
                  ),
                  Expanded(
                    child: _Stat(
                      value: '$ruled',
                      label: 'Ruled',
                      color: ruled > 0 ? CourtColors.notGuilty : null,
                    ),
                  ),
                  Expanded(
                    child: _Stat(value: '$jurors', label: 'Jurors'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: RoundAction(
                      icon: Icons.gavel,
                      label: 'New case',
                      onTap: () => context.push('/cases/new'),
                    ),
                  ),
                  Flexible(
                    child: RoundAction(
                      icon: Icons.groups_outlined,
                      label: 'Courts',
                      onTap: () => context.go('/courts'),
                    ),
                  ),
                  Flexible(
                    child: RoundAction(
                      icon: Icons.fingerprint,
                      label: 'Record',
                      onTap: () => context.go('/rap-sheet'),
                    ),
                  ),
                  Flexible(
                    child: RoundAction(
                      icon: Icons.notifications_none_rounded,
                      label: 'Alerts',
                      onTap: () => context.push('/notifications'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (shared.isNotEmpty) ...[
          const SizedBox(height: 24),
          const SectionLabel('Shared with me'),
          const SizedBox(height: 10),
          for (final item in shared)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SharedCard(item: item),
            ),
        ],
        const SizedBox(height: 24),
        const SectionLabel('My cases'),
        const SizedBox(height: 10),
        if (items.isEmpty) const _EmptyDocketCard() else cards(),
        const SizedBox(height: 12),
        DashedAddTile(
          label: 'File a new case',
          onTap: () => context.push('/cases/new'),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: context.text.bodySmall?.copyWith(color: context.palette.inkDim),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: context.text.displaySmall?.copyWith(color: color, fontSize: 34),
      ),
    ],
  );
}

class _SharedCard extends StatelessWidget {
  const _SharedCard({required this.item});

  final SharedCase item;

  @override
  Widget build(BuildContext context) => CourtCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => showSharedCase(context, item),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AvatarTile(name: item.creatorName, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: context.text.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${item.creatorName} · you are the '
                    '${item.role == 'accused' ? 'accused' : 'juror'}',
                    style: context.text.bodySmall?.copyWith(
                      color: context.palette.inkDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.palette.inkFaint),
          ],
        ),
      ),
    ),
  );
}

/// Jury duty and summonses are answered in the browser; hand over the link.
void showSharedCase(BuildContext context, SharedCase item) {
  final link = '${Env.webBaseUrl}${item.path}';
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: context.text.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '${item.creatorName} added you as '
            '${item.role == 'accused' ? 'the accused' : 'a juror'}.',
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(link, style: context.text.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy link to answer in browser'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Link copied')));
            },
          ),
        ],
      ),
    ),
  );
}

class _EmptyDocketCard extends StatelessWidget {
  const _EmptyDocketCard();

  @override
  Widget build(BuildContext context) => CourtCard(
    child: Column(
      children: [
        Icon(Icons.balance, size: 40, color: context.palette.inkFaint),
        const SizedBox(height: 10),
        Text('The docket is empty', style: context.text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'File your first case and summon a friend to defend themselves.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.inkDim,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => context.push('/cases/new'),
          child: const Text('File a case'),
        ),
      ],
    ),
  );
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.summary});

  final CaseSummary summary;

  @override
  Widget build(BuildContext context) {
    final statusColor = summary.status.color(context);
    final number = summary.id.length >= 5
        ? summary.id.substring(0, 5).toUpperCase()
        : summary.id.toUpperCase();

    // A "Court Trial" card from the reference: courthouse, number, and a pill.
    // The fill and the shadow live on the same box. A shadow on a box with no
    // fill shows through its own middle as a grey wash.
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: courtShadow(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => context.push('/cases/${summary.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.palette.surfaceAlt,
                  ),
                  child: Icon(
                    Icons.account_balance,
                    size: 22,
                    color: context.colors.onSurface,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(summary.title, style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Court Trial · $number'
                        '${summary.defendantNickname == null ? '' : ' · v. ${summary.defendantNickname}'}',
                        style: context.text.bodySmall?.copyWith(
                          color: context.palette.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            summary.status.icon,
                            size: 15,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              summary.status.label,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (summary.shareEnabled) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.public,
                              size: 15,
                              color: context.palette.inkFaint,
                            ),
                          ],
                          if (summary.juryCount > 0) ...[
                            const SizedBox(width: 8),
                            CourtChip(
                              '${summary.juryCount}',
                              color: context.palette.accent,
                              icon: Icons.groups_outlined,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: ShapeDecoration(
                    color: context.palette.accent,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    summary.verdictReady ? 'Verdict' : 'Open',
                    style: TextStyle(
                      color: context.colors.onPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
    children: const [
      CourtSkeleton(height: 12, width: 90),
      SizedBox(height: 14),
      CourtSkeleton(height: 34, width: 220),
      SizedBox(height: 22),
      CourtSkeleton(height: 74),
      SizedBox(height: 22),
      CourtSkeleton(height: 132),
      SizedBox(height: 12),
      CourtSkeleton(height: 132),
      SizedBox(height: 12),
      CourtSkeleton(height: 132),
    ],
  );
}
