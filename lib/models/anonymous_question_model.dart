class AnonymousQuestionModel {
  final String id;
  final String targetUserId;
  final String question;
  final String? answer;
  final bool answered;
  final bool isPublic;
  final DateTime createdAt;
  final DateTime? answeredAt;

  // Joined fields for display
  final String? targetUserAlias;
  final String? targetUserProfileImageUrl;

  AnonymousQuestionModel({
    required this.id,
    required this.targetUserId,
    required this.question,
    this.answer,
    required this.answered,
    required this.isPublic,
    required this.createdAt,
    this.answeredAt,
    this.targetUserAlias,
    this.targetUserProfileImageUrl,
  });

  factory AnonymousQuestionModel.fromJson(Map<String, dynamic> json) {
    return AnonymousQuestionModel(
      id: json['id'] as String,
      targetUserId: json['target_user_id'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String?,
      answered: json['answered'] as bool? ?? false,
      isPublic: json['is_public'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      answeredAt: json['answered_at'] != null
          ? DateTime.parse(json['answered_at'] as String)
          : null,
      targetUserAlias: json['target']?['alias'] as String?,
      targetUserProfileImageUrl: json['target']?['profile_image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'target_user_id': targetUserId,
      'question': question,
      'answer': answer,
      'answered': answered,
      'is_public': isPublic,
      'created_at': createdAt.toIso8601String(),
      'answered_at': answeredAt?.toIso8601String(),
    };
  }

  AnonymousQuestionModel copyWith({
    String? id,
    String? targetUserId,
    String? question,
    String? answer,
    bool? answered,
    bool? isPublic,
    DateTime? createdAt,
    DateTime? answeredAt,
    String? targetUserAlias,
    String? targetUserProfileImageUrl,
  }) {
    return AnonymousQuestionModel(
      id: id ?? this.id,
      targetUserId: targetUserId ?? this.targetUserId,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      answered: answered ?? this.answered,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt ?? this.createdAt,
      answeredAt: answeredAt ?? this.answeredAt,
      targetUserAlias: targetUserAlias ?? this.targetUserAlias,
      targetUserProfileImageUrl: targetUserProfileImageUrl ?? this.targetUserProfileImageUrl,
    );
  }
}
