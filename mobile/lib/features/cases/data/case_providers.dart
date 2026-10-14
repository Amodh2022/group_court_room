import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../game/data/game_providers.dart';
import '../../auth/data/auth_providers.dart';
import '../../courts/data/court_providers.dart';

/// Dashboard list. Rebuilds when the signed-in user changes.
final casesProvider = FutureProvider.autoDispose<List<CaseSummary>>((
  ref,
) async {
  ref.watch(authControllerProvider);
  return ref.watch(apiClientProvider).listCases();
});

final caseDetailProvider = FutureProvider.autoDispose
    .family<CaseDetail, String>((ref, id) async {
      return ref.watch(apiClientProvider).getCase(id);
    });

/// This court's criminal records. Refreshed whenever a verdict lands.
final rapSheetProvider = FutureProvider.autoDispose<List<RapSheetEntry>>((
  ref,
) async {
  ref.watch(authControllerProvider);
  return ref.watch(apiClientProvider).rapSheet();
});

/// Polls the verdict while a case is generating.
///
/// Generation is asynchronous server-side, so the app watches rather than
/// blocks. Polling stops the moment the case reaches a settled state.
class VerdictController extends StateNotifier<AsyncValue<VerdictState>> {
  VerdictController(this._api, this._caseId, {this.onSettled})
    : super(const AsyncValue.loading()) {
    refresh();
  }

  final ApiClient _api;
  final String _caseId;

  /// Called once the case reaches a settled state. A new verdict changes
  /// somebody's criminal record, so the records view must not stay stale.
  final void Function()? onSettled;
  Timer? _timer;
  int _polls = 0;

  static const _interval = Duration(seconds: 2);
  static const _maxPolls = 45; // ~90s before we stop and offer a retry

  Future<void> refresh() async {
    try {
      final result = await _api.getVerdict(_caseId);
      if (!mounted) return;
      state = AsyncValue.data(result);
      _schedule(result.status);
    } on ApiException catch (error, stack) {
      if (!mounted) return;
      state = AsyncValue.error(error, stack);
    }
  }

  /// Asks the court to rule. Safe to call twice: the API is idempotent.
  Future<void> requestVerdict() async {
    state = const AsyncValue.loading();
    try {
      final result = await _api.requestVerdict(_caseId);
      if (!mounted) return;
      state = AsyncValue.data(result);
      _schedule(result.status);
    } on ApiException catch (error, stack) {
      if (!mounted) return;
      state = AsyncValue.error(error, stack);
    }
  }

  void _schedule(CaseStatus status) {
    _timer?.cancel();
    if (status != CaseStatus.generating) {
      if (_polls > 0) onSettled?.call();
      _polls = 0;
      return;
    }
    if (_polls >= _maxPolls) return;
    _polls++;
    _timer = Timer(_interval, refresh);
  }

  /// True when generation has run long enough that we stopped waiting.
  bool get timedOut => _polls >= _maxPolls;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final verdictControllerProvider = StateNotifierProvider.autoDispose
    .family<VerdictController, AsyncValue<VerdictState>, String>(
      (ref, caseId) => VerdictController(
        ref.watch(apiClientProvider),
        caseId,
        onSettled: () {
          ref.invalidate(rapSheetProvider);
          ref.invalidate(casesProvider);
        },
      ),
    );

/// Create / delete / share actions that the dashboard must refresh after.
class CaseActions {
  CaseActions(this._ref);

  final Ref _ref;

  ApiClient get _api => _ref.read(apiClientProvider);

  Future<CaseDetail> create({
    required String title,
    required String category,
    required String accusation,
    String? defendantNickname,
    String? courtId,
    String? accusedUserId,
    int pettyLevel = 1,
  }) async {
    final created = await _api.createCase(
      courtId: courtId,
      accusedUserId: accusedUserId,
      title: title,
      category: category,
      accusation: accusation,
      defendantNickname: defendantNickname,
      pettyLevel: pettyLevel,
    );
    _ref.invalidate(casesProvider);
    // Filing costs coins and moves a quest, so the player card is stale the
    // moment this returns.
    _ref.invalidate(gameStateProvider);
    return created;
  }

  /// Seat a friend on a live case. The server notifies them — that is the
  /// whole point of seating somebody by account rather than by nickname.
  Future<void> addMember(String caseId, String userId, String role) async {
    await _api.addCaseMember(caseId, userId, role);
    _ref.invalidate(caseDetailProvider(caseId));
    _ref.invalidate(casesProvider);
  }

  Future<void> delete(String id) async {
    await _api.deleteCase(id);
    _ref.invalidate(casesProvider);
  }

  Future<ShareLink> enableShare(String id) async {
    final link = await _api.enableShare(id);
    _ref.invalidate(casesProvider);
    _ref.invalidate(caseDetailProvider(id));
    return link;
  }

  Future<void> revokeShare(String id) async {
    await _api.revokeShare(id);
    _ref.invalidate(casesProvider);
    _ref.invalidate(caseDetailProvider(id));
  }
}

final caseActionsProvider = Provider<CaseActions>(CaseActions.new);

/// The summons behind a `SharedCase` whose `linkKind` is `jury`.
///
/// Keyed by the jury token, which is the only capability the endpoint wants.
/// The voter key is the signed-in user id, so the same account answering from
/// phone and browser is still one juror.
final juryRoomProvider = FutureProvider.autoDispose.family<JuryRoom, String>((
  ref,
  token,
) async {
  final me = ref.watch(authControllerProvider).valueOrNull;
  return ref
      .watch(apiClientProvider)
      .juryRoom(token, voterKey: me?.userId ?? '');
});

/// Casts this account's ballot on a case it was summoned to.
final juryVoteProvider = Provider<Future<void> Function(String, String)>((ref) {
  return (String token, String vote) async {
    final me = ref.read(authControllerProvider).valueOrNull;
    if (me == null) return;
    await ref
        .read(apiClientProvider)
        .castVote(
          token,
          vote: vote,
          voterKey: me.userId,
          jurorName: me.displayName,
        );
    ref.invalidate(juryRoomProvider(token));
    ref.invalidate(sharedCasesProvider);
  };
});
