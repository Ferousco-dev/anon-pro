import 'package:supabase_flutter/supabase_flutter.dart';

class DirectMessageService {
  static final DirectMessageService _instance =
      DirectMessageService._internal();

  factory DirectMessageService() {
    return _instance;
  }

  DirectMessageService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Check if user can send DM to another user based on DM privacy settings
  Future<bool> canSendDM({
    required String senderId,
    required String recipientId,
  }) async {
    try {
      // Get recipient's DM privacy setting
      final recipientRes = await _supabase
          .from('users')
          .select('dm_privacy, is_verified')
          .eq('id', recipientId)
          .single();

      final dmPrivacy = recipientRes['dm_privacy'] as String? ?? 'everyone';

      // If privacy is 'everyone', all can message
      if (dmPrivacy == 'everyone') {
        return true;
      }

      // If privacy is 'verified_only', sender must be verified
      if (dmPrivacy == 'verified_only') {
        final senderRes = await _supabase
            .from('users')
            .select('is_verified')
            .eq('id', senderId)
            .single();

        return senderRes['is_verified'] as bool? ?? false;
      }

      // If privacy is 'followers_only', sender must be following recipient
      if (dmPrivacy == 'followers_only') {
        final follow = await _supabase
            .from('follows')
            .select('id')
            .eq('follower_id', senderId)
            .eq('following_id', recipientId)
            .maybeSingle();

        return follow != null;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Send a direct message
  Future<String> sendMessage({
    required String senderId,
    required String recipientId,
    required String content,
    String? imageUrl,
  }) async {
    try {
      // First check privacy
      final canSend =
          await canSendDM(senderId: senderId, recipientId: recipientId);
      if (!canSend) {
        throw Exception(
            'Cannot send message: recipient privacy settings restrict access');
      }

      // Insert message
      final res = await _supabase
          .from('messages')
          .insert({
            'sender_id': senderId,
            'recipient_id': recipientId,
            'content': content,
            'image_url': imageUrl,
            'is_read': false,
          })
          .select()
          .single();

      return res['id'] as String;
    } catch (e) {
      rethrow;
    }
  }

  /// Get conversation between two users (messages with privacy check)
  Future<List<Map<String, dynamic>>> getConversation({
    required String userId1,
    required String userId2,
    int limit = 50,
  }) async {
    try {
      final canAccess =
          await canSendDM(senderId: userId1, recipientId: userId2);
      if (!canAccess) {
        throw Exception('No access to this conversation');
      }

      // Get messages where userId1 is sender and userId2 is recipient
      final messages1 = await _supabase
          .from('messages')
          .select('*')
          .eq('sender_id', userId1)
          .eq('recipient_id', userId2);

      // Get messages where userId2 is sender and userId1 is recipient
      final messages2 = await _supabase
          .from('messages')
          .select('*')
          .eq('sender_id', userId2)
          .eq('recipient_id', userId1);

      // Combine and sort by created_at
      final allMessages = [...messages1, ...messages2];
      allMessages.sort((a, b) {
        final dateA = DateTime.parse(a['created_at'] as String);
        final dateB = DateTime.parse(b['created_at'] as String);
        return dateB.compareTo(dateA);
      });

      return allMessages.cast<Map<String, dynamic>>().take(limit).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Mark messages as read
  Future<void> markAsRead(List<String> messageIds) async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true}).inFilter('id', messageIds);
    } catch (e) {
      rethrow;
    }
  }

  /// Get user's DM privacy setting
  Future<String> getDMPrivacySetting(String userId) async {
    try {
      final res = await _supabase
          .from('users')
          .select('dm_privacy')
          .eq('id', userId)
          .single();

      return res['dm_privacy'] as String? ?? 'everyone';
    } catch (e) {
      return 'everyone';
    }
  }

  /// Update DM privacy setting
  Future<void> setDMPrivacy({
    required String userId,
    required String setting, // 'everyone', 'verified_only', 'followers_only'
  }) async {
    try {
      if (!['everyone', 'verified_only', 'followers_only'].contains(setting)) {
        throw Exception('Invalid DM privacy setting');
      }

      await _supabase
          .from('users')
          .update({'dm_privacy': setting}).eq('id', userId);
    } catch (e) {
      rethrow;
    }
  }

  /// Subscribe to new messages
  RealtimeChannel subscribeToMessages(String userId) {
    return _supabase
        .channel('messages:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (payload) {
            // Handled by caller
          },
        )
        .subscribe();
  }
}
