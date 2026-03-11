import 'package:flutter/material.dart';
import '../../utils/constants.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await supabase
          .from('app_settings')
          .select('maintenance_mode, app_shutdown')
          .single();

      if (mounted) {
        setState(() {
          _maintenanceMode = response['maintenance_mode'] ?? false;
          _appShutdown = response['app_shutdown'] ?? false;
          _isLoading = false;
        });
      }
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
            content: Text('Failed to update setting: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
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
}
