import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class BroadcastMessage {
  final String id;
  final String emoji;
  final String type; // 'announcement', 'update', 'warning', 'event'
  final String title;
  final String body;
  final String typeColor; // hex color code

  BroadcastMessage({
    required this.id,
    required this.emoji,
    required this.type,
    required this.title,
    required this.body,
    required this.typeColor,
  });

  factory BroadcastMessage.fromJson(Map<String, dynamic> json) {
    return BroadcastMessage(
      id: json['id'] as String,
      emoji: json['emoji'] as String? ?? '📢',
      type: json['broadcast_type'] as String? ?? 'announcement',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      typeColor: json['type_color'] as String? ?? '#007AFF',
    );
  }
}

class BroadcastService {
  static final BroadcastService _instance = BroadcastService._internal();
  factory BroadcastService() => _instance;
  BroadcastService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  Set<String> _seenBroadcasts = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _loadSeenBroadcasts();
    _initialized = true;
  }

  Future<void> _loadSeenBroadcasts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenList = prefs.getStringList('seen_broadcasts') ?? [];
      _seenBroadcasts = Set<String>.from(seenList);
    } catch (e) {
      print('Error loading seen broadcasts: $e');
    }
  }

  Future<List<BroadcastMessage>> getUnseenBroadcasts() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) return [];

      // Get all active broadcasts
      final response = await _supabase
          .from('broadcasts')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(50);

      final List<BroadcastMessage> broadcasts = [];

      for (final broadcast in response as List) {
        final broadcastId = broadcast['id'] as String;

        // Check if user has already viewed this broadcast
        final hasViewed = await _supabase
            .from('broadcast_views')
            .select()
            .eq('broadcast_id', broadcastId)
            .eq('user_id', currentUser.id)
            .maybeSingle();

        if (hasViewed == null && !_seenBroadcasts.contains(broadcastId)) {
          broadcasts.add(
              BroadcastMessage.fromJson(broadcast as Map<String, dynamic>));
        }
      }

      return broadcasts;
    } catch (e) {
      print('Error fetching broadcasts: $e');
      return [];
    }
  }

  Future<void> markAsSeen(String broadcastId) async {
    _seenBroadcasts.add(broadcastId);
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) return;

      // Record in database
      await _supabase.from('broadcast_views').insert({
        'broadcast_id': broadcastId,
        'user_id': currentUser.id,
      });

      // Save locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('seen_broadcasts', _seenBroadcasts.toList());
    } catch (e) {
      print('Error saving seen broadcast: $e');
    }
  }

  void dispose() {}
}

final broadcastService = BroadcastService();
