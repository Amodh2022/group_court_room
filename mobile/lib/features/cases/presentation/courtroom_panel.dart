import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/courtroom.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';

/// The trial, as a group chat. Presentation only: what it shows comes from the
/// controller, and what it does goes back through it.
class CourtroomPanel extends ConsumerStatefulWidget {
  const CourtroomPanel({super.key, required this.caseId, this.height = 440});

  final String caseId;
  final double height;

  @override
  ConsumerState<CourtroomPanel> createState() => _CourtroomPanelState();
}

class _CourtroomPanelState extends ConsumerState<CourtroomPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _muted = <String>{};
  bool _stuck = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _stuck = p.maxScrollExtent - p.pixels < 80;
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _followConversation() {
    if (!_stuck) return; // never yank someone who scrolled up to read
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send(CourtroomController room) {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (room.say(text)) {
      _input.clear();
      _stuck = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(courtroomProvider(widget.caseId));
    final room = ref.read(courtroomProvider(widget.caseId).notifier);

    ref.listen(courtroomProvider(widget.caseId), (prev, next) {
      if ((prev?.messages.length ?? 0) != next.messages.length) {
        _followConversation();
      }
    });

    final visible = state.messages
        .where(
          (m) =>
              !_muted.contains(m.ref) ||
              m.kind == ChatKind.judge ||
              m.kind == ChatKind.system,
        )
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.palette.line),
        boxShadow: courtShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
            child: Row(
              children: [
                const _WindowDots(),
                const SizedBox(width: 12),
                const Expanded(child: SectionLabel('The courtroom')),
                CourtChip(switch (state.conn) {
                  ConnState.live => '${state.online} here now',
                  ConnState.refused => 'Closed',
                  ConnState.reconnecting => 'Reconnecting…',
                  ConnState.connecting => 'Connecting…',
                }, color: state.isLive ? context.palette.accent : null),
              ],
            ),
          ),
          Divider(height: 1, color: context.palette.line),
          SizedBox(
            height: widget.height,
            child: state.conn == ConnState.refused
                ? const CourtNotice(
                    icon: Icons.lock_outline,
                    title: 'The courtroom is closed',
                    message: 'This case may have expired or been deleted.',
                  )
                : ListView.separated(
                    key: const Key('chat-log'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                    itemCount: visible.isEmpty ? 1 : visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (visible.isEmpty) {
                        return Center(
                          child: Text(
                            state.isLive
                                ? 'The room is quiet.'
                                : 'Entering the courtroom…',
                            style: context.text.bodySmall?.copyWith(
                              color: context.palette.inkDim,
                            ),
                          ),
                        );
                      }
                      final m = visible[i];
                      final mine = state.seatRef == m.ref;
                      return _Bubble(
                        message: m,
                        mine: mine,
                        canClear:
                            state.seatRole == 'plaintiff' &&
                            (m.kind == ChatKind.juror ||
                                m.kind == ChatKind.defendant) &&
                            m.statement == null &&
                            !m.isObjection,
                        onClear: () => room.hide(m.id),
                        onMute: () => setState(() => _muted.add(m.ref)),
                      );
                    },
                  ),
          ),
          JuryStrip(seats: state.roster),
          Divider(height: 1, color: context.palette.line),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // A solid red pill, like the reference's Deny / Excuse buttons.
                FilledButton(
                  onPressed:
                      state.isLive && state.caseStatus != CaseStatus.completed
                      ? room.objectNow
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: CourtColors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.palette.surfaceAlt2,
                    shadowColor: CourtColors.red.withValues(alpha: 0.5),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text(
                    'Objection!',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('chat-input'),
                    controller: _input,
                    enabled: state.isLive,
                    maxLength: 280,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(room),
                    decoration: InputDecoration(
                      hintText: state.isLive
                          ? 'Say something to the court…'
                          : 'Connecting…',
                      counterText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide(color: context.palette.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide(color: context.palette.line),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('chat-send'),
                  onPressed: state.isLive ? () => _send(room) : null,
                  style: IconButton.styleFrom(
                    backgroundColor: context.palette.accent,
                    foregroundColor: context.colors.onPrimary,
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  tooltip: 'Send',
                ),
              ],
            ),
          ),
          SizedBox(
            height: 24,
            child: state.notice == null
                ? null
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        state.notice!,
                        key: const Key('chat-notice'),
                        style: context.text.bodySmall?.copyWith(
                          color: CourtColors.guilty,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.canClear,
    required this.onClear,
    required this.onMute,
  });

  final ChatMessage message;
  final bool mine;
  final bool canClear;
  final VoidCallback onClear;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final m = message;

    if (m.kind == ChatKind.system) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: context.palette.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            m.body,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.inkDim,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    if (m.kind == ChatKind.judge) {
      final ruling = m.ruling;
      return Container(
        key: const Key('chat-judge'),
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(color: context.palette.line),
          borderRadius: BorderRadius.circular(20),
          boxShadow: courtShadow(context),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AvatarTile(name: 'Judge Byte', judge: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Judge Byte',
                        style: context.text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (ruling != null) ...[
                        const SizedBox(width: 8),
                        CourtChip(
                          ruling.toUpperCase(),
                          color: ruling == 'sustained'
                              ? context.palette.successText
                              : CourtColors.red,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(m.body, style: context.text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (m.isObjection) {
      return Center(
        key: const Key('chat-objection'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -0.05,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: CourtColors.guilty, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'OBJECTION!',
                  style: TextStyle(
                    fontFamily: courtDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    letterSpacing: 1,
                    color: CourtColors.guilty,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              mine ? 'You' : m.author,
              style: context.text.bodySmall?.copyWith(
                color: context.palette.inkDim,
              ),
            ),
          ],
        ),
      );
    }

    final statement = m.statement;
    if (statement != null) {
      return Container(
        key: Key('chat-statement-$statement'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: statement == 'opening'
                  ? context.palette.accent
                  : CourtColors.notGuilty,
              width: 4,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(
              statement == 'opening'
                  ? 'Opening statement · ${m.author}'
                  : 'The defense · ${m.author}',
            ),
            const SizedBox(height: 8),
            Text('“${m.body}”', style: context.text.bodyLarge),
          ],
        ),
      );
    }

    final bubbleColor = mine
        ? context.palette.accent
        : context.palette.surfaceAlt;
    final textColor = mine
        ? context.colors.onPrimary
        : context.colors.onSurface;
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[AvatarTile(name: m.author), const SizedBox(width: 8)],
        Flexible(
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 3),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: m.author,
                          style: context.text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.palette.inkDim,
                          ),
                        ),
                        if (m.kind != ChatKind.juror)
                          TextSpan(
                            text: '  ${m.kind.name.toUpperCase()}',
                            style: context.text.bodySmall?.copyWith(
                              fontSize: 10,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w600,
                              color: context.palette.accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 18),
                  ),
                ),
                child: Text(
                  m.body,
                  style: context.text.bodyMedium?.copyWith(color: textColor),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.at != null)
                      Text(
                        DateFormat.jm().format(m.at!),
                        style: context.text.bodySmall?.copyWith(
                          fontSize: 11,
                          color: context.palette.inkDim,
                        ),
                      ),
                    if (!mine) _TinyLink('mute', onMute),
                    if (canClear) _TinyLink('clear', onClear),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (mine) const SizedBox(width: 2),
      ],
    );
  }
}

class _TinyLink extends StatelessWidget {
  const _TinyLink(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
      child: Text(
        label,
        style: context.text.bodySmall?.copyWith(
          fontSize: 11,
          color: context.palette.inkDim,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  );
}

/// macOS-style traffic lights marking a window, as in the reference.
class _WindowDots extends StatelessWidget {
  const _WindowDots();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Dot(Color(0xFFE94A6A)),
      SizedBox(width: 6),
      _Dot(Color(0xFFEC9C3D)),
      SizedBox(width: 6),
      _Dot(Color(0xFF63C554)),
    ],
  );
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 11,
    height: 11,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
