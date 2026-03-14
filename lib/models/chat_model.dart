class ChatModel {
  final String id;
  final String name;
  final bool isGroup;
  final String? lastMessageContent;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final String? otherUserId;
  final String? otherUserAlias;
  final String? otherUserDisplayName;
  final String? otherUserProfileImageUrl;
  final List<String> participantIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Group-specific fields
  final String? groupImageUrl;
  final String? description;
  final bool isLocked;
  final String? createdBy;
  final String? currentUserRole; // 'admin' or 'member'
  final String? pinnedMessage;
  final String? pinnedBy;
  final DateTime? pinnedAt;

  ChatModel({
    required this.id,
    required this.name,
    this.isGroup = false,
    this.lastMessageContent,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.otherUserId,
    this.otherUserAlias,
    this.otherUserDisplayName,
    this.otherUserProfileImageUrl,
    this.participantIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.groupImageUrl,
    this.description,
    this.isLocked = false,
    this.createdBy,
    this.currentUserRole,
    this.pinnedMessage,
    this.pinnedBy,
    this.pinnedAt,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unknown',
      isGroup: json['is_group'] as bool? ?? false,
      lastMessageContent: json['last_message_content'] as String?,
      lastMessageTime: json['last_message_time'] != null
          ? DateTime.parse(json['last_message_time'] as String)
          : null,
      unreadCount: json['unread_count'] as int? ?? 0,
      otherUserId: json['other_user_id'] as String?,
      otherUserAlias: json['other_user_alias'] as String?,
      otherUserDisplayName: json['other_user_display_name'] as String?,
      otherUserProfileImageUrl: json['other_user_profile_image_url'] as String?,
      participantIds: json['participant_ids'] != null
          ? List<String>.from(json['participant_ids'] as List)
          : [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      groupImageUrl: json['group_image_url'] as String?,
      description: json['description'] as String?,
      isLocked: json['is_locked'] as bool? ?? false,
      createdBy: json['created_by'] as String?,
      currentUserRole: json['current_user_role'] as String?,
      pinnedMessage: json['pinned_message'] as String?,
      pinnedBy: json['pinned_by'] as String?,
      pinnedAt: json['pinned_at'] != null
          ? DateTime.tryParse(json['pinned_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_group': isGroup,
      'last_message_content': lastMessageContent,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'unread_count': unreadCount,
      'other_user_id': otherUserId,
      'other_user_alias': otherUserAlias,
      'other_user_display_name': otherUserDisplayName,
      'other_user_profile_image_url': otherUserProfileImageUrl,
      'participant_ids': participantIds,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'group_image_url': groupImageUrl,
      'description': description,
      'is_locked': isLocked,
      'created_by': createdBy,
      'current_user_role': currentUserRole,
      'pinned_message': pinnedMessage,
      'pinned_by': pinnedBy,
      'pinned_at': pinnedAt?.toIso8601String(),
    };
  }

  ChatModel copyWith({
    String? id,
    String? name,
    bool? isGroup,
    String? lastMessageContent,
    DateTime? lastMessageTime,
    int? unreadCount,
    String? otherUserId,
    String? otherUserAlias,
    String? otherUserDisplayName,
    String? otherUserProfileImageUrl,
    List<String>? participantIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? groupImageUrl,
    String? description,
    bool? isLocked,
    String? createdBy,
    String? currentUserRole,
    String? pinnedMessage,
    String? pinnedBy,
    DateTime? pinnedAt,
  }) {
    return ChatModel(
      id: id ?? this.id,
      name: name ?? this.name,
      isGroup: isGroup ?? this.isGroup,
      lastMessageContent: lastMessageContent ?? this.lastMessageContent,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      otherUserId: otherUserId ?? this.otherUserId,
      otherUserAlias: otherUserAlias ?? this.otherUserAlias,
      otherUserDisplayName: otherUserDisplayName ?? this.otherUserDisplayName,
      otherUserProfileImageUrl:
          otherUserProfileImageUrl ?? this.otherUserProfileImageUrl,
      participantIds: participantIds ?? this.participantIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      groupImageUrl: groupImageUrl ?? this.groupImageUrl,
      description: description ?? this.description,
      isLocked: isLocked ?? this.isLocked,
      createdBy: createdBy ?? this.createdBy,
      currentUserRole: currentUserRole ?? this.currentUserRole,
      pinnedMessage: pinnedMessage ?? this.pinnedMessage,
      pinnedBy: pinnedBy ?? this.pinnedBy,
      pinnedAt: pinnedAt ?? this.pinnedAt,
    );
  }

  String get displayName {
    if (isGroup) return name;
    return otherUserDisplayName ?? otherUserAlias ?? name;
  }

  String? get displayImageUrl {
    if (isGroup) return groupImageUrl;
    return otherUserProfileImageUrl;
  }

  bool get isAdmin => currentUserRole == 'admin';

  bool get canSendMessages {
    if (!isGroup) return true;
    if (!isLocked) return true;
    return isAdmin;
  }
}
