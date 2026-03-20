import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // For supabase client
import '../utils/app_logger.dart';
import '../utils/app_config.dart';
import '../screens/post/post_detail_screen.dart';
import '../models/chat_model.dart';
import '../screens/inbox/conversation_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  bool _initialized = false;
  String? _fcmToken;
  static const int _dailyMotivationBaseId = 9100;
  static const int _dailyMotivationDays = 7;
  static const int _inactivityReminderId = 9200;
  static const int _inactivityDays = 7;
  static const String _dmReplyActionId = 'dm_reply';
  static const String _commentActionId = 'post_comment';
  static const String _newPostsChannelId = 'new_posts';
  static const String _postSoundAndroid = 'bamboo';
  static const String _postSoundIos = 'bamboo.m4r';
  static const String _globalTopic = 'all_users';
  static const String _broadcastTopic = 'broadcasts';
  static const Duration _navRetryDelay = Duration(milliseconds: 350);
  static const int _navRetryMax = 10;

  Timer? _navRetryTimer;
  Map<String, dynamic>? _pendingNavigation;
  int _navRetryCount = 0;
  String? _lastNavigationMessageId;

  static const List<String> _motivationQuotes = [
    'You are stronger than you think.',
    'Small steps still move you forward.',
    'Your voice matters. Share it today.',
    'Take a breath. You have got this.',
    'One post can change a day.',
    'Progress, not perfection.',
    'Your story could help someone else.',
  ];

  tz.TZDateTime _next8Pm(tz.TZDateTime now) {
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      20,
      0,
    );
    if (next.isBefore(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  Future<void> init() async {
    if (_initialized) return;

    // Initialize local notifications
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onSelectNotification,
    );

    tz.initializeTimeZones();
    await _firebaseMessaging.setAutoInitEnabled(true);

    // Android 8+ requires notification channels.
    final channel = AndroidNotificationChannel(
      _newPostsChannelId,
      'New Posts',
      description: 'Notifications for new posts',
      importance: Importance.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_postSoundAndroid),
    );
    const generalChannel = AndroidNotificationChannel(
      'general',
      'General',
      description: 'General notifications',
      importance: Importance.high,
      playSound: true,
    );
    const scheduledChannel = AndroidNotificationChannel(
      'scheduled_posts',
      'Scheduled Posts',
      description: 'Reminders for scheduled posts',
      importance: Importance.high,
      playSound: true,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);
    await android?.createNotificationChannel(generalChannel);
    await android?.createNotificationChannel(scheduledChannel);

    // Request notification permissions (Android 13+ and iOS)
    await _requestPermissions();

    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get FCM token
    await _getFCMToken();

    // Listen for foreground notifications
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle when app is opened from a notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }

    await scheduleDailyMotivation();
    await scheduleInactivityReminderFromPrefs();

    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) {
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return;
    }

    // Request permissions for iOS
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        final enabled = await android?.areNotificationsEnabled();
        AppLogger.d('Android notifications enabled: $enabled');
      } catch (e, stack) {
        AppLogger.e('Android notification permission check failed',
            error: e, stack: stack);
      }
    }

    // Check if granted
    final settings = await _firebaseMessaging.getNotificationSettings();
    AppLogger.d('Notification permissions updated: ${settings.authorizationStatus}');
  }

  Future<void> _getFCMToken() async {
    try {
      if (kIsWeb && AppConfig.firebaseWebVapidKey.isEmpty) {
        AppLogger.w('Missing web VAPID key; skipping FCM token request.');
        return;
      }
      _fcmToken = await _firebaseMessaging.getToken(
        vapidKey: kIsWeb ? AppConfig.firebaseWebVapidKey : null,
      );
      AppLogger.d('FCM token updated');

      // Save token to Supabase if user is logged in
      await _saveFCMTokenToSupabase();
      await _ensureTopicSubscriptions();
    } catch (e, stack) {
      AppLogger.e('Error getting FCM token', error: e, stack: stack);
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      AppLogger.d('FCM token refreshed');
      _fcmToken = newToken;
      _saveFCMTokenToSupabase();
      _ensureTopicSubscriptions();
    });
  }

  Future<void> _ensureTopicSubscriptions() async {
    if (kIsWeb) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      AppLogger.d('No user logged in, skipping topic subscriptions');
      return;
    }
    final newPostEnabled = await _isNewPostNotificationsEnabled(user.id);
    if (newPostEnabled) {
      await _subscribeToAllUsersTopic();
      await _syncFollowedTopicsInternal(user.id);
    } else {
      await _unsubscribeFromAllUsersTopic();
      await _unsubscribeFromFollowedTopicsInternal(user.id);
    }
    await _subscribeToBroadcastTopic();
  }

  Future<void> _subscribeToAllUsersTopic() async {
    if (kIsWeb) return;
    try {
      await _firebaseMessaging.subscribeToTopic(_globalTopic);
      AppLogger.d('Subscribed to $_globalTopic topic');
    } catch (e, stack) {
      AppLogger.e('Failed to subscribe to $_globalTopic topic',
          error: e, stack: stack);
    }
  }

  Future<void> _unsubscribeFromAllUsersTopic() async {
    if (kIsWeb) return;
    try {
      await _firebaseMessaging.unsubscribeFromTopic(_globalTopic);
      AppLogger.d('Unsubscribed from $_globalTopic topic');
    } catch (e, stack) {
      AppLogger.e('Failed to unsubscribe from $_globalTopic topic',
          error: e, stack: stack);
    }
  }

  Future<void> _subscribeToBroadcastTopic() async {
    if (kIsWeb) return;
    try {
      await _firebaseMessaging.subscribeToTopic(_broadcastTopic);
      AppLogger.d('Subscribed to $_broadcastTopic topic');
    } catch (e, stack) {
      AppLogger.e('Failed to subscribe to $_broadcastTopic topic',
          error: e, stack: stack);
    }
  }

  String _followersTopic(String userId) => 'followers_$userId';

  Future<void> subscribeToFollowersTopic(String userId) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      await _firebaseMessaging.subscribeToTopic(_followersTopic(userId));
      AppLogger.d('Subscribed to followers topic for $userId');
    } catch (e, stack) {
      AppLogger.e('Failed to subscribe to followers topic for $userId',
          error: e, stack: stack);
    }
  }

  Future<void> unsubscribeFromFollowersTopic(String userId) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      await _firebaseMessaging.unsubscribeFromTopic(_followersTopic(userId));
      AppLogger.d('Unsubscribed from followers topic for $userId');
    } catch (e, stack) {
      AppLogger.e('Failed to unsubscribe from followers topic for $userId',
          error: e, stack: stack);
    }
  }

  Future<void> syncFollowedTopics() async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await _syncFollowedTopicsInternal(user.id);
  }

  Future<void> _syncFollowedTopicsInternal(String userId) async {
    try {
      final res = await supabase
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId);
      final ids = (res as List)
          .map((row) => row['following_id'] as String)
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final id in ids) {
        await _firebaseMessaging.subscribeToTopic(_followersTopic(id));
      }
    } catch (e, stack) {
      AppLogger.e('Failed to sync follower topics', error: e, stack: stack);
    }
  }

  Future<void> _unsubscribeFromFollowedTopicsInternal(String userId) async {
    try {
      final res = await supabase
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId);
      final ids = (res as List)
          .map((row) => row['following_id'] as String)
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final id in ids) {
        await _firebaseMessaging.unsubscribeFromTopic(_followersTopic(id));
      }
    } catch (e, stack) {
      AppLogger.e('Failed to unsubscribe from follower topics',
          error: e, stack: stack);
    }
  }

  Future<bool> _isNewPostNotificationsEnabled(String userId) async {
    try {
      final res = await supabase
          .from('notification_settings')
          .select('notify_new_post')
          .eq('user_id', userId)
          .maybeSingle();
      if (res == null) return true;
      return res['notify_new_post'] == true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setNewPostNotificationsEnabled(bool enabled) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    if (enabled) {
      await _subscribeToAllUsersTopic();
      final user = supabase.auth.currentUser;
      if (user != null) {
        await _syncFollowedTopicsInternal(user.id);
      }
    } else {
      await _unsubscribeFromAllUsersTopic();
      final user = supabase.auth.currentUser;
      if (user != null) {
        await _unsubscribeFromFollowedTopicsInternal(user.id);
      }
    }
  }

  Future<void> ensureBroadcastSubscription() async {
    if (!_initialized) {
      await init();
    } else {
      await _ensureTopicSubscriptions();
    }
  }

  Future<void> _saveFCMTokenToSupabase() async {
    if (_fcmToken == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      AppLogger.d('No user logged in, skipping FCM token save');
      return;
    }

    try {
      await supabase
          .from('users')
          .update({'fcm_token': _fcmToken}).eq('id', user.id);
      AppLogger.d('FCM token saved');
    } catch (e, stack) {
      AppLogger.e('Error saving FCM token', error: e, stack: stack);
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    AppLogger.d('Foreground message received');

    final dataType = message.data['type']?.toString();
    final dataTitle = message.data['title']?.toString();
    final dataBody = message.data['body']?.toString();
    final imageUrl = message.data['imageUrl']?.toString();
    final payload = jsonEncode(message.data);

    if (dataType == 'new_post') {
      final title = message.notification?.title ?? dataTitle ?? 'New post';
      final body = message.notification?.body ?? dataBody ?? '';
      showNewPost(
        title: title,
        body: body,
        payload: payload,
        imageUrl: imageUrl,
      );
      return;
    }

    if (dataType == 'dm') {
      final title = message.notification?.title ?? dataTitle ?? 'New message';
      final body = message.notification?.body ?? dataBody ?? '';
      _showDirectMessageNotification(
        title: title,
        body: body,
        payload: payload,
      );
      return;
    }

    // Show local notification for foreground messages
    if (message.notification != null) {
      showNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        payload: payload,
      );
      return;
    }

    if (dataTitle != null || dataBody != null) {
      showNotification(
        title: dataTitle ?? 'Notification',
        body: dataBody ?? '',
        payload: payload,
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    _navigateBasedOnData(
      message.data,
      messageId: message.messageId,
    );
  }

  void _onSelectNotification(NotificationResponse response) {
    if (response.payload != null) {
      if (response.actionId == _dmReplyActionId) {
        final reply = response.input?.trim();
        if (reply != null && reply.isNotEmpty) {
          final data =
              jsonDecode(response.payload!) as Map<String, dynamic>;
          final conversationId = data['conversationId']?.toString();
          if (conversationId != null && conversationId.isNotEmpty) {
            _sendQuickReply(conversationId, reply);
          }
        }
        return;
      }
      if (response.actionId == _commentActionId) {
        final data =
            jsonDecode(response.payload!) as Map<String, dynamic>;
        data['openComments'] = true;
        _navigateBasedOnData(data);
        return;
      }
      final data = jsonDecode(response.payload!);
      _navigateBasedOnData(data);
    }
  }

  void _navigateBasedOnData(
    Map<String, dynamic> data, {
    String? messageId,
  }) {
    if (messageId != null && messageId == _lastNavigationMessageId) {
      return;
    }
    if (messageId != null) {
      _lastNavigationMessageId = messageId;
    }
    if (!_isNavigatorReady()) {
      _queueNavigation(data);
      return;
    }
    _performNavigation(data);
  }

  bool _isNavigatorReady() {
    final nav = navigatorKey.currentState;
    return nav != null && nav.mounted;
  }

  void _queueNavigation(Map<String, dynamic> data) {
    _pendingNavigation = data;
    _scheduleNavigationRetry();
  }

  void _scheduleNavigationRetry() {
    if (_navRetryCount >= _navRetryMax) {
      _pendingNavigation = null;
      _navRetryTimer?.cancel();
      _navRetryCount = 0;
      return;
    }
    _navRetryCount += 1;
    _navRetryTimer?.cancel();
    _navRetryTimer = Timer(_navRetryDelay, _tryNavigatePending);
  }

  void _tryNavigatePending() {
    final pending = _pendingNavigation;
    if (pending == null) return;
    if (!_isNavigatorReady()) {
      _scheduleNavigationRetry();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isNavigatorReady()) {
        _scheduleNavigationRetry();
        return;
      }
      _pendingNavigation = null;
      _navRetryCount = 0;
      _performNavigation(pending);
    });
  }

  void _performNavigation(Map<String, dynamic> data) {
    final type = data['type'];
    switch (type) {
      case 'new_follower':
        final userId = data['userId'];
        if (userId != null) {
          navigatorKey.currentState?.pushNamed('/profile', arguments: userId);
        } else {
          navigatorKey.currentState?.pushNamed('/home');
        }
        break;
      case 'room_created':
        navigatorKey.currentState?.pushNamed('/home');
        break;
      case 'question_reply':
        navigatorKey.currentState?.pushNamed('/profile');
        break;
      case 'streak_unlocked':
        navigatorKey.currentState?.pushNamed('/profile');
        break;
      case 'new_post':
      case 'post_like':
      case 'post_comment':
        final postId = data['postId']?.toString();
        final openComments =
            type == 'post_comment' || _isTruthy(data['openComments']);
        if (postId != null && postId.isNotEmpty) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => PostDetailScreen(
                postId: postId,
                openComments: openComments,
              ),
            ),
          );
        } else {
          navigatorKey.currentState?.pushNamed('/home');
        }
        break;
      case 'dm':
      case 'group_message':
        final conversationId = data['conversationId']?.toString();
        if (conversationId != null && conversationId.isNotEmpty) {
          _openConversation(conversationId);
        } else {
          navigatorKey.currentState?.pushNamed('/groups');
        }
        break;
      default:
        navigatorKey.currentState?.pushNamed('/home');
    }
  }

  Future<void> _openConversation(String conversationId) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      navigatorKey.currentState?.pushNamed('/login');
      return;
    }
    try {
      final response = await supabase.rpc(
        'get_user_conversations_optimized',
        params: {'user_uuid': currentUser.id},
      );
      final conversations = response as List;
      final match = conversations.cast<Map<String, dynamic>>().firstWhere(
            (item) => item['conversation_id'] == conversationId,
            orElse: () => {},
          );
      if (match.isEmpty) {
        navigatorKey.currentState?.pushNamed('/groups');
        return;
      }
      final chat = ChatModel(
        id: match['conversation_id'] as String,
        name: match['conversation_name'] as String? ?? 'Unknown',
        isGroup: match['is_group'] as bool? ?? false,
        lastMessageContent: match['last_message_content'] as String?,
        lastMessageSenderName: match['last_message_sender_name'] as String?,
        lastMessageTime: match['last_message_time'] != null
            ? DateTime.parse(match['last_message_time'] as String)
            : null,
        unreadCount: (match['unread_count'] as num?)?.toInt() ?? 0,
        otherUserId: match['other_user_id'] as String?,
        otherUserAlias: match['other_user_alias'] as String?,
        otherUserDisplayName: match['other_user_display_name'] as String?,
        otherUserProfileImageUrl:
            match['other_user_profile_image_url'] as String?,
        participantIds: match['participant_ids'] != null
            ? List<String>.from(match['participant_ids'] as List)
            : const [],
        createdAt: DateTime.parse(match['created_at'] as String),
        updatedAt: DateTime.parse(match['updated_at'] as String),
        groupImageUrl: match['group_image_url'] as String?,
        isLocked: match['is_locked'] as bool? ?? false,
        currentUserRole: match['current_user_role'] as String?,
      );
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => ConversationScreen(chat: chat)),
      );
    } catch (e, stack) {
      AppLogger.e('Failed to open conversation',
          error: e, stack: stack);
      navigatorKey.currentState?.pushNamed('/groups');
    }
  }

  Future<void> showNewPost({
    required String title,
    required String body,
    String? payload,
    String? imageUrl,
  }) async {
    await showNotification(
      title: title,
      body: body,
      payload: payload,
      channelId: _newPostsChannelId,
      channelName: 'New Posts',
      imageUrl: imageUrl,
      androidActions: const [
        AndroidNotificationAction(
          _commentActionId,
          'Comment',
          showsUserInterface: true,
        ),
      ],
      androidSound: _postSoundAndroid,
      iosSound: _postSoundIos,
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = 'general',
    String channelName = 'General',
    String? imageUrl,
    List<AndroidNotificationAction>? androidActions,
    String? androidSound,
    String? iosSound,
  }) async {
    if (!_initialized) {
      await init();
    }
    if (await _isInQuietHours()) {
      return;
    }
    final previewEnabled = await _isPreviewEnabled();
    final displayTitle = previewEnabled ? title : 'AnonPro';
    final displayBody = previewEnabled ? body : 'You have a new notification';

    BigPictureStyleInformation? styleInformation;
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      final bitmap = await _downloadAndroidBitmap(imageUrl.trim());
      if (bitmap != null) {
        styleInformation = BigPictureStyleInformation(
          bitmap,
          contentTitle: displayTitle,
          summaryText: displayBody,
        );
      }
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      icon: '@drawable/ic_notification',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: androidSound != null
          ? RawResourceAndroidNotificationSound(androidSound)
          : null,
      styleInformation: styleInformation,
      actions: androidActions,
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      sound: iosSound,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _plugin.show(id, displayTitle, displayBody, details,
        payload: payload);
  }

  Future<void> _showDirectMessageNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      await init();
    }
    if (await _isInQuietHours()) {
      return;
    }
    final previewEnabled = await _isPreviewEnabled();
    final displayTitle = previewEnabled ? title : 'AnonPro';
    final displayBody = previewEnabled ? body : 'New message';

    final androidDetails = AndroidNotificationDetails(
      'general',
      'General',
      icon: '@drawable/ic_notification',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      actions: const [
        AndroidNotificationAction(
          _dmReplyActionId,
          'Reply',
          inputs: [AndroidNotificationActionInput(label: 'Type your reply')],
          showsUserInterface: true,
          allowGeneratedReplies: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _plugin.show(id, displayTitle, displayBody, details,
        payload: payload);
  }

  Future<void> scheduleDailyMotivation() async {
    if (kIsWeb) {
      return;
    }
    if (!_initialized) {
      await init();
    }
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notif_daily_motivation_enabled') ?? true;
    if (!enabled) {
      await _cancelDailyMotivation();
      return;
    }

    // Schedule the next 7 evenings at 8:00 PM.
    final now = tz.TZDateTime.now(tz.local);
    final base = _next8Pm(now);
    final quotes = List<String>.from(_motivationQuotes)..shuffle();

    for (var i = 0; i < _dailyMotivationDays; i++) {
      final id = _dailyMotivationBaseId + i;
      final when = base.add(Duration(days: i));
      final quote = quotes[i % quotes.length];
      await _plugin.zonedSchedule(
        id,
        'Daily motivation',
        quote,
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'general',
            'General',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> scheduleInactivityReminderFromPrefs() async {
    if (kIsWeb) {
      return;
    }
    if (!_initialized) {
      await init();
    }
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notif_inactivity_enabled') ?? true;
    if (!enabled) {
      await _plugin.cancel(_inactivityReminderId);
      return;
    }
    final lastPostMs = prefs.getInt('last_post_at_ms');
    if (lastPostMs == null || lastPostMs <= 0) {
      return;
    }
    final lastPostAt = DateTime.fromMillisecondsSinceEpoch(lastPostMs);
    await scheduleInactivityReminder(lastPostAt);
  }

  Future<void> scheduleInactivityReminder(DateTime lastPostAt) async {
    if (kIsWeb) {
      return;
    }
    if (!_initialized) {
      await init();
    }
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notif_inactivity_enabled') ?? true;
    if (!enabled) {
      await _plugin.cancel(_inactivityReminderId);
      return;
    }

    var target = lastPostAt.add(const Duration(days: _inactivityDays));
    target = DateTime(
      target.year,
      target.month,
      target.day,
      20,
      0,
    );
    final now = DateTime.now();
    if (target.isBefore(now)) {
      target = now.add(const Duration(minutes: 5));
    }

    await _plugin.zonedSchedule(
      _inactivityReminderId,
      'We miss your posts',
      'It has been a while. Share a quick update?',
      tz.TZDateTime.from(target, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'general',
          'General',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _cancelDailyMotivation() async {
    for (var i = 0; i < _dailyMotivationDays; i++) {
      await _plugin.cancel(_dailyMotivationBaseId + i);
    }
  }

  Future<void> _sendQuickReply(String conversationId, String reply) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AppLogger.w('Quick reply skipped: no user session');
      return;
    }
    try {
      await supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': user.id,
        'content': reply,
        'message_type': 'text',
        'created_at': DateTime.now().toIso8601String(),
      });
      AppLogger.d('Quick reply sent');
    } catch (e, stack) {
      AppLogger.e('Quick reply failed', error: e, stack: stack);
    }
  }

  Future<void> schedulePostReminder({
    required DateTime when,
    required String body,
  }) async {
    if (kIsWeb) {
      return;
    }
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      'scheduled_posts',
      'Scheduled Posts',
      channelDescription: 'Reminders for scheduled posts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final id = when.millisecondsSinceEpoch ~/ 1000;
    await _plugin.zonedSchedule(
      id,
      'Scheduled post',
      body,
      tz.TZDateTime.from(when, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<bool> _isPreviewEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notif_preview_enabled') ?? true;
  }

  Future<bool> _isInQuietHours() async {
    final prefs = await SharedPreferences.getInstance();
    final startMinutes = prefs.getInt('notif_quiet_start') ?? -1;
    final endMinutes = prefs.getInt('notif_quiet_end') ?? -1;
    if (startMinutes < 0 || endMinutes < 0 || startMinutes == endMinutes) {
      return false;
    }

    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    if (startMinutes < endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }
    return nowMinutes >= startMinutes || nowMinutes < endMinutes;
  }

  bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    final s = value.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  Future<ByteArrayAndroidBitmap?> _downloadAndroidBitmap(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final bytes = res.bodyBytes;
      if (bytes.isEmpty) return null;
      return ByteArrayAndroidBitmap(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  // Method to call after login to save FCM token
  Future<void> saveFCMTokenAfterLogin() async {
    if (!_initialized) {
      await init();
    } else {
      await _saveFCMTokenToSupabase();
      await _ensureTopicSubscriptions();
    }
  }
}

@pragma('vm:entry-point')
Future<void> showBackgroundNotification(RemoteMessage message) async {
  if (message.notification != null) {
    return;
  }
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings =
      AndroidInitializationSettings('@drawable/ic_notification');
  const iosSettings = DarwinInitializationSettings();
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await plugin.initialize(settings);

  const generalChannel = AndroidNotificationChannel(
    'general',
    'General',
    description: 'General notifications',
    importance: Importance.high,
    playSound: true,
  );
  const newPostsChannel = AndroidNotificationChannel(
    NotificationService._newPostsChannelId,
    'New Posts',
    description: 'Notifications for new posts',
    importance: Importance.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound(
      NotificationService._postSoundAndroid,
    ),
  );
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(generalChannel);
  await android?.createNotificationChannel(newPostsChannel);

  final dataType = message.data['type']?.toString();
  final imageUrl = message.data['imageUrl']?.toString();
  final title = message.data['title']?.toString() ?? 'Notification';
  final body = message.data['body']?.toString() ?? 'You have a new notification';
  final channelId = dataType == 'new_post'
      ? NotificationService._newPostsChannelId
      : 'general';
  final channelName = dataType == 'new_post' ? 'New Posts' : 'General';
  BigPictureStyleInformation? styleInformation;
  if (dataType == 'new_post' && imageUrl != null && imageUrl.trim().isNotEmpty) {
    final bitmap =
        await NotificationService()._downloadAndroidBitmap(imageUrl.trim());
    if (bitmap != null) {
      styleInformation = BigPictureStyleInformation(
        bitmap,
        contentTitle: title,
        summaryText: body,
      );
    }
  }
  List<AndroidNotificationAction>? actions;
  if (dataType == 'dm') {
    actions = const [
      AndroidNotificationAction(
        NotificationService._dmReplyActionId,
        'Reply',
        inputs: [AndroidNotificationActionInput(label: 'Type your reply')],
        showsUserInterface: true,
        allowGeneratedReplies: true,
      ),
    ];
  } else if (dataType == 'new_post') {
    actions = const [
      AndroidNotificationAction(
        NotificationService._commentActionId,
        'Comment',
        showsUserInterface: true,
      ),
    ];
  }
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      icon: '@drawable/ic_notification',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: dataType == 'new_post'
          ? const RawResourceAndroidNotificationSound(
              NotificationService._postSoundAndroid,
            )
          : null,
      styleInformation: styleInformation,
      actions: actions,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      sound: dataType == 'new_post'
          ? NotificationService._postSoundIos
          : null,
    ),
  );

  final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await plugin.show(id, title, body, details,
      payload: jsonEncode(message.data));
}
