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
import '../../../core/widgets/sue_widgets.dart';
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

    final subtitle = items.isEmpty
        ? 'No courts yet'
        : '${items.length} ${items.length == 1 ? 'court' : 'courts'} · '
              '$people ${people == 1 ? 'person' : 'people'}';

    return CourtScaffold(
      title: 'Courts',
      maxWidth: 640,
      tablet: _TabletCourts(
        courts: courts,
        subtitle: subtitle,
        onCreate: create,
        onJoin: join,
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Courts',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.palette.inkDim,
                    ),
                  ),
                ],
              ),
            ),
            _NewCourtButton(onTap: create),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(courtsProvider.future),
        child: courts.when(
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, courtNavBottomInset),
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, courtNavBottomInset),
            children: [
              if (items.isNotEmpty)
                _CourtGrid(courts: items)
              else
                const _NoCourtsCard(),
              const SizedBox(height: 22),
              const Text(
                'Join a court',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _JoinRow(onJoin: join),
            ],
          ),
        ),
      ),
    );
  }
}

/// Courts as the tablet artboards draw it: the tiles in a grid, and the join
/// card beside them once the window is landscape-wide.
class _TabletCourts extends ConsumerWidget {
  const _TabletCourts({
    required this.courts,
    required this.subtitle,
    required this.onCreate,
    required this.onJoin,
  });

  final AsyncValue<List<Court>> courts;
  final String subtitle;
  final VoidCallback onCreate;
  final Future<void> Function(String code) onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SueTabletPage(
    header: SueTabletHeader(
      title: 'Courts',
      subtitle: subtitle,
      trailing: _NewCourtButton(onTap: onCreate),
    ),
    child: courts.when(
      loading: () => ListView(
        padding: EdgeInsets.zero,
        children: const [
          CourtSkeleton(height: 150),
          SizedBox(height: 12),
          CourtSkeleton(height: 150),
        ],
      ),
      error: (e, _) => CourtErrorView(
        message: e is ApiException ? e.message : 'Could not load your courts.',
        onRetry: () => ref.invalidate(courtsProvider),
      ),
      data: (items) => RefreshIndicator(
        onRefresh: () async => ref.refresh(courtsProvider.future),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SueColumns(
              startFlex: 3,
              endFlex: 2,
              start: [
                if (items.isNotEmpty)
                  _CourtGrid(courts: items)
                else
                  const _NoCourtsCard(),
              ],
              end: [_JoinCard(onJoin: onJoin, onCreate: onCreate)],
            ),
          ],
        ),
      ),
    ),
  );
}

/// "JOIN WITH INVITE CODE" — the code box and the way to start a court of
/// your own, as one card.
class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.onJoin, required this.onCreate});

  final Future<void> Function(String code) onJoin;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => SueCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SueSectionLabel('JOIN WITH INVITE CODE'),
        const SizedBox(height: 12),
        _JoinRow(onJoin: onJoin),
        const SizedBox(height: 14),
        TextButton(
          onPressed: onCreate,
          child: const Text('+ Start a new court'),
        ),
      ],
    ),
  );
}

/// The round "+" in the header.
class _NewCourtButton extends StatelessWidget {
  const _NewCourtButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'New court',
    child: Tooltip(
      message: 'New court',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.surfaceContainerHighest,
            boxShadow: courtHardShadow(context),
          ),
          child: CourtIcon(
            CourtGlyph.plus,
            size: 20,
            color: context.palette.accent,
            strokeWidth: 2.6,
          ),
        ),
      ),
    ),
  );
}

/// A small all-caps rail heading, optionally with the live dot.
class _RailHeading extends StatefulWidget {
  // ignore: unused_element_parameter
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

/// Two columns of court tiles. Each court keeps one accent colour, picked from
/// its position, so the grid reads as four different places.
class _CourtGrid extends StatelessWidget {
  const _CourtGrid({required this.courts});

  final List<Court> courts;

  @override
  Widget build(BuildContext context) {
    const tones = [SueTone.orange, SueTone.blue, SueTone.teal, SueTone.gray];
    final rows = <Widget>[];
    for (var i = 0; i < courts.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _CourtTile(court: courts[i], tone: tones[i % 4]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < courts.length
                    ? _CourtTile(court: courts[i + 1], tone: tones[(i + 1) % 4])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < courts.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }
}

class _CourtTile extends ConsumerWidget {
  const _CourtTile({required this.court, required this.tone});

  final Court court;
  final SueTone tone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull?.userId;
    final owner = me != null && court.ownerId == me;
    final color = tone.fg(context);
    final n = court.members.length;
    final faces = court.members.take(4).toList();
    return SueCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      onTap: () => context.push('/courts/${court.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 3),
                ),
                child: Text(
                  courtMonogram(court.name),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              if (owner)
                const Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SuePill('OWNER', tone: SueTone.gold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$n ${n == 1 ? 'MEMBER' : 'MEMBERS'}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            court.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 24,
            width: faces.isEmpty ? 0 : 24.0 + (faces.length - 1) * 18,
            child: Stack(
              children: [
                for (var i = 0; i < faces.length; i++)
                  Positioned(
                    left: i * 18.0,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.alphaBlend(
                          toneFor(faces[i].displayName).tint(context),
                          context.colors.surfaceContainerHighest,
                        ),
                        border: Border.all(
                          color: context.colors.surfaceContainerHighest,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        faces[i].displayName.isEmpty
                            ? '?'
                            : faces[i].displayName[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: toneFor(faces[i].displayName).fg(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    return SueCard(
      small: true,
      radius: 16,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: widget.onJoin,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Enter invite code',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                hintStyle: TextStyle(color: context.palette.inkDim),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: SueButton(
              label: 'JOIN',
              height: 46,
              onPressed: () => widget.onJoin(_controller.text.trim()),
            ),
          ),
        ],
      ),
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
