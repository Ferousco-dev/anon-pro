import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../services/streak_service.dart';

class VerificationCongratulationsScreen extends StatefulWidget {
  final String userId;
  final VoidCallback? onComplete;

  const VerificationCongratulationsScreen({
    super.key,
    required this.userId,
    this.onComplete,
  });

  @override
  State<VerificationCongratulationsScreen> createState() =>
      _VerificationCongratulationsScreenState();
}

class _VerificationCongratulationsScreenState
    extends State<VerificationCongratulationsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final StreakService _streakService = StreakService();
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..forward();
  }

  Future<void> _postAnnouncement() async {
    setState(() => _isPosting = true);
    try {
      await _streakService.createVerificationAnnouncement(
        userId: widget.userId,
        imageUrl: null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification announcement posted!'),
            backgroundColor: AppConstants.primaryBlue,
          ),
        );
        widget.onComplete?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error posting announcement: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated celebration icon
                ScaleTransition(
                  scale: Tween<double>(begin: 0, end: 1).animate(
                    CurvedAnimation(
                        parent: _animationController, curve: Curves.elasticOut),
                  ),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppConstants.primaryBlue.withOpacity(0.3),
                          AppConstants.primaryBlue.withOpacity(0.1),
                        ],
                      ),
                      border: Border.all(
                        color: AppConstants.primaryBlue,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      size: 60,
                      color: Color(0xFF00D4FF),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                Text(
                  '🎉 Congratulations! 🎉',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),

                // Message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppConstants.primaryBlue.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'You\'re Now Verified!',
                        style: TextStyle(
                          color: Color(0xFF00D4FF),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Your active participation and engagement have unlocked verified status on AnonPro. You now have access to exclusive features:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Features list
                Column(
                  children: [
                    _featureItem(
                      icon: Icons.help_outline_rounded,
                      title: 'Ask Me Anything',
                      subtitle: 'Let followers ask anonymous questions',
                    ),
                    const SizedBox(height: 12),
                    _featureItem(
                      icon: Icons.chat_bubble_outline,
                      title: 'Confession Rooms',
                      subtitle: 'Create temporary anonymous chat rooms',
                    ),
                    const SizedBox(height: 12),
                    _featureItem(
                      icon: Icons.trending_up_rounded,
                      title: 'Priority Feed Ranking',
                      subtitle: 'Your posts rank higher in followers\' feeds',
                    ),
                    const SizedBox(height: 12),
                    _featureItem(
                      icon: Icons.analytics_rounded,
                      title: 'Profile Analytics',
                      subtitle: 'Track your engagement and reach',
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Action button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isPosting ? null : _postAnnouncement,
                    icon: const Icon(Icons.celebration_rounded),
                    label: const Text('Share This Achievement'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryBlue,
                      disabledBackgroundColor:
                          AppConstants.primaryBlue.withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Skip button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onComplete?.call();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.darkGray,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Skip for Now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _featureItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppConstants.primaryBlue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF00D4FF), size: 20),
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
              const SizedBox(height: 4),
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
      ],
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
