import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_message.dart';
import 'ai_brain_engine.dart';
import 'ai_knowledge_repository.dart';

class AiChatService extends ChangeNotifier {
  static const String _boxPrefix = 'ai_chat_history';
  static const String _recentTopicsPrefix = 'ai_recent_topics';
  static const int _recentTopicsLimit = 5;

  late Box<AiMessage> _chatBox;
  late AiKnowledgeRepository _knowledgeRepo;
  late AIBrainEngine _brain;
  String? _activeBoxName;
  List<String> _recentTopics = [];
  List<String> _suggestedQuestions = [];

  bool _isInit = false;
  bool _isTyping = false;
  bool _hasGreeted = false;

  bool get isInitialized => _isInit;
  bool get isTyping => _isTyping;
  List<String> getSuggestedQuestions() => _suggestedQuestions;

  // Initialize Hive and AI Brain
  Future<void> init() async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    final nextBoxName = '$_boxPrefix\_$userId';
    if (_isInit && _activeBoxName == nextBoxName) return;

    // Initialize Hive and open box
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(AiMessageAdapter());
    }
    if (_isInit && _chatBox.isOpen) {
      await _chatBox.close();
    }
    _chatBox = await Hive.openBox<AiMessage>(nextBoxName);
    _activeBoxName = nextBoxName;
    _hasGreeted = false;

    try {
      await _loadRecentTopics(userId);
      _knowledgeRepo = AiKnowledgeRepository();
      await _knowledgeRepo.loadIndex();
      await _knowledgeRepo.refreshRemoteEntries();
      _brain = AIBrainEngine(_knowledgeRepo);
      await _brain.init();

      debugPrint("✓ Knowledge base loaded successfully");
      debugPrint("✓ AI Brain Engine initialized with intelligent search");
    } catch (e) {
      debugPrint("Failed to load knowledge base: $e");
      _knowledgeRepo = AiKnowledgeRepository();
      await _knowledgeRepo.loadIndex();
      await _knowledgeRepo.refreshRemoteEntries();
      _brain = AIBrainEngine(_knowledgeRepo);
      await _brain.init();
    }

    notifyListeners();
    _isInit = true;
  }

  // Get local chat history for UI Display
  List<AiMessage> getChatHistory() {
    if (!_isInit || !_chatBox.isOpen) return [];
    return _chatBox.values.toList().cast<AiMessage>();
  }

  // Send message with INTELLIGENT BRAIN PROCESSING
  Future<String> sendMessage(String text) async {
    if (!_isInit) {
      throw Exception('AiChatService not initialized');
    }
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';

    // Save user message
    final userMsg = AiMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    await _chatBox.add(userMsg);

    _isTyping = true;
    notifyListeners();

    try {
      // Use the intelligent BRAIN to process the question
      // Step 1: Check for blocked topics
      if (_brain.isBlockedTopic(text)) {
        final blockedReply = _brain.getBlockedResponse();

        final aiMsg = AiMessage(
          text: blockedReply,
          isUser: false,
          timestamp: DateTime.now(),
        );
        await _chatBox.add(aiMsg);

        _isTyping = false;
        notifyListeners();
        return blockedReply;
      }

      // Step 2: Use BRAIN to intelligently search knowledge base
      final reply = await _brain.generateReply(
        text,
        recentTopics: _recentTopics,
      );
      final replyText = reply.text;

      if (reply.topic != null && reply.topic!.isNotEmpty) {
        await _updateRecentTopics(userId, reply.topic!);
      }
      _suggestedQuestions =
          await _brain.getSuggestedQuestions(recentTopics: _recentTopics);

      // Step 3: Save AI reply
      final aiMsg = AiMessage(
        text: replyText,
        isUser: false,
        timestamp: DateTime.now(),
      );
      await _chatBox.add(aiMsg);

      _isTyping = false;
      notifyListeners();

      return replyText;
    } catch (e) {
      debugPrint('AI Chat Error: $e');

      final errorMsg = AiMessage(
        text: 'Omo, something went wrong. Try again later, abeg.',
        isUser: false,
        timestamp: DateTime.now(),
      );
      await _chatBox.add(errorMsg);

      _isTyping = false;
      notifyListeners();
      return 'Omo, something went wrong. Try again later, abeg.';
    }
  }

  // Generate dynamic greeting based on time
  String getGreeting(String? username) {
    if (_hasGreeted) return "";

    final hour = DateTime.now().hour;
    String timeOfDay;

    if (hour < 12) {
      timeOfDay = 'morning';
    } else if (hour < 17) {
      timeOfDay = 'afternoon';
    } else {
      timeOfDay = 'evening';
    }

    final name = username != null ? '@$username' : 'boss';
    _hasGreeted = true;

    return 'Hey yooo wassup $name 😄\nGood $timeOfDay.\nAsk me anything about AnonPro!';
  }

  // Clear chat history
  Future<void> clearHistory() async {
    await _chatBox.clear();
    _hasGreeted = false;
    _suggestedQuestions = [];
    notifyListeners();
  }

  Future<void> _loadRecentTopics(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    _recentTopics =
        prefs.getStringList('$_recentTopicsPrefix\_$userId') ?? [];
  }

  Future<void> _updateRecentTopics(String userId, String topic) async {
    _recentTopics.remove(topic);
    _recentTopics.insert(0, topic);
    if (_recentTopics.length > _recentTopicsLimit) {
      _recentTopics = _recentTopics.sublist(0, _recentTopicsLimit);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_recentTopicsPrefix\_$userId', _recentTopics);
  }
}
