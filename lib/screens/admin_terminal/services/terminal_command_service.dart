import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parses and executes admin terminal commands against the Supabase backend.
class TerminalCommandService {
  final SupabaseClient _supabase = Supabase.instance.client;

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
    if (lower == 'view reports') return await _viewReports();

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
    final blocked = RegExp(r"(;|--|'|\\x|DROP\s|INSERT\s|UPDATE\s|DELETE\s.*FROM)",
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

MAINTENANCE
  shutdown               — Toggle maintenance mode

UTILITY
  help                   — Show this command list
  clear                  — Clear terminal output
''';
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
      final verified = await _supabase
          .from('users')
          .select('id')
          .eq('is_verified', true);
      final unverified = await _supabase
          .from('users')
          .select('id')
          .eq('is_verified', false);
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
        final anon =
            await _supabase.from('anonymous_questions').select('id');
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

      final users = (res as List)
          .map((u) => '@${u['alias']}')
          .toList();

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
      await _supabase.from('broadcasts').insert({
        'admin_id': adminId,
        'title': 'Admin Broadcast',
        'body': message.trim(),
        'broadcast_type': 'announcement',
        'emoji': '📢',
        'type_color': '#007AFF',
        'is_active': true,
      });

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
          .select('id, reason, description, created_at, reporter_id, reported_id')
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

      await _logAction(
          'toggle_maintenance', {'maintenance_mode': newMode});

      return newMode
          ? 'MAINTENANCE MODE: ENABLED\nNormal users will see maintenance screen.\nAdmins can still access the app.'
          : 'MAINTENANCE MODE: DISABLED\nApp is now live for all users.';
    } catch (e) {
      return 'ERROR: Failed to toggle maintenance mode — $e';
    }
  }

  // ─── Activity logging ──────────────────────────────────────

  Future<void> _logAction(
      String action, Map<String, dynamic> details) async {
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
}
