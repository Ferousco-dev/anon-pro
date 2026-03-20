import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserActivityService {
  static final UserActivityService _instance = UserActivityService._internal();
  factory UserActivityService() => _instance;
  UserActivityService._internal();

  Future<void> updateLastSeen() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      await client.from('user_activity').upsert(
        {
          'user_id': userId,
          'last_seen_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id',
      );
    } on AssertionError {
      // Supabase not initialized yet; skip until it is ready.
    } catch (e) {
      debugPrint('Failed to update last seen: $e');
    }
  }
}
