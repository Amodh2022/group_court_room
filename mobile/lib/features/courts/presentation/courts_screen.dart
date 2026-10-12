import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../data/court_providers.dart';
import 'user_search_sheet.dart';

class CourtsScreen extends ConsumerWidget {
  const CourtsScreen({super.key});

  Future<String?> _ask(
    BuildContext context, {
    required String title,
    required String hint,
    required String action,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _fail(BuildContext context, Object e) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : '$e')));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(courtsProvider);

    Future<void> create() async {
      final name = await _ask(
        context,
        title: 'New court',
        hint: 'The Brunch Crew',
        action: 'Create',
      );
      if (name == null || name.isEmpty) return;
      try {
        final court = await ref.read(apiClientProvider).createCourt(name);
        ref.invalidate(courtsProvider);
        if (context.mounted) context.push('/courts/${court.id}');
      } catch (e) {
        if (context.mounted) _fail(context, e);
      }
    }

    Future<void> join() async {
      final code = await _ask(
        context,
        title: 'Join a court',
        hint: 'Invite code',
        action: 'Join',
      );
      if (code == null || code.isEmpty) return;
      try {
        await ref.read(apiClientProvider).joinCourt(code);
        ref.invalidate(courtsProvider);
      } catch (e) {
        if (context.mounted) _fail(context, e);
      }
    }

    return CourtScaffold(
      title: 'Courts',
      tab: CourtTab.courts,
      actions: const [NotificationBell()],
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(courtsProvider.future),
        child: courts.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              CourtSkeleton(height: 90),
              SizedBox(height: 12),
              CourtSkeleton(height: 90),
            ],
          ),
          error: (e, _) => ListView(
            children: [
              SizedBox(
                height: 360,
                child: CourtErrorView(
                  message: e is ApiException
                      ? e.message
                      : 'Could not load your courts.',
                  onRetry: () => ref.invalidate(courtsProvider),
                ),
              ),
            ],
          ),
          data: (items) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              Text('Your friend groups', style: context.text.displaySmall),
              const SizedBox(height: 6),
              Text(
                'Add friends once. File a case in a court and everyone in it is on the jury.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.palette.inkDim,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Flexible(
                    child: RoundAction(
                      icon: Icons.add,
                      label: 'New court',
                      onTap: create,
                    ),
                  ),
                  Flexible(
                    child: RoundAction(
                      icon: Icons.vpn_key_outlined,
                      label: 'Join by code',
                      onTap: join,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              for (final court in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CourtCard(court: court),
                ),
              DashedAddTile(label: 'Start a new court', onTap: create),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court});

  final Court court;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(24),
      boxShadow: courtShadow(context),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/courts/${court.id}'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      court.name,
                      style: context.text.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${court.members.length} member'
                      '${court.members.length == 1 ? '' : 's'}',
                      style: context.text.bodySmall?.copyWith(
                        color: context.palette.inkDim,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 36.0 * (court.members.take(4).length + 1) * 0.6 + 10,
                height: 36,
                child: Stack(
                  children: [
                    for (var i = 0; i < court.members.take(4).length; i++)
                      Positioned(
                        left: i * 20.0,
                        child: AvatarTile(
                          name: court.members[i].displayName,
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.palette.inkFaint),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One court: members, the invite code, and adding a friend by handle.
class CourtDetailScreen extends ConsumerWidget {
  const CourtDetailScreen({super.key, required this.courtId});

  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(courtsProvider);
    final me = ref.watch(authControllerProvider).valueOrNull?.userId;

    return CourtScaffold(
      title: 'Court',
      body: courts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => CourtErrorView(
          message: e is ApiException ? e.message : 'Could not load this court.',
          onRetry: () => ref.invalidate(courtsProvider),
        ),
        data: (items) {
          final court = items.where((c) => c.id == courtId).firstOrNull;
          if (court == null) {
            return const CourtNotice(
              icon: Icons.groups_outlined,
              title: 'Court not found',
              message: 'You are not a member of this court.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Text(court.name, style: context.text.displaySmall),
              const SizedBox(height: 18),
              CourtCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Invite code', style: context.text.bodySmall),
                          const SizedBox(height: 4),
                          SelectableText(
                            court.inviteCode,
                            style: context.text.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy code',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: court.inviteCode),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite code copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text('Members', style: context.text.titleMedium),
              const SizedBox(height: 10),
              for (final m in court.members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CourtCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        AvatarTile(name: m.displayName, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '@${m.handle}'
                                '${m.userId == court.ownerId ? ' · owner' : ''}'
                                '${m.userId == me ? ' · you' : ''}',
                                style: context.text.bodySmall?.copyWith(
                                  color: context.palette.inkDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              DashedAddTile(
                label: 'Add a friend',
                height: 64,
                onTap: () async {
                  final user = await pickUser(context, title: 'Add to court');
                  if (user == null) return;
                  try {
                    await ref
                        .read(apiClientProvider)
                        .addCourtMember(court.id, user.userId);
                    ref.invalidate(courtsProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e is ApiException ? e.message : '$e'),
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () => context.push('/cases/new?court=${court.id}'),
                icon: const Icon(Icons.gavel),
                label: const Text('File a case here'),
              ),
            ],
          );
        },
      ),
    );
  }
}
