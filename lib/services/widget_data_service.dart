import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bridges Flutter app data → native iOS/Android home screen widgets.
class WidgetDataService {
  static const String _appGroupId = 'group.com.ferous.anonpro';
  static const String _androidWidgetName = 'AnonProWidgetProvider';
  static const String _iOSWidgetName = 'AnonProWidget';

  // Shared keys (must match native widget code)
  static const String keyNewPostsCount        = 'new_posts_count';
  static const String keyAnonConfessionsCount  = 'anon_confessions_count';
  static const String keyUnreadMessagesCount   = 'unread_messages_count';
  static const String keyLatestAnonPreview     = 'latest_anon_preview';
  static const String keyLastUpdated           = 'last_updated';
  static const String keyUserDisplayName       = 'user_display_name';
  static const String keyUserAvatarUrl         = 'user_avatar_url';
  static const String keyRecentPostsJson       = 'recent_posts_json'; // ← NEW

  static Future<void> initialize() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      HomeWidget.registerInteractivityCallback(interactivityCallback);
    } catch (e) {
      debugPrint('WidgetDataService: init error: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> interactivityCallback(Uri? uri) async {
    debugPrint('Widget tapped with URI: $uri');
  }

  /// Fetch live counts + recent posts from Supabase and push to native widgets.
  static Future<void> updateWidgetData() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Recent posts (feed) — up to 20, for Gmail-style list
      List<Map<String, dynamic>> recentPostsData = [];
      int newPostsCount = 0;
      int anonCount = 0;
      String latestAnonPreview = 'No new confessions';

      try {
        final postsResp = await supabase
            .from('posts')
            .select('id, content, is_anonymous, created_at, users(display_name, alias)')
            .order('created_at', ascending: false)
            .limit(20);

        final posts = List<Map<String, dynamic>>.from(postsResp as List);

        // Build serialisable list for the widget
        for (final p in posts) {
          final user = p['users'] as Map<String, dynamic>?;
          final displayName = (user?['display_name'] as String?)?.trim() ?? 
                              (user?['alias'] as String?) ?? 'Anonymous';
          final isAnon = p['is_anonymous'] == true;
          final content = (p['content'] as String?) ?? '';
          final createdAt = p['created_at'] as String? ?? '';

          // Human-readable time
          String timeAgo = '';
          try {
            final parsed = DateTime.parse(createdAt).toLocal();
            final diff = DateTime.now().difference(parsed);
            if (diff.inMinutes < 1) timeAgo = 'now';
            else if (diff.inMinutes < 60) timeAgo = '${diff.inMinutes}m';
            else if (diff.inHours < 24) timeAgo = '${diff.inHours}h';
            else timeAgo = '${diff.inDays}d';
          } catch (_) {}

          recentPostsData.add({
            'author': isAnon ? 'Anonymous' : displayName,
            'initial': isAnon ? '?' : displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
            'content': content.length > 100 ? '${content.substring(0, 100)}...' : content,
            'timeAgo': timeAgo,
            'isAnon': isAnon,
          });
        }

        // Count last-24h
        newPostsCount = posts.where((p) {
          try {
            return DateTime.now().difference(DateTime.parse(p['created_at'])).inHours < 24;
          } catch (_) { return false; }
        }).length;

        anonCount = posts.where((p) => p['is_anonymous'] == true).length;

        // Latest anon preview
        final latestAnon = posts.firstWhere(
          (p) => p['is_anonymous'] == true, 
          orElse: () => {},
        );
        if (latestAnon.isNotEmpty) {
          final c = latestAnon['content'] as String? ?? '';
          latestAnonPreview = c.length > 80 ? '${c.substring(0, 80)}...' : c;
        }
      } catch (e) {
        debugPrint('WidgetDataService: posts fetch error: $e');
      }

      // 2. Unread messages
      int unreadCount = 0;
      try {
        final msgResp = await supabase
            .from('messages')
            .select('id')
            .neq('sender_id', userId)
            .eq('is_read', false)
            .count(CountOption.exact);
        unreadCount = msgResp.count;
      } catch (_) {}

      // 3. User info
      String displayName = 'User';
      String avatarUrl = '';
      try {
        final userRow = await supabase
            .from('users')
            .select('display_name, alias, profile_image_url')
            .eq('id', userId)
            .maybeSingle();
        if (userRow != null) {
          displayName = userRow['display_name'] ?? userRow['alias'] ?? 'User';
          avatarUrl = userRow['profile_image_url'] ?? '';
        }
      } catch (_) {}

      // 4. Write to home_widget shared store
      final recentPostsJson = jsonEncode(recentPostsData);

      await Future.wait([
        HomeWidget.saveWidgetData(keyNewPostsCount, newPostsCount),
        HomeWidget.saveWidgetData(keyAnonConfessionsCount, anonCount),
        HomeWidget.saveWidgetData(keyUnreadMessagesCount, unreadCount),
        HomeWidget.saveWidgetData(keyLatestAnonPreview, latestAnonPreview),
        HomeWidget.saveWidgetData(keyLastUpdated, DateTime.now().toIso8601String()),
        HomeWidget.saveWidgetData(keyUserDisplayName, displayName),
        HomeWidget.saveWidgetData(keyUserAvatarUrl, avatarUrl),
        HomeWidget.saveWidgetData(keyRecentPostsJson, recentPostsJson),
      ]);

      // 5. Tell native widgets to refresh
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
        iOSName: _iOSWidgetName,
      );


    } catch (e) {
      debugPrint('WidgetDataService: update error: $e');
    }
  }
}
