class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? senderAlias;
  final String? senderDisplayName;
  final String? senderProfileImageUrl;

  // Group features
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSenderName;
  final String? groupId;
  final String messageType; // 'text', 'image', 'system'
  final List<String> mentions; // user IDs mentioned
  final bool isSystemMessage;
  final Map<String, List<String>> reactions; // emoji -> list of user IDs

  MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    this.readAt,
    this.senderAlias,
    this.senderDisplayName,
    this.senderProfileImageUrl,
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    this.groupId,
    this.messageType = 'text',
    this.mentions = const [],
    this.isSystemMessage = false,
    this.reactions = const {},
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    // Parse reactions from JSON
    Map<String, List<String>> parsedReactions = {};
    if (json['reactions'] != null) {
      final rawReactions = json['reactions'] as Map<String, dynamic>;
      rawReactions.forEach((key, value) {
        parsedReactions[key] = List<String>.from(value as List);
      });
    }

    return MessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      senderAlias: json['sender_alias'] as String?,
      senderDisplayName: json['sender_display_name'] as String?,
      senderProfileImageUrl: json['sender_profile_image_url'] as String?,
      replyToId: json['reply_to_id'] as String?,
      replyToContent: json['reply_to_content'] as String?,
      replyToSenderName: json['reply_to_sender_name'] as String?,
      groupId: json['group_id'] as String?,
      messageType: json['message_type'] as String? ?? 'text',
      mentions: json['mentions'] != null
          ? List<String>.from(json['mentions'] as List)
          : [],
      isSystemMessage: json['is_system_message'] as bool? ?? false,
      reactions: parsedReactions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'image_url': imageUrl,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'reply_to_id': replyToId,
      'group_id': groupId,
      'message_type': messageType,
      'mentions': mentions,
      'is_system_message': isSystemMessage,
    };
  }

  MessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? readAt,
    String? senderAlias,
    String? senderDisplayName,
    String? senderProfileImageUrl,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
    String? groupId,
    String? messageType,
    List<String>? mentions,
    bool? isSystemMessage,
    Map<String, List<String>>? reactions,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      senderAlias: senderAlias ?? this.senderAlias,
      senderDisplayName: senderDisplayName ?? this.senderDisplayName,
      senderProfileImageUrl:
          senderProfileImageUrl ?? this.senderProfileImageUrl,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      groupId: groupId ?? this.groupId,
      messageType: messageType ?? this.messageType,
      mentions: mentions ?? this.mentions,
      isSystemMessage: isSystemMessage ?? this.isSystemMessage,
      reactions: reactions ?? this.reactions,
    );
  }

  bool get isRead => readAt != null;

  int get totalReactions =>
      reactions.values.fold(0, (sum, users) => sum + users.length);
}
