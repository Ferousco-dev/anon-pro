import 'package:flutter/material.dart';
import '../../models/user_streak_model.dart';
import '../../services/streak_service.dart';
import '../../utils/constants.dart';

class StreakProgressScreen extends StatefulWidget {
  final String userId;

  const StreakProgressScreen({
    super.key,
    required this.userId,
  });

  @override
  State<StreakProgressScreen> createState() => _StreakProgressScreenState();
}

class _StreakProgressScreenState extends State<StreakProgressScreen> {
  final StreakService _streakService = StreakService();
  UserStreakModel? _streak;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    try {
      final streak = await _streakService.getStreak(widget.userId);
      if (mounted) {
        setState(() {
          _streak = streak;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading streak: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Verification Progress'),
        backgroundColor: AppConstants.black,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : _streak == null
              ? const Center(
                  child: Text('No streak data'),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Verification status card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _streak!.isEligibleForVerification
                                ? [
                                    AppConstants.green.withOpacity(0.2),
                                    AppConstants.green.withOpacity(0.05),
                                  ]
                                : [
                                    AppConstants.primaryBlue.withOpacity(0.2),
                                    AppConstants.primaryBlue.withOpacity(0.05),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _streak!.isEligibleForVerification
                                ? AppConstants.green.withOpacity(0.5)
                                : AppConstants.primaryBlue.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _streak!.isEligibleForVerification
                                  ? Icons.verified_rounded
                                  : Icons.hourglass_empty_rounded,
                              size: 48,
                              color: _streak!.isEligibleForVerification
                                  ? AppConstants.green
                                  : AppConstants.primaryBlue,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _streak!.isEligibleForVerification
                                  ? '🎉 You\'re Eligible for Verification!'
                                  : 'Almost There! Keep Posting',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _streak!.isEligibleForVerification
                                  ? 'You can now request verification status'
                                  : 'Keep creating content to unlock verified status',
                              style: const TextStyle(
                                color: AppConstants.textSecondary,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Overall progress
                      Text(
                        'Overall Progress',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _streak!.verificationProgress / 100,
                          minHeight: 8,
                          backgroundColor: AppConstants.darkGray,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _streak!.isEligibleForVerification
                                ? AppConstants.green
                                : AppConstants.primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_streak!.verificationProgress.toStringAsFixed(0)}% Complete',
                        style: const TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Posts requirement
                      _buildRequirementCard(
                        title: 'Total Posts',
                        current: _streak!.totalPosts,
                        required: 12,
                        icon: Icons.edit_rounded,
                        isCompleted: _streak!.totalPosts >= 12,
                      ),
                      const SizedBox(height: 16),

                      // Engagement requirement
                      _buildRequirementCard(
                        title: 'Posts with Engagement',
                        current: _streak!.postsWithEngagement,
                        required: 5,
                        icon: Icons.favorite_rounded,
                        isCompleted: _streak!.postsWithEngagement >= 5,
                        subtitle:
                            'Posts with at least 1 like or comment count as engaged',
                      ),
                      const SizedBox(height: 32),

                      // Tips
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppConstants.darkGray.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppConstants.primaryBlue.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outlined,
                                  color: AppConstants.primaryBlue,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Tips to Get Verified',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildTip(
                                '📝 Post regularly - Mix anonymous and public posts'),
                            _buildTip(
                                '👍 Engage others - Get likes and comments on your posts'),
                            _buildTip(
                                '⏰ Be consistent - Keep posting to maintain momentum'),
                            _buildTip(
                                '💬 Share thoughts - Authentic content gets more engagement'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRequirementCard({
    required String title,
    required int current,
    required int required,
    required IconData icon,
    required bool isCompleted,
    String? subtitle,
  }) {
    final percentage = (current / required * 100).clamp(0, 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isCompleted ? AppConstants.green : AppConstants.primaryBlue)
              .withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isCompleted
                          ? AppConstants.green
                          : AppConstants.primaryBlue)
                      .withOpacity(0.2),
                ),
                child: Icon(
                  icon,
                  color: isCompleted
                      ? AppConstants.green
                      : AppConstants.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '$current/$required',
                style: TextStyle(
                  color: isCompleted
                      ? AppConstants.green
                      : AppConstants.primaryBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 6,
              backgroundColor: AppConstants.lightGray.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? AppConstants.green : AppConstants.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${percentage.toStringAsFixed(0)}% progress',
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppConstants.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }
}
