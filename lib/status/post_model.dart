class Post {
  final String id;
  final String userId;
  final String mediaUrl;
  final DateTime createdAt;
  final bool isVideo;
  final String? caption;
  final DateTime? expiresAt;
  final int viewsCount;
  final List<String> viewedBy;
  final Map<String, int> reactions;
  final bool isOwner;
  final bool isViewed;

  const Post({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.createdAt,
    required this.isVideo,
    this.caption,
    this.expiresAt,
    this.viewsCount = 0,
    this.viewedBy = const [],
    this.reactions = const {},
    this.isOwner = false,
    this.isViewed = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      mediaUrl:
          json['media_path'] as String? ?? json['media_url'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      isVideo: (json['media_type'] as String?) == 'video',
      caption: json['caption'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      viewsCount: json['views_count'] as int? ?? 0,
      viewedBy: List<String>.from(json['viewed_by'] as List<dynamic>? ?? []),
      reactions: Map<String, int>.from(
        (json['reactions'] as Map<dynamic, dynamic>? ?? {}).cast<String, int>(),
      ),
      isOwner: json['is_owner'] as bool? ?? false,
      isViewed: json['is_viewed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'media_path': mediaUrl,
      'media_url': mediaUrl,
      'created_at': createdAt.toIso8601String(),
      'media_type': isVideo ? 'video' : 'image',
      'caption': caption,
      'expires_at': expiresAt?.toIso8601String(),
      'views_count': viewsCount,
      'viewed_by': viewedBy,
      'reactions': reactions,
      'is_owner': isOwner,
      'is_viewed': isViewed,
    };
  }

  Post copyWith({
    String? id,
    String? userId,
    String? mediaUrl,
    DateTime? createdAt,
    bool? isVideo,
    String? caption,
    DateTime? expiresAt,
    int? viewsCount,
    List<String>? viewedBy,
    Map<String, int>? reactions,
    bool? isOwner,
    bool? isViewed,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      createdAt: createdAt ?? this.createdAt,
      isVideo: isVideo ?? this.isVideo,
      caption: caption ?? this.caption,
      expiresAt: expiresAt ?? this.expiresAt,
      viewsCount: viewsCount ?? this.viewsCount,
      viewedBy: viewedBy ?? this.viewedBy,
      reactions: reactions ?? this.reactions,
      isOwner: isOwner ?? this.isOwner,
      isViewed: isViewed ?? this.isViewed,
    );
  }
}
