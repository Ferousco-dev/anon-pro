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
    // Requirements: 12+ posts AND posts with engagement
    return totalPosts >= 12 && postsWithEngagement >= 5;
  }

  /// Get verification progress (0-100%)
  int get verificationProgress {
    final postProgress = (totalPosts / 12 * 50).clamp(0, 50).toInt();
    final engagementProgress =
        (postsWithEngagement / 5 * 50).clamp(0, 50).toInt();
    return postProgress + engagementProgress;
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
