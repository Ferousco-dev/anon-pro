class UserAnalyticsModel {
  final String userId;
  final int profileViews;
  final int postViews;
  final int likesReceived;
  final int commentsReceived;
  final DateTime? updatedAt;

  UserAnalyticsModel({
    required this.userId,
    this.profileViews = 0,
    this.postViews = 0,
    this.likesReceived = 0,
    this.commentsReceived = 0,
    this.updatedAt,
  });

  factory UserAnalyticsModel.fromJson(Map<String, dynamic> json) {
    return UserAnalyticsModel(
      userId: json['user_id'] as String,
      profileViews: json['profile_views'] as int? ?? 0,
      postViews: json['post_views'] as int? ?? 0,
      likesReceived: json['likes_received'] as int? ?? 0,
      commentsReceived: json['comments_received'] as int? ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  int get totalEngagement => likesReceived + commentsReceived;
}
