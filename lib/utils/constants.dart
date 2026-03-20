import 'package:flutter/material.dart';
import 'package:anonpro/utils/app_config.dart';

class AppConstants {
  // App Info
  static const String appName = 'ANONPRO';
  static const String appTagline = 'Anonymous. Professional. Protected.';

  // Colors - Apple + Twitter hybrid
  static const Color primaryBlue = Color(0xFF007AFF);
  static const Color twitterBlue = Color(0xFF1DA1F2);
  static const Color purple = Color(0xFF5856D6);
  static const Color black = Color(0xFF000000);
  static const Color darkGray = Color(0xFF1C1C1E);
  static const Color mediumGray = Color(0xFF2C2C2E);
  static const Color lightGray = Color(0xFF3A3A3C);
  static const Color white = Color(0xFFFFFFFF);
  static const Color red = Color(0xFFFF3B30);
  static const Color green = Color(0xFF34C759);
  static const Color orange = Color(0xFFFF9500);

  // X-style feed colors
  static const Color dividerColor = Color(0xFF2F3336);
  static const Color surfaceHover = Color(0xFF16181C);

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF636366);

  // Spacing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 20.0;
  static const double radiusRound = 999.0;

  // Animation Durations
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationMedium = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // Post Limits
  static const int maxPostLength = 280; // Twitter-style
  static const int maxCommentLength = 280;
  static const int maxBioLength = 160;

  // ImageKit Configuration
  static String get imagekitUrlEndpoint => AppConfig.imagekitUrlEndpoint;
  static String get imagekitPublicKey => AppConfig.imagekitPublicKey;

  // Image Upload Limits
  static const int maxImageSizeMB = 10;

  // Story Settings
  static const Duration storyDuration = Duration(hours: 24);
  static const int maxStoriesPerDay = 10;

  // Pagination
  static const int postsPerPage = 20;
  static const int commentsPerPage = 50;

  // Routes
  static const String splashRoute = '/';
  static const String loginRoute = '/login';
  static const String signupRoute = '/signup';
  static const String homeRoute = '/home';
  static const String anonymousRoute = '/anonymous';
  static const String groupsRoute = '/groups';
  static const String storiesRoute = '/stories';
  static const String profileRoute = '/profile';
  static const String adminRoute = '/admin';
}

// Gradient presets
class AppGradients {
  static const LinearGradient bluePurple = LinearGradient(
    colors: [AppConstants.primaryBlue, AppConstants.purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient redOrange = LinearGradient(
    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleBlue = LinearGradient(
    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient greenBlue = LinearGradient(
    colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// Text Styles
class AppTextStyles {
  // Headers
  static const TextStyle h1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppConstants.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppConstants.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppConstants.textPrimary,
  );

  static const TextStyle h4 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppConstants.textPrimary,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppConstants.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppConstants.textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppConstants.textSecondary,
  );

  // Special
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppConstants.textTertiary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppConstants.white,
  );
}
