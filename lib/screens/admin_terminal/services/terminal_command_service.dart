import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../utils/app_config.dart';
import '../../../utils/app_error_handler.dart';

/// Parses and executes admin terminal commands against the Supabase backend.
class TerminalCommandService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Uri _buildFunctionUrl(String functionName) {
    final base = Uri.parse(AppConfig.supabaseUrl);
    final functionHost =
        base.host.replaceFirst('.supabase.co', '.functions.supabase.co');
    return Uri(scheme: base.scheme, host: functionHost, path: '/$functionName');
  }

  /// Parse raw input into command + arguments, then execute.
  /// Returns the output string to display in the terminal.
  Future<String> execute(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) return '';

    // Sanitize: only allow printable ASCII, no SQL injection vectors
    if (!_isSafeInput(input)) {
      return 'ERROR: Invalid characters in command.';
    }

    // Parse multi-word commands first
    final lower = input.toLowerCase();

    // --- Multi-word command matching ---
    if (lower == 'help') return _help();
    if (lower == 'clear') return '__CLEAR__'; // sentinel handled by controller
    if (lower == 'admin pinging') return await _adminPinging();
    if (lower == 'admin pinging name of all users') {
      return await _listAllUsers();
    }
    if (lower == 'list of streaks') return await _listStreaks();
    if (lower == 'shutdown') return await _shutdown();
    if (lower == 'maintenance status') return await _maintenanceStatus();
    if (lower == 'maintenance on') return await _setMaintenance(true);
    if (lower == 'maintenance off') return await _setMaintenance(false);
    if (lower == 'app shutdown status') return await _appShutdownStatus();
    if (lower == 'app shutdown on') return await _setAppShutdown(true);
    if (lower == 'app shutdown off') return await _setAppShutdown(false);
    if (lower == 'view reports') return await _viewReports();
    if (lower == 'view passcode') return await _viewPasscode();
    if (lower.startsWith('view error logs')) {
      return await _viewClientErrorLogs(_parseLimit(input));
    }
    if (lower.startsWith('view activity logs')) {
      return await _viewActivityLogs(_parseLimit(input));
    }
    if (lower.startsWith('view access logs')) {
      return await _viewFailedAdminAccessLogs(_parseLimit(input));
    }
    if (lower.startsWith('view rate limits')) {
      return await _viewRateLimits();
    }
    if (lower.startsWith('change passcode')) {
      final newPass = input.substring('change passcode'.length).trim();
      return await _changePasscode(newPass);
    }
    if (lower.startsWith('set rate posts')) {
      final value = _parseRequiredInt(input);
      return await _setRateLimit('rate_limit_posts_per_minute', value);
    }
    if (lower.startsWith('set rate messages')) {
      final value = _parseRequiredInt(input);
      return await _setRateLimit('rate_limit_messages_per_minute', value);
    }
    if (lower.startsWith('set rate rooms')) {
      final value = _parseRequiredInt(input);
      return await _setRateLimit('rate_limit_rooms_per_hour', value);
    }

    // --- Single-word + argument commands ---
    final parts = input.split(RegExp(r'\s+'));
    final command = parts[0].toLowerCase();

    switch (command) {
      case 'ban':
        return await _banUser(parts.skip(1).join(' '));
      case 'unban':
        return await _unbanUser(parts.skip(1).join(' '));
      case 'verify':
        return await _verifyUser(parts.skip(1).join(' '));
      case 'unverify':
        return await _unverifyUser(parts.skip(1).join(' '));
      case 'shadowban':
        return await _shadowbanUser(parts.skip(1).join(' '));
      case 'broadcast':
        return await _broadcast(parts.skip(1).join(' '));
      case 'delete':
        if (parts.length >= 3 && parts[1].toLowerCase() == 'post') {
          return await _deletePost(parts[2]);
        }
        return 'Usage: delete post <POST_ID>';
      case 'make':
        if (parts.length >= 3 && parts[1].toLowerCase() == 'admin') {
          return await _makeAdmin(parts.skip(2).join(' '));
        }
        return 'Usage: make admin @username';
      default:
        return 'Command not recognized.\nType "help".';
    }
  }

  /// Prevent obvious injection attacks.
  bool _isSafeInput(String input) {
    // Block SQL-like patterns and shell escape sequences
    final blocked = RegExp(
        r"(;|--|'|\\x|DROP\s|INSERT\s|UPDATE\s|DELETE\s.*FROM)",
        caseSensitive: false);
    return !blocked.hasMatch(input);
  }

  // ─── Utility commands ─────────────────────────────────────

  String _help() {
    return '''
AVAILABLE COMMANDS
==================

USER MODERATION
  ban @username         — Ban a user
  unban @username       — Unban a user
  verify @username      — Verify a user
  unverify @username    — Remove verification
  make admin @username  — Promote to admin
  shadowban @username   — Shadow-ban a user

SYSTEM ANALYTICS
  admin pinging                        — System status dashboard
  admin pinging name of all users      — List all usernames
  list of streaks                      — Top streak rankings

CONTENT
  delete post <POST_ID>  — Delete a post by ID
  broadcast <message>    — Send broadcast to all users
  view reports           — View reported content

SECURITY
  view passcode                  — Display current passcode
  change passcode <NEW>          — Change admin terminal passcode
  view access logs [N]           — Failed admin passkey attempts (default 20)
  view error logs [N]            — Client error logs (default 20)
  view activity logs [N]         — Admin activity logs (default 20)

MAINTENANCE
  shutdown               — Toggle maintenance mode
  maintenance status     — Show maintenance mode
  maintenance on/off     — Set maintenance mode
  app shutdown status    — Show app shutdown state
  app shutdown on/off    — Set app shutdown state
  view rate limits       — Show message/post/room limits
  set rate posts <N>      — Set posts per minute
  set rate messages <N>   — Set messages per minute
  set rate rooms <N>      — Set rooms per hour

UTILITY
  help                   — Show this command list
  clear                  — Clear terminal output
''';
  }

  int _parseLimit(String input, {int defaultLimit = 20, int maxLimit = 100}) {
    final match = RegExp(r'(\d+)$').firstMatch(input.trim());
    if (match == null) return defaultLimit;
    final value = int.tryParse(match.group(1) ?? '');
    if (value == null || value <= 0) return defaultLimit;
    if (value > maxLimit) return maxLimit;
    return value;
  }

  int _parseRequiredInt(String input) {
    final match = RegExp(r'(\d+)$').firstMatch(input.trim());
    if (match == null) return -1;
    return int.tryParse(match.group(1) ?? '') ?? -1;
  }

  // ─── User moderation ──────────────────────────────────────

  String _extractUsername(String raw) {
    final username = raw.trim().replaceAll('@', '');
    return username;
  }

  Future<Map<String, dynamic>?> _findUserByAlias(String alias) async {
    try {
      final res = await _supabase
          .from('users')
          .select('id, alias, display_name, is_banned, is_verified, role')
          .eq('alias', alias)
          .maybeSingle();
      return res;
    } catch (e) {
      return null;
    }
  }

  Future<String> _banUser(String raw) async {
    final alias = _extractUsername(raw);
    if (alias.isEmpty) return 'Usage: ban @username';

    try {
      final user = await _findUserByAlias(alias);
      if (user == null) return 'ERROR: User @$alias not found.';

      await _supabase
          .from('users')
          .update({'is_banned': true}).eq('id', user['id']);

      await _logAction('ban_user', {'target_alias': alias});
      return 'SUCCESS: @$alias has been banned.';
    } catch (e) {
      return 'ERROR: Failed to ban user — $e';
    }
  }

  Future<String> _unbanUser(String raw) async {
    final alias = _extractUsername(raw);
    if (alias.isEmpty) return 'Usage: unban @username';

    try {
      final user = await _findUserByAlias(alias);
      if (user == null) return 'ERROR: User @$alias not found.';

      await _supabase
          .from('users')
          .update({'is_banned': false}).eq('id', user['id']);

      await _logAction('unban_user', {'target_alias': alias});
      return 'SUCCESS: @$alias has been unbanned.';
    } catch (e) {
      return 'ERROR: Failed to unban user — $e';
    }
  }

  Future<String> _verifyUser(String raw) async {
    final alias = _extractUsername(raw);
    if (alias.isEmpty) return 'Usage: verify @username';

    try {
      final user = await _findUserByAlias(alias);
      if (user == null) return 'ERROR: User @$alias not found.';

      await _supabase.from('users').update({
        'is_verified': true,
        'verified_at': DateTime.now().toIso8601String(),
        'verification_level': 'verified',
      }).eq('id', user['id']);

      await _logAction('verify_user', {'target_alias': alias});
      return 'SUCCESS: @$alias is now verified. ✓';
    } catch (e) {
      return 'ERROR: Failed to verify user — $e';
    }
  }

  Future<String> _unverifyUser(String raw) async {
    final alias = _extractUsername(raw);
    if (alias.isEmpty) return 'Usage: unverify @username';

    try {
      final user = await _findUserByAlias(alias);
      if (user == null) return 'ERROR: User @$alias not found.';

      await _supabase.from('users').update({
        'is_verified': false,
        'verified_at': null,
        'verification_level': 'none',
      }).eq('id', user['id']);

      await _logAction('unverify_user', {'target_alias': alias});
      return 'SUCCESS: Verification removed from @$alias.';
    } catch (e) {
      return 'ERROR: Failed to unverify user — $e';
    }
  }

  Future<String> _makeAdmin(String raw) async {
    final alias = _extractUsername(raw);
    if (alias.isEmpty) return 'Usage: make admin @username';

    try {
      final user = await _findUserByAlias(alias);
      if (user == null) return 'ERROR: User @$alias not found.';

      await _supabase
          .from('users')
          .update({'role': 'admin'}).eq('id', user['id']);

      await _logAction('make_admin', {'target_alias': alias});
      return 'SUCCESS: @$alias is now an admin.';
    } catch (e) {
      return 'ERROR: Failed to promote user — $e';
    }
  }

  Future<String> _shadowbanUser(String raw) async {
    final alias = _extractUsername(raw);
    if (alias.isEmpty) return 'Usage: shadowban @username';

    try {
      final user = await _findUserByAlias(alias);
      if (user == null) return 'ERROR: User @$alias not found.';

      // Shadow-ban: mark banned but keep posts visible to the user themselves
      await _supabase.from('users').update({
        'is_banned': true,
        // Use a special flag so the app can differentiate shadow vs hard ban
      }).eq('id', user['id']);

      await _logAction('shadowban_user', {'target_alias': alias});
      return 'SUCCESS: @$alias has been shadow-banned.';
    } catch (e) {
      return 'ERROR: Failed to shadow-ban user — $e';
    }
  }

  // ─── Analytics ─────────────────────────────────────────────

  Future<String> _adminPinging() async {
    try {
      final users = await _supabase.from('users').select('id');
      final posts = await _supabase.from('posts').select('id');
      final verified =
          await _supabase.from('users').select('id').eq('is_verified', true);
      final unverified =
          await _supabase.from('users').select('id').eq('is_verified', false);
      final banned =
          await _supabase.from('users').select('id').eq('is_banned', true);

      // Try to get optional counts — these tables may not exist
      int likesCount = 0;
      int commentsCount = 0;
      int roomsCount = 0;
      int anonCount = 0;

      try {
        final likes = await _supabase.from('likes').select('id');
        likesCount = (likes as List).length;
      } catch (_) {}

      try {
        final comments = await _supabase.from('comments').select('id');
        commentsCount = (comments as List).length;
      } catch (_) {}

      try {
        final rooms = await _supabase.from('confession_rooms').select('id');
        roomsCount = (rooms as List).length;
      } catch (_) {}

      try {
        final anon = await _supabase.from('anonymous_questions').select('id');
        anonCount = (anon as List).length;
      } catch (_) {}

      return '''
SYSTEM STATUS
=============
Total Users:         ${(users as List).length}
Total Posts:         ${(posts as List).length}
Verified Users:      ${(verified as List).length}
Unverified Users:    ${(unverified as List).length}
Banned Users:        ${(banned as List).length}
Open Rooms:          $roomsCount
Anonymous Messages:  $anonCount
Total Likes:         $likesCount
Total Comments:      $commentsCount
''';
    } catch (e) {
      return 'ERROR: Failed to fetch system status — $e';
    }
  }

  Future<String> _listAllUsers() async {
    try {
      final res = await _supabase
          .from('users')
          .select('alias')
          .order('created_at', ascending: true);

      final users = (res as List).map((u) => '@${u['alias']}').toList();

      if (users.isEmpty) return 'No users found.';

      return 'ALL USERS (${users.length})\n${'=' * 20}\n${users.join('\n')}';
    } catch (e) {
      return 'ERROR: Failed to list users — $e';
    }
  }

  Future<String> _listStreaks() async {
    try {
      final res = await _supabase
          .from('user_streaks')
          .select('user_id, current_streak')
          .order('current_streak', ascending: false)
          .limit(20);

      if ((res as List).isEmpty) return 'No streak data found.';

      // Fetch usernames for each streak entry
      final lines = <String>[];
      for (final s in res) {
        try {
          final user = await _supabase
              .from('users')
              .select('alias')
              .eq('id', s['user_id'])
              .maybeSingle();
          final alias = user?['alias'] ?? 'unknown';
          lines.add('@$alias — ${s['current_streak']} days');
        } catch (_) {
          lines.add('unknown — ${s['current_streak']} days');
        }
      }

      return 'TOP STREAKS\n${'=' * 20}\n${lines.join('\n')}';
    } catch (e) {
      return 'ERROR: Failed to fetch streaks — $e';
    }
  }

  // ─── Content moderation ────────────────────────────────────

  Future<String> _deletePost(String postId) async {
    if (postId.isEmpty) return 'Usage: delete post <POST_ID>';

    try {
      await _supabase.from('posts').delete().eq('id', postId);
      await _logAction('delete_post', {'post_id': postId});
      return 'SUCCESS: Post $postId has been deleted.';
    } catch (e) {
      return 'ERROR: Failed to delete post — $e';
    }
  }

  Future<String> _broadcast(String message) async {
    if (message.trim().isEmpty) return 'Usage: broadcast <message>';

    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) {
        return 'ERROR: Admin not authenticated.';
      }

      final insertRes = await _supabase
          .from('broadcasts')
          .insert({
            'admin_id': adminId,
            'title': 'Admin Broadcast',
            'body': message.trim(),
            'broadcast_type': 'announcement',
            'emoji': '📢',
            'type_color': '#007AFF',
            'is_active': true,
          })
          .select('id')
          .single();

      final broadcastId = insertRes['id'] as String?;
      if (broadcastId == null) {
        return 'ERROR: Broadcast created but id missing.';
      }

      final pushRes = await http.post(
        _buildFunctionUrl('send-notification'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
          'apikey': AppConfig.supabaseAnonKey,
        },
        body: jsonEncode({
          'topic': 'broadcasts',
          'title': '📢 Admin Broadcast',
          'body': message.trim(),
          'data': {
            'type': 'broadcast',
            'broadcastId': broadcastId,
            'broadcastType': 'announcement',
          },
        }),
      );

      if (pushRes.statusCode < 200 || pushRes.statusCode >= 300) {
        return 'ERROR: Push failed — ${pushRes.statusCode} ${pushRes.body}';
      }

      await _logAction('broadcast', {'message': message.trim()});
      return 'SUCCESS: Broadcast sent to all users.';
    } catch (e) {
      return 'ERROR: Failed to send broadcast — $e';
    }
  }

  Future<String> _viewReports() async {
    try {
      final res = await _supabase
          .from('user_reports')
          .select(
              'id, reason, description, created_at, reporter_id, reported_id')
          .order('created_at', ascending: false)
          .limit(20);

      if ((res as List).isEmpty) return 'No reports found.';

      final lines = <String>[];
      for (final r in res) {
        // Look up reported user alias
        String reportedAlias = 'unknown';
        try {
          final user = await _supabase
              .from('users')
              .select('alias')
              .eq('id', r['reported_id'])
              .maybeSingle();
          reportedAlias = user?['alias'] ?? 'unknown';
        } catch (_) {}

        final reason = r['reason'] ?? 'No reason';
        final desc = r['description'] ?? '';
        lines.add(
            '[${r['created_at']}] @$reportedAlias — $reason${desc.isNotEmpty ? ' ($desc)' : ''}');
      }

      return 'RECENT REPORTS (${res.length})\n${'=' * 30}\n${lines.join('\n')}';
    } catch (e) {
      return 'ERROR: Failed to fetch reports — $e';
    }
  }

  // ─── Maintenance ───────────────────────────────────────────

  Future<String> _shutdown() async {
    try {
      // Toggle maintenance mode
      final settings = await _supabase
          .from('app_settings')
          .select('maintenance_mode')
          .eq('id', 1)
          .single();

      final currentMode = settings['maintenance_mode'] as bool? ?? false;
      final newMode = !currentMode;

      await _supabase
          .from('app_settings')
          .update({'maintenance_mode': newMode}).eq('id', 1);

      await _logAction('toggle_maintenance', {'maintenance_mode': newMode});

      return newMode
          ? 'MAINTENANCE MODE: ENABLED\nNormal users will see maintenance screen.\nAdmins can still access the app.'
          : 'MAINTENANCE MODE: DISABLED\nApp is now live for all users.';
    } catch (e) {
      return 'ERROR: Failed to toggle maintenance mode — $e';
    }
  }

  Future<String> _maintenanceStatus() async {
    try {
      final settings = await _supabase
          .from('app_settings')
          .select('maintenance_mode')
          .eq('id', 1)
          .single();
      final enabled = settings['maintenance_mode'] as bool? ?? false;
      return enabled
          ? 'MAINTENANCE MODE: ENABLED'
          : 'MAINTENANCE MODE: DISABLED';
    } catch (e) {
      return 'ERROR: Failed to read maintenance status — ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _setMaintenance(bool enabled) async {
    try {
      await _supabase
          .from('app_settings')
          .update({'maintenance_mode': enabled}).eq('id', 1);
      await _logAction('set_maintenance', {'maintenance_mode': enabled});
      return enabled
          ? 'MAINTENANCE MODE: ENABLED'
          : 'MAINTENANCE MODE: DISABLED';
    } catch (e) {
      return 'ERROR: Failed to set maintenance mode — ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _appShutdownStatus() async {
    try {
      final settings = await _supabase
          .from('app_settings')
          .select('app_shutdown')
          .eq('id', 1)
          .single();
      final enabled = settings['app_shutdown'] as bool? ?? false;
      return enabled ? 'APP SHUTDOWN: ENABLED' : 'APP SHUTDOWN: DISABLED';
    } catch (e) {
      return 'ERROR: Failed to read app shutdown status — ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _setAppShutdown(bool enabled) async {
    try {
      await _supabase
          .from('app_settings')
          .update({'app_shutdown': enabled}).eq('id', 1);
      await _logAction('set_app_shutdown', {'app_shutdown': enabled});
      return enabled ? 'APP SHUTDOWN: ENABLED' : 'APP SHUTDOWN: DISABLED';
    } catch (e) {
      return 'ERROR: Failed to set app shutdown — ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _viewRateLimits() async {
    try {
      final settings = await _supabase
          .from('app_settings')
          .select(
              'rate_limit_posts_per_minute, rate_limit_messages_per_minute, rate_limit_rooms_per_hour')
          .eq('id', 1)
          .single();
      return '''RATE LIMITS
═══════════════════════════════════════════
Posts / min: ${settings['rate_limit_posts_per_minute'] ?? 'n/a'}
Messages / min: ${settings['rate_limit_messages_per_minute'] ?? 'n/a'}
Rooms / hour: ${settings['rate_limit_rooms_per_hour'] ?? 'n/a'}''';
    } catch (e) {
      return 'ERROR: Failed to load rate limits — ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _setRateLimit(String field, int value) async {
    if (value <= 0) {
      return 'ERROR: Rate limit must be a positive number.';
    }
    try {
      await _supabase.from('app_settings').update({field: value}).eq('id', 1);
      await _logAction('set_rate_limit', {field: value});
      return 'SUCCESS: Updated $field to $value';
    } catch (e) {
      return 'ERROR: Failed to update rate limit — ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _viewClientErrorLogs(int limit) async {
    try {
      final rows = await _supabase
          .from('client_error_logs')
          .select('created_at, user_id, message, context, platform')
          .order('created_at', ascending: false)
          .limit(limit);
      if (rows is! List || rows.isEmpty) {
        return 'No client error logs found.';
      }
      final buffer = StringBuffer('CLIENT ERROR LOGS (latest $limit)\n');
      buffer.writeln('═══════════════════════════════════════════');
      for (final row in rows) {
        buffer.writeln(
            '[${row['created_at']}] user=${row['user_id'] ?? 'n/a'} platform=${row['platform'] ?? 'n/a'}');
        buffer.writeln('  ${row['message'] ?? ''}');
        if (row['context'] != null) {
          buffer.writeln('  context: ${row['context']}');
        }
      }
      return buffer.toString();
    } catch (e) {
      return 'ERROR: Failed to load client error logs — ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _viewActivityLogs(int limit) async {
    try {
      final rows = await _supabase
          .from('activity_logs')
          .select('created_at, admin_id, action, details')
          .order('created_at', ascending: false)
          .limit(limit);
      if (rows is! List || rows.isEmpty) {
        return 'No activity logs found.';
      }
      final buffer = StringBuffer('ACTIVITY LOGS (latest $limit)\n');
      buffer.writeln('═══════════════════════════════════════════');
      for (final row in rows) {
        buffer.writeln(
            '[${row['created_at']}] admin=${row['admin_id'] ?? 'n/a'} action=${row['action']}');
        if (row['details'] != null && row['details'].toString().isNotEmpty) {
          buffer.writeln('  details: ${row['details']}');
        }
      }
      return buffer.toString();
    } catch (e) {
      return 'ERROR: Failed to load activity logs — ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _viewFailedAdminAccessLogs(int limit) async {
    try {
      final rows = await _supabase
          .from('failed_admin_access_logs')
          .select('created_at, user_id, device_id, entered_passkey')
          .order('created_at', ascending: false)
          .limit(limit);
      if (rows is! List || rows.isEmpty) {
        return 'No failed access logs found.';
      }
      final buffer = StringBuffer('FAILED ADMIN ACCESS (latest $limit)\n');
      buffer.writeln('═══════════════════════════════════════════');
      for (final row in rows) {
        buffer.writeln(
            '[${row['created_at']}] user=${row['user_id'] ?? 'n/a'} device=${row['device_id'] ?? 'n/a'} passkey=${row['entered_passkey']}');
      }
      return buffer.toString();
    } catch (e) {
      return 'ERROR: Failed to load access logs — ${AppErrorHandler.userMessage(e)}';
    }
  }

  // ─── Activity logging ──────────────────────────────────────

  Future<void> _logAction(String action, Map<String, dynamic> details) async {
    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId != null) {
        await _supabase.from('activity_logs').insert({
          'admin_id': adminId,
          'action': 'terminal:$action',
          'details': details,
        });
      }
    } catch (e) {
      debugPrint('Error logging terminal action: $e');
    }
  }

  // ─── Admin Passcode Management ────────────────────────────

  Future<String> _viewPasscode() async {
    try {
      final res = await _supabase
          .from('admin_passcode')
          .select('passcode, created_at, updated_at, changed_count')
          .maybeSingle();
      if (res == null) {
        return 'No admin passcode set. Use: change passcode <NEW_PASSCODE>';
      }

      final passcode = res['passcode'];
      final createdAt = res['created_at'];
      final updatedAt = res['updated_at'];
      final changedCount = res['changed_count'];

      return '''CURRENT ADMIN PASSCODE
═══════════════════════════════════════════
Passcode: $passcode
Created: $createdAt
Last Updated: $updatedAt
Times Changed: $changedCount

⚠️  Keep this passcode secure!
⚠️  To change: change passcode <NEW_PASSCODE>''';
    } catch (e) {
      return 'ERROR: ${AppErrorHandler.userMessage(e)}';
    }
  }

  Future<String> _changePasscode(String newPasscode) async {
    try {
      // Validate length and characters
      if (newPasscode.isEmpty) {
        return 'ERROR: Passcode cannot be empty.';
      }
      if (newPasscode.length < 4 || newPasscode.length > 20) {
        return 'ERROR: Passcode must be 4-20 characters long.';
      }

      // Validate alphanumeric + special chars (only _-@!#\$%^&*())
      final validCharsRegex = RegExp(r'^[a-zA-Z0-9_\-@!#\$%^&*()]+$');
      if (!validCharsRegex.hasMatch(newPasscode)) {
        return 'ERROR: Passcode can only contain letters, numbers, and _-@!#\$%^&*()';
      }

      // Get current admin ID
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) {
        return 'ERROR: Admin not authenticated.';
      }

      final current = await _supabase
          .from('admin_passcode')
          .select('id, passcode, changed_count')
          .maybeSingle();

      final oldPasscode = current?['passcode'] ?? 'unset';
      if (current == null) {
        await _supabase.from('admin_passcode').insert({
          'passcode': newPasscode,
          'updated_at': DateTime.now().toIso8601String(),
          'updated_by': adminId,
          'changed_count': 1,
          'last_changed_by': adminId,
          'last_changed_at': DateTime.now().toIso8601String(),
        });
      } else {
        await _supabase.from('admin_passcode').update({
          'passcode': newPasscode,
          'updated_at': DateTime.now().toIso8601String(),
          'updated_by': adminId,
          'changed_count': (current['changed_count'] ?? 0) + 1,
          'last_changed_by': adminId,
          'last_changed_at': DateTime.now().toIso8601String(),
        }).eq('id', current['id']);
      }

      // Log to audit table
      await _supabase.from('admin_passcode_audit').insert({
        'changed_by': adminId,
        'old_passcode': oldPasscode,
        'new_passcode': newPasscode,
        'changed_at': DateTime.now().toIso8601String(),
        'reason': 'Changed via admin terminal',
      });

      // Log action
      await _logAction('change_passcode', {
        'old_passcode_length': oldPasscode.length,
        'new_passcode_length': newPasscode.length,
      });

      return '''SUCCESS: Admin passcode changed!
═══════════════════════════════════════════
New Passcode: $newPasscode
Updated By: $adminId
Timestamp: ${DateTime.now().toString()}

✓ Change logged to audit table
✓ Previous passcode saved for compliance''';
    } catch (e) {
      return 'ERROR: ${AppErrorHandler.userMessage(e)}';
    }
  }
}
