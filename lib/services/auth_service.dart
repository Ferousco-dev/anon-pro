import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _client = supabase;

  /// Sign up a new user with automatic profile creation
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? fullName,
    String? alias,
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      // Prepare user metadata for the trigger
      final userMetadata = <String, dynamic>{
        if (fullName != null) 'full_name': fullName,
        if (alias != null) 'alias': alias,
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

      // Sign up user (email confirmation disabled)
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: userMetadata,
        emailRedirectTo: null, // No email confirmation needed
      );

      // The trigger will automatically create the user profile
      // But we'll also manually ensure it's created for reliability
      if (response.user != null) {
        await _ensureUserProfileExists(response.user!, userMetadata);
      }

      return response;
    } catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in user with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // Ensure user profile exists after login
      if (response.user != null) {
        await _ensureUserProfileExists(response.user!, {});
      }

      return response;
    } catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in user with alias (by finding email first)
  Future<AuthResponse> signInWithAlias({
    required String alias,
    required String password,
  }) async {
    try {
      // Important:
      // During login we are unauthenticated, so we cannot reliably query public.users
      // if RLS is enabled (it should be). Instead, we derive the email.
      //
      // If the user types an email, use it.
      // If the user types an alias, use the internal email format used at signup.
      final trimmed = alias.trim();
      final emailToUse = trimmed.contains('@') ? trimmed : '$trimmed@anonpro.internal';

      try {
        return await signIn(email: emailToUse, password: password);
      } on Exception catch (e) {
        // If the user actually signed up with a real email (optional field),
        // alias@anonpro.internal won't match. Fall back to resolving alias -> email
        // via a SECURITY DEFINER RPC.
        final msg = e.toString();
        final isInvalidCredentials = msg.contains('Invalid email or password') ||
            msg.contains('Invalid login credentials');
        if (!isInvalidCredentials || trimmed.contains('@')) {
          rethrow;
        }

        final resolvedEmail = await _client.rpc(
          'get_email_for_alias',
          params: {'p_alias': trimmed},
        );

        final email = resolvedEmail is String
            ? resolvedEmail
            : (resolvedEmail is Map && resolvedEmail['email'] is String)
                ? resolvedEmail['email'] as String
                : null;
        if (email == null || email.isEmpty) {
          throw Exception('Invalid email or password');
        }

        return await signIn(email: email, password: password);
      }
    } catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Get current authenticated user
  User? get currentUser => _client.auth.currentUser;

  /// Check if user is authenticated
  bool get isAuthenticated => currentUser != null;

  /// Get user profile from users table
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      return await _client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
    } catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Get current user's profile
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    if (!isAuthenticated) return null;
    return await getUserProfile(currentUser!.id);
  }

  /// Update user profile
  Future<void> updateUserProfile({
    String? fullName,
    String? displayName,
    String? alias,
    String? bio,
    String? avatarUrl,
    String? profileImageUrl,
  }) async {
    if (!isAuthenticated) {
      throw Exception('User not authenticated');
    }

    try {
      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (displayName != null) updates['display_name'] = displayName;
      if (alias != null) updates['alias'] = alias;
      if (bio != null) updates['bio'] = bio;

      // Some parts of the app use profile_image_url; initial schema used avatar_url.
      // Update both when provided so UI stays consistent.
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (profileImageUrl != null) updates['profile_image_url'] = profileImageUrl;
      if (profileImageUrl != null && avatarUrl == null) {
        updates['avatar_url'] = profileImageUrl;
      }
      if (avatarUrl != null && profileImageUrl == null) {
        updates['profile_image_url'] = avatarUrl;
      }

      if (updates.isNotEmpty) {
        await _client
            .from('users')
            .update(updates)
            .eq('id', currentUser!.id);
      }
    } catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Update password
  Future<void> updatePassword(String newPassword) async {
    if (!isAuthenticated) {
      throw Exception('User not authenticated');
    }

    try {
      await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Ensure user profile exists in users table
  Future<void> _ensureUserProfileExists(User user, Map<String, dynamic> metadata) async {
    try {
      // Check if profile already exists
      final existingProfile = await _client
          .from('users')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (existingProfile == null) {
        // Create profile if it doesn't exist
        await _client.from('users').insert({
          'id': user.id,
          'email': user.email ?? '',
          'full_name': metadata['full_name'],
          'alias': metadata['alias'] ?? user.email?.split('@')[0],
          'display_name': metadata['display_name'] ?? 
                         metadata['alias'] ?? 
                         user.email?.split('@')[0] ?? 'User',
          'avatar_url': metadata['avatar_url'],
        });
      }
    } catch (e) {
      // Log error but don't throw - the trigger should handle this
      print('Warning: Failed to ensure user profile exists: $e');
    }
  }

  /// Handle authentication exceptions and provide user-friendly messages
  Exception _handleAuthException(dynamic exception) {
    if (exception is AuthException) {
      switch (exception.message) {
        case 'Invalid login credentials':
          return Exception('Invalid email or password');
        case 'User already registered':
          return Exception('An account with this email already exists');
        case 'Password should be at least 6 characters':
          return Exception('Password must be at least 6 characters long');
        case 'Email not confirmed':
          return Exception('Please confirm your email address');
        case 'Too many requests':
          return Exception('Too many attempts. Please try again later');
        default:
          return Exception(exception.message);
      }
    }
    return Exception(exception.toString());
  }

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}
