import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import 'app_settings_screen.dart';
import 'verify_users_screen.dart';
import 'moderate_posts_screen.dart';
import 'ban_users_screen.dart';
import 'feedback_screen.dart';
import 'activity_logs_screen.dart';
import 'manage_admins_screen.dart';
import 'broadcast_screen.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Admin Panel'),
        backgroundColor: AppConstants.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAdminCard(
            'App Settings',
            'Lock app, maintenance mode',
            Icons.settings_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const AppSettingsScreen())),
          ),
          const SizedBox(height: 12),
          _buildAdminCard(
            'Verify Users',
            'Manage verified badges',
            Icons.verified_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const VerifyUsersScreen())),
          ),
          const SizedBox(height: 12),
          _buildAdminCard(
            'Moderate Posts',
            'Delete inappropriate content',
            Icons.delete_outline_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ModeratePostsScreen())),
          ),
          const SizedBox(height: 12),
          _buildAdminCard(
            'Ban Users',
            'Suspend user accounts',
            Icons.block_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const BanUsersScreen())),
          ),
          const SizedBox(height: 12),
          _buildAdminCard(
            'Feedback',
            'View user feedback',
            Icons.feedback_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const FeedbackScreen())),
          ),
          const SizedBox(height: 12),
          _buildAdminCard(
            'Activity Logs',
            'Monitor app activity',
            Icons.history_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ActivityLogsScreen())),
          ),
          const SizedBox(height: 12),
          _buildAdminCard(
            'Manage Admins',
            'Grant or remove admin privileges',
            Icons.admin_panel_settings_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ManageAdminsScreen())),
          ),
          const SizedBox(height: 12),
          _buildAdminCard(
            'Broadcast Messages',
            'Send push notifications to all users',
            Icons.campaign_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const BroadcastScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminCard(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryBlue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppConstants.primaryBlue, size: 24),
                ),
                const SizedBox(width: 16),
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
                const Icon(
                  Icons.chevron_right,
                  color: AppConstants.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
