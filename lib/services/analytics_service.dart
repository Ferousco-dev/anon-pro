import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_analytics_model.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();

  factory AnalyticsService() {
    return _instance;
  }

  AnalyticsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get user's analytics
  Future<UserAnalyticsModel?> getAnalytics(String userId) async {
    try {
      final res = await _supabase
          .from('user_analytics')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      if (res == null) return null;
      return UserAnalyticsModel.fromJson(res);
    } catch (e) {
      return null;
    }
  }

  /// Initialize analytics for a new user
  Future<void> initializeAnalytics(String userId) async {
    try {
      await _supabase.from('user_analytics').insert({
        'user_id': userId,
        'profile_views': 0,
        'post_views': 0,
        'likes_received': 0,
        'comments_received': 0,
      });
    } catch (e) {
      // Row might already exist
    }
  }

  /// Record a profile view
  Future<void> recordProfileView(String userId) async {
    try {
      final analytics = await getAnalytics(userId);
      if (analytics == null) {
        await initializeAnalytics(userId);
      }

      await _supabase.rpc(
        'increment_profile_views',
        params: {'p_user_id': userId},
      );
    } catch (e) {
      // Fallback: just skip
    }
  }

  /// Record post views
  Future<void> recordPostViews(String userId, int count) async {
    try {
      await _supabase.from('user_analytics').update(
          {'post_views': '`post_views` + $count'}).eq('user_id', userId);
    } catch (e) {
      // Skip
    }
  }

  /// Record likes received (usually done via trigger)
  Future<void> recordLikesReceived(String userId, int count) async {
    try {
      await _supabase
          .from('user_analytics')
          .update({'likes_received': '`likes_received` + $count'}).eq(
              'user_id', userId);
    } catch (e) {
      // Skip
    }
  }

  /// Record comments received (usually done via trigger)
  Future<void> recordCommentsReceived(String userId, int count) async {
    try {
      await _supabase
          .from('user_analytics')
          .update({'comments_received': '`comments_received` + $count'}).eq(
              'user_id', userId);
    } catch (e) {
      // Skip
    }
  }

  /// Get top performing metrics for a user
  Map<String, dynamic> getMetricsSummary(UserAnalyticsModel analytics) {
    return {
      'profileViews': analytics.profileViews,
      'postViews': analytics.postViews,
      'totalEngagement': analytics.totalEngagement,
      'avgEngagementPerPost': analytics.postViews > 0
          ? analytics.totalEngagement / analytics.postViews
          : 0,
    };
  }
}
