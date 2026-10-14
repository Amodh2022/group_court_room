import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../auth/data/auth_providers.dart';

/// The player's own game state: level, XP, coins, streak, quests, badges.
///
/// Reading it is what tells the server the player showed up today, so this is
/// deliberately watched by the screens that open first rather than fetched on
/// a timer.
final gameStateProvider = FutureProvider.autoDispose<GameState>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.gameState();
});

/// What one case paid this player. Empty until the judge has ruled, and empty
/// for a case that paid them nothing — which is the honest answer, not zero
/// dressed up as a reward.
final caseRewardsProvider = FutureProvider.autoDispose
    .family<CaseRewards, String>((ref, caseId) async {
      final api = ref.watch(apiClientProvider);
      return api.caseRewards(caseId);
    });
