import 'package:flutter/foundation.dart';

class AppConfig {
  static const String supabaseUrl =
      String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: 'https://mnfbdrdmqromgfnqetzh.supabase.co',
      );
  static const String supabaseAnonKey =
      String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg',
      );

  static const String imagekitUrlEndpoint = String.fromEnvironment(
    'IMAGEKIT_URL_ENDPOINT',
    defaultValue: 'https://ik.imagekit.io/bchbwqir6',
  );
  static const String imagekitPublicKey = String.fromEnvironment(
    'IMAGEKIT_PUBLIC_KEY',
    defaultValue: 'public_uCAbFKLn80XJ3aLz2lQul/Hfkbk=',
  );

  static const String firebaseApiKey =
      String.fromEnvironment(
        'FIREBASE_API_KEY',
        defaultValue: 'AIzaSyAbYibHGg14y8A8Ag7ylsgR91PmMOooyHQ',
      );
  static const String firebaseAuthDomain =
      String.fromEnvironment(
        'FIREBASE_AUTH_DOMAIN',
        defaultValue: 'anon-pro.firebaseapp.com',
      );
  static const String firebaseProjectId =
      String.fromEnvironment(
        'FIREBASE_PROJECT_ID',
        defaultValue: 'anon-pro',
      );
  static const String firebaseStorageBucket =
      String.fromEnvironment(
        'FIREBASE_STORAGE_BUCKET',
        defaultValue: 'anon-pro.firebasestorage.app',
      );
  static const String firebaseMessagingSenderId =
      String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
        defaultValue: '616821146393',
      );
  static const String firebaseAppId =
      String.fromEnvironment(
        'FIREBASE_APP_ID',
        defaultValue: '1:616821146393:web:22dd80de6f4e13fad63b88',
      );
  static const String firebaseWebVapidKey =
      String.fromEnvironment(
        'FIREBASE_WEB_VAPID_KEY',
        defaultValue:
            'BDMT3Mz2SzdzwckTbxAo4VZ41DVyttT0-0SNDh8Lxu54ZVm2-aeyUKxm0d3jLz2XV6clx5i1gUyeC2aP43Ax9z0',
      );
  static const String adminTerminalPasskey =
      String.fromEnvironment(
        'ADMIN_TERMINAL_PASSKEY',
        defaultValue: '190308',
      );
  static const bool enableAdminTools =
      bool.fromEnvironment('ENABLE_ADMIN_TOOLS', defaultValue: true);

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasFirebaseWebConfig =>
      firebaseApiKey.isNotEmpty &&
      firebaseAuthDomain.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseStorageBucket.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseAppId.isNotEmpty;

  static bool get adminToolsEnabled => kDebugMode || enableAdminTools;

  static void ensureConfigured() {
    if (kReleaseMode && !hasSupabaseConfig) {
      throw StateError('Missing Supabase configuration.');
    }
  }
}
