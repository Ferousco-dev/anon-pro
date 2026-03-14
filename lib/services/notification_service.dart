import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // For supabase client

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  bool _initialized = false;
  String? _fcmToken;
  static const String _webVapidKey =
      'BDMT3Mz2SzdzwckTbxAo4VZ41DVyttT0-0SNDh8Lxu54ZVm2-aeyUKxm0d3jLz2XV6clx5i1gUyeC2aP43Ax9z0';

  Future<void> init() async {
    if (_initialized) return;

    // Initialize local notifications
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings,
        onDidReceiveNotificationResponse: _onSelectNotification);

    tz.initializeTimeZones();

    // Android 8+ requires notification channels.
    const channel = AndroidNotificationChannel(
      'new_posts',
      'New Posts',
      description: 'Notifications for new posts',
      importance: Importance.high,
      playSound: true,
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

    // Get FCM token
    await _getFCMToken();

    // Listen for foreground notifications
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle when app is opened from a notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

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

    // For Android 13+, permissions are handled automatically by Firebase
    // But you can check if granted
    final settings = await _firebaseMessaging.getNotificationSettings();
    print('Notification permissions: ${settings.authorizationStatus}');
  }

  Future<void> _getFCMToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken(
        vapidKey: kIsWeb ? _webVapidKey : null,
      );
      print("FCM Token: $_fcmToken");

      // Save token to Supabase if user is logged in
      await _saveFCMTokenToSupabase();
    } catch (e) {
      print("Error getting FCM token: $e");
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      print("FCM Token refreshed: $newToken");
      _fcmToken = newToken;
      _saveFCMTokenToSupabase();
    });
  }

  Future<void> _saveFCMTokenToSupabase() async {
    if (_fcmToken == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      print("No user logged in, skipping FCM token save");
      return;
    }

    try {
      await supabase
          .from('users')
          .update({'fcm_token': _fcmToken}).eq('id', user.id);
      print("FCM token saved to Supabase");
    } catch (e) {
      print("Error saving FCM token: $e");
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print(
        "Foreground message: ${message.notification?.title} - ${message.notification?.body}");

    // Show local notification for foreground messages
    if (message.notification != null) {
      showNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    _navigateBasedOnData(message.data);
  }

  void _onSelectNotification(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      _navigateBasedOnData(data);
    }
  }

  void _navigateBasedOnData(Map<String, dynamic> data) {
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
      case 'post_like':
      case 'post_comment':
        navigatorKey.currentState?.pushNamed('/home');
        break;
      case 'dm':
      case 'group_message':
        navigatorKey.currentState?.pushNamed('/groups');
        break;
      default:
        navigatorKey.currentState?.pushNamed('/home');
    }
  }

  Future<void> showNewPost({
    required String title,
    required String body,
    String? payload,
  }) async {
    await showNotification(
      title: title,
      body: body,
      payload: payload,
      channelId: 'new_posts',
      channelName: 'New Posts',
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = 'general',
    String channelName = 'General',
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

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
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

  // Method to call after login to save FCM token
  Future<void> saveFCMTokenAfterLogin() async {
    await _saveFCMTokenToSupabase();
  }
}
