class AiKnowledgeEntry {
  final String id;
  final String topic;
  final String content;
  final List<String> keywords;
  final bool isActive;
  final DateTime? createdAt;

  AiKnowledgeEntry({
    required this.id,
    required this.topic,
    required this.content,
    required this.keywords,
    required this.isActive,
    required this.createdAt,
  });

  factory AiKnowledgeEntry.fromMap(Map<String, dynamic> map) {
    return AiKnowledgeEntry(
      id: map['id'] as String,
      topic: (map['topic'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      keywords: (map['keywords'] as List? ?? []).whereType<String>().toList(),
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }
}
