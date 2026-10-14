/// Contributor XP summary returned by `POST /worker-contribution:sync`.
///
/// XP values are integer centi-XP; no floating point is used for scoring.
class WorkerContributionSummary {
  const WorkerContributionSummary({
    required this.level,
    required this.nextLevel,
    required this.totalCentiXp,
    required this.totalXp,
    required this.currentLevelMinCentiXp,
    required this.nextLevelMinCentiXp,
    required this.remainingCentiXp,
    required this.progressBps,
    required this.verifiedTaskCount,
    required this.acceptedProcessingMs,
    required this.boost,
    required this.boostPurchase,
    required this.scoringDegraded,
  });

  factory WorkerContributionSummary.fromJson(Map<String, dynamic> json) {
    final boost = json['boost'] as Map<String, dynamic>;
    final purchase = json['boostPurchase'] as Map<String, dynamic>;
    return WorkerContributionSummary(
      level: json['level'] as String,
      nextLevel: json['nextLevel'] as String?,
      totalCentiXp: json['totalCentiXp'] as int,
      totalXp: json['totalXp'] as String,
      currentLevelMinCentiXp: json['currentLevelMinCentiXp'] as int,
      nextLevelMinCentiXp: json['nextLevelMinCentiXp'] as int?,
      remainingCentiXp: json['remainingCentiXp'] as int?,
      progressBps: json['progressBps'] as int,
      verifiedTaskCount: json['verifiedTaskCount'] as int,
      acceptedProcessingMs: json['acceptedProcessingMs'] as int?,
      boost: ContributionBoostStatus(
        active: boost['active'] as bool,
        bonusBps: boost['bonusBps'] as int,
        expiresAt: boost['expiresAt'] == null
            ? null
            : DateTime.parse(boost['expiresAt'] as String),
        remainingTasks: boost['remainingTasks'] as int?,
      ),
      boostPurchase: ContributionBoostPurchase(
        enabled: purchase['enabled'] as bool,
        blockedReason: purchase['blockedReason'] as String?,
        priceTokenMinorUnits: purchase['priceTokenMinorUnits'] as int?,
        durationHours: purchase['durationHours'] as int,
        taskQuota: purchase['taskQuota'] as int,
      ),
      scoringDegraded: json['scoringStatus'] == 'degraded',
    );
  }

  final String level;
  final String? nextLevel;
  final int totalCentiXp;
  final String totalXp;
  final int currentLevelMinCentiXp;
  final int? nextLevelMinCentiXp;
  final int? remainingCentiXp;
  final int progressBps;
  final int verifiedTaskCount;

  /// Null when no award had server-verified processing time.
  final int? acceptedProcessingMs;
  final ContributionBoostStatus boost;
  final ContributionBoostPurchase boostPurchase;
  final bool scoringDegraded;

  bool get isTopLevel => nextLevel == null;
}

class ContributionBoostStatus {
  const ContributionBoostStatus({
    required this.active,
    required this.bonusBps,
    required this.expiresAt,
    required this.remainingTasks,
  });

  final bool active;
  final int bonusBps;
  final DateTime? expiresAt;
  final int? remainingTasks;
}

class ContributionBoostPurchase {
  const ContributionBoostPurchase({
    required this.enabled,
    required this.blockedReason,
    required this.priceTokenMinorUnits,
    required this.durationHours,
    required this.taskQuota,
  });

  final bool enabled;
  final String? blockedReason;
  final int? priceTokenMinorUnits;
  final int durationHours;
  final int taskQuota;
}

/// Formats integer centi-XP as `123.45` without floating point.
String formatCentiXp(int centiXp) {
  final sign = centiXp < 0 ? '-' : '';
  final abs = centiXp.abs();
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '$sign${abs ~/ 100}.$cents';
}
