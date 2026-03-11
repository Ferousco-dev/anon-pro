import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../providers/connectivity_provider.dart';

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

    // Check auth status and navigate
    Timer(const Duration(seconds: 2), _checkAuthAndNavigate);
  }

  Future<void> _checkAuthAndNavigate() async {
    final session = supabase.auth.currentSession;

    // If there is no session at all, we can't assume a logged-in user.
    if (session == null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    // We have a session; decide behavior based on connectivity.
    bool isOnline = true;
    if (mounted) {
      try {
        isOnline = context.read<ConnectivityProvider>().isOnline;
      } catch (_) {
        isOnline = true;
      }
    }

    // Offline: keep the user logged in and go straight to home,
    // without hitting the network or signing them out.
    if (!isOnline) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }

    // Online: verify profile as before, but do not log the user out
    // just because of a transient error.
    try {
      final userProfile = await AuthService().getUserProfile(session.user.id);

      if (!mounted) return;

      if (userProfile != null) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // If the profile truly doesn't exist while online, fall back to login.
        await AuthService().signOut();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (_) {
      // On error but with a valid session, keep the user in the app.
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  void dispose() {
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
                            gradient: const LinearGradient(
                              colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF007AFF).withOpacity(0.4),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: Colors.white,
                            size: 60,
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
            child: Text(
              'Built by The Oracles',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
