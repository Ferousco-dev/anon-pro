import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/local_database_service.dart';
import 'services/offline_sync_service.dart';
import 'services/auth_service.dart';
import 'services/maintenance_service.dart';
import 'services/user_activity_service.dart';
import 'services/app_startup_service.dart';
import 'providers/connectivity_provider.dart';
import 'providers/new_posts_provider.dart';
import 'services/ai_chat_service.dart';
import 'widgets/offline_banner.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/reset_password_otp_screen.dart';
import 'screens/auth/profile_setup_screen.dart';
import 'screens/home/home_screen_simple.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/anonymous/anonymous_screen.dart';
import 'screens/inbox/inbox_screen.dart';
import 'screens/stories/stories_screen.dart';
import 'screens/admin/admin_panel_screen.dart';
import 'screens/confession_rooms/confession_rooms_screen.dart';
import 'screens/maintenance_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'utils/constants.dart';
import 'utils/app_config.dart';
import 'utils/app_error_handler.dart';
import 'utils/app_logger.dart';

import 'dart:async';
import 'package:flutter/foundation.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Disable all print and debugPrint output in Release mode to prevent log leaks
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    } else {
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          AppLogger.d(message);
        }
      };
    }

    runApp(const AnonProApp());
    unawaited(AppStartupService.initialize());
  }, (error, stack) {
    // Catch global unhandled errors
    AppErrorHandler.report(
      error: error,
      stack: stack,
      context: 'runZonedGuarded',
    );
  }, zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      // Swallow all print() statements in Release mode completely
      if (!kReleaseMode) {
        AppLogger.d(line);
      }
    },
  ));
}

class AnonProApp extends StatelessWidget {
  const AnonProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ConnectivityProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => OfflineSyncService(
            LocalDatabaseService(),
            supabase,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => NewPostsProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AiChatService(),
        ),
      ],
      child: MaintenanceGate(
        child: MaterialApp(
          title: 'ANONPRO',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF000000),
            primaryColor: const Color(0xFF007AFF),
            fontFamily: 'SF Pro Display',
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF007AFF),
              secondary: Color(0xFF5856D6),
              surface: Color(0xFF1C1C1E),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.light,
            ),
          ),
          builder: (context, child) {
            return Stack(
              children: [
                if (child != null) child,
                const OfflineBanner(),
              ],
            );
          },
          initialRoute: '/',
          onGenerateRoute: (settings) {
            // Handle deep links from home screen widget taps
            final uri = Uri.tryParse(settings.name ?? '');
            if (uri != null && uri.scheme == 'anonpro') {
              switch (uri.host) {
                case 'home':
                  final roomId = uri.queryParameters['roomId'];
                  if (roomId != null) {
                    final userId = Supabase.instance.client.auth.currentUser?.id;
                    if (userId != null) {
                      return MaterialPageRoute(
                        builder: (_) => ConfessionRoomsScreen(
                          userId: userId,
                          initialRoomId: roomId,
                        ),
                        settings: RouteSettings(name: '/confession_room?id=$roomId'),
                      );
                    }
                  }
                  return MaterialPageRoute(
                      builder: (_) => const HomeScreenSimple(),
                      settings: const RouteSettings(name: '/home'));
                case 'anonymous':
                  return MaterialPageRoute(
                      builder: (_) => const AnonymousScreen(),
                      settings: const RouteSettings(name: '/anonymous'));
                case 'inbox':
                  return MaterialPageRoute(
                      builder: (_) => const InboxScreen(),
                      settings: const RouteSettings(name: '/groups'));
                case 'profile':
                  final userId = Supabase.instance.client.auth.currentUser?.id;
                  if (userId != null) {
                    return MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: userId),
                        settings: const RouteSettings(name: '/profile'));
                  }
              }
            }
            // Fall through to named routes
            return null;
          },
          routes: {
            '/': (context) => const SplashScreen(),
            '/onboarding': (context) => const OnboardingScreen(),
            '/login': (context) => const LoginScreen(),
            '/signup': (context) => const SignupScreen(),
            '/setup-profile': (context) => const ProfileSetupScreen(),
            '/reset-password-otp': (context) => const ResetPasswordOtpScreen(),
            '/home': (context) => const HomeScreenSimple(),
            '/maintenance': (context) => const MaintenanceScreen(),
            '/profile': (context) {
              final userId =
                  ModalRoute.of(context)?.settings.arguments as String?;
              if (userId == null || userId.isEmpty) {
                return Scaffold(
                  backgroundColor: AppConstants.black,
                  appBar: AppBar(
                    backgroundColor: AppConstants.black,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    title: Row(
                      children: [
                        Image.asset('assets/images/anon.png', height: 32),
                        const SizedBox(width: 8),
                        const Text(
                          'ANONPRO',
                          style: TextStyle(
                            color: AppConstants.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    centerTitle: false,
                  ),
                  body: const Center(
                    child: Text(
                      'User ID is required',
                      style: TextStyle(color: AppConstants.white),
                    ),
                  ),
                );
              }
              return ProfileScreen(userId: userId);
            },
            '/anonymous': (context) => const AnonymousScreen(),
            '/groups': (context) => const InboxScreen(),
            '/stories': (context) => const StoriesScreen(),
            '/admin': (context) => AppConfig.adminToolsEnabled
                ? const AdminPanelScreen()
                : const HomeScreenSimple(),
          },
        ),
      ),
    );
  }
}

class MaintenanceGate extends StatefulWidget {
  const MaintenanceGate({super.key, required this.child});

  final Widget child;

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndEnforce();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkAndEnforce();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      UserActivityService().updateLastSeen();
      _checkAndEnforce();
    }
  }

  Future<void> _checkAndEnforce() async {
    if (_checking) return;
    _checking = true;
    try {
      final session = supabase.auth.currentSession;
      if (session == null) return;

      final shouldBlock = await MaintenanceService()
          .shouldBlockAuthenticated(session.user);
      if (!shouldBlock) return;

      await AuthService().signOut();
      navigatorKey.currentState?.pushReplacementNamed('/maintenance');
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// Supabase client lazy getter (evaluated after initialization)
SupabaseClient get supabase => Supabase.instance.client;
