import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_streak_model.dart';

class StreakService {
  static final StreakService _instance = StreakService._internal();

  factory StreakService() {
    return _instance;
  }

  StreakService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Initialize streak for new user
  Future<void> initializeStreak(String userId) async {
    try {
      await _supabase.from('user_streaks').insert({
        'user_id': userId,
        'current_streak': 0,
        'total_posts': 0,
        'posts_with_engagement': 0,
      });
    } catch (e) {
      // Already exists
    }
  }

  /// Get user's streak
  Future<UserStreakModel?> getStreak(String userId) async {
    try {
      final res = await _supabase
          .from('user_streaks')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      if (res == null) return null;
      return UserStreakModel.fromJson(res);
    } catch (e) {
      return null;
    }
  }

  /// Record a new post (both anonymous and normal)
  Future<void> recordPost({
    required String userId,
    required bool hasEngagement, // true if post has likes/comments already
  }) async {
    try {
      final streak = await getStreak(userId);
      if (streak == null) {
        await initializeStreak(userId);
      }

      final today = DateTime.now();
      final update = {
        'total_posts': (streak?.totalPosts ?? 0) + 1,
        'posts_with_engagement': hasEngagement
            ? (streak?.postsWithEngagement ?? 0) + 1
            : (streak?.postsWithEngagement ?? 0),
        'last_post_date': today.toString().split(' ')[0],
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('user_streaks').update(update).eq('user_id', userId);

      // Check if eligible for verification
      await _checkAndUnlockVerification(userId);
    } catch (e) {
      debugPrint('Error recording post: $e');
    }
  }

  /// Check if user qualifies for verification and unlock if eligible
  Future<bool> _checkAndUnlockVerification(String userId) async {
    try {
      final streak = await getStreak(userId);
      if (streak == null || !streak.isEligibleForVerification) {
        return false;
      }

      // Get user to check if already verified
      final userRes = await _supabase
          .from('users')
          .select('is_verified')
          .eq('id', userId)
          .single();

      final isVerified = userRes['is_verified'] as bool? ?? false;
      if (isVerified) {
        return false; // Already verified
      }

      // Auto-verify the user
      await _supabase.from('users').update({
        'is_verified': true,
        'verified_at': DateTime.now().toIso8601String(),
        'verification_level': 'verified',
      }).eq('id', userId);

      // Record milestone
      await _supabase.from('streak_milestones').insert({
        'user_id': userId,
        'milestone_type': 'verified_unlocked',
        'description':
            'Automatically verified after ${streak.totalPosts} posts with high engagement',
        'verified_date': DateTime.now().toIso8601String(),
      });

      // Send congratulations notification
      await _sendCongratulationsNotification(userId);

      return true;
    } catch (e) {
      debugPrint('Error checking verification: $e');
      return false;
    }
  }

  /// Send congratulations notification
  Future<void> _sendCongratulationsNotification(String userId) async {
    try {
      await _supabase.from('verification_notifications').insert({
        'user_id': userId,
        'notification_type': 'verified_unlocked',
        'title': '🎉 You\'re Verified!',
        'message':
            'Congratulations! Your active participation has unlocked verified status on AnonPro. You now have access to exclusive features like Q&A and Confession Rooms!',
        'is_read': false,
      });
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  /// Get user's notifications
  Future<List<VerificationNotificationModel>> getNotifications(
      String userId) async {
    try {
      final res = await _supabase
          .from('verification_notifications')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (res as List)
          .map((n) => VerificationNotificationModel.fromJson(n))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _supabase
          .from('verification_notifications')
          .update({'is_read': true}).eq('id', notificationId);
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  /// Get unread notifications count
  Future<int> getUnreadNotificationsCount(String userId) async {
    try {
      final res = await _supabase
          .from('verification_notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      return res.length;
    } catch (e) {
      return 0;
    }
  }

  /// Force post the "I'm now verified" announcement
  Future<String> createVerificationAnnouncement({
    required String userId,
    required String? imageUrl,
  }) async {
    try {
      final res = await _supabase
          .from('posts')
          .insert({
            'user_id': userId,
            'content': '🎉 I\'m now a verified user on AnonPro! 🔥',
            'image_url': imageUrl,
            'is_anonymous': false,
            'post_identity_mode': 'public',
          })
          .select()
          .single();

      return res['id'] as String;
    } catch (e) {
      rethrow;
    }
  }

  /// Get verification progress for user
  Future<int> getVerificationProgress(String userId) async {
    final streak = await getStreak(userId);
    return streak?.verificationProgress ?? 0;
  }
}
