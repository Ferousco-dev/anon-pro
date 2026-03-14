import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_knowledge_entry.dart';

class AiKnowledgeAdminService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AiKnowledgeEntry>> fetchEntries() async {
    final response = await _client
        .from('ai_knowledge_entries')
        .select('*')
        .order('created_at', ascending: false);

    return response
        .map((row) => AiKnowledgeEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createEntry({
    required String topic,
    required String content,
    List<String> keywords = const [],
  }) async {
    await _client.from('ai_knowledge_entries').insert({
      'topic': topic.trim(),
      'content': content.trim(),
      'keywords': keywords,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> updateEntry({
    required String id,
    String? topic,
    String? content,
    List<String>? keywords,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{};
    if (topic != null) payload['topic'] = topic.trim();
    if (content != null) payload['content'] = content.trim();
    if (keywords != null) payload['keywords'] = keywords;
    if (isActive != null) payload['is_active'] = isActive;

    if (payload.isEmpty) return;
    await _client.from('ai_knowledge_entries').update(payload).eq('id', id);
  }

  Future<void> deleteEntry(String id) async {
    await _client.from('ai_knowledge_entries').delete().eq('id', id);
  }
}
