import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../courts/data/court_providers.dart';

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
      header: ScreenHeader(
        title: 'Notifications',
        eyebrow: feed.valueOrNull == null || feed.valueOrNull!.unread == 0
            ? 'NOTHING NEW'
            : '${feed.valueOrNull!.unread} UNREAD',
        titleSize: 30,
        padding: const EdgeInsets.fromLTRB(16, 18, 20, 12),
        leading: RoundIconButton(
          glyph: CourtGlyph.back,
          label: 'Back',
          onTap: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
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

  /// Summons go to the defence, jury duty to the jury box, court invites to
  /// the court; the same routing the web bell uses.
  ///
  /// These open in the app. They used to hand over the web URL and a "copy
  /// link to answer in browser" button, which sent somebody who already had
  /// the app out of it to answer their own summons.
  void _open(BuildContext context) {
    final token = item.token;
    if (item.linkKind == 'invite' && token != null) {
      context.push('/invite/$token');
    } else if (item.linkKind == 'jury' && token != null) {
      context.push('/jury/$token');
    } else if (item.courtId != null) {
      context.go('/courts/${item.courtId}');
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _open(context),
    child: CourtCard(
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
                    DateFormat.MMMd().add_jm().format(
                      item.createdAt!.toLocal(),
                    ),
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
    ),
  );
}
