import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/new_posts_provider.dart';

class NewPostsNotificationBar extends StatefulWidget {
  final VoidCallback onTap;
  final Duration autoHideDuration;
  final bool enableHapticFeedback;

  const NewPostsNotificationBar({
    Key? key,
    required this.onTap,
    this.autoHideDuration = const Duration(seconds: 0),
    this.enableHapticFeedback = true,
  }) : super(key: key);

  @override
  State<NewPostsNotificationBar> createState() =>
      _NewPostsNotificationBarState();
}

class _NewPostsNotificationBarState extends State<NewPostsNotificationBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: const Offset(0, 0),
    ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
  }

  void _showBar() {
    // Reset animation
    _animationController.forward(from: 0.0);

    // Set auto-hide timer if duration is specified
    if (widget.autoHideDuration.inMilliseconds > 0) {
      _autoHideTimer?.cancel();
      _autoHideTimer = Timer(widget.autoHideDuration, () {
        if (mounted) {
          _hideBar();
        }
      });
    }
  }

  void _hideBar() {
    _animationController.reverse().then((_) {
      if (mounted) {
        // Notify provider to hide notification
        final provider = Provider.of<NewPostsProvider>(context, listen: false);
        provider.hideNotification();
      }
    });
  }

  void _handleTap() {
    if (widget.enableHapticFeedback) {
      HapticFeedback.mediumImpact();
    }
    _hideBar();
    widget.onTap();
  }

  @override
  void didUpdateWidget(NewPostsNotificationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The animation is managed by the parent widget via the provider
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NewPostsProvider>(
      builder: (context, provider, _) {
        // Show animation when notification should be displayed
        if (provider.showNotification && !_animationController.isAnimating) {
          _showBar();
        }

        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onTap: _handleTap,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a1a2e),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF0066ff),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0066ff).withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Pulse icon animation
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0066ff).withOpacity(
                              0.3 + (0.4 * _animationController.value),
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            color: const Color(0xFF0066ff),
                            size: 16,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    // Text message
                    Expanded(
                      child: Text(
                        _buildMessage(provider.newPostsCount),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Badge with count
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0066ff),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        provider.newPostsCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildMessage(int count) {
    if (count == 1) {
      return "1 new post";
    } else if (count <= 5) {
      return "$count new posts";
    } else {
      return "$count posts added";
    }
  }
}
