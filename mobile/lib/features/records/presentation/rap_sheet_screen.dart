import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../cases/data/case_providers.dart';

/// Standings in this court. The reason case #5 is funnier than case #1.
class RapSheetScreen extends ConsumerWidget {
  const RapSheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheet = ref.watch(rapSheetProvider);

    return CourtScaffold(
      title: 'Rap sheet',
      tab: CourtTab.record,
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(rapSheetProvider.future),
        child: sheet.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, __) => const CourtCard(
              child: Row(
                children: [
                  CourtSkeleton(height: 28, width: 28),
                  SizedBox(width: 14),
                  Expanded(child: CourtSkeleton(height: 18)),
                ],
              ),
            ),
          ),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: CourtErrorView(
                  message: error is ApiException
                      ? error.message
                      : 'Could not pull the records.',
                  onRetry: () => ref.invalidate(rapSheetProvider),
                ),
              ),
            ],
          ),
          data: (rows) => rows.isEmpty
              ? ListView(
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.7,
                      child: CourtNotice(
                        icon: Icons.folder_open,
                        title: 'No convictions yet',
                        message:
                            'Suspiciously clean, this group. Every verdict '
                            'the court hands down lands on somebody\'s record.',
                        action: FilledButton(
                          onPressed: () => context.push('/cases/new'),
                          child: const Text('File a case'),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    PageTitle(
                      label: 'Standings',
                      title: 'The rap sheet',
                      subtitle:
                          'Every verdict this court has handed down, by '
                          'the person who earned it. The judge reads these '
                          'out before sentencing.',
                    ),
                    StatStrip(
                      tiles: [
                        StatTile(
                          value:
                              '${rows.fold<int>(0, (n, r) => n + r.convictions)}',
                          label: 'Convictions',
                          color: CourtColors.guilty,
                        ),
                        StatTile(
                          value:
                              '${rows.fold<int>(0, (n, r) => n + r.acquittals)}',
                          label: 'Acquittals',
                          color: CourtColors.notGuilty,
                        ),
                        StatTile(
                          value:
                              '${rows.fold<int>(0, (n, r) => r.longestStreak > n ? r.longestStreak : n)}',
                          label: 'Longest streak',
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: _RecordCard(entry: row),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.entry});

  final RapSheetEntry entry;

  @override
  Widget build(BuildContext context) {
    final isTop = entry.rank == 1;
    return SpineCard(
      spine: entry.convictions == 0
          ? CourtColors.notGuilty
          : isTop
          ? CourtColors.guilty
          : context.palette.accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: context.text.headlineSmall?.copyWith(
                color: isTop ? context.palette.accent : context.palette.inkDim,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.displayName, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  entry.title,
                  style: context.text.bodySmall?.copyWith(
                    color: context.palette.inkDim,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    CourtChip('${entry.casesTotal} tried'),
                    CourtChip(
                      '${entry.acquittals} acquitted',
                      color: CourtColors.notGuilty,
                    ),
                    if (entry.mistrials > 0)
                      CourtChip(
                        '${entry.mistrials} mistrial',
                        color: CourtColors.insufficient,
                      ),
                    if (entry.currentStreak >= 2)
                      CourtChip(
                        '${entry.currentStreak}-case streak',
                        color: context.palette.accent,
                        icon: Icons.local_fire_department,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Text(
                '${entry.convictions}',
                style: context.text.headlineSmall?.copyWith(
                  color: CourtColors.guilty,
                ),
              ),
              Text(
                'GUILTY',
                style: context.text.bodySmall?.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: context.palette.inkDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
