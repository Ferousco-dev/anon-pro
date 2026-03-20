import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../utils/app_config.dart';

/// Handles passkey validation, rate limiting, and failed attempt logging.
class TerminalSecurityService {
  String get _fallbackPasskey => AppConfig.adminTerminalPasskey;
  static const int _maxAttempts = 5;
  static const int _cooldownMinutes = 5;

  // SharedPreferences keys
  static const String _attemptsKey = 'admin_terminal_attempts';
  static const String _lockoutTimeKey = 'admin_terminal_lockout_time';

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Returns null on success, or an error message string on failure.
  Future<String?> validatePasskey(String enteredPasskey) async {
    if (!AppConfig.adminToolsEnabled) {
      return 'ACCESS DENIED\nAdmin terminal disabled.';
    }
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return 'ACCESS DENIED\nLogin required.';
    }
    // Check if currently locked out
    final lockoutError = await _checkLockout();
    if (lockoutError != null) return lockoutError;

    final isAdmin = await _isAdmin(user.id);
    if (!isAdmin) {
      return 'ACCESS DENIED\nAdmin role required.';
    }

    final dbPasskey = await _fetchPasskeyFromSupabase();
    final resolvedPasskey =
        (dbPasskey != null && dbPasskey.isNotEmpty)
            ? dbPasskey
            : _fallbackPasskey;

    if (resolvedPasskey.isEmpty) {
      return 'ACCESS DENIED\nAdmin passkey not configured.';
    }

    if (enteredPasskey == resolvedPasskey) {
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

  Future<bool> _isAdmin(String userId) async {
    try {
      final res = await _supabase
          .from('users')
          .select('role')
          .eq('id', userId)
          .single();
      return res['role'] == 'admin';
    } catch (e) {
      debugPrint('Error checking admin role: $e');
      return false;
    }
  }

  Future<String?> _fetchPasskeyFromSupabase() async {
    try {
      final res = await _supabase
          .from('admin_passcode')
          .select('passcode')
          .maybeSingle();
      return res?['passcode'] as String?;
    } catch (e) {
      debugPrint('Error fetching admin passkey: $e');
      return null;
    }
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
        'entered_passkey': enteredPasskey.isEmpty
            ? ''
            : 'redacted(${enteredPasskey.length})',
        'ip_address': null, // IP not directly accessible from Flutter client
        'user_id': user?.id,
      });
    } catch (e) {
      debugPrint('Error logging failed admin access attempt: $e');
    }
  }
}
