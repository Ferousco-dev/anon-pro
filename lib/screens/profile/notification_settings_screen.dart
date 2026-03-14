import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/constants.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final String userId;

  const NotificationSettingsScreen({super.key, required this.userId});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;

  bool _newFollower = true;
  bool _newPost = true;
  bool _postLike = true;
  bool _postComment = true;
  bool _roomCreated = true;
  bool _roomMessage = false;
  bool _questionReply = true;
  bool _streakUnlocked = true;
  bool _dmMessage = true;
  bool _previewEnabled = true;
  TimeOfDay? _quietStart;
  TimeOfDay? _quietEnd;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadLocalSettings();
  }

  Future<void> _loadLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final startMinutes = prefs.getInt('notif_quiet_start');
    final endMinutes = prefs.getInt('notif_quiet_end');
    final preview = prefs.getBool('notif_preview_enabled');

    setState(() {
      _previewEnabled = preview ?? true;
      if (startMinutes != null && endMinutes != null) {
        _quietStart = TimeOfDay(
          hour: startMinutes ~/ 60,
          minute: startMinutes % 60,
        );
        _quietEnd = TimeOfDay(
          hour: endMinutes ~/ 60,
          minute: endMinutes % 60,
        );
      }
    });
  }

  Future<void> _saveQuietHours(
      {required TimeOfDay start, required TimeOfDay end}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_quiet_start', start.hour * 60 + start.minute);
    await prefs.setInt('notif_quiet_end', end.hour * 60 + end.minute);
    setState(() {
      _quietStart = start;
      _quietEnd = end;
    });
  }

  Future<void> _setPreviewEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_preview_enabled', value);
    setState(() => _previewEnabled = value);
  }

  Future<void> _loadSettings() async {
    try {
      final res = await _supabase
          .from('notification_settings')
          .select('*')
          .eq('user_id', widget.userId)
          .maybeSingle();

      if (res == null) {
        await _supabase.from('notification_settings').insert({
          'user_id': widget.userId,
          'notify_new_follower': true,
          'notify_new_post': true,
          'notify_post_like': true,
          'notify_post_comment': true,
          'notify_room_created': true,
          'notify_room_message': false,
          'notify_question_reply': true,
          'notify_streak_unlocked': true,
          'notify_dm_message': true,
        });
        return _loadSettings();
      }

      if (!mounted) return;
      setState(() {
        _newFollower = res['notify_new_follower'] == true;
        _newPost = res['notify_new_post'] == true;
        _postLike = res['notify_post_like'] == true;
        _postComment = res['notify_post_comment'] == true;
        _roomCreated = res['notify_room_created'] == true;
        _roomMessage = res['notify_room_message'] == true;
        _questionReply = res['notify_question_reply'] == true;
        _streakUnlocked = res['notify_streak_unlocked'] == true;
        _dmMessage = res['notify_dm_message'] == true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load settings: $e'),
          backgroundColor: AppConstants.red,
        ),
      );
    }
  }

  Future<void> _updateSetting(String field, bool value) async {
    try {
      await _supabase
          .from('notification_settings')
          .update({field: value}).eq('user_id', widget.userId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: AppConstants.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: AppConstants.black,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionTitle('Local Settings'),
                _buildToggle(
                  'Show notification previews',
                  _previewEnabled,
                  (v) => _setPreviewEnabled(v),
                ),
                _buildQuietHoursCard(),
                const SizedBox(height: 16),
                _buildSectionTitle('Notification Types'),
                _buildToggle(
                  'New followers',
                  _newFollower,
                  (v) {
                    setState(() => _newFollower = v);
                    _updateSetting('notify_new_follower', v);
                  },
                ),
                _buildToggle(
                  'New posts',
                  _newPost,
                  (v) {
                    setState(() => _newPost = v);
                    _updateSetting('notify_new_post', v);
                  },
                ),
                _buildToggle(
                  'Post likes',
                  _postLike,
                  (v) {
                    setState(() => _postLike = v);
                    _updateSetting('notify_post_like', v);
                  },
                ),
                _buildToggle(
                  'Post comments',
                  _postComment,
                  (v) {
                    setState(() => _postComment = v);
                    _updateSetting('notify_post_comment', v);
                  },
                ),
                _buildToggle(
                  'Confession rooms created',
                  _roomCreated,
                  (v) {
                    setState(() => _roomCreated = v);
                    _updateSetting('notify_room_created', v);
                  },
                ),
                _buildToggle(
                  'Confession room messages',
                  _roomMessage,
                  (v) {
                    setState(() => _roomMessage = v);
                    _updateSetting('notify_room_message', v);
                  },
                ),
                _buildToggle(
                  'Question replies',
                  _questionReply,
                  (v) {
                    setState(() => _questionReply = v);
                    _updateSetting('notify_question_reply', v);
                  },
                ),
                _buildToggle(
                  'Streak unlocks',
                  _streakUnlocked,
                  (v) {
                    setState(() => _streakUnlocked = v);
                    _updateSetting('notify_streak_unlocked', v);
                  },
                ),
                _buildToggle(
                  'Direct messages',
                  _dmMessage,
                  (v) {
                    setState(() => _dmMessage = v);
                    _updateSetting('notify_dm_message', v);
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildQuietHoursCard() {
    final startLabel = _quietStart?.format(context) ?? 'Not set';
    final endLabel = _quietEnd?.format(context) ?? 'Not set';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ListTile(
        title: const Text('Quiet hours',
            style: TextStyle(color: Colors.white)),
        subtitle: Text(
          '$startLabel → $endLabel',
          style: const TextStyle(color: AppConstants.textSecondary),
        ),
        trailing: const Icon(Icons.timer, color: Colors.white70),
        onTap: () async {
          final start = await showTimePicker(
            context: context,
            initialTime: _quietStart ?? const TimeOfDay(hour: 22, minute: 0),
          );
          if (start == null) return;
          final end = await showTimePicker(
            context: context,
            initialTime: _quietEnd ?? const TimeOfDay(hour: 7, minute: 0),
          );
          if (end == null) return;
          await _saveQuietHours(start: start, end: end);
        },
      ),
    );
  }

  Widget _buildToggle(
      String title, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: AppConstants.primaryBlue,
      ),
    );
  }
}
