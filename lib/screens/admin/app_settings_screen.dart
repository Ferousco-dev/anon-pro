import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../utils/app_error_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase client
final supabase = Supabase.instance.client;

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _maintenanceMode = false;
  bool _appShutdown = false;
  bool _isLoading = true;
  final _streakPostsController = TextEditingController();
  final _streakEngagedPostsController = TextEditingController();
  final _streakTotalEngagementController = TextEditingController();
  final _streakAvgLikesController = TextEditingController();
  final _strikeLimitController = TextEditingController();
  bool _autoBanOnStrike = false;
  final _ratePostsController = TextEditingController();
  final _rateMessagesController = TextEditingController();
  final _rateRoomsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _streakPostsController.dispose();
    _streakEngagedPostsController.dispose();
    _streakTotalEngagementController.dispose();
    _streakAvgLikesController.dispose();
    _strikeLimitController.dispose();
    _ratePostsController.dispose();
    _rateMessagesController.dispose();
    _rateRoomsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await supabase
          .from('app_settings')
          .select('maintenance_mode, app_shutdown, streak_required_posts, '
              'streak_required_engaged_posts, '
              'streak_required_total_engagement, streak_required_avg_likes, '
              'strike_limit, auto_ban_on_strike, '
              'rate_limit_posts_per_minute, rate_limit_messages_per_minute, '
              'rate_limit_rooms_per_hour')
          .eq('id', 1)
          .maybeSingle();

      if (response == null) {
        await _createDefaultSettings();
        return _loadSettings();
      }

      if (!mounted) return;
      setState(() {
        _maintenanceMode = response['maintenance_mode'] ?? false;
        _appShutdown = response['app_shutdown'] ?? false;
        _streakPostsController.text =
            (response['streak_required_posts'] ?? 12).toString();
        _streakEngagedPostsController.text =
            (response['streak_required_engaged_posts'] ?? 5).toString();
        _streakTotalEngagementController.text =
            (response['streak_required_total_engagement'] ?? 0).toString();
        _streakAvgLikesController.text =
            (response['streak_required_avg_likes'] ?? 0).toString();
        _strikeLimitController.text =
            (response['strike_limit'] ?? 3).toString();
        _autoBanOnStrike = response['auto_ban_on_strike'] ?? false;
        _ratePostsController.text =
            (response['rate_limit_posts_per_minute'] ?? 5).toString();
        _rateMessagesController.text =
            (response['rate_limit_messages_per_minute'] ?? 20).toString();
        _rateRoomsController.text =
            (response['rate_limit_rooms_per_hour'] ?? 3).toString();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createDefaultSettings() async {
    try {
      await supabase.from('app_settings').insert({
        'maintenance_mode': false,
        'app_shutdown': false,
        'streak_required_posts': 12,
        'streak_required_engaged_posts': 5,
        'streak_required_total_engagement': 0,
        'streak_required_avg_likes': 0,
        'strike_limit': 3,
        'auto_ban_on_strike': false,
        'rate_limit_posts_per_minute': 5,
        'rate_limit_messages_per_minute': 20,
        'rate_limit_rooms_per_hour': 3,
      });
    } catch (e) {
      debugPrint('Error creating default settings: $e');
    }
  }

  Future<void> _updateSetting(String field, bool value) async {
    try {
      await supabase
          .from('app_settings')
          .update({field: value}).eq('id', 1); // Assuming single row

      // Log activity
      await _logActivity('Updated $field to $value');
    } catch (e) {
      debugPrint('Error updating setting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.userMessage(e)),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  Future<void> _updateStreakRequirements() async {
    final totalPosts = int.tryParse(_streakPostsController.text.trim());
    final engagedPosts =
        int.tryParse(_streakEngagedPostsController.text.trim());
    final totalEngagement =
        int.tryParse(_streakTotalEngagementController.text.trim());
    final avgLikes = double.tryParse(_streakAvgLikesController.text.trim());

    if (totalPosts == null ||
        engagedPosts == null ||
        totalEngagement == null ||
        avgLikes == null) {
      _showError('Please enter valid numbers for all fields');
      return;
    }
    if (totalPosts < 0 ||
        engagedPosts < 0 ||
        totalEngagement < 0 ||
        avgLikes < 0) {
      _showError('Values cannot be negative');
      return;
    }

    try {
      await supabase.from('app_settings').update({
        'streak_required_posts': totalPosts,
        'streak_required_engaged_posts': engagedPosts,
        'streak_required_total_engagement': totalEngagement,
        'streak_required_avg_likes': avgLikes,
      }).eq('id', 1);

      await _logActivity(
          'Updated streak requirements: posts=$totalPosts, engaged=$engagedPosts, engagement=$totalEngagement, avg_likes=$avgLikes');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Streak requirements updated'),
            backgroundColor: AppConstants.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating streak requirements: $e');
      _showError(AppErrorHandler.userMessage(e));
    }
  }

  Future<void> _updateModerationSettings() async {
    final strikeLimit = int.tryParse(_strikeLimitController.text.trim());
    if (strikeLimit == null || strikeLimit <= 0) {
      _showError('Strike limit must be a positive number');
      return;
    }
    try {
      await supabase.from('app_settings').update({
        'strike_limit': strikeLimit,
        'auto_ban_on_strike': _autoBanOnStrike,
      }).eq('id', 1);
      await _logActivity('Updated strike_limit to $strikeLimit');
      await _logActivity(
          'Updated auto_ban_on_strike to $_autoBanOnStrike');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Moderation settings updated'),
            backgroundColor: AppConstants.green,
          ),
        );
      }
    } catch (e) {
      _showError(AppErrorHandler.userMessage(e));
    }
  }

  Future<void> _updateRateLimits() async {
    final posts = int.tryParse(_ratePostsController.text.trim());
    final messages = int.tryParse(_rateMessagesController.text.trim());
    final rooms = int.tryParse(_rateRoomsController.text.trim());
    if (posts == null || messages == null || rooms == null) {
      _showError('Rate limits must be valid numbers');
      return;
    }
    if (posts <= 0 || messages <= 0 || rooms <= 0) {
      _showError('Rate limits must be positive');
      return;
    }
    try {
      await supabase.from('app_settings').update({
        'rate_limit_posts_per_minute': posts,
        'rate_limit_messages_per_minute': messages,
        'rate_limit_rooms_per_hour': rooms,
      }).eq('id', 1);
      await _logActivity(
          'Updated rate limits posts=$posts messages=$messages rooms=$rooms');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rate limits updated'),
            backgroundColor: AppConstants.green,
          ),
        );
      }
    } catch (e) {
      _showError(AppErrorHandler.userMessage(e));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppConstants.red,
      ),
    );
  }

  Future<void> _logActivity(String action) async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        await supabase.from('activity_logs').insert({
          'admin_id': currentUser.id,
          'action': action,
          'details': {},
        });
      }
    } catch (e) {
      debugPrint('Error logging activity: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('App Settings'),
        backgroundColor: AppConstants.black,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSettingCard(
                  'Maintenance Mode',
                  'Only admins can login when enabled',
                  _maintenanceMode,
                  (value) {
                    setState(() => _maintenanceMode = value);
                    _updateSetting('maintenance_mode', value);
                  },
                ),
                const SizedBox(height: 16),
                _buildSettingCard(
                  'App Shutdown',
                  'Prevent all users from accessing the app',
                  _appShutdown,
                  (value) {
                    setState(() => _appShutdown = value);
                    _updateSetting('app_shutdown', value);
                  },
                ),
                const SizedBox(height: 16),
                _buildStreakSettingsCard(),
                const SizedBox(height: 16),
                _buildModerationSettingsCard(),
                const SizedBox(height: 16),
                _buildRateLimitCard(),
              ],
            ),
    );
  }

  Widget _buildSettingCard(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppConstants.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppConstants.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Streak Requirements',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Adjust verification challenge thresholds',
              style: TextStyle(
                fontSize: 14,
                color: AppConstants.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildNumberField(
              controller: _streakPostsController,
              label: 'Total posts required',
            ),
            const SizedBox(height: 12),
            _buildNumberField(
              controller: _streakEngagedPostsController,
              label: 'Posts with engagement required',
            ),
            const SizedBox(height: 12),
            _buildNumberField(
              controller: _streakTotalEngagementController,
              label: 'Total engagement required',
            ),
            const SizedBox(height: 12),
            _buildNumberField(
              controller: _streakAvgLikesController,
              label: 'Average likes required',
              allowDecimal: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateStreakRequirements,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryBlue,
                ),
                child: const Text(
                  'Save Requirements',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModerationSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Moderation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Auto‑flagging and strike limits',
              style: TextStyle(
                fontSize: 14,
                color: AppConstants.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildNumberField(
              controller: _strikeLimitController,
              label: 'Strike limit',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _autoBanOnStrike,
              activeColor: AppConstants.primaryBlue,
              onChanged: (value) => setState(() => _autoBanOnStrike = value),
              title: const Text(
                'Auto‑ban on limit',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Ban users when they reach strike limit',
                style: TextStyle(color: AppConstants.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateModerationSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryBlue,
                ),
                child: const Text(
                  'Save Moderation Settings',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateLimitCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rate Limits',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Server-side throttles',
              style: TextStyle(
                fontSize: 14,
                color: AppConstants.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildNumberField(
              controller: _ratePostsController,
              label: 'Posts per minute',
            ),
            const SizedBox(height: 12),
            _buildNumberField(
              controller: _rateMessagesController,
              label: 'Messages per minute',
            ),
            const SizedBox(height: 12),
            _buildNumberField(
              controller: _rateRoomsController,
              label: 'Rooms per hour',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateRateLimits,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryBlue,
                ),
                child: const Text(
                  'Save Rate Limits',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    bool allowDecimal = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: allowDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppConstants.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: AppConstants.lightGray.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppConstants.primaryBlue),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
