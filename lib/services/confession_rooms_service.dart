import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/confession_room_model.dart';

class ConfessionRoomsService {
  static final ConfessionRoomsService _instance =
      ConfessionRoomsService._internal();

  factory ConfessionRoomsService() {
    return _instance;
  }

  ConfessionRoomsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a new confession room (duration in minutes) and post it to homepage
  Future<String> createRoom({
    required String creatorId,
    required String roomName,
    required int durationMinutes,
    String? rules,
    String? pinnedMessage,
    DateTime? scheduledStartAt,
  }) async {
    try {
      final expiresAt = DateTime.now().add(Duration(minutes: durationMinutes));
      final joinCode = _generateJoinCode();

      // Step 1: Create the confession room
      final res = await _supabase
          .from('confession_rooms')
          .insert({
            'creator_id': creatorId,
            'room_name': roomName,
            'expires_at': expiresAt.toIso8601String(),
            'join_code': joinCode,
            'rules': rules,
            'pinned_message': pinnedMessage,
            'scheduled_start_at': scheduledStartAt?.toIso8601String(),
          })
          .select()
          .single();

      final roomId = res['id'] as String;

      // Step 2: Automatically create a post for the room
      try {
        await _supabase.from('posts').insert({
          'user_id': creatorId,
          'content':
              '🎭 Started a new confession room: $roomName\n\nSearch join code: $joinCode to join!',
          'image_url': null,
          'is_anonymous': false,
          'post_identity_mode': 'public',
          'post_type': 'confession_room',
          'related_confession_room_id': roomId,
        });
      } catch (e) {
        // Log the post creation error but don't fail the room creation
        print('Warning: Failed to create post for confession room: $e');
      }

      return roomId;
    } catch (e) {
      rethrow;
    }
  }

  String _generateJoinCode() {
    final random = DateTime.now().microsecondsSinceEpoch % 10000;
    return random.toString().padLeft(4, '0');
  }

  /// Get room by join code
  Future<ConfessionRoomModel?> getRoomByCode(String code) async {
    try {
      final res = await _supabase
          .from('confession_rooms')
          .select('*')
          .eq('join_code', code)
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String())
          .maybeSingle();

      if (res == null) return null;
      return ConfessionRoomModel.fromJson(res);
    } catch (e) {
      return null;
    }
  }

  /// Get all active rooms created by a user
  Future<List<ConfessionRoomModel>> getUserRooms(String creatorId) async {
    try {
      final res = await _supabase
          .from('confession_rooms')
          .select('*')
          .eq('creator_id', creatorId)
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);

      return (res as List).map((r) => ConfessionRoomModel.fromJson(r)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Get all active rooms
  Future<List<ConfessionRoomModel>> getActiveRooms() async {
    try {
      final res = await _supabase
          .from('confession_rooms')
          .select('*')
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);

      return (res as List).map((r) => ConfessionRoomModel.fromJson(r)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Get a specific room
  Future<ConfessionRoomModel?> getRoom(String roomId) async {
    try {
      final res = await _supabase
          .from('confession_rooms')
          .select('*')
          .eq('id', roomId)
          .maybeSingle();

      if (res == null) return null;
      return ConfessionRoomModel.fromJson(res);
    } catch (e) {
      return null;
    }
  }

  /// Send a message to a room
  Future<String> sendMessage({
    required String roomId,
    required String message,
  }) async {
    try {
      final res = await _supabase
          .from('room_messages')
          .insert({
            'room_id': roomId,
            'message': message,
          })
          .select()
          .single();

      return res['id'] as String;
    } catch (e) {
      rethrow;
    }
  }

  /// Get messages for a room
  Future<List<Map<String, dynamic>>> getRoomMessages(String roomId) async {
    try {
      final res = await _supabase
          .from('room_messages')
          .select('*')
          .eq('room_id', roomId)
          .order('created_at', ascending: true);

      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      rethrow;
    }
  }

  /// Delete/expire a room (only creator)
  Future<void> closeRoom(String roomId) async {
    try {
      await _supabase
          .from('confession_rooms')
          .update({'is_active': false}).eq('id', roomId);
    } catch (e) {
      rethrow;
    }
  }

  /// Auto-expire rooms (cleanup background job)
  Future<void> expireOldRooms() async {
    try {
      await _supabase.from('confession_rooms').update({'is_active': false}).lt(
          'expires_at', DateTime.now().toIso8601String());
    } catch (e) {
      rethrow;
    }
  }

  /// Subscribe to room messages in real-time
  RealtimeChannel subscribeToRoomMessages(String roomId) {
    return _supabase
        .channel('room:$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            // Handled by the caller
          },
        )
        .subscribe();
  }

  /// Subscribe to room creation/expiration
  RealtimeChannel subscribeToUserRooms(String creatorId) {
    return _supabase
        .channel('user_rooms:$creatorId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'confession_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'creator_id',
            value: creatorId,
          ),
          callback: (payload) {
            // Handled by the caller
          },
        )
        .subscribe();
  }
}
