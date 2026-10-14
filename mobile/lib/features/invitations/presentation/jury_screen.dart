import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/widgets/sue_widgets.dart';
import '../../cases/data/case_providers.dart';

/// The jury box, in the app.
///
/// Like the summons, a jury link is a capability: holding the token is the
/// whole authorisation. The feed votes inline for cases you were seated on,
/// but a link that arrives any other way — a notification, a story, a message
/// from a friend — lands here instead of in a browser.
///
/// The tally stays sealed until you have voted. That is the rule the whole
/// thing turns on: you commit before you know which way the room went.
class JuryScreen extends ConsumerStatefulWidget {
  const JuryScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JuryScreen> createState() => _JuryScreenState();
}

class _JuryScreenState extends ConsumerState<JuryScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _vote(String vote) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(juryVoteProvider)(widget.token, vote);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(juryRoomProvider(widget.token));

    return CourtScaffold(
      title: 'Jury duty',
      maxWidth: 640,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Row(
          children: [
            RoundIconButton(
              glyph: CourtGlyph.close,
              label: 'Close',
              onTap: () => context.canPop() ? context.pop() : context.go('/'),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOU ARE ON THE JURY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: context.palette.inkDim,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Jury duty',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: room.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => error is ApiException && !error.isNetwork
            ? CourtNotice(
                icon: Icons.link_off,
                title: 'This summons is no longer valid',
                message:
                    'The link may have expired, been revoked, or never '
                    'existed. Ask your friend to send a fresh one.',
                action: CourtKey(
                  label: 'Back to the docket',
                  glyph: CourtGlyph.home,
                  onPressed: () => context.go('/'),
                ),
              )
            : CourtErrorView(
                message: 'Could not reach the courthouse.',
                onRetry: () => ref.invalidate(juryRoomProvider(widget.token)),
              ),
        data: (data) =>
            _Room(room: data, busy: _busy, error: _error, onVote: _vote),
      ),
    );
  }
}

class _Room extends StatelessWidget {
  const _Room({
    required this.room,
    required this.busy,
    required this.error,
    required this.onVote,
  });

  final JuryRoom room;
  final bool busy;
  final String? error;
  final ValueChanged<String> onVote;

  @override
  Widget build(BuildContext context) {
    final voted = room.yourVote != null;
    final closed = !room.juryOpen || room.verdictReady;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
      children: [
        SueCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SuePair(a: room.plaintiffName, b: room.defendantName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      room.defendantName.isEmpty
                          ? room.plaintiffName
                          : '${room.plaintiffName} v. ${room.defendantName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (room.juryOpen && !room.verdictReady)
                    const SuePill('JURY LIVE', dot: true),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'THE CHARGE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: context.palette.inkDim,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                room.caseTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                room.accusation,
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SueCard(
          small: true,
          radius: 16,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DEFENCE · ${room.defendantName.toUpperCase()}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: SueTone.orange.fg(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                room.defense ?? 'Nothing on the record yet. The court waits.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: room.defense == null ? context.palette.inkDim : null,
                ),
              ),
            ],
          ),
        ),
        if (!voted && !closed) ...[const SizedBox(height: 14), const _Stake()],
        if (room.tally != null) ...[
          const SizedBox(height: 14),
          VoteBar(guilty: room.tally!.guilty, notGuilty: room.tally!.notGuilty),
        ],
        if (error != null) ...[const SizedBox(height: 12), InlineError(error!)],
        const SizedBox(height: 16),
        if (voted)
          _Voted(vote: room.yourVote!)
        else if (closed)
          Text(
            room.verdictReady
                ? 'The court has ruled. The jury is dismissed.'
                : 'The jury in this case has been dismissed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.palette.inkDim,
            ),
          )
        else ...[
          Text(
            'Your verdict on ${room.defendantName.isEmpty ? 'the accused' : room.defendantName}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SueButton(
                  label: 'GUILTY',
                  tone: SueTone.orange,
                  height: 60,
                  busy: busy,
                  onPressed: () => onVote('guilty'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SueButton(
                  label: 'NOT GUILTY',
                  tone: SueTone.teal,
                  height: 60,
                  busy: busy,
                  onPressed: () => onVote('not_guilty'),
                ),
              ),
            ],
          ),
        ],
        const CourtDisclaimer(
          text:
              'Votes stay sealed until the judge rules. You get one, and you '
              'cannot change it.',
        ),
      ],
    );
  }
}

/// What a juror is playing for. The numbers are the server's own rules.
class _Stake extends StatelessWidget {
  const _Stake();

  static const correctXp = 25;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: SueTone.gold.tint(context),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const SueCoin(size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Call it like the judge',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Match the final ruling for +$correctXp XP. '
                'First to vote gets 2×.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: context.palette.inkDim,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Voted extends StatelessWidget {
  const _Voted({required this.vote});

  final String vote;

  @override
  Widget build(BuildContext context) {
    final guilty = vote == 'guilty';
    final tone = guilty ? SueTone.orange : SueTone.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tone.tint(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.how_to_vote, size: 20, color: tone.fg(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You voted ${guilty ? 'guilty' : 'not guilty'}. '
              'The court will let you know.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tone.fg(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
