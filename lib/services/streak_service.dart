import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_streak_model.dart';
import '../models/streak_requirements.dart';

class StreakService {
  static final StreakService _instance = StreakService._internal();

  factory StreakService() {
    return _instance;
  }

  StreakService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<StreakRequirements> getStreakRequirements() async {
    try {
      final res = await _supabase
          .from('app_settings')
          .select(
              'streak_required_posts, streak_required_engaged_posts, streak_required_total_engagement, streak_required_avg_likes')
          .single();
      return StreakRequirements.fromMap(res);
    } catch (e) {
      debugPrint('Error loading streak requirements: $e');
      return StreakRequirements.defaults;
    }
  }

  /// Initialize streak for new user
  Future<void> initializeStreak(String userId) async {
    try {
      // First check if it exists
      final existing = await _supabase
          .from('user_streaks')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        return; // Already exists
      }

      // Create new streak record
      await _supabase.from('user_streaks').insert({
        'user_id': userId,
        'current_streak': 0,
        'total_posts': 0,
        'posts_with_engagement': 0,
      });
    } catch (e) {
      debugPrint('Error initializing streak: $e');
      // Don't rethrow - initialization is optional
    }
  }

  /// Get user's streak (auto-initializes if missing)
  Future<UserStreakModel?> getStreak(String userId) async {
    try {
      var res = await _supabase
          .from('user_streaks')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      if (res == null) {
        // Try to initialize
        await initializeStreak(userId);

        // Try to fetch again
        res = await _supabase
            .from('user_streaks')
            .select('*')
            .eq('user_id', userId)
            .maybeSingle();
      }

      if (res == null) return null;
      return UserStreakModel.fromJson(res);
    } catch (e) {
      debugPrint('Error getting streak: $e');
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
      if (streak == null) {
        return false;
      }

      final requirements = await getStreakRequirements();
      final totalEngagement = requirements.totalEngagementRequired > 0
          ? await getTotalEngagement(userId)
          : 0;
      final avgLikes = requirements.avgLikesRequired > 0
          ? await getAverageLikesPerPost(userId)
          : 0.0;

      final isEligible = streak.isEligibleForVerificationWith(
        requirements.totalPostsRequired,
        requirements.engagedPostsRequired,
        requirements.totalEngagementRequired,
        requirements.avgLikesRequired,
        totalEngagement: totalEngagement,
        avgLikes: avgLikes,
      );

      if (!isEligible) {
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

  /// Get user's posts from last 30 days
  Future<List<Map<String, dynamic>>> getPostsHistory(String userId) async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

      final res = await _supabase
          .from('posts')
          .select('id, created_at, likes_count, comments_count')
          .eq('user_id', userId)
          .gte('created_at', thirtyDaysAgo.toIso8601String())
          .order('created_at', ascending: false);

      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error fetching posts history: $e');
      return [];
    }
  }

  /// Get daily posts count for last 30 days
  Future<List<Map<String, int>>> getDailyPostsCount(String userId) async {
    try {
      final posts = await getPostsHistory(userId);
      final dailyMap = <String, int>{};

      for (final post in posts) {
        final date =
            DateTime.parse(post['created_at']).toIso8601String().split('T')[0];
        dailyMap[date] = (dailyMap[date] ?? 0) + 1;
      }

      // Create 30-day range with 0 for days with no posts
      final List<Map<String, int>> dailyList = [];
      for (int i = 29; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = date.toIso8601String().split('T')[0];
        dailyList.add({
          'date': int.parse(
              date.toIso8601String().split('T')[0].replaceAll('-', '')),
          'count': dailyMap[dateStr] ?? 0,
        });
      }

      return dailyList;
    } catch (e) {
      debugPrint('Error calculating daily posts: $e');
      return [];
    }
  }

  /// Get engagement history (likes + comments)
  Future<int> getTotalEngagement(String userId) async {
    try {
      final res = await _supabase
          .from('posts')
          .select('likes_count, comments_count')
          .eq('user_id', userId);

      int totalEngagement = 0;
      for (final post in res) {
        totalEngagement += (post['likes_count'] as int? ?? 0) +
            (post['comments_count'] as int? ?? 0);
      }

      return totalEngagement;
    } catch (e) {
      return 0;
    }
  }

  /// Get average likes per post
  Future<double> getAverageLikesPerPost(String userId) async {
    try {
      final streak = await getStreak(userId);
      if (streak == null || streak.totalPosts == 0) return 0;

      final totalLikes = await _getTotalLikes(userId);
      return totalLikes / streak.totalPosts;
    } catch (e) {
      return 0;
    }
  }

  /// Get total likes (helper)
  Future<int> _getTotalLikes(String userId) async {
    try {
      final res = await _supabase
          .from('posts')
          .select('likes_count')
          .eq('user_id', userId);

      int total = 0;
      for (final post in res) {
        total += post['likes_count'] as int? ?? 0;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  /// Request verification (manual)
  Future<bool> requestVerification(String userId) async {
    try {
      final streak = await getStreak(userId);
      if (streak == null) {
        return false;
      }

      final requirements = await getStreakRequirements();
      final totalEngagement = requirements.totalEngagementRequired > 0
          ? await getTotalEngagement(userId)
          : 0;
      final avgLikes = requirements.avgLikesRequired > 0
          ? await getAverageLikesPerPost(userId)
          : 0.0;

      final isEligible = streak.isEligibleForVerificationWith(
        requirements.totalPostsRequired,
        requirements.engagedPostsRequired,
        requirements.totalEngagementRequired,
        requirements.avgLikesRequired,
        totalEngagement: totalEngagement,
        avgLikes: avgLikes,
      );

      if (!isEligible) {
        return false;
      }

      // Auto-verify if not already
      await _checkAndUnlockVerification(userId);
      return true;
    } catch (e) {
      debugPrint('Error requesting verification: $e');
      return false;
    }
  }

  /// Create a verification announcement post
  Future<String> createVerificationAnnouncement({
    required String userId,
    required String? imageUrl,
  }) async {
    try {
      final res = await _supabase
          .from('posts')
          .insert({
            'user_id': userId,
            'content':
                '🎉 I\'ve unlocked VERIFIED status on AnonPro! 🔥\n\nThanks to the amazing community for the support. Now I can answer questions in Q&A rooms and access exclusive features!',
            'image_url': imageUrl,
            'is_anonymous': false,
            'post_identity_mode': 'public',
          })
          .select()
          .single();

      return res['id'] as String;
    } catch (e) {
      debugPrint('Error creating verification announcement: $e');
      rethrow;
    }
  }
}
