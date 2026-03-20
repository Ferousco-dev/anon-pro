class ErrorSanitizer {
  static final RegExp _urlPattern = RegExp(r'https?://[^\s)"]+');
  static final RegExp _jwtPattern =
      RegExp(r'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+');
  static final RegExp _keyValuePattern = RegExp(
    r'(api[_-]?key|token|secret|password|authorization)\s*[:=]\s*[^,\s]+',
    caseSensitive: false,
  );

  static String sanitize(String input) {
    var result = input;
    result = result.replaceAll(_jwtPattern, '[redacted]');
    result = result.replaceAll(_urlPattern, '[redacted-url]');
    result = result.replaceAll(_keyValuePattern, '[redacted]');
    return result;
  }

  static String sanitizeError(Object error) {
    return sanitize(error.toString());
  }

  static String? sanitizeStack(StackTrace? stack) {
    if (stack == null) return null;
    return sanitize(stack.toString());
  }

  static String userMessage(Object error) {
    return 'Something went wrong. Please try again.';
  }
}
