import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ErrorReportingService {
  ErrorReportingService._();

  static final ErrorReportingService _instance = ErrorReportingService._();
  static ErrorReportingService get instance => _instance;

  final SupabaseClient _client = Supabase.instance.client;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
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
      await _client.from('client_error_logs').insert({
        'user_id': _client.auth.currentUser?.id,
        'message': error.toString(),
        'stack': stack?.toString(),
        'context': context,
        'platform': defaultTargetPlatform.name,
      });
    } catch (_) {
      // Avoid crashing on error logging failures.
    }
  }
}
