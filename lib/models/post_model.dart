import 'user_model.dart';

class PostModel {
  final String id;
  final String userId;
  final String content;
  final String? imageUrl;
  final bool isAnonymous;
  final String postIdentityMode; // 'anonymous', 'verified_anonymous', 'public'
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final int viewsCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? originalPostId;
  final int repostsCount;
  final String? originalContent; // For reposts
  final PostModel? originalPost;
  final String postType; // 'regular', 'confession_room'
  final String?
      relatedConfessionRoomId; // Room ID if this is a confession room post

  UserModel? user;
  bool? isLikedByCurrentUser;
  bool? isBookmarkedByCurrentUser;
  bool? isRepostedByCurrentUser;

  /// Map of @alias -> userId for tagged users (clickable mentions)
  Map<String, String>? taggedUsers;

  PostModel({
    required this.id,
    required this.userId,
    required this.content,
    required this.imageUrl,
    required this.isAnonymous,
    this.postIdentityMode = 'anonymous',
    required this.likesCount,
    required this.commentsCount,
    required this.sharesCount,
    required this.viewsCount,
    required this.createdAt,
    required this.updatedAt,
    required this.originalPostId,
    required this.repostsCount,
    required this.originalContent,
    this.originalPost,
    this.user,
    this.isLikedByCurrentUser,
    this.isBookmarkedByCurrentUser,
    this.isRepostedByCurrentUser,
    this.taggedUsers,
    this.postType = 'regular',
    this.relatedConfessionRoomId,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    return PostModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      imageUrl: json['image_url'] as String?,
      isAnonymous: json['is_anonymous'] is int
          ? (json['is_anonymous'] as int) == 1
          : json['is_anonymous'] as bool? ?? false,
      postIdentityMode: json['post_identity_mode'] as String? ?? 'anonymous',
      likesCount: json['likes_count'] as int? ?? 0,
      commentsCount: json['comments_count'] as int? ?? 0,
      sharesCount: json['shares_count'] as int? ?? 0,
      viewsCount: json['views_count'] as int? ?? 0,
      repostsCount: json['reposts_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      originalPostId: json['original_post_id'] as String?,
      originalContent: json['original'] != null
          ? json['original']['content'] as String?
          : null,
      originalPost: null, // Will be loaded separately if needed
      user: json['users'] != null ? UserModel.fromJson(json['users']) : null,
      isLikedByCurrentUser: json['is_liked'] as bool?,
      isBookmarkedByCurrentUser: json['is_bookmarked'] as bool?,
      isRepostedByCurrentUser: json['is_reposted'] as bool?,
      taggedUsers: null, // Loaded separately from post_tags
      postType: json['post_type'] as String? ?? 'regular',
      relatedConfessionRoomId: json['related_confession_room_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'content': content,
      'image_url': imageUrl,
      'is_anonymous': isAnonymous,
      'post_identity_mode': postIdentityMode,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'shares_count': sharesCount,
      'views_count': viewsCount,
      'reposts_count': repostsCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'original_post_id': originalPostId,
      'original_content': originalContent,
      'post_type': postType,
      'related_confession_room_id': relatedConfessionRoomId,
    };
  }

  PostModel copyWith({
    String? id,
    String? userId,
    String? content,
    String? imageUrl,
    bool? isAnonymous,
    String? postIdentityMode,
    int? likesCount,
    int? commentsCount,
    int? sharesCount,
    int? viewsCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? originalPostId,
    int? repostsCount,
    String? originalContent,
    PostModel? originalPost,
    UserModel? user,
    bool? isLikedByCurrentUser,
    bool? isBookmarkedByCurrentUser,
    bool? isRepostedByCurrentUser,
    Map<String, String>? taggedUsers,
    String? postType,
    String? relatedConfessionRoomId,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      postIdentityMode: postIdentityMode ?? this.postIdentityMode,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      viewsCount: viewsCount ?? this.viewsCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      originalPostId: originalPostId ?? this.originalPostId,
      repostsCount: repostsCount ?? this.repostsCount,
      originalContent: originalContent ?? this.originalContent,
      originalPost: originalPost ?? this.originalPost,
      user: user ?? this.user,
      isLikedByCurrentUser: isLikedByCurrentUser ?? this.isLikedByCurrentUser,
      isBookmarkedByCurrentUser:
          isBookmarkedByCurrentUser ?? this.isBookmarkedByCurrentUser,
      isRepostedByCurrentUser:
          isRepostedByCurrentUser ?? this.isRepostedByCurrentUser,
      taggedUsers: taggedUsers ?? this.taggedUsers,
      postType: postType ?? this.postType,
      relatedConfessionRoomId:
          relatedConfessionRoomId ?? this.relatedConfessionRoomId,
    );
  }

  String get displayAuthorName {
    switch (postIdentityMode) {
      case 'public':
        return user?.displayName ?? user?.alias ?? 'Unknown';
      case 'verified_anonymous':
        return 'Verified Anonymous';
      case 'anonymous':
      default:
        if (isAnonymous) return 'Anonymous';
        return user?.displayName ?? user?.alias ?? 'Unknown';
    }
  }

  String? get displayAuthorImage {
    switch (postIdentityMode) {
      case 'public':
        return user?.profileImageUrl;
      case 'verified_anonymous':
      case 'anonymous':
      default:
        if (isAnonymous) return null;
        return user?.profileImageUrl;
    }
  }

  bool get showVerifiedBadge {
    if (postIdentityMode == 'verified_anonymous') return true;
    if (postIdentityMode == 'public' && (user?.isVerifiedUser ?? false))
      return true;
    if (!isAnonymous && (user?.isVerifiedUser ?? false)) return true;
    return false;
  }

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  bool get isRepost => originalPostId != null;

  String get displayContent {
    if (isRepost && originalPost != null) {
      return originalPost!.content;
    }
    return content;
  }

  String? get displayImageUrl {
    if (isRepost && originalPost != null) {
      return originalPost!.imageUrl;
    }
    return imageUrl;
  }

  String get repostAuthorName {
    if (isRepost && originalPost != null) {
      return originalPost!.displayAuthorName;
    }
    return displayAuthorName;
  }

  String? get repostAuthorImage {
    if (isRepost && originalPost != null) {
      return originalPost!.displayAuthorImage;
    }
    return displayAuthorImage;
  }
}
