class StreakRequirements {
  final int totalPostsRequired;
  final int engagedPostsRequired;
  final int totalEngagementRequired;
  final double avgLikesRequired;

  const StreakRequirements({
    required this.totalPostsRequired,
    required this.engagedPostsRequired,
    required this.totalEngagementRequired,
    required this.avgLikesRequired,
  });

  static const defaults = StreakRequirements(
    totalPostsRequired: 12,
    engagedPostsRequired: 5,
    totalEngagementRequired: 0,
    avgLikesRequired: 0,
  );

  factory StreakRequirements.fromMap(Map<String, dynamic> data) {
    return StreakRequirements(
      totalPostsRequired: data['streak_required_posts'] as int? ?? 12,
      engagedPostsRequired: data['streak_required_engaged_posts'] as int? ?? 5,
      totalEngagementRequired:
          data['streak_required_total_engagement'] as int? ?? 0,
      avgLikesRequired:
          (data['streak_required_avg_likes'] as num?)?.toDouble() ?? 0,
    );
  }
}
