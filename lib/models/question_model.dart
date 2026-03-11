class AnonymousQuestionModel {
  final String id;
  final String targetUserId;
  final String? askerUserId;
  final String question;
  final String? answer;
  final bool answered;
  final DateTime? answeredAt;
  final DateTime createdAt;

  AnonymousQuestionModel({
    required this.id,
    required this.targetUserId,
    this.askerUserId,
    required this.question,
    this.answer,
    this.answered = false,
    this.answeredAt,
    required this.createdAt,
  });

  factory AnonymousQuestionModel.fromJson(Map<String, dynamic> json) {
    return AnonymousQuestionModel(
      id: json['id'] as String,
      targetUserId: json['target_user_id'] as String,
      askerUserId: json['asker_user_id'] as String?,
      question: json['question'] as String,
      answer: json['answer'] as String?,
      answered: json['answered'] as bool? ?? false,
      answeredAt: json['answered_at'] != null
          ? DateTime.parse(json['answered_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'target_user_id': targetUserId,
      'asker_user_id': askerUserId,
      'question': question,
      'answer': answer,
      'answered': answered,
      'answered_at': answeredAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
