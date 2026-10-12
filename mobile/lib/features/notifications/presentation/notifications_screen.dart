import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../courts/data/court_providers.dart';

/// The bell with an unread count. Opens the notification list.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider).valueOrNull?.unread ?? 0;
    return IconButton(
      tooltip: unread > 0 ? 'Notifications ($unread unread)' : 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        backgroundColor: CourtColors.red,
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _marked = false;

  Future<void> _markRead(NotificationFeed feed) async {
    if (_marked || feed.unread == 0) return;
    _marked = true;
    try {
      await ref.read(apiClientProvider).markNotificationsRead();
    } catch (_) {
      _marked = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(notificationsProvider);
    ref.watch(authControllerProvider);

    return CourtScaffold(
      title: 'Notifications',
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(notificationsProvider.future),
        child: feed.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              CourtSkeleton(height: 70),
              SizedBox(height: 10),
              CourtSkeleton(height: 70),
            ],
          ),
          error: (e, _) => ListView(
            children: [
              SizedBox(
                height: 360,
                child: CourtErrorView(
                  message: e is ApiException ? e.message : 'Could not load.',
                  onRetry: () => ref.invalidate(notificationsProvider),
                ),
              ),
            ],
          ),
          data: (data) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await _markRead(data);
            });
            if (data.items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(
                    height: 360,
                    child: CourtNotice(
                      icon: Icons.notifications_none_rounded,
                      title: 'All quiet',
                      message: 'Summons and court invites show up here.',
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                for (final n in data.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _NotificationTile(item: n),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final AppNotification item;

  IconData get _icon => switch (item.kind) {
    'added_to_court' => Icons.groups_outlined,
    'summoned' => Icons.gavel,
    _ => Icons.how_to_vote_outlined,
  };

  @override
  Widget build(BuildContext context) => CourtCard(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.palette.surfaceAlt,
          ),
          child: Icon(_icon, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.text,
                style: TextStyle(
                  fontWeight: item.read ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
              if (item.createdAt != null)
                Text(
                  DateFormat.MMMd().add_jm().format(item.createdAt!.toLocal()),
                  style: context.text.bodySmall?.copyWith(
                    color: context.palette.inkFaint,
                  ),
                ),
            ],
          ),
        ),
        if (!item.read)
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: CourtColors.red,
              shape: BoxShape.circle,
            ),
          ),
      ],
    ),
  );
}
