import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AiKnowledgeRepository {
  static const String _cacheKey = 'ai_remote_knowledge_cache';
  static const String _cacheTimeKey = 'ai_remote_knowledge_cache_time';
  static const Duration _cacheTtl = Duration(hours: 6);

  Map<String, dynamic> _index = {};
  final Map<String, Map<String, dynamic>> _topicCache = {};
  final Map<String, List<String>> _remoteEntries = {};

  Map<String, dynamic> get index => _index;

  List<String> get topicNames {
    final topics = _index['topics'] as Map<String, dynamic>? ?? {};
    return topics.keys.toList();
  }

  Map<String, dynamic> getTopicMeta(String topic) {
    final topics = _index['topics'] as Map<String, dynamic>? ?? {};
    final meta = topics[topic] as Map<String, dynamic>? ?? {};
    return meta;
  }

  Future<void> loadIndex() async {
    try {
      _index = await _loadJsonAsset('assets/knowledge/index.json');
      if (_index.isNotEmpty) {
        await _loadRemoteEntriesFromCache();
        return;
      }
    } catch (_) {
      // Fall back to legacy knowledge.json below.
    }

    final legacy = await _loadJsonAsset('assets/knowledge.json');
    _index = {
      ...legacy,
      'topics': {
        'all': {
          'file': 'assets/knowledge.json',
          'keywords': <String>[],
        }
      }
    };
    await _loadRemoteEntriesFromCache();
  }

  Future<Map<String, dynamic>> loadTopic(String topic) async {
    if (_topicCache.containsKey(topic)) {
      return _topicCache[topic]!;
    }
    final meta = getTopicMeta(topic);
    final file = meta['file'] as String?;
    Map<String, dynamic> data = {};
    if (file != null && file.isNotEmpty) {
      data = await _loadJsonAsset(file);
    }
    final merged = Map<String, dynamic>.from(data);
    final customEntries = _remoteEntries[topic] ?? [];
    if (customEntries.isNotEmpty) {
      merged['custom_entries'] = customEntries;
    }
    _topicCache[topic] = merged;
    return merged;
  }

  Future<Map<String, dynamic>> _loadJsonAsset(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {};
  }

  Future<void> refreshRemoteEntries({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastTime = prefs.getInt(_cacheTimeKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        lastTime != null &&
        now - lastTime < _cacheTtl.inMilliseconds) {
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('ai_knowledge_entries')
          .select('topic, content, keywords')
          .eq('is_active', true);

      _remoteEntries.clear();
      for (final row in response) {
        final topic = (row['topic'] as String?)?.trim();
        final content = (row['content'] as String?)?.trim();
        if (topic == null || topic.isEmpty || content == null || content.isEmpty) {
          continue;
        }
        _remoteEntries.putIfAbsent(topic, () => []);
        _remoteEntries[topic]!.add(content);

        final keywords = row['keywords'] as List?;
        if (keywords != null && keywords.isNotEmpty) {
          _remoteEntries[topic]!.addAll(
            keywords.whereType<String>().map((k) => k.trim()).where((k) => k.isNotEmpty),
          );
        }
      }

      final topics = _index['topics'] as Map<String, dynamic>? ?? {};
      for (final topic in _remoteEntries.keys) {
        topics.putIfAbsent(topic, () {
          return {
            'file': '',
            'keywords': <String>[],
          };
        });
      }
      _index['topics'] = topics;

      await prefs.setString(_cacheKey, jsonEncode(_remoteEntries));
      await prefs.setInt(_cacheTimeKey, now);
    } catch (_) {
      // Ignore remote fetch failures and rely on cached data.
    }
  }

  Future<void> _loadRemoteEntriesFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _remoteEntries.clear();
        decoded.forEach((key, value) {
          if (value is List) {
            _remoteEntries[key] = value.whereType<String>().toList();
          }
        });
      }
    } catch (_) {
      // Ignore cache issues.
    }
  }
}
