import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles passkey validation, rate limiting, and failed attempt logging.
class TerminalSecurityService {
  static const String _passkey = '190308';
  static const int _maxAttempts = 5;
  static const int _cooldownMinutes = 5;

  // SharedPreferences keys
  static const String _attemptsKey = 'admin_terminal_attempts';
  static const String _lockoutTimeKey = 'admin_terminal_lockout_time';

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Returns null on success, or an error message string on failure.
  Future<String?> validatePasskey(String enteredPasskey) async {
    // Check if currently locked out
    final lockoutError = await _checkLockout();
    if (lockoutError != null) return lockoutError;

    if (enteredPasskey == _passkey) {
      // Reset attempts on success
      await _resetAttempts();
      return null; // success
    }

    // Wrong passkey — increment attempts and log
    await _incrementAttempts();
    await _logFailedAttempt(enteredPasskey);

    final remaining = await _remainingAttempts();
    if (remaining <= 0) {
      await _startLockout();
      return 'ACCESS DENIED\nMaximum attempts reached.\nTry again in $_cooldownMinutes minutes.';
    }

    return 'ACCESS DENIED\nInvalid passkey\n($remaining attempts remaining)';
  }

  /// Check if the user is currently locked out.
  Future<String?> _checkLockout() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutMs = prefs.getInt(_lockoutTimeKey);
    if (lockoutMs == null) return null;

    final lockoutTime = DateTime.fromMillisecondsSinceEpoch(lockoutMs);
    final now = DateTime.now();
    if (now.isBefore(lockoutTime)) {
      final remaining = lockoutTime.difference(now);
      final mins = remaining.inMinutes;
      final secs = remaining.inSeconds % 60;
      return 'ACCESS DENIED\nLocked out. Try again in ${mins}m ${secs}s.';
    }

    // Lockout expired — reset
    await _resetAttempts();
    return null;
  }

  Future<int> _remainingAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = prefs.getInt(_attemptsKey) ?? 0;
    return _maxAttempts - attempts;
  }

  Future<void> _incrementAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_attemptsKey) ?? 0;
    await prefs.setInt(_attemptsKey, current + 1);
  }

  Future<void> _startLockout() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutEnd =
        DateTime.now().add(Duration(minutes: _cooldownMinutes));
    await prefs.setInt(_lockoutTimeKey, lockoutEnd.millisecondsSinceEpoch);
  }

  Future<void> _resetAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_attemptsKey);
    await prefs.remove(_lockoutTimeKey);
  }

  /// Log the failed attempt to Supabase for security auditing.
  Future<void> _logFailedAttempt(String enteredPasskey) async {
    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from('failed_admin_access_logs').insert({
        'device_id': user?.id ?? 'unknown',
        'entered_passkey': enteredPasskey,
        'ip_address': null, // IP not directly accessible from Flutter client
        'user_id': user?.id,
      });
    } catch (e) {
      debugPrint('Error logging failed admin access attempt: $e');
    }
  }
}
