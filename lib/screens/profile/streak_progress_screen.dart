import 'package:flutter/material.dart';
import '../../models/user_streak_model.dart';
import '../../models/streak_requirements.dart';
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
  List<Map<String, int>> _dailyPosts = [];
  int _totalEngagement = 0;
  double _avgLikes = 0;
  StreakRequirements _requirements = StreakRequirements.defaults;
  bool _isLoading = true;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    try {
      // Initialize streak if it doesn't exist
      await _streakService.initializeStreak(widget.userId);

      final [streak, dailyPosts, engagement, avgLikes, requirements] =
          await Future.wait([
        _streakService.getStreak(widget.userId),
        _streakService.getDailyPostsCount(widget.userId),
        _streakService.getTotalEngagement(widget.userId),
        _streakService.getAverageLikesPerPost(widget.userId),
        _streakService.getStreakRequirements(),
      ]);

      if (mounted) {
        setState(() {
          _streak = streak as UserStreakModel?;
          _dailyPosts = dailyPosts as List<Map<String, int>>;
          _totalEngagement = engagement as int;
          _avgLikes = avgLikes as double;
          _requirements = requirements as StreakRequirements;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading streak data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unlockVerification() async {
    final isEligible = _streak != null &&
        _streak!.isEligibleForVerificationWith(
          _requirements.totalPostsRequired,
          _requirements.engagedPostsRequired,
          _requirements.totalEngagementRequired,
          _requirements.avgLikesRequired,
          totalEngagement: _totalEngagement,
          avgLikes: _avgLikes,
        );
    if (!isEligible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to meet the requirements first!'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final success = await _streakService.requestVerification(widget.userId);

      if (mounted) {
        setState(() => _isVerifying = false);

        if (success) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppConstants.darkGray,
              title: const Text(
                '🎉 Congratulations!',
                style: TextStyle(color: Colors.white),
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You\'ve unlocked verified status! 🔥',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'You can now access:',
                    style: TextStyle(color: AppConstants.textSecondary),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '✓ Q&A Room - Answer anonymous questions\n✓ Confession Rooms - Share confessions safely\n✓ Verified Badge - Show on your profile',
                    style: TextStyle(color: AppConstants.textSecondary),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryBlue,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  child: const Text('Awesome!'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Already verified!'),
              backgroundColor: AppConstants.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : _streak == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_rounded,
                        size: 48,
                        color: AppConstants.textSecondary,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Unable to load streak data',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Please try again later',
                        style: TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Status Header
                      _buildStatusCard(),
                      const SizedBox(height: 24),

                      // Overall Progress
                      _buildProgressSection(),
                      const SizedBox(height: 24),

                      // Activity Graph
                      _buildActivityGraph(),
                      const SizedBox(height: 24),

                      // Stats Grid
                      _buildStatsGrid(),
                      const SizedBox(height: 24),

                      // Verification Challenge Card
                      _buildVerificationChallenge(),
                      const SizedBox(height: 24),

                      // Requirements
                      _buildRequirementsSection(),
                      const SizedBox(height: 24),

                      // Next Milestones
                      _buildNextMilestonesSection(),
                      const SizedBox(height: 24),

                      // Tips
                      _buildTipsSection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatusCard() {
    final isEligible = _streak!.isEligibleForVerificationWith(
      _requirements.totalPostsRequired,
      _requirements.engagedPostsRequired,
      _requirements.totalEngagementRequired,
      _requirements.avgLikesRequired,
      totalEngagement: _totalEngagement,
      avgLikes: _avgLikes,
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isEligible
              ? [
                  AppConstants.green.withOpacity(0.2),
                  AppConstants.green.withOpacity(0.05),
                ]
              : [
                  AppConstants.primaryBlue.withOpacity(0.2),
                  AppConstants.primaryBlue.withOpacity(0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isEligible ? AppConstants.green : AppConstants.primaryBlue)
              .withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isEligible ? Icons.verified_rounded : Icons.hourglass_empty_rounded,
            size: 56,
            color: isEligible ? AppConstants.green : AppConstants.primaryBlue,
          ),
          const SizedBox(height: 16),
          Text(
            isEligible
                ? '✨ Ready for Verification! ✨'
                : '📈 Keep Building Your Streak',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isEligible
                ? 'You\'ve met all requirements. Unlock your verified badge now!'
                : 'Post regularly and get engagement to unlock verified status',
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    final isEligible = _streak!.isEligibleForVerificationWith(
      _requirements.totalPostsRequired,
      _requirements.engagedPostsRequired,
      _requirements.totalEngagementRequired,
      _requirements.avgLikesRequired,
      totalEngagement: _totalEngagement,
      avgLikes: _avgLikes,
    );
    final progress = _streak!.verificationProgressWith(
      totalPostsRequired: _requirements.totalPostsRequired,
      engagedPostsRequired: _requirements.engagedPostsRequired,
      totalEngagementRequired: _requirements.totalEngagementRequired,
      avgLikesRequired: _requirements.avgLikesRequired,
      totalEngagement: _totalEngagement,
      avgLikes: _avgLikes,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overall Progress',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: (progress / 100).clamp(0, 1),
            minHeight: 12,
            backgroundColor: AppConstants.darkGray,
            valueColor: AlwaysStoppedAnimation<Color>(
              isEligible ? AppConstants.green : AppConstants.primaryBlue,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$progress% Complete',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              isEligible ? '✓ All Requirements Met' : 'In Progress',
              style: TextStyle(
                color:
                    isEligible ? AppConstants.green : AppConstants.primaryBlue,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActivityGraph() {
    if (_dailyPosts.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxCount = _dailyPosts.isEmpty
        ? 1
        : _dailyPosts
            .map((d) => d['count'] as int)
            .reduce((a, b) => a > b ? a : b);
    final maxHeight = maxCount == 0 ? 1 : maxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Last 30 Days Activity',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppConstants.darkGray,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppConstants.primaryBlue.withOpacity(0.2),
            ),
          ),
          child: Column(
            children: [
              // Simple bar graph
              SizedBox(
                height: 120,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _dailyPosts.asMap().entries.map((entry) {
                    final count = entry.value['count'] as int;
                    final height = count == 0 ? 10.0 : count / maxHeight * 100;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: '$count posts',
                          child: Container(
                            width: 6,
                            height: height,
                            decoration: BoxDecoration(
                              color: AppConstants.primaryBlue,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '30 days ago',
                    style: TextStyle(
                      color: AppConstants.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Today'.padRight(1),
                    style: const TextStyle(
                      color: AppConstants.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Statistics',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _buildStatCard(
              title: 'Total Posts',
              value: _streak!.totalPosts.toString(),
              icon: Icons.edit_rounded,
              color: AppConstants.primaryBlue,
            ),
            _buildStatCard(
              title: 'Engagement',
              value: _totalEngagement.toString(),
              icon: Icons.favorite_rounded,
              color: Colors.red,
            ),
            _buildStatCard(
              title: 'Engaged Posts',
              value: _streak!.postsWithEngagement.toString(),
              icon: Icons.thumb_up_rounded,
              color: AppConstants.green,
            ),
            _buildStatCard(
              title: 'Avg. Likes',
              value: _avgLikes.toStringAsFixed(1),
              icon: Icons.trending_up_rounded,
              color: Colors.orange,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationChallenge() {
    final isEligible = _streak!.isEligibleForVerificationWith(
      _requirements.totalPostsRequired,
      _requirements.engagedPostsRequired,
      _requirements.totalEngagementRequired,
      _requirements.avgLikesRequired,
      totalEngagement: _totalEngagement,
      avgLikes: _avgLikes,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isEligible
              ? [
                  AppConstants.green.withOpacity(0.15),
                  AppConstants.primaryBlue.withOpacity(0.1),
                ]
              : [
                  AppConstants.primaryBlue.withOpacity(0.1),
                  AppConstants.primaryBlue.withOpacity(0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEligible
              ? AppConstants.green.withOpacity(0.5)
              : AppConstants.primaryBlue.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEligible ? Icons.stars : Icons.lock_outline,
                color:
                    isEligible ? AppConstants.green : AppConstants.primaryBlue,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEligible
                      ? 'Verification Challenge - UNLOCKED'
                      : 'Verification Challenge',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isEligible
                ? 'You\'ve completed the challenge! Click below to activate your verified badge.'
                : 'Complete the requirements to unlock your verified badge.',
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  isEligible && !_isVerifying ? _unlockVerification : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isEligible ? AppConstants.green : AppConstants.darkGray,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isVerifying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      isEligible
                          ? '🔓 Unlock Verified Badge'
                          : '🔒 Meet Requirements First',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Requirements',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _buildRequirementCard(
          title: 'Total Posts',
          current: _streak!.totalPosts,
          required: _requirements.totalPostsRequired,
          icon: Icons.edit_rounded,
          isCompleted: _streak!.totalPosts >= _requirements.totalPostsRequired,
        ),
        const SizedBox(height: 12),
        _buildRequirementCard(
          title: 'Posts with Engagement',
          current: _streak!.postsWithEngagement,
          required: _requirements.engagedPostsRequired,
          icon: Icons.favorite_rounded,
          isCompleted:
              _streak!.postsWithEngagement >= _requirements.engagedPostsRequired,
          subtitle: 'Posts with at least 1 like or comment',
        ),
        if (_requirements.totalEngagementRequired > 0) ...[
          const SizedBox(height: 12),
          _buildRequirementCard(
            title: 'Total Engagement',
            current: _totalEngagement,
            required: _requirements.totalEngagementRequired,
            icon: Icons.insights_rounded,
            isCompleted:
                _totalEngagement >= _requirements.totalEngagementRequired,
            subtitle: 'Likes + comments on your posts',
          ),
        ],
        if (_requirements.avgLikesRequired > 0) ...[
          const SizedBox(height: 12),
          _buildRequirementCardDouble(
            title: 'Avg. Likes',
            current: _avgLikes,
            required: _requirements.avgLikesRequired,
            icon: Icons.trending_up_rounded,
            isCompleted: _avgLikes >= _requirements.avgLikesRequired,
          ),
        ],
      ],
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
    final percentage =
        required == 0 ? 100.0 : (current / required * 100).clamp(0, 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isCompleted ? AppConstants.green : AppConstants.primaryBlue)
              .withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isCompleted
                          ? AppConstants.green
                          : AppConstants.primaryBlue)
                      .withOpacity(0.15),
                ),
                child: Icon(
                  isCompleted ? Icons.check_rounded : icon,
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
                        fontSize: 14,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$current/$required',
                    style: TextStyle(
                      color: isCompleted
                          ? AppConstants.green
                          : AppConstants.primaryBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    isCompleted ? '✓ Done' : 'In Progress',
                    style: TextStyle(
                      color: isCompleted
                          ? AppConstants.green
                          : AppConstants.primaryBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (percentage / 100).clamp(0, 1),
              minHeight: 6,
              backgroundColor: AppConstants.lightGray.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? AppConstants.green : AppConstants.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${percentage.toStringAsFixed(0)}% completed',
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementCardDouble({
    required String title,
    required double current,
    required double required,
    required IconData icon,
    required bool isCompleted,
    String? subtitle,
  }) {
    final percentage =
        required == 0 ? 100.0 : (current / required * 100).clamp(0, 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isCompleted ? AppConstants.green : AppConstants.primaryBlue)
              .withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isCompleted
                          ? AppConstants.green
                          : AppConstants.primaryBlue)
                      .withOpacity(0.15),
                ),
                child: Icon(
                  isCompleted ? Icons.check_rounded : icon,
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
                        fontSize: 14,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${current.toStringAsFixed(1)}/${required.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: isCompleted
                          ? AppConstants.green
                          : AppConstants.primaryBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    isCompleted ? '✓ Done' : 'In Progress',
                    style: TextStyle(
                      color: isCompleted
                          ? AppConstants.green
                          : AppConstants.primaryBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (percentage / 100).clamp(0, 1),
              minHeight: 6,
              backgroundColor: AppConstants.lightGray.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? AppConstants.green : AppConstants.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${percentage.toStringAsFixed(0)}% completed',
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsSection() {
    return Container(
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
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTip('📝 Post regularly - Share your thoughts daily'),
          _buildTip('👍 Engage authentically - Create content that resonates'),
          _buildTip('💬 Be consistent - Keep the momentum going'),
          _buildTip('🎯 Quality over quantity - Focus on meaningful posts'),
          _buildTip('⏰ Diversify - Mix anonymous and public posts'),
        ],
      ),
    );
  }

  Widget _buildNextMilestonesSection() {
    if (_streak == null) return const SizedBox.shrink();

    final remainingPosts =
        (_requirements.totalPostsRequired - _streak!.totalPosts).clamp(0, 9999);
    final remainingEngaged = (_requirements.engagedPostsRequired -
            _streak!.postsWithEngagement)
        .clamp(0, 9999);
    final remainingEngagement = (_requirements.totalEngagementRequired -
            _totalEngagement)
        .clamp(0, 999999);
    final remainingAvgLikes =
        (_requirements.avgLikesRequired - _avgLikes).clamp(0, 9999);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.primaryBlue.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next Milestones',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          _buildMilestoneRow(
            'Posts remaining',
            remainingPosts.toInt(),
          ),
          _buildMilestoneRow(
            'Engaged posts remaining',
            remainingEngaged.toInt(),
          ),
          if (_requirements.totalEngagementRequired > 0)
            _buildMilestoneRow(
              'Engagement remaining',
              remainingEngagement.toInt(),
            ),
          if (_requirements.avgLikesRequired > 0)
            _buildMilestoneRow(
              'Avg likes remaining',
              remainingAvgLikes.ceil(),
            ),
        ],
      ),
    );
  }

  Widget _buildMilestoneRow(String label, int remaining) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            remaining == 0 ? '✓ Done' : remaining.toString(),
            style: TextStyle(
              color:
                  remaining == 0 ? AppConstants.green : AppConstants.primaryBlue,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppConstants.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}
