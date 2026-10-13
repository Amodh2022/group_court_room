import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../data/court_providers.dart';
import 'user_search_sheet.dart';

/// Initials for a court's tile: up to two letters, as the canvas draws them.
String courtMonogram(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '??';
  if (words.length == 1) {
    final one = words.first;
    return (one.length == 1 ? one : one.substring(0, 2)).toUpperCase();
  }
  return (words.first[0] + words.elementAt(1)[0]).toUpperCase();
}

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
    final items = courts.valueOrNull ?? const <Court>[];
    final people = items
        .expand((c) => c.members.map((m) => m.userId))
        .toSet()
        .length;

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

    Future<void> join(String code) async {
      if (code.isEmpty) return;
      try {
        await ref.read(apiClientProvider).joinCourt(code);
        ref.invalidate(courtsProvider);
      } catch (e) {
        if (context.mounted) _fail(context, e);
      }
    }

    return CourtScaffold(
      title: 'Courts',
      header: ScreenHeader(
        title: 'Courts',
        eyebrow: items.isEmpty
            ? 'No courts yet'
            : '${items.length} ${items.length == 1 ? 'court' : 'courts'} · '
                  '$people ${people == 1 ? 'person' : 'people'}',
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        trailing: [_NewCourtButton(onTap: create)],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(courtsProvider.future),
        child: courts.when(
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, courtNavBottomInset),
            children: const [
              CourtSkeleton(height: 150),
              SizedBox(height: 12),
              CourtSkeleton(height: 150),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, courtNavBottomInset),
            children: [
              if (items.isNotEmpty) ...[
                const _RailHeading(label: 'IN SESSION', live: true),
                const SizedBox(height: 12),
                for (final court in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CourtCard(court: court),
                  ),
              ] else
                const _NoCourtsCard(),
              const SizedBox(height: 10),
              const _RailHeading(label: 'JOIN ONE'),
              const SizedBox(height: 10),
              _JoinRow(onJoin: join),
              const SizedBox(height: 12),
              DashedAddTile(label: 'Start a new court', onTap: create),
            ],
          ),
        ),
      ),
    );
  }
}

/// The violet key in the header.
class _NewCourtButton extends StatelessWidget {
  const _NewCourtButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    decoration: BoxDecoration(
      color: CourtColors.violet,
      borderRadius: BorderRadius.circular(courtRadiusPill),
      border: Border.all(
        color: context.palette.border,
        width: courtBorderWidth,
      ),
      boxShadow: const [
        BoxShadow(color: CourtColors.violetInk, offset: Offset(0, 4)),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CourtIcon(
                CourtGlyph.plus,
                size: 18,
                color: Colors.white,
                strokeWidth: 3.2,
              ),
              SizedBox(width: 6),
              Text(
                'New court',
                style: TextStyle(
                  fontFamily: courtDisplayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A small all-caps rail heading, optionally with the live dot.
class _RailHeading extends StatefulWidget {
  const _RailHeading({required this.label, this.live = false});

  final String label;
  final bool live;

  @override
  State<_RailHeading> createState() => _RailHeadingState();
}

class _RailHeadingState extends State<_RailHeading>
    with SingleTickerProviderStateMixin {
  AnimationController? _blink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A controller that repeats forever keeps a frame permanently scheduled,
    // so `pumpAndSettle` would never return. Honour the reduced-motion flag,
    // which widget tests also set.
    final wants = widget.live && !MediaQuery.disableAnimationsOf(context);
    if (wants && _blink == null) {
      _blink = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat(reverse: true);
    } else if (!wants && _blink != null) {
      _blink!.dispose();
      _blink = null;
    }
  }

  @override
  void dispose() {
    _blink?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: CourtColors.red,
      ),
    );
    if (_blink != null) {
      dot = FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.35).animate(_blink!),
        child: dot,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (widget.live) ...[dot, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: context.palette.inkDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourtCard extends ConsumerWidget {
  const _CourtCard({required this.court});

  final Court court;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final me = ref.watch(authControllerProvider).valueOrNull?.userId;
    final owner = me != null && court.ownerId == me;
    final faces = court.members.take(4).toList();

    return Container(
      decoration: courtChunk(context, radius: courtRadiusLg, dy: 5),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => context.push('/courts/${court.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.rotate(
                      angle: -0.07,
                      child: Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tintFor(court.name),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: palette.border,
                            width: courtBorderWidth,
                          ),
                        ),
                        child: Text(
                          courtMonogram(court.name),
                          style: const TextStyle(
                            fontFamily: courtDisplayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            height: 1,
                            color: CourtColors.lightInk,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            court.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: courtDisplayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 21,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              // Overlapping faces are a Stack, not negative
                              // margins: Container asserts a non-negative
                              // margin and throws on layout.
                              if (faces.isNotEmpty)
                                // Flexible + scaleDown: five faces are wider
                                // than the name column on a 320px phone, and a
                                // fixed stack would overflow it.
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      width: 26 + 20.0 * (faces.length - 1),
                                      height: 26,
                                      child: Stack(
                                        children: [
                                          for (var i = 0; i < faces.length; i++)
                                            Positioned(
                                              left: i * 20.0,
                                              child: Container(
                                                width: 26,
                                                height: 26,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: tintFor(
                                                    faces[i].displayName,
                                                  ),
                                                  border: Border.all(
                                                    color: palette.border,
                                                    width: courtBorderThin,
                                                  ),
                                                ),
                                                child: Text(
                                                  faces[i].displayName
                                                          .trim()
                                                          .isEmpty
                                                      ? '?'
                                                      : faces[i].displayName
                                                            .trim()[0]
                                                            .toUpperCase(),
                                                  style: const TextStyle(
                                                    fontFamily:
                                                        courtDisplayFont,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 11,
                                                    height: 1,
                                                    color: CourtColors.lightInk,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  '${court.members.length} '
                                  '${court.members.length == 1 ? 'member' : 'members'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: palette.inkDim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    CourtPill(
                      label: owner ? 'YOURS' : 'MEMBER',
                      fill: owner ? CourtColors.red : palette.surfaceAlt,
                      foreground: owner ? Colors.white : palette.inkDim,
                      bordered: true,
                      fontSize: 11,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _MiniBox(
                          label: 'INVITE CODE',
                          value: court.inviteCode,
                          fill: palette.surfaceAlt,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MiniBox(
                        label: 'FILE HERE',
                        value: 'Sue',
                        fill: CourtColors.violet,
                        foreground: Colors.white,
                        onTap: () =>
                            context.push('/cases/new?court=${court.id}'),
                      ),
                    ],
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

class _MiniBox extends StatelessWidget {
  const _MiniBox({
    required this.label,
    required this.value,
    required this.fill,
    this.foreground,
    this.onTap,
  });

  final String label;
  final String value;
  final Color fill;
  final Color? foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? context.colors.onSurface;
    final body = Container(
      constraints: const BoxConstraints(minWidth: 74),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(courtRadiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: fg.withValues(alpha: 0.75),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: courtDisplayFont,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              height: 1.2,
              color: fg,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(courtRadiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}

/// The dashed invite-code field and its dark Join key.
class _JoinRow extends StatefulWidget {
  const _JoinRow({required this.onJoin});

  final Future<void> Function(String code) onJoin;

  @override
  State<_JoinRow> createState() => _JoinRowState();
}

class _JoinRowState extends State<_JoinRow> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: widget.onJoin,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Got an invite code?',
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(courtRadiusSm + 2),
                  borderSide: BorderSide(
                    color: palette.inkFaint,
                    width: courtBorderWidth,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(courtRadiusSm + 2),
                  borderSide: BorderSide(
                    color: palette.accent,
                    width: courtBorderWidth,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 50,
          child: CourtKey(
            label: 'Join',
            height: 50,
            radius: courtRadiusSm + 2,
            fill: context.colors.onSurface,
            foreground: context.colors.surface,
            shadowInk: palette.border,
            onPressed: () => widget.onJoin(_controller.text.trim()),
          ),
        ),
      ],
    );
  }
}

class _NoCourtsCard extends StatelessWidget {
  const _NoCourtsCard();

  @override
  Widget build(BuildContext context) => CourtCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('No courts yet', style: context.text.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Add friends once. File a case in a court and everyone in it is '
          'seated on the jury.',
          style: context.text.bodyMedium?.copyWith(
            color: context.palette.inkDim,
          ),
        ),
      ],
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
    final court = courts.valueOrNull?.where((c) => c.id == courtId).firstOrNull;

    return CourtScaffold(
      title: 'Court',
      header: ScreenHeader(
        title: court?.name ?? 'Court',
        eyebrow: court == null
            ? null
            : '${court.members.length} '
                  '${court.members.length == 1 ? 'member' : 'members'}',
        titleSize: 28,
        padding: const EdgeInsets.fromLTRB(16, 18, 20, 12),
        leading: RoundIconButton(
          glyph: CourtGlyph.back,
          label: 'Back',
          onTap: () => context.canPop() ? context.pop() : context.go('/courts'),
        ),
      ),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              StagePanel(
                spot: CourtColors.yellow,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'INVITE CODE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: CourtColors.yellow,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            court.inviteCode,
                            style: const TextStyle(
                              fontFamily: courtDisplayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 28,
                              height: 1.1,
                              color: CourtColors.stageInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    RoundIconButton(
                      glyph: CourtGlyph.share,
                      label: 'Copy code',
                      fill: CourtColors.yellow,
                      foreground: CourtColors.lightInk,
                      onTap: () {
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
              const SizedBox(height: 18),
              const _RailHeading(label: 'MEMBERS'),
              const SizedBox(height: 10),
              Container(
                decoration: courtChunk(context, radius: courtRadiusLg),
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    for (final m in court.members)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            AvatarTile(name: m.displayName, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    m.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '@${m.handle}'
                                    '${m.userId == court.ownerId ? ' · owner' : ''}'
                                    '${m.userId == me ? ' · you' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: context.palette.inkDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
              CourtKey(
                label: 'File a case here',
                glyph: CourtGlyph.gavel,
                onPressed: () => context.push('/cases/new?court=${court.id}'),
              ),
            ],
          );
        },
      ),
    );
  }
}
