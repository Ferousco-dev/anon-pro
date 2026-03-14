import 'dart:math';
import 'package:flutter/material.dart';
import 'ai_knowledge_repository.dart';

class AiIntentMatch {
  final String intent;
  final double score;
  final String? answer;

  const AiIntentMatch({
    required this.intent,
    required this.score,
    required this.answer,
  });
}

class AiBrainReply {
  final String text;
  final String? topic;
  final AiIntentMatch? intent;
  final double confidence;

  const AiBrainReply({
    required this.text,
    required this.topic,
    required this.intent,
    required this.confidence,
  });
}

class ScoredResult {
  final String text;
  final double score;

  const ScoredResult(this.text, this.score);
}

class AIBrainEngine {
  final AiKnowledgeRepository _repo;
  late Map<String, dynamic> _index;
  late Map<String, List<String>> _keywordMap;
  String? _lastTopic;
  List<ScoredResult> _lastResults = [];
  List<String> _lastSuggestions = [];

  AIBrainEngine(this._repo);

  Future<void> init() async {
    await _repo.loadIndex();
    _index = _repo.index;
    _keywordMap = _extractKeywordMap();
  }

  Map<String, List<String>> _extractKeywordMap() {
    final map = <String, List<String>>{};

    final keywordMap = _index['ai_keywords_map'] as Map<String, dynamic>?;
    if (keywordMap != null) {
      for (final entry in keywordMap.entries) {
        map[entry.key] = List<String>.from(entry.value as List);
      }
    }

    final extended = _index['extended_keywords'] as Map<String, dynamic>?;
    if (extended != null) {
      for (final entry in extended.entries) {
        if (entry.value is List) {
          map[entry.key] = List<String>.from(entry.value as List);
        }
      }
    }

    return map;
  }

  List<String> _tokenizeQuery(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[?!.,;:]'), '')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && token.length > 2)
        .toList();
  }

  double _calculateSimilarity(List<String> queryTokens, List<String> keywords) {
    if (queryTokens.isEmpty || keywords.isEmpty) return 0.0;

    final intersection =
        queryTokens.toSet().intersection(keywords.toSet()).length;
    final union = queryTokens.toSet().union(keywords.toSet()).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  AiIntentMatch? _classifyIntent(String query) {
    final intents = _index['intent_questions'] as List? ?? [];
    if (intents.isEmpty) return null;

    final queryLower = query.toLowerCase().trim();
    final queryTokens = _tokenizeQuery(query);
    double bestScore = 0.0;
    AiIntentMatch? bestMatch;

    for (final item in intents) {
      if (item is! Map<String, dynamic>) continue;
      final intent = item['intent'] as String? ?? 'unknown';
      final questions = item['questions'] as List? ?? [];
      final answer = item['answer'] as String?;

      for (final q in questions) {
        final questionStr = (q as String).toLowerCase();
        if (queryLower == questionStr) {
          return AiIntentMatch(intent: intent, score: 1.0, answer: answer);
        }
        final questionTokens = _tokenizeQuery(questionStr);
        final score = _calculateSimilarity(queryTokens, questionTokens);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = AiIntentMatch(intent: intent, score: score, answer: answer);
        }
      }
    }

    return bestScore > 0.35 ? bestMatch : null;
  }

  List<ScoredResult> _deepSearchScored(
    Map<String, dynamic> section,
    List<String> queryTokens, {
    int depth = 0,
    int maxDepth = 5,
  }) {
    final results = <ScoredResult>[];
    if (depth > maxDepth || section.isEmpty) return results;

    section.forEach((key, value) {
      final keyTokens = _tokenizeQuery(key);
      final keyScore = _calculateSimilarity(queryTokens, keyTokens);

      if (value is String) {
        final valueTokens = _tokenizeQuery(value);
        final valueScore = _calculateSimilarity(queryTokens, valueTokens);
        final score = max(keyScore * 0.7, valueScore);
        if (score > 0.08) {
          results.add(ScoredResult(value, score));
        }
      } else if (value is List) {
        for (final item in value) {
          if (item is String) {
            final itemTokens = _tokenizeQuery(item);
            final itemScore = _calculateSimilarity(queryTokens, itemTokens);
            final score = max(keyScore * 0.5, itemScore);
            if (score > 0.08) {
              results.add(ScoredResult(item, score));
            }
          } else if (item is Map<String, dynamic>) {
            results.addAll(_deepSearchScored(
              item,
              queryTokens,
              depth: depth + 1,
              maxDepth: maxDepth,
            ));
          }
        }
      } else if (value is Map<String, dynamic>) {
        if (keyScore > 0.05) {
          results.addAll(_deepSearchScored(
            value,
            queryTokens,
            depth: depth + 1,
            maxDepth: maxDepth,
          ));
        }
      }
    });

    return results;
  }

  bool _isExpandRequest(String query) {
    final lower = query.trim().toLowerCase();
    return lower == 'expand' ||
        lower == 'more' ||
        lower == 'details' ||
        lower == 'tell me more' ||
        lower == 'go deeper' ||
        lower == 'explain more';
  }

  List<MapEntry<String, double>> _rankTopics(
    List<String> queryTokens,
    List<String> recentTopics,
  ) {
    final topics = _index['topics'] as Map<String, dynamic>? ?? {};
    final scores = <String, double>{};

    for (final entry in topics.entries) {
      final meta = entry.value as Map<String, dynamic>? ?? {};
      final keywords = (meta['keywords'] as List? ?? []).cast<String>();
      final score = _calculateSimilarity(queryTokens, keywords);
      scores[entry.key] = score;
    }

    for (final recent in recentTopics) {
      scores.update(recent, (value) => value + 0.12, ifAbsent: () => 0.12);
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ranked;
  }

  String _formatResults(List<ScoredResult> results) {
    if (results.isEmpty) return '';
    if (results.length == 1) return results.first.text;
    final lines = results.map((item) => '• ${item.text}').join('\n');
    return 'Quick summary:\n$lines';
  }

  List<String> _extractQuestionsFromData(dynamic data) {
    final results = <String>[];
    void walk(dynamic node) {
      if (node is String) {
        final trimmed = node.trim();
        if (trimmed.contains('?') && trimmed.length <= 140) {
          results.add(trimmed);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      } else if (node is Map<String, dynamic>) {
        node.values.forEach(walk);
      }
    }
    walk(data);
    return results;
  }

  String? _pickExample(Map<String, dynamic> topicData) {
    final questions = _extractQuestionsFromData(topicData);
    if (questions.isNotEmpty) {
      questions.shuffle();
      return questions.first;
    }
    final customEntries = topicData['custom_entries'] as List?;
    if (customEntries != null && customEntries.isNotEmpty) {
      final entry = customEntries.whereType<String>().first.trim();
      if (entry.isNotEmpty) {
        return entry.length > 140 ? '${entry.substring(0, 137)}...' : entry;
      }
    }
    return null;
  }

  String _applyTone(String response) {
    final personality =
        _index['assistant_personality'] as Map<String, dynamic>? ?? {};
    final traits = personality['traits'] as List? ?? [];
    if (traits.isEmpty) return response;

    final intros = [
      'Quick take:',
      'Short answer:',
      'Here’s the gist:',
      'Fast breakdown:',
    ];
    final useIntro = response.length > 80 && Random().nextInt(3) == 0;
    final intro = useIntro ? '${intros[Random().nextInt(intros.length)]}\n' : '';
    return '$intro$response';
  }

  String _appendFollowUp(String base, String query, String? category) {
    if (base.isEmpty) return base;
    if (base.contains('?')) return base;
    final followUp = _getFollowUpPrompt(query, category);
    if (followUp == null || followUp.isEmpty) return base;
    return '$base\n\n$followUp';
  }

  String? _getFollowUpPrompt(String query, String? category) {
    final lower = query.toLowerCase();
    if (lower.contains('post')) {
      return 'Want tips for writing posts that get more engagement?';
    }
    if (lower.contains('dm') ||
        lower.contains('message') ||
        lower.contains('chat')) {
      return 'Need help with DM privacy or starting a conversation?';
    }
    if (lower.contains('follow')) {
      return 'Want to manage followers or see how follow notifications work?';
    }
    if (lower.contains('streak')) {
      return 'Want to know how streaks are calculated or how to level up?';
    }
    if (lower.contains('verify') || lower.contains('verified')) {
      return 'Want the verification steps and benefits?';
    }
    if (lower.contains('confession') || lower.contains('room')) {
      return 'Want help finding or joining confession rooms?';
    }
    if (category != null) {
      return 'Want a quick walkthrough or where to find this in the app?';
    }
    return 'Want a quick walkthrough or a tip related to this?';
  }

  bool isBlockedTopic(String query) {
    final securityRules = _index['ai_security_rules'] as Map<String, dynamic>?;
    final blockedTopics = securityRules?['blocked_topics'] as List? ?? [];

    final lowerQuery = query.toLowerCase();
    for (final topic in blockedTopics) {
      if (lowerQuery.contains((topic as String).toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  String getBlockedResponse() {
    final securityRules = _index['ai_security_rules'] as Map<String, dynamic>?;
    return securityRules?['response_to_blocked_topics'] as String? ??
        "I'm sorry, but I can't provide information about that.";
  }

  String _checkGreeting(String query) {
    final greetingsData = _index['greetings'] as Map<String, dynamic>?;
    if (greetingsData == null) return '';
    final triggers = greetingsData['triggers'] as List? ?? [];
    final response = greetingsData['response'] as String?;
    if (response == null) return '';

    final queryLower = query.toLowerCase().trim();
    for (final trigger in triggers) {
      final triggerStr = (trigger as String).toLowerCase();
      if (queryLower == triggerStr ||
          queryLower.split(RegExp(r'\s+')).contains(triggerStr) ||
          queryLower.startsWith(triggerStr)) {
        return response;
      }
    }
    return '';
  }

  String _getDefaultResponse(String query) {
    final queryLower = query.toLowerCase();
    if (queryLower.contains('help') || queryLower.contains('support')) {
      return "I'm here to help! Ask me about posting, messaging, profiles, or anything else in AnonPro.";
    }
    if (queryLower.contains('hi') ||
        queryLower.contains('hello') ||
        queryLower.contains('hey')) {
      return "Hey boss! 👋 Ask me anything about AnonPro.";
    }
    if (queryLower.contains('bug') ||
        queryLower.contains('error') ||
        queryLower.contains('crash')) {
      return "Try restarting the app, checking your connection, or clearing cache. If it keeps failing, reach out through Settings > Help.";
    }
    if (queryLower.contains('privacy') || queryLower.contains('safe')) {
      return "Privacy is core here. You can post anonymously, control DM settings, block/report users, and stay protected.";
    }
    return "Interesting question! Can you be more specific about what you want to do in AnonPro?";
  }

  String _buildClarification(List<MapEntry<String, double>> topics) {
    final suggestions = topics.take(2).map((e) => e.key).toList();
    if (suggestions.isEmpty) {
      return 'Are you asking about posting, messaging, or profile settings?';
    }
    if (suggestions.length == 1) {
      return 'Are you asking about ${suggestions.first}?';
    }
    return 'Do you mean ${suggestions[0]} or ${suggestions[1]}?';
  }

  Future<AiBrainReply> generateReply(
    String query, {
    List<String> recentTopics = const [],
  }) async {
    if (query.trim().isEmpty) {
      return const AiBrainReply(
        text: 'Ask me anything about AnonPro. What would you like to know?',
        topic: null,
        intent: null,
        confidence: 0.0,
      );
    }

    if (isBlockedTopic(query)) {
      return AiBrainReply(
        text: getBlockedResponse(),
        topic: null,
        intent: null,
        confidence: 1.0,
      );
    }

    if (_isExpandRequest(query) && _lastResults.isNotEmpty) {
      final expanded = _formatResults(_lastResults.take(6).toList());
      final response = _applyTone(expanded);
      return AiBrainReply(
        text: response,
        topic: _lastTopic,
        intent: null,
        confidence: 0.7,
      );
    }

    final greeting = _checkGreeting(query);
    if (greeting.isNotEmpty) {
      return AiBrainReply(
        text: greeting,
        topic: null,
        intent: null,
        confidence: 1.0,
      );
    }

    final intentMatch = _classifyIntent(query);
    final queryTokens = _tokenizeQuery(query);
    final rankedTopics = _rankTopics(queryTokens, recentTopics);
    final topTopics = rankedTopics.where((e) => e.value > 0.08).take(2).toList();

    if ((intentMatch == null || intentMatch.score < 0.45) &&
        (topTopics.isEmpty || topTopics.first.value < 0.15)) {
      final clarify = _buildClarification(rankedTopics);
      return AiBrainReply(
        text: _applyTone(clarify),
        topic: null,
        intent: intentMatch,
        confidence: intentMatch?.score ?? 0.1,
      );
    }

    final combinedResults = <String, double>{};
    String? matchedTopic;
    Map<String, dynamic> matchedTopicData = {};

    for (final entry in topTopics) {
      final topic = entry.key;
      matchedTopic ??= topic;
      final topicData = await _repo.loadTopic(topic);
      if (matchedTopicData.isEmpty) {
        matchedTopicData = topicData;
      }
      final results = _deepSearchScored(topicData, queryTokens);
      for (final result in results) {
        combinedResults.update(
          result.text,
          (value) => max(value, result.score),
          ifAbsent: () => result.score,
        );
      }
    }

    final sortedResults = combinedResults.entries
        .map((e) => ScoredResult(e.key, e.value))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (sortedResults.isEmpty && intentMatch?.answer != null) {
      final response = _applyTone(intentMatch!.answer!);
      return AiBrainReply(
        text: _appendFollowUp(response, query, matchedTopic),
        topic: matchedTopic,
        intent: intentMatch,
        confidence: intentMatch.score,
      );
    }

    if (sortedResults.isEmpty) {
      final response = _applyTone(_getDefaultResponse(query));
      return AiBrainReply(
        text: _appendFollowUp(response, query, matchedTopic),
        topic: matchedTopic,
        intent: intentMatch,
        confidence: intentMatch?.score ?? 0.2,
      );
    }

    _lastResults = sortedResults;
    _lastTopic = matchedTopic;

    final shortList = sortedResults.take(2).toList();
    final formatted = _formatResults(shortList);
    var response = _applyTone(_appendFollowUp(formatted, query, matchedTopic));
    final example = matchedTopicData.isNotEmpty ? _pickExample(matchedTopicData) : null;
    if (example != null && !response.contains(example)) {
      response = '$response\n\nExample: $example';
    }
    final moreHint = sortedResults.length > shortList.length
        ? '\n\nSay \"expand\" to see more details.'
        : '';

    return AiBrainReply(
      text: '$response$moreHint',
      topic: matchedTopic,
      intent: intentMatch,
      confidence: sortedResults.first.score,
    );
  }

  Future<List<String>> getSuggestedQuestions({
    List<String> recentTopics = const [],
    int limit = 4,
  }) async {
    final suggestions = <String>{};
    final topics = _index['topics'] as Map<String, dynamic>? ?? {};
    final targetTopics = <String>[
      if (_lastTopic != null) _lastTopic!,
      ...recentTopics,
    ].where((t) => topics.containsKey(t)).toList();

    for (final topic in targetTopics) {
      final topicData = await _repo.loadTopic(topic);
      final questions = _extractQuestionsFromData(topicData);
      questions.shuffle();
      for (final q in questions) {
        suggestions.add(q);
        if (suggestions.length >= limit) break;
      }
      if (suggestions.length >= limit) break;
    }

    if (suggestions.length < limit) {
      final intentQuestions = _index['intent_questions'] as List? ?? [];
      final pool = <String>[];
      for (final item in intentQuestions) {
        if (item is! Map<String, dynamic>) continue;
        final questions = item['questions'] as List? ?? [];
        for (final q in questions) {
          if (q is String && q.contains('?')) {
            pool.add(q);
          }
        }
      }
      pool.shuffle();
      for (final q in pool) {
        suggestions.add(q);
        if (suggestions.length >= limit) break;
      }
    }

    _lastSuggestions = suggestions.toList();
    return _lastSuggestions;
  }
}
