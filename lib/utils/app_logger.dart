import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class AppLogger {
  static void d(String message, {Object? error, StackTrace? stack}) {
    if (kDebugMode) {
      developer.log(message, name: 'AnonPro', error: error, stackTrace: stack);
    }
  }

  static void w(String message, {Object? error, StackTrace? stack}) {
    if (kDebugMode) {
      developer.log('WARN: $message',
          name: 'AnonPro', error: error, stackTrace: stack);
    }
  }

  static void e(String message, {Object? error, StackTrace? stack}) {
    if (kDebugMode) {
      developer.log('ERROR: $message',
          name: 'AnonPro', error: error, stackTrace: stack);
    }
  }
}
