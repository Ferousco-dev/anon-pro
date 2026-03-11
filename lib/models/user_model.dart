class UserModel {
  final String id;
  final String email;
  final String alias;
  final String? displayName;
  final String? bio;
  final String? profileImageUrl;
  final String? coverImageUrl;
  final String role; // 'user', 'verified', 'admin'
  final bool isBanned;
  final bool isVerified;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? verifiedAt;
  final String verificationLevel; // 'none', 'verified', 'premium_verified'
  final String dmPrivacy; // 'everyone', 'verified_only', 'followers_only'
  final bool qaEnabled;

  UserModel({
    required this.id,
    required this.email,
    required this.alias,
    this.displayName,
    this.bio,
    this.profileImageUrl,
    this.coverImageUrl,
    required this.role,
    required this.isBanned,
    required this.isVerified,
    required this.followersCount,
    required this.followingCount,
    required this.postsCount,
    required this.createdAt,
    required this.updatedAt,
    this.verifiedAt,
    this.verificationLevel = 'none',
    this.dmPrivacy = 'everyone',
    this.qaEnabled = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      // FIXED: Handle missing email field (when querying from posts relationship)
      email: json['email'] as String? ?? '',
      alias: json['alias'] as String,
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      role: json['role'] as String? ?? 'user',
      isBanned: json['is_banned'] as bool? ?? false,
      isVerified: json['is_verified'] as bool? ?? false,
      followersCount: json['followers_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      postsCount: json['posts_count'] as int? ?? 0,
      // FIXED: Handle missing timestamp fields (when querying from posts relationship)
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
      verificationLevel: json['verification_level'] as String? ?? 'none',
      dmPrivacy: json['dm_privacy'] as String? ?? 'everyone',
      qaEnabled: json['qa_enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'alias': alias,
      'display_name': displayName,
      'bio': bio,
      'profile_image_url': profileImageUrl,
      'cover_image_url': coverImageUrl,
      'role': role,
      'is_banned': isBanned,
      'is_verified': isVerified,
      'followers_count': followersCount,
      'following_count': followingCount,
      'posts_count': postsCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'verified_at': verifiedAt?.toIso8601String(),
      'verification_level': verificationLevel,
      'dm_privacy': dmPrivacy,
      'qa_enabled': qaEnabled,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? alias,
    String? displayName,
    String? bio,
    String? profileImageUrl,
    String? coverImageUrl,
    String? role,
    bool? isBanned,
    bool? isVerified,
    int? followersCount,
    int? followingCount,
    int? postsCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? verifiedAt,
    String? verificationLevel,
    String? dmPrivacy,
    bool? qaEnabled,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      alias: alias ?? this.alias,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      role: role ?? this.role,
      isBanned: isBanned ?? this.isBanned,
      isVerified: isVerified ?? this.isVerified,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      postsCount: postsCount ?? this.postsCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      verificationLevel: verificationLevel ?? this.verificationLevel,
      dmPrivacy: dmPrivacy ?? this.dmPrivacy,
      qaEnabled: qaEnabled ?? this.qaEnabled,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isVerifiedUser =>
      isVerified || role == 'verified' || role == 'admin';
  bool get isPremiumVerified => verificationLevel == 'premium_verified';
}
