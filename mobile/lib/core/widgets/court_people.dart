import 'package:flutter/material.dart';

import '../courtroom.dart';
import '../theme.dart';

/// A stable tint per person, so a face keeps its colour from message to message.
Color tintFor(String key) {
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return CourtColors.tints[hash % CourtColors.tints.length];
}

enum Presence { on, away }

/// The reference's squircle participant tile, with an optional presence dot.
class AvatarTile extends StatelessWidget {
  const AvatarTile({
    super.key,
    required this.name,
    this.size = 40,
    this.judge = false,
    this.presence,
  });

  final String name;
  final double size;
  final bool judge;
  final Presence? presence;

  @override
  Widget build(BuildContext context) {
    final fill = judge ? context.colors.onSurface : tintFor(name);
    final onFill = judge ? context.colors.surface : CourtColors.lightInk;
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: fill,
              shape: const CircleBorder(),
            ),
            child: judge
                ? Icon(Icons.gavel, size: size * 0.5, color: onFill)
                : Text(
                    letter,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.38,
                      color: onFill,
                    ),
                  ),
          ),
          if (presence != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: presence == Presence.on
                      ? CourtColors.presence
                      : CourtColors.orange,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The reference's Plaintiff / Defense trays: a large tile for each side under a
/// folder tab.
class PartyTrays extends StatelessWidget {
  const PartyTrays({
    super.key,
    required this.plaintiff,
    required this.defendant,
    required this.defended,
  });

  final String plaintiff;
  final String defendant;
  final bool defended;

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('party-trays'),
    children: [
      Expanded(
        child: _Tray(
          tab: 'Plaintiff',
          name: plaintiff,
          caption: 'Brings the charge',
          presence: Presence.on,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _Tray(
          tab: 'Defense',
          name: defendant,
          caption: defended ? 'Has answered' : 'Awaiting a defense',
          presence: defended ? Presence.on : Presence.away,
        ),
      ),
    ],
  );
}

class _Tray extends StatelessWidget {
  const _Tray({
    required this.tab,
    required this.name,
    required this.caption,
    required this.presence,
  });

  final String tab;
  final String name;
  final String caption;
  final Presence presence;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt2,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.zero,
                bottomRight: Radius.circular(12),
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Text(
              tab,
              style: context.text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.palette.inkDim,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AvatarTile(name: name, size: 64, presence: presence),
        const SizedBox(height: 10),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          caption,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.inkFaint,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

/// The jury box as a horizontal strip: everyone in the room, numbered, with a
/// presence dot. `voted` says a ballot exists, never which way.
class JuryStrip extends StatelessWidget {
  const JuryStrip({super.key, required this.seats});

  final List<RosterSeat> seats;

  String _label(RosterSeat seat) => switch (seat.role) {
    'plaintiff' => 'Plaintiff',
    'defendant' => 'Defense',
    _ => seat.voted ? 'Voted' : 'Juror',
  };

  @override
  Widget build(BuildContext context) {
    if (seats.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('jury-box'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      color: context.palette.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('JURY BOX', style: context.text.labelSmall),
          const SizedBox(height: 10),
          SizedBox(
            height: 98,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final seat = seats[i];
                return SizedBox(
                  width: 62,
                  child: Column(
                    children: [
                      AvatarTile(
                        name: seat.name,
                        size: 42,
                        presence: seat.role != 'juror' || seat.voted
                            ? Presence.on
                            : Presence.away,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        seat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _label(seat),
                        style: context.text.bodySmall?.copyWith(
                          fontSize: 10.5,
                          color: context.palette.inkFaint,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
