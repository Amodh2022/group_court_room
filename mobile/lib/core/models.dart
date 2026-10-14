import 'package:flutter/material.dart';

import 'theme.dart';

enum CaseStatus {
  draft,
  awaitingDefense,
  ready,
  generating,
  completed,
  failed,
  expired;

  static CaseStatus parse(String value) => switch (value) {
    'draft' => CaseStatus.draft,
    'awaiting_defense' => CaseStatus.awaitingDefense,
    'ready' => CaseStatus.ready,
    'generating' => CaseStatus.generating,
    'completed' => CaseStatus.completed,
    'failed' => CaseStatus.failed,
    'expired' => CaseStatus.expired,
    _ => CaseStatus.draft,
  };

  /// Short status for a dashboard card.
  String get label => switch (this) {
    CaseStatus.draft => 'Draft',
    CaseStatus.awaitingDefense => 'Awaiting defense',
    CaseStatus.ready => 'Ready for verdict',
    CaseStatus.generating => 'In deliberation',
    CaseStatus.completed => 'Verdict in',
    CaseStatus.failed => 'Needs a retry',
    CaseStatus.expired => 'Expired',
  };

  IconData get icon => switch (this) {
    CaseStatus.draft => Icons.edit_note,
    CaseStatus.awaitingDefense => Icons.hourglass_top,
    CaseStatus.ready => Icons.gavel,
    CaseStatus.generating => Icons.auto_awesome,
    CaseStatus.completed => Icons.verified,
    CaseStatus.failed => Icons.error_outline,
    CaseStatus.expired => Icons.lock_clock,
  };

  Color color(BuildContext context) => switch (this) {
    CaseStatus.completed => CourtColors.notGuilty,
    CaseStatus.failed => CourtColors.guilty,
    CaseStatus.expired => context.palette.inkDim,
    CaseStatus.generating => CourtColors.bothGuilty,
    _ => context.palette.accent,
  };

  bool get isPending =>
      this == CaseStatus.generating || this == CaseStatus.ready;
}

enum VerdictKind {
  guilty,
  notGuilty,
  bothGuilty,
  insufficientEvidence;

  static VerdictKind parse(String value) => switch (value) {
    'guilty' => VerdictKind.guilty,
    'not_guilty' => VerdictKind.notGuilty,
    'both_guilty' => VerdictKind.bothGuilty,
    _ => VerdictKind.insufficientEvidence,
  };

  String get label => switch (this) {
    VerdictKind.guilty => 'GUILTY',
    VerdictKind.notGuilty => 'NOT GUILTY',
    VerdictKind.bothGuilty => 'BOTH GUILTY',
    VerdictKind.insufficientEvidence => 'INSUFFICIENT EVIDENCE',
  };

  /// Whether this ruling sides with a jury that voted guilty.
  bool get convicts =>
      this == VerdictKind.guilty || this == VerdictKind.bothGuilty;

  /// True when the judge landed opposite a jury that reached a majority.
  bool overrules(JuryTally? tally) {
    if (tally == null || tally.majority == null) return false;
    if (this == VerdictKind.insufficientEvidence) return false;
    return convicts != (tally.majority == 'guilty');
  }

  Color get color => switch (this) {
    VerdictKind.guilty => CourtColors.guilty,
    VerdictKind.notGuilty => CourtColors.notGuilty,
    VerdictKind.bothGuilty => CourtColors.bothGuilty,
    VerdictKind.insufficientEvidence => CourtColors.insufficient,
  };
}

/// How the group voted. Counts only — the API never publishes who voted what.
class JuryTally {
  const JuryTally({
    required this.guilty,
    required this.notGuilty,
    required this.total,
    required this.majority,
    required this.summary,
  });

  final int guilty;
  final int notGuilty;
  final int total;

  /// 'guilty', 'not_guilty', or null when the jury deadlocked.
  final String? majority;
  final String summary;

  bool get isEmpty => total == 0;

  factory JuryTally.fromJson(Map<String, dynamic> json) => JuryTally(
    guilty: json['guilty'] as int? ?? 0,
    notGuilty: json['not_guilty'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
    majority: json['majority'] as String?,
    summary: json['summary'] as String? ?? '',
  );
}

/// One person's standing in this court, across every case they have been in.
class RapSheetEntry {
  const RapSheetEntry({
    required this.id,
    required this.displayName,
    required this.rank,
    required this.title,
    required this.casesTotal,
    required this.convictions,
    required this.acquittals,
    required this.mistrials,
    required this.currentStreak,
    required this.longestStreak,
    required this.convictionRate,
    this.isYou = false,
  });

  final String id;
  final String displayName;
  final int rank;
  final String title;
  final int casesTotal;
  final int convictions;
  final int acquittals;
  final int mistrials;
  final int currentStreak;
  final int longestStreak;
  final double convictionRate;

  /// The caller's own record in their own court. The server decides this;
  /// a rap sheet row carries a record id, not a user id, so the client
  /// cannot work it out for itself.
  final bool isYou;

  factory RapSheetEntry.fromJson(Map<String, dynamic> json) => RapSheetEntry(
    id: json['id'] as String,
    displayName: json['display_name'] as String? ?? 'Unknown',
    rank: json['rank'] as int? ?? 0,
    title: json['title'] as String? ?? '',
    casesTotal: json['cases_total'] as int? ?? 0,
    convictions: json['convictions'] as int? ?? 0,
    acquittals: json['acquittals'] as int? ?? 0,
    mistrials: json['mistrials'] as int? ?? 0,
    currentStreak: json['current_streak'] as int? ?? 0,
    longestStreak: json['longest_streak'] as int? ?? 0,
    convictionRate: (json['conviction_rate'] as num? ?? 0).toDouble(),
    isYou: json['is_you'] as bool? ?? false,
  );
}

class CaseCategory {
  const CaseCategory(this.id, this.label, this.emoji);

  final String id;
  final String label;
  final String emoji;

  static const all = <CaseCategory>[
    CaseCategory('food', 'Food crimes', '🍕'),
    CaseCategory('roommates', 'Roommates', '🏠'),
    CaseCategory('group_chat', 'Group chat', '💬'),
    CaseCategory('travel', 'Travel', '✈️'),
    CaseCategory('money', 'Money', '💸'),
    CaseCategory('pets', 'Pets', '🐾'),
    CaseCategory('gaming', 'Gaming', '🎮'),
    CaseCategory('other', 'Other', '⚖️'),
  ];

  static CaseCategory byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.last);
}

class CaseSummary {
  const CaseSummary({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.defendantNickname,
    required this.defenseSubmitted,
    required this.verdictReady,
    required this.shareEnabled,
    this.juryCount = 0,
  });

  final String id;
  final String title;
  final String category;
  final CaseStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? defendantNickname;
  final bool defenseSubmitted;
  final bool verdictReady;
  final bool shareEnabled;
  final int juryCount;

  factory CaseSummary.fromJson(Map<String, dynamic> json) => CaseSummary(
    id: json['id'] as String,
    title: json['title'] as String,
    category: json['category'] as String,
    status: CaseStatus.parse(json['status'] as String),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String).toLocal(),
    defendantNickname: json['defendant_nickname'] as String?,
    defenseSubmitted: json['defense_submitted'] as bool? ?? false,
    verdictReady: json['verdict_ready'] as bool? ?? false,
    shareEnabled: json['share_enabled'] as bool? ?? false,
    juryCount: json['jury_count'] as int? ?? 0,
  );
}

class CaseDetail extends CaseSummary {
  const CaseDetail({
    required super.id,
    required super.title,
    required super.category,
    required super.status,
    required super.createdAt,
    required super.expiresAt,
    required super.defendantNickname,
    required super.defenseSubmitted,
    required super.verdictReady,
    required super.shareEnabled,
    required this.accusation,
    required this.failureReason,
    super.juryCount,
    this.inviteToken,
    this.inviteUrl,
    this.juryToken,
    this.juryUrl,
    this.juryTally,
  });

  final String accusation;
  final String? failureReason;

  /// Returned exactly once, by POST /cases. Never re-fetchable.
  final String? inviteToken;
  final String? inviteUrl;

  /// The jury summons, also returned exactly once by POST /cases.
  final String? juryToken;
  final String? juryUrl;

  /// Visible to the creator at any time: they are not a juror, so seeing the
  /// running count cannot spoil their own vote.
  final JuryTally? juryTally;

  factory CaseDetail.fromJson(Map<String, dynamic> json) {
    final summary = CaseSummary.fromJson(json);
    return CaseDetail(
      id: summary.id,
      title: summary.title,
      category: summary.category,
      status: summary.status,
      createdAt: summary.createdAt,
      expiresAt: summary.expiresAt,
      defendantNickname: summary.defendantNickname,
      defenseSubmitted: summary.defenseSubmitted,
      verdictReady: summary.verdictReady,
      shareEnabled: summary.shareEnabled,
      accusation: json['accusation'] as String? ?? '',
      failureReason: json['failure_reason'] as String?,
      juryCount: summary.juryCount,
      inviteToken: json['invite_token'] as String?,
      inviteUrl: json['invite_url'] as String?,
      juryToken: json['jury_token'] as String?,
      juryUrl: json['jury_url'] as String?,
      juryTally: json['jury_tally'] == null
          ? null
          : JuryTally.fromJson(json['jury_tally'] as Map<String, dynamic>),
    );
  }
}

class Verdict {
  const Verdict({
    required this.caseTitle,
    required this.charge,
    required this.prosecutionSummary,
    required this.defenseSummary,
    required this.verdict,
    required this.reasoning,
    required this.sentence,
    required this.judgeRoast,
    required this.closingLine,
    required this.shareCaption,
    this.juryNote = '',
  });

  final String caseTitle;
  final String charge;
  final String prosecutionSummary;
  final String defenseSummary;
  final VerdictKind verdict;
  final String reasoning;
  final String sentence;
  final String judgeRoast;
  final String closingLine;
  final String shareCaption;

  /// The judge's comment on the jury, present mainly when overruling them.
  final String juryNote;

  factory Verdict.fromJson(Map<String, dynamic> json) => Verdict(
    caseTitle: json['case_title'] as String? ?? '',
    charge: json['charge'] as String? ?? '',
    prosecutionSummary: json['prosecution_summary'] as String? ?? '',
    defenseSummary: json['defense_summary'] as String? ?? '',
    verdict: VerdictKind.parse(json['verdict'] as String? ?? ''),
    reasoning: json['reasoning'] as String? ?? '',
    sentence: json['sentence'] as String? ?? '',
    judgeRoast: json['judge_roast'] as String? ?? '',
    closingLine: json['closing_line'] as String? ?? '',
    shareCaption: json['share_caption'] as String? ?? '',
    juryNote: json['jury_note'] as String? ?? '',
  );
}

class VerdictState {
  const VerdictState({required this.status, this.verdict});

  final CaseStatus status;
  final Verdict? verdict;

  factory VerdictState.fromJson(Map<String, dynamic> json) => VerdictState(
    status: CaseStatus.parse(json['status'] as String),
    verdict: json['result'] == null
        ? null
        : Verdict.fromJson(json['result'] as Map<String, dynamic>),
  );
}

class ShareLink {
  const ShareLink({required this.token, required this.url});

  final String token;
  final String url;

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
    token: json['share_token'] as String,
    url: json['share_url'] as String,
  );
}

class Session {
  const Session({
    required this.accessToken,
    required this.userId,
    required this.displayName,
    this.email,
  });

  final String accessToken;
  final String userId;
  final String displayName;
  final String? email;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    accessToken: json['access_token'] as String,
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String,
    email: json['email'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'user_id': userId,
    'display_name': displayName,
    'email': email,
  };
}

/// A person found through user search, or a member of a court.
class UserRef {
  const UserRef({
    required this.userId,
    required this.handle,
    required this.displayName,
  });

  final String userId;
  final String handle;
  final String displayName;

  factory UserRef.fromJson(Map<String, dynamic> json) => UserRef(
    userId: json['user_id'] as String,
    handle: json['handle'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
  );
}

/// A persistent friend group.
class Court {
  const Court({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
    required this.members,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String ownerId;
  final List<UserRef> members;

  factory Court.fromJson(Map<String, dynamic> json) => Court(
    id: json['id'] as String,
    name: json['name'] as String,
    inviteCode: json['invite_code'] as String? ?? '',
    ownerId: json['owner_id'] as String? ?? '',
    members: ((json['members'] as List<dynamic>?) ?? const [])
        .map((e) => UserRef.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// A case somebody else filed that I was added to directly.
class SharedCase {
  const SharedCase({
    required this.caseId,
    required this.title,
    required this.category,
    required this.status,
    required this.role,
    required this.creatorName,
    required this.linkKind,
    required this.token,
  });

  final String caseId;
  final String title;
  final String category;
  final String status;
  final String role;
  final String creatorName;

  /// `invite` (I am the accused) or `jury` (I am a juror).
  final String linkKind;
  final String token;

  String get path => '/${linkKind == 'invite' ? 'invite' : 'jury'}/$token';

  factory SharedCase.fromJson(Map<String, dynamic> json) => SharedCase(
    caseId: json['case_id'] as String,
    title: json['title'] as String? ?? '',
    category: json['category'] as String? ?? '',
    status: json['status'] as String? ?? '',
    role: json['role'] as String? ?? '',
    creatorName: json['creator_name'] as String? ?? '',
    linkKind: json['link_kind'] as String? ?? 'jury',
    token: json['token'] as String? ?? '',
  );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.text,
    required this.createdAt,
    required this.read,
    this.caseId,
    this.courtId,
    this.linkKind,
    this.token,
  });

  final String id;
  final String kind;
  final String text;
  final DateTime? createdAt;
  final bool read;
  final String? caseId;
  final String? courtId;
  final String? linkKind;
  final String? token;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? '',
        text: json['text'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        read: json['read'] as bool? ?? false,
        caseId: json['case_id'] as String?,
        courtId: json['court_id'] as String?,
        linkKind: json['link_kind'] as String?,
        token: json['token'] as String?,
      );
}

class NotificationFeed {
  const NotificationFeed({required this.unread, required this.items});

  final int unread;
  final List<AppNotification> items;

  factory NotificationFeed.fromJson(Map<String, dynamic> json) =>
      NotificationFeed(
        unread: json['unread'] as int? ?? 0,
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// What a juror sees when they open a summons. The tally stays null until
/// they have voted: seeing the running count first would turn a vote into a
/// poll, and the point is committing before you know.
class JuryRoom {
  const JuryRoom({
    required this.caseTitle,
    required this.accusation,
    required this.defense,
    required this.plaintiffName,
    required this.defendantName,
    required this.juryOpen,
    required this.verdictReady,
    required this.yourVote,
    required this.tally,
  });

  final String caseTitle;
  final String accusation;
  final String? defense;
  final String plaintiffName;
  final String defendantName;
  final bool juryOpen;
  final bool verdictReady;

  /// 'guilty', 'not_guilty', or null when this juror has not voted.
  final String? yourVote;
  final JuryTally? tally;

  bool get hasVoted => yourVote != null;

  factory JuryRoom.fromJson(Map<String, dynamic> json) => JuryRoom(
    caseTitle: json['case_title'] as String? ?? '',
    accusation: json['accusation'] as String? ?? '',
    defense: json['defense'] as String?,
    plaintiffName: json['plaintiff_name'] as String? ?? '',
    defendantName: json['defendant_name'] as String? ?? '',
    juryOpen: json['jury_open'] as bool? ?? false,
    verdictReady: json['verdict_ready'] as bool? ?? false,
    yourVote: json['your_vote'] as String?,
    tally: json['tally'] == null
        ? null
        : JuryTally.fromJson(json['tally'] as Map<String, dynamic>),
  );
}

// --- the game layer --------------------------------------------------------

/// One badge in the catalogue, earned or still to earn.
///
/// `GameBadge`, not `Badge`: Material has a `Badge` widget, and a screen that
/// draws badges needs both names in scope.
class GameBadge {
  const GameBadge({
    required this.code,
    required this.name,
    required this.glyph,
    required this.hint,
    required this.earned,
    this.earnedAt,
  });

  final String code;
  final String name;

  /// One or two characters for the hexagon on the player card.
  final String glyph;

  /// How it was earned, or how to earn it.
  final String hint;
  final bool earned;
  final DateTime? earnedAt;

  factory GameBadge.fromJson(Map<String, dynamic> json) => GameBadge(
    code: json['code'] as String? ?? '',
    name: json['name'] as String? ?? '',
    glyph: json['glyph'] as String? ?? '?',
    hint: json['hint'] as String? ?? '',
    earned: json['earned'] as bool? ?? false,
    earnedAt: json['earned_at'] == null
        ? null
        : DateTime.tryParse(json['earned_at'] as String)?.toLocal(),
  );
}

/// One of today's quests.
class Quest {
  const Quest({
    required this.code,
    required this.text,
    required this.progress,
    required this.target,
    required this.xp,
    required this.done,
  });

  final String code;
  final String text;
  final int progress;
  final int target;
  final int xp;
  final bool done;

  double get fraction => target <= 0 ? 0 : (progress / target).clamp(0, 1);

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
    code: json['code'] as String? ?? '',
    text: json['text'] as String? ?? '',
    progress: json['progress'] as int? ?? 0,
    target: json['target'] as int? ?? 1,
    xp: json['xp'] as int? ?? 0,
    done: json['done'] as bool? ?? false,
  );
}

/// The player card: level, experience, coins and streak.
class Player {
  const Player({
    required this.displayName,
    required this.level,
    required this.xp,
    required this.xpIntoLevel,
    required this.xpPerLevel,
    required this.xpToNextLevel,
    required this.coins,
    required this.streakDays,
    required this.longestStreakDays,
    required this.badgesEarned,
    required this.badgesTotal,
  });

  final String displayName;
  final int level;
  final int xp;
  final int xpIntoLevel;
  final int xpPerLevel;
  final int xpToNextLevel;
  final int coins;
  final int streakDays;
  final int longestStreakDays;
  final int badgesEarned;
  final int badgesTotal;

  double get levelFraction =>
      xpPerLevel <= 0 ? 0 : (xpIntoLevel / xpPerLevel).clamp(0, 1);

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    displayName: json['display_name'] as String? ?? '',
    level: json['level'] as int? ?? 1,
    xp: json['xp'] as int? ?? 0,
    xpIntoLevel: json['xp_into_level'] as int? ?? 0,
    xpPerLevel: json['xp_per_level'] as int? ?? 1000,
    xpToNextLevel: json['xp_to_next_level'] as int? ?? 1000,
    coins: json['coins'] as int? ?? 0,
    streakDays: json['streak_days'] as int? ?? 0,
    longestStreakDays: json['longest_streak_days'] as int? ?? 0,
    badgesEarned: json['badges_earned'] as int? ?? 0,
    badgesTotal: json['badges_total'] as int? ?? 0,
  );
}

/// Everything the game screens need, in one call.
class GameState {
  const GameState({
    required this.player,
    required this.quests,
    required this.badges,
  });

  final Player player;
  final List<Quest> quests;
  final List<GameBadge> badges;

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
    player: Player.fromJson(
      (json['player'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    quests: ((json['quests'] as List?) ?? const [])
        .map((e) => Quest.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    badges: ((json['badges'] as List?) ?? const [])
        .map((e) => GameBadge.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

/// One line on the verdict's rewards card.
class Reward {
  const Reward({
    required this.kind,
    required this.detail,
    required this.xp,
    required this.coins,
    this.badgeCode,
    this.badgeName,
    this.levelReached,
  });

  final String kind;
  final String detail;
  final int xp;
  final int coins;
  final String? badgeCode;
  final String? badgeName;
  final int? levelReached;

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
    kind: json['kind'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
    xp: json['xp'] as int? ?? 0,
    coins: json['coins'] as int? ?? 0,
    badgeCode: json['badge_code'] as String?,
    badgeName: json['badge_name'] as String?,
    levelReached: json['level_reached'] as int?,
  );
}

/// What one case paid one player. Empty until the judge has ruled.
class CaseRewards {
  const CaseRewards({
    required this.totalXp,
    required this.totalCoins,
    required this.items,
    this.levelReached,
  });

  final int totalXp;
  final int totalCoins;
  final int? levelReached;
  final List<Reward> items;

  bool get isEmpty => items.isEmpty;

  factory CaseRewards.fromJson(Map<String, dynamic> json) => CaseRewards(
    totalXp: json['total_xp'] as int? ?? 0,
    totalCoins: json['total_coins'] as int? ?? 0,
    levelReached: json['level_reached'] as int?,
    items: ((json['items'] as List?) ?? const [])
        .map((e) => Reward.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

// --- answering a summons ---------------------------------------------------

/// What the accused is shown before they write. Deliberately thin: the charge
/// and who brought it, and nothing else about the case or the plaintiff's
/// account.
class InvitePreview {
  const InvitePreview({
    required this.caseTitle,
    required this.category,
    required this.accusation,
    required this.plaintiffName,
    required this.alreadySubmitted,
    required this.verdictReady,
    required this.juryCount,
    this.defendantNickname,
    this.expiresAt,
  });

  final String caseTitle;
  final String category;
  final String accusation;
  final String plaintiffName;
  final String? defendantNickname;
  final DateTime? expiresAt;

  /// A defence is already on the record; this link cannot be used again.
  final bool alreadySubmitted;
  final bool verdictReady;

  /// How many of the group are already in the jury box.
  final int juryCount;

  factory InvitePreview.fromJson(Map<String, dynamic> json) => InvitePreview(
    caseTitle: json['case_title'] as String? ?? '',
    category: json['category'] as String? ?? '',
    accusation: json['accusation'] as String? ?? '',
    plaintiffName: json['plaintiff_name'] as String? ?? 'The plaintiff',
    defendantNickname: json['defendant_nickname'] as String?,
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.tryParse(json['expires_at'] as String)?.toLocal(),
    alreadySubmitted: json['already_submitted'] as bool? ?? false,
    verdictReady: json['verdict_ready'] as bool? ?? false,
    juryCount: json['jury_count'] as int? ?? 0,
  );
}

/// The receipt for a defence the court has accepted.
class DefenseAccepted {
  const DefenseAccepted({required this.caseTitle, required this.nickname});

  final String caseTitle;
  final String nickname;

  factory DefenseAccepted.fromJson(Map<String, dynamic> json) =>
      DefenseAccepted(
        caseTitle: json['case_title'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
      );
}
