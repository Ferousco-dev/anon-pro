import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

/// A reusable verified badge widget with glassmorphism glow effect.
///
/// Badge colors:
/// - Blue glow: standard verified
/// - Gold glow: admin
/// - Purple glow: premium verified
class VerifiedBadge extends StatelessWidget {
  final UserModel? user;
  final double size;
  final String? role;
  final bool? isVerified;
  final String? verificationLevel;

  const VerifiedBadge({
    super.key,
    this.user,
    this.size = 16,
    this.role,
    this.isVerified,
    this.verificationLevel,
  });

  /// Convenience factories for common uses without a full UserModel
  factory VerifiedBadge.fromRole({
    required String role,
    bool isVerified = true,
    String verificationLevel = 'verified',
    double size = 16,
  }) {
    return VerifiedBadge(
      role: role,
      isVerified: isVerified,
      verificationLevel: verificationLevel,
      size: size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRole = role ?? user?.role ?? 'user';
    final effectiveIsVerified = isVerified ?? user?.isVerifiedUser ?? false;
    final effectiveLevel = verificationLevel ?? user?.verificationLevel ?? 'none';

    if (!effectiveIsVerified) return const SizedBox.shrink();

    // Determine badge color and icon
    Color badgeColor;
    Color glowColor;
    IconData badgeIcon;

    if (effectiveRole == 'admin') {
      badgeColor = const Color(0xFFFFD700); // Gold
      glowColor = const Color(0xFFFFD700);
      badgeIcon = Icons.admin_panel_settings_rounded;
    } else if (effectiveLevel == 'premium_verified') {
      badgeColor = const Color(0xFF9B59B6); // Purple
      glowColor = const Color(0xFF8E44AD);
      badgeIcon = Icons.verified_rounded;
    } else {
      badgeColor = AppConstants.primaryBlue;
      glowColor = AppConstants.primaryBlue;
      badgeIcon = Icons.verified_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.4),
            blurRadius: size * 0.5,
            spreadRadius: size * 0.05,
          ),
        ],
      ),
      child: Icon(
        badgeIcon,
        color: badgeColor,
        size: size,
      ),
    );
  }
}
