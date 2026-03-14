import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:anonpro/screens/auth/login_screen.dart';
import 'package:anonpro/screens/auth/signup_screen.dart';
import 'package:anonpro/widgets/create_post_sheet.dart';
import 'package:anonpro/models/user_model.dart';

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'anon',
    );
  });

  testWidgets('Login screen builds', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Signup screen builds', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    expect(find.text('Create Account'), findsOneWidget);
  });

  testWidgets('Create post sheet builds', (tester) async {
    final user = UserModel(
      id: 'u1',
      email: 'test@example.com',
      alias: 'tester',
      displayName: 'Tester',
      bio: '',
      profileImageUrl: null,
      coverImageUrl: null,
      profileTheme: null,
      customEmoji: null,
      profileLink: null,
      highlightPostId: null,
      role: 'user',
      isBanned: false,
      isVerified: false,
      followersCount: 0,
      followingCount: 0,
      postsCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CreatePostSheet(currentUser: user),
      ),
    ));
    expect(find.text('Post'), findsOneWidget);
  });
}
