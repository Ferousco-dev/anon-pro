class UserStreakModel {
  final String userId;
  final int currentStreak;
  final int totalPosts;
  final int postsWithEngagement;
  final DateTime? lastPostDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserStreakModel({
    required this.userId,
    this.currentStreak = 0,
    this.totalPosts = 0,
    this.postsWithEngagement = 0,
    this.lastPostDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserStreakModel.fromJson(Map<String, dynamic> json) {
    return UserStreakModel(
      userId: json['user_id'] as String,
      currentStreak: json['current_streak'] as int? ?? 0,
      totalPosts: json['total_posts'] as int? ?? 0,
      postsWithEngagement: json['posts_with_engagement'] as int? ?? 0,
      lastPostDate: json['last_post_date'] != null
          ? DateTime.parse(json['last_post_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'current_streak': currentStreak,
      'total_posts': totalPosts,
      'posts_with_engagement': postsWithEngagement,
      'last_post_date': lastPostDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Check if user qualifies for automatic verification
  bool get isEligibleForVerification {
    // Defaults retained for legacy callers.
    return totalPosts >= 12 && postsWithEngagement >= 5;
  }

  bool isEligibleForVerificationWith(
    int totalPostsRequired,
    int engagedPostsRequired,
    int totalEngagementRequired,
    double avgLikesRequired, {
    required int totalEngagement,
    required double avgLikes,
  }) {
    if (totalPosts < totalPostsRequired) return false;
    if (postsWithEngagement < engagedPostsRequired) return false;
    if (totalEngagement < totalEngagementRequired) return false;
    if (avgLikes < avgLikesRequired) return false;
    return true;
  }

  /// Get verification progress (0-100%)
  int get verificationProgress {
    final postProgress = (totalPosts / 12 * 50).clamp(0, 50).toInt();
    final engagementProgress =
        (postsWithEngagement / 5 * 50).clamp(0, 50).toInt();
    return postProgress + engagementProgress;
  }

  int verificationProgressWith({
    required int totalPostsRequired,
    required int engagedPostsRequired,
    required int totalEngagementRequired,
    required double avgLikesRequired,
    required int totalEngagement,
    required double avgLikes,
  }) {
    final activeRequirements = [
      totalPostsRequired > 0,
      engagedPostsRequired > 0,
      totalEngagementRequired > 0,
      avgLikesRequired > 0,
    ].where((v) => v).length;

    if (activeRequirements == 0) return 100;

    final weight = 100 / activeRequirements;
    double progress = 0;

    if (totalPostsRequired > 0) {
      progress += (totalPosts / totalPostsRequired).clamp(0, 1) * weight;
    }
    if (engagedPostsRequired > 0) {
      progress +=
          (postsWithEngagement / engagedPostsRequired).clamp(0, 1) * weight;
    }
    if (totalEngagementRequired > 0) {
      progress +=
          (totalEngagement / totalEngagementRequired).clamp(0, 1) * weight;
    }
    if (avgLikesRequired > 0) {
      progress += (avgLikes / avgLikesRequired).clamp(0, 1) * weight;
    }

    return progress.clamp(0, 100).round();
  }

  UserStreakModel copyWith({
    String? userId,
    int? currentStreak,
    int? totalPosts,
    int? postsWithEngagement,
    DateTime? lastPostDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserStreakModel(
      userId: userId ?? this.userId,
      currentStreak: currentStreak ?? this.currentStreak,
      totalPosts: totalPosts ?? this.totalPosts,
      postsWithEngagement: postsWithEngagement ?? this.postsWithEngagement,
      lastPostDate: lastPostDate ?? this.lastPostDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class VerificationNotificationModel {
  final String id;
  final String userId;
  final String notificationType;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  VerificationNotificationModel({
    required this.id,
    required this.userId,
    this.notificationType = 'verified_unlocked',
    required this.title,
    required this.message,
    this.isRead = false,
    required this.createdAt,
  });

  factory VerificationNotificationModel.fromJson(Map<String, dynamic> json) {
    return VerificationNotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      notificationType:
          json['notification_type'] as String? ?? 'verified_unlocked',
      title: json['title'] as String,
      message: json['message'] as String,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'notification_type': notificationType,
      'title': title,
      'message': message,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
