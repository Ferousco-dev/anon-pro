class StatusModel {
  final String id;
  final String userId;
  final String alias;
  final String? displayName;
  final String? profileImageUrl;
  final String mediaPath;
  final String mediaType; // 'image', 'video'
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool hasViewed;
  final int viewsCount;
  final int likesCount;
  final bool hasLiked;

  StatusModel({
    required this.id,
    required this.userId,
    required this.alias,
    this.displayName,
    this.profileImageUrl,
    required this.mediaPath,
    required this.mediaType,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
    this.hasViewed = false,
    this.viewsCount = 0,
    this.likesCount = 0,
    this.hasLiked = false,
  });

  factory StatusModel.fromJson(Map<String, dynamic> json) {
    return StatusModel(
      id: json['status_id'] as String? ?? json['id'] as String,
      userId: json['user_id'] as String,
      alias: json['alias'] as String? ?? '',
      displayName: json['display_name'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      mediaPath: json['media_path'] as String,
      mediaType: json['media_type'] as String? ?? 'image',
      caption: json['caption'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      hasViewed: json['has_viewed'] as bool? ?? false,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      hasLiked: json['has_liked'] as bool? ?? false,
    );
  }
}

