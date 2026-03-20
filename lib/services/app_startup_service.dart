import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_config.dart';
import '../utils/app_error_handler.dart';
import '../utils/app_logger.dart';
import 'error_reporting_service.dart';
import 'feed_cache_service.dart';
import 'notification_service.dart';
import 'user_activity_service.dart';
import 'widget_data_service.dart';

class AppStartupService {
  static Future<void>? _initFuture;
  static Future<void>? _criticalFuture;
  static bool _supabaseReady = false;

  static Future<void> initialize() {
    _initFuture ??= _initializeFull();
    return _initFuture!;
  }

  static Future<void> initializeCritical() {
    _criticalFuture ??= _initializeCritical();
    return _criticalFuture!;
  }

  static Future<void> _initializeCritical() async {
    try {
      AppConfig.ensureConfigured();
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          if (!AppConfig.hasFirebaseWebConfig) {
            throw StateError('Missing Firebase web configuration.');
          }
          await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: AppConfig.firebaseApiKey,
              authDomain: AppConfig.firebaseAuthDomain,
              projectId: AppConfig.firebaseProjectId,
              storageBucket: AppConfig.firebaseStorageBucket,
              messagingSenderId: AppConfig.firebaseMessagingSenderId,
              appId: AppConfig.firebaseAppId,
            ),
          );
        } else {
          await Firebase.initializeApp();
        }
      }

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      if (!_supabaseReady) {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
        _supabaseReady = true;
      }
    } catch (e, stack) {
      AppLogger.e('Critical startup initialization failed',
          error: e, stack: stack);
      await AppErrorHandler.report(
        error: e,
        stack: stack,
        context: 'startup:critical',
      );
      rethrow;
    }
  }

  static Future<void> _initializeFull() async {
    try {
      await initializeCritical();
      await Hive.initFlutter();

      ErrorReportingService.instance.init();
      await UserActivityService().updateLastSeen();
      await NotificationService().init();
      await FeedCacheService().initialize();
      await WidgetDataService.initialize();
      WidgetDataService.updateWidgetData();
    } catch (e, stack) {
      AppLogger.e('Startup initialization failed', error: e, stack: stack);
      await AppErrorHandler.report(
        error: e,
        stack: stack,
        context: 'startup:init',
      );
    }
  }
}

// Background message handler for FCM (must be a top-level function and async)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  await showBackgroundNotification(message);
}
