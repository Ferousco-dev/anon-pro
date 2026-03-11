import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
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

    // Android 8+ requires notification channels.
    const channel = AndroidNotificationChannel(
      'new_posts',
      'New Posts',
      description: 'Notifications for new posts',
      importance: Importance.high,
      playSound: true,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);

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
      _fcmToken = await _firebaseMessaging.getToken();
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
      showNewPost(
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
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      'new_posts',
      'New Posts',
      channelDescription: 'Notifications for new posts',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Use a changing ID so multiple notifications show.
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _plugin.show(id, title, body, details, payload: payload);
  }

  // Method to call after login to save FCM token
  Future<void> saveFCMTokenAfterLogin() async {
    await _saveFCMTokenToSupabase();
  }
}
