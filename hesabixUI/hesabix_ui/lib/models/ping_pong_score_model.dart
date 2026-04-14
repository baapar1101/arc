class PingPongScore {
  final int? id;
  final int userId;
  final int score;
  final int survivalTime;
  final int heroModeUses;
  final double difficultyLevel;
  final DateTime? playedAt;
  final DateTime? createdAt;

  PingPongScore({
    this.id,
    required this.userId,
    required this.score,
    required this.survivalTime,
    required this.heroModeUses,
    required this.difficultyLevel,
    this.playedAt,
    this.createdAt,
  });

  factory PingPongScore.fromJson(Map<String, dynamic> json) {
    return PingPongScore(
      id: json['id'] as int?,
      userId: json['user_id'] as int,
      score: json['score'] as int,
      survivalTime: json['survival_time'] as int,
      heroModeUses: json['hero_mode_uses'] as int? ?? 0,
      difficultyLevel: (json['difficulty_level'] as num?)?.toDouble() ?? 1.0,
      playedAt: json['played_at'] != null
          ? DateTime.parse(json['played_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'score': score,
      'survival_time': survivalTime,
      'hero_mode_uses': heroModeUses,
      'difficulty_level': difficultyLevel,
      if (playedAt != null) 'played_at': playedAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}

class PingPongStats {
  final int totalGames;
  final int bestScore;
  final int bestSurvivalTime;
  final double averageScore;
  final int totalPlaytime;
  final int heroModeUsesTotal;

  PingPongStats({
    required this.totalGames,
    required this.bestScore,
    required this.bestSurvivalTime,
    required this.averageScore,
    required this.totalPlaytime,
    required this.heroModeUsesTotal,
  });

  factory PingPongStats.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return PingPongStats(
      totalGames: data['total_games'] as int? ?? 0,
      bestScore: data['best_score'] as int? ?? 0,
      bestSurvivalTime: data['best_survival_time'] as int? ?? 0,
      averageScore: (data['average_score'] as num?)?.toDouble() ?? 0.0,
      totalPlaytime: data['total_playtime'] as int? ?? 0,
      heroModeUsesTotal: data['hero_mode_uses_total'] as int? ?? 0,
    );
  }
}

class LeaderboardEntry {
  final int userId;
  final String userName;
  final int score;
  final int survivalTime;
  final DateTime playedAt;
  final int rank;

  LeaderboardEntry({
    required this.userId,
    required this.userName,
    required this.score,
    required this.survivalTime,
    required this.playedAt,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      userId: json['user_id'] as int,
      userName: json['user_name'] as String? ?? 'کاربر ناشناس',
      score: json['score'] as int,
      survivalTime: json['survival_time'] as int,
      playedAt: DateTime.parse(json['played_at'] as String),
      rank: json['rank'] as int,
    );
  }
}

