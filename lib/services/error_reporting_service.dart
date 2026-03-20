import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:anonpro/utils/error_sanitizer.dart';

class ErrorReportingService {
  ErrorReportingService._();

  static final ErrorReportingService _instance = ErrorReportingService._();
  static ErrorReportingService get instance => _instance;

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
      unawaited(_report(
        error: details.exception,
        stack: details.stack,
        context: details.context?.toDescription(),
      ));
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(_report(
        error: error,
        stack: stack,
        context: 'PlatformDispatcher',
      ));
      return false;
    };
  }

  Future<void> report({
    required Object error,
    StackTrace? stack,
    String? context,
  }) async {
    await _report(error: error, stack: stack, context: context);
  }

  Future<void> _report({
    required Object error,
    StackTrace? stack,
    String? context,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.from('client_error_logs').insert({
        'user_id': client.auth.currentUser?.id,
        'message': ErrorSanitizer.sanitizeError(error),
        'stack': ErrorSanitizer.sanitizeStack(stack),
        'context': context == null ? null : ErrorSanitizer.sanitize(context),
        'platform': defaultTargetPlatform.name,
      });
    } on AssertionError {
      // Supabase not initialized yet; skip remote error reporting.
    } catch (_) {
      // Avoid crashing on error logging failures.
    }
  }
}
