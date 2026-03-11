import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A fast, JSON-based caching layer using SharedPreferences.
///
/// Strategy: **cache-first, network-second**
/// 1. On load, instantly return cached data (< 10ms)
/// 2. Fetch from Supabase in background
/// 3. Merge & save new data to cache
///
/// This keeps loading under 2s and reduces Supabase traffic dramatically.
class FeedCacheService {
  FeedCacheService._();
  static final FeedCacheService _instance = FeedCacheService._();
  factory FeedCacheService() => _instance;

  SharedPreferences? _prefs;

  // Cache key constants
  static const String _homeFeedKey = 'cache_home_feed';
  static const String _anonFeedKey = 'cache_anon_feed';
  static const String _notificationsKey = 'cache_notifications';
  static const String _profilePrefix = 'cache_profile_';
  static const String _profilePostsPrefix = 'cache_profile_posts_';
  static const String _conversationsKey = 'cache_conversations';
  static const String _currentUserKey = 'cache_current_user';
  static const String _followingIdsKey = 'cache_following_ids';
  static const String _timestampSuffix = '_ts';

  // Cache TTL (time-to-live) in seconds
  static const int _feedTTL = 120;         // 2 minutes for feeds
  static const int _profileTTL = 300;      // 5 minutes for profiles
  static const int _notifTTL = 180;        // 3 minutes for notifications
  static const int _conversationsTTL = 60; // 1 minute for conversations
  static const int _userTTL = 600;         // 10 minutes for current user

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ═══════════════════════ GENERIC HELPERS ═══════════════════════

  Future<void> _saveJsonList(String key, List<Map<String, dynamic>> data) async {
    final prefs = await _preferences;
    final jsonStr = jsonEncode(data);
    await prefs.setString(key, jsonStr);
    await prefs.setInt('$key$_timestampSuffix', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _saveJsonMap(String key, Map<String, dynamic> data) async {
    final prefs = await _preferences;
    final jsonStr = jsonEncode(data);
    await prefs.setString(key, jsonStr);
    await prefs.setInt('$key$_timestampSuffix', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _saveStringList(String key, List<String> data) async {
    final prefs = await _preferences;
    await prefs.setStringList(key, data);
    await prefs.setInt('$key$_timestampSuffix', DateTime.now().millisecondsSinceEpoch);
  }

  List<Map<String, dynamic>>? _getJsonList(String key) {
    if (_prefs == null) return null;
    final jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return null;
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _getJsonMap(String key) {
    if (_prefs == null) return null;
    final jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    } catch (_) {
      return null;
    }
  }

  bool _isCacheValid(String key, int ttlSeconds) {
    if (_prefs == null) return false;
    final ts = _prefs!.getInt('$key$_timestampSuffix');
    if (ts == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    return age < (ttlSeconds * 1000);
  }

  // ═══════════════════════ HOME FEED ═══════════════════════

  Future<void> saveHomeFeed(List<Map<String, dynamic>> posts) async {
    await _saveJsonList(_homeFeedKey, posts);
  }

  List<Map<String, dynamic>>? getHomeFeed() {
    return _getJsonList(_homeFeedKey);
  }

  bool isHomeFeedValid() => _isCacheValid(_homeFeedKey, _feedTTL);

  // ═══════════════════════ ANONYMOUS FEED ═══════════════════════

  Future<void> saveAnonFeed(List<Map<String, dynamic>> posts) async {
    await _saveJsonList(_anonFeedKey, posts);
  }

  List<Map<String, dynamic>>? getAnonFeed() {
    return _getJsonList(_anonFeedKey);
  }

  bool isAnonFeedValid() => _isCacheValid(_anonFeedKey, _feedTTL);

  // ═══════════════════════ NOTIFICATIONS ═══════════════════════

  Future<void> saveNotifications(List<Map<String, dynamic>> notifs) async {
    await _saveJsonList(_notificationsKey, notifs);
  }

  List<Map<String, dynamic>>? getNotifications() {
    return _getJsonList(_notificationsKey);
  }

  bool isNotificationsValid() => _isCacheValid(_notificationsKey, _notifTTL);

  // ═══════════════════════ FOLLOWING IDS ═══════════════════════

  Future<void> saveFollowingIds(List<String> ids) async {
    await _saveStringList(_followingIdsKey, ids);
  }

  List<String>? getFollowingIds() {
    if (_prefs == null) return null;
    return _prefs!.getStringList(_followingIdsKey);
  }

  // ═══════════════════════ PROFILE ═══════════════════════

  Future<void> saveProfile(String userId, Map<String, dynamic> profile) async {
    await _saveJsonMap('$_profilePrefix$userId', profile);
  }

  Map<String, dynamic>? getProfile(String userId) {
    return _getJsonMap('$_profilePrefix$userId');
  }

  bool isProfileValid(String userId) =>
      _isCacheValid('$_profilePrefix$userId', _profileTTL);

  Future<void> saveProfilePosts(
      String userId, List<Map<String, dynamic>> posts) async {
    await _saveJsonList('$_profilePostsPrefix$userId', posts);
  }

  List<Map<String, dynamic>>? getProfilePosts(String userId) {
    return _getJsonList('$_profilePostsPrefix$userId');
  }

  bool isProfilePostsValid(String userId) =>
      _isCacheValid('$_profilePostsPrefix$userId', _profileTTL);

  // ═══════════════════════ CONVERSATIONS ═══════════════════════

  Future<void> saveConversations(List<Map<String, dynamic>> convos) async {
    await _saveJsonList(_conversationsKey, convos);
  }

  List<Map<String, dynamic>>? getConversations() {
    return _getJsonList(_conversationsKey);
  }

  bool isConversationsValid() =>
      _isCacheValid(_conversationsKey, _conversationsTTL);

  // ═══════════════════════ CURRENT USER ═══════════════════════

  Future<void> saveCurrentUser(Map<String, dynamic> user) async {
    await _saveJsonMap(_currentUserKey, user);
  }

  Map<String, dynamic>? getCurrentUser() {
    return _getJsonMap(_currentUserKey);
  }

  bool isCurrentUserValid() => _isCacheValid(_currentUserKey, _userTTL);

  // ═══════════════════════ INIT & CLEAR ═══════════════════════

  /// Call this once at app startup to pre-warm SharedPreferences
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> clearAll() async {
    final prefs = await _preferences;
    final keys = prefs.getKeys().where((k) => k.startsWith('cache_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  Future<void> clearFeedCaches() async {
    final prefs = await _preferences;
    await prefs.remove(_homeFeedKey);
    await prefs.remove('$_homeFeedKey$_timestampSuffix');
    await prefs.remove(_anonFeedKey);
    await prefs.remove('$_anonFeedKey$_timestampSuffix');
  }
}
