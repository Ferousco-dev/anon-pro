import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/maintenance_service.dart';
import '../providers/connectivity_provider.dart';
import '../services/app_startup_service.dart';
import 'onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _startupTimedOut = false;
  bool _navigating = false;
  Timer? _startupTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );

    _controller.forward();

    // Initialize critical services, then navigate quickly.
    AppStartupService.initializeCritical();
    _startupTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || _navigating) return;
      setState(() => _startupTimedOut = true);
    });
    Timer(const Duration(milliseconds: 800), _checkAuthAndNavigate);
  }

  Future<void> _checkAuthAndNavigate({bool forceContinue = false}) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await AppStartupService.initializeCritical()
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      if (mounted) {
        setState(() => _startupTimedOut = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _startupTimedOut = true);
      }
    }
    final session = supabase.auth.currentSession;

    // If there is no session at all, we can't assume a logged-in user.
    if (session == null) {
      final prefs = await SharedPreferences.getInstance();
      final hasOnboarded =
          prefs.getBool(OnboardingScreen.prefKey) ?? false;
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        hasOnboarded ? '/login' : '/onboarding',
      );
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');

    // We have a session; decide behavior based on connectivity.
    bool isOnline = true;
    if (mounted) {
      try {
        isOnline = context.read<ConnectivityProvider>().isOnline;
      } catch (_) {
        isOnline = true;
      }
    }

    if (!isOnline) {
      return;
    }

    // Online checks run after initial navigation for faster launch.
    unawaited(_postNavigateChecks(session.user.id));
  }

  Future<void> _postNavigateChecks(String userId) async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return;
      }
      final shouldBlock =
          await MaintenanceService().shouldBlockAuthenticated(currentUser);
      if (shouldBlock) {
        await AuthService().signOut();
        navigatorKey.currentState?.pushReplacementNamed('/maintenance');
        return;
      }

      final userProfile = await AuthService().getUserProfile(userId);
      if (userProfile == null) {
        await AuthService().signOut();
        navigatorKey.currentState?.pushReplacementNamed('/login');
      }
    } catch (_) {
      // Ignore post-navigation errors to keep launch fast.
    }
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // App Logo
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Image.asset(
                            'assets/images/anon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // App Name
                        const Text(
                          'ANONPRO',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tagline
                        Text(
                          'STAY HIDDEN...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 60),

                        // Loading Indicator
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_startupTimedOut)
                  GestureDetector(
                    onTap: () => _checkAuthAndNavigate(forceContinue: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        'Still loading… Tap to continue',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Built by The Oracles',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
