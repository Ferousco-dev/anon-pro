import 'package:flutter/foundation.dart';
import 'package:anonpro/services/error_reporting_service.dart';
import 'package:anonpro/utils/app_logger.dart';
import 'package:anonpro/utils/error_sanitizer.dart';

class AppErrorHandler {
  static String userMessage(Object error) {
    return ErrorSanitizer.userMessage(error);
  }

  static Future<void> report({
    required Object error,
    StackTrace? stack,
    String? context,
  }) async {
    if (kDebugMode) {
      AppLogger.e('Unhandled error', error: error, stack: stack);
    }
    await ErrorReportingService.instance.report(
      error: ErrorSanitizer.sanitizeError(error),
      stack: stack == null ? null : StackTrace.fromString(ErrorSanitizer.sanitizeStack(stack)!),
      context: context == null ? null : ErrorSanitizer.sanitize(context),
    );
  }
}
