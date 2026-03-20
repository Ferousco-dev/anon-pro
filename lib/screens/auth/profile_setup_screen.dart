import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/image_upload_service.dart';
import '../../utils/constants.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  static const String prefKey = 'profile_setup_complete';

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _bioController = TextEditingController();

  String? _profileImageUrl;
  File? _localAvatar;
  String? _initialBio;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;

  List<UserModel> _suggestedUsers = [];
  final Set<String> _followingIds = {};
  final Set<String> _followInFlight = {};

  @override
  void initState() {
    super.initState();
    _loadSetup();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadSetup() async {
    final me = _supabase.auth.currentUser;
    if (me == null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    try {
      final profile = await AuthService().getUserProfile(me.id);
      _profileImageUrl = (profile?['profile_image_url'] ??
              profile?['avatar_url']) as String?;
      _initialBio = profile?['bio'] as String?;
      _bioController.text = _initialBio ?? '';

      await _loadFollowingIds(me.id);
      await _loadSuggestedUsers(me.id);
    } catch (_) {
      // Ignore load errors; the user can still proceed.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFollowingIds(String userId) async {
    try {
      final followingRes = await _supabase
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId);
      _followingIds
        ..clear()
        ..addAll(
          (followingRes as List)
              .map((row) => row['following_id'] as String),
        );
    } catch (_) {
      _followingIds.clear();
    }
  }

  Future<void> _loadSuggestedUsers(String userId) async {
    try {
      final res = await _supabase
          .from('users')
          .select(
              'id, email, alias, display_name, bio, profile_image_url, role, is_banned, is_verified, followers_count, following_count, posts_count, created_at, updated_at')
          .eq('is_banned', false)
          .neq('id', userId)
          .order('followers_count', ascending: false)
          .limit(8);
      _suggestedUsers = (res as List)
          .map((row) => UserModel.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _suggestedUsers = [];
    }
  }

  Future<void> _pickAvatar() async {
    final me = _supabase.auth.currentUser;
    if (me == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (picked == null) return;

    setState(() {
      _localAvatar = File(picked.path);
      _isUploadingAvatar = true;
    });

    try {
      final url = await ImageUploadService.uploadPostImage(
        imageFile: File(picked.path),
        postId: 'profile_${me.id}_${DateTime.now().millisecondsSinceEpoch}',
      );
      await AuthService().updateUserProfile(profileImageUrl: url);
      if (mounted) {
        setState(() {
          _profileImageUrl = url;
          _localAvatar = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to upload photo: $e');
      setState(() => _localAvatar = null);
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _toggleFollow(String targetId) async {
    final me = _supabase.auth.currentUser;
    if (me == null || _followInFlight.contains(targetId)) return;

    final wasFollowing = _followingIds.contains(targetId);
    setState(() {
      _followInFlight.add(targetId);
      if (wasFollowing) {
        _followingIds.remove(targetId);
      } else {
        _followingIds.add(targetId);
      }
    });

    try {
      if (wasFollowing) {
        await _supabase
            .from('follows')
            .delete()
            .eq('follower_id', me.id)
            .eq('following_id', targetId);
        try {
          await NotificationService()
              .unsubscribeFromFollowersTopic(targetId);
        } catch (e) {
          debugPrint(
              'Failed to unsubscribe from followers topic for $targetId: $e');
        }
      } else {
        await _supabase.from('follows').insert({
          'follower_id': me.id,
          'following_id': targetId,
        });
        try {
          await NotificationService().subscribeToFollowersTopic(targetId);
        } catch (e) {
          debugPrint(
              'Failed to subscribe to followers topic for $targetId: $e');
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Could not update follow. Please try again.');
      setState(() {
        if (wasFollowing) {
          _followingIds.add(targetId);
        } else {
          _followingIds.remove(targetId);
        }
      });
    } finally {
      if (mounted) {
        setState(() => _followInFlight.remove(targetId));
      }
    }
  }

  Future<void> _finishSetup({required bool skipped}) async {
    if (_isSaving || _isUploadingAvatar) return;
    setState(() => _isSaving = true);

    try {
      final bio = _bioController.text.trim();
      if (!skipped && bio != _initialBio) {
        await AuthService().updateUserProfile(bio: bio.isEmpty ? null : bio);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ProfileSetupScreen.prefKey, true);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppConstants.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppConstants.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppConstants.primaryBlue),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppConstants.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _finishSetup(skipped: true),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: AppConstants.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Set up your profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add a photo, a short bio, and follow a few people to shape your feed.',
                  style: TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _buildAvatarPicker(),
                const SizedBox(height: 24),
                _buildBioField(),
                const SizedBox(height: 24),
                _buildSuggestedSection(),
                const SizedBox(height: 28),
                _buildFooterActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    final ImageProvider<Object>? avatarImage = _localAvatar != null
        ? FileImage(_localAvatar!) as ImageProvider<Object>
        : (_profileImageUrl != null
            ? NetworkImage(_profileImageUrl!) as ImageProvider<Object>
            : null);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppConstants.lightGray),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppConstants.mediumGray,
                backgroundImage: avatarImage,
                child: _profileImageUrl == null && _localAvatar == null
                    ? const Icon(Icons.person, color: Colors.white, size: 30)
                    : null,
              ),
              if (_isUploadingAvatar)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppConstants.white),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Profile photo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Upload a clean, clear shot that feels authentic.',
                  style: TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _isUploadingAvatar ? null : _pickAvatar,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppConstants.primaryBlue),
              foregroundColor: AppConstants.primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  Widget _buildBioField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bio',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppConstants.darkGray,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppConstants.lightGray),
          ),
          child: TextField(
            controller: _bioController,
            maxLines: 4,
            maxLength: AppConstants.maxBioLength,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Share a short intro about yourself…',
              hintStyle: TextStyle(color: AppConstants.textTertiary),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              counterStyle: TextStyle(color: AppConstants.textTertiary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Suggested to follow',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Start with a few accounts. You can always unfollow later.',
          style: TextStyle(
            color: AppConstants.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        if (_suggestedUsers.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: AppConstants.darkGray,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppConstants.lightGray),
            ),
            child: const Text(
              'No suggestions right now. You can find people later in Search.',
              style: TextStyle(color: AppConstants.textSecondary, fontSize: 12),
            ),
          )
        else
          Column(
            children: _suggestedUsers.map(_buildSuggestedTile).toList(),
          ),
      ],
    );
  }

  Widget _buildSuggestedTile(UserModel user) {
    final isFollowing = _followingIds.contains(user.id);
    final inFlight = _followInFlight.contains(user.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.lightGray),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppConstants.primaryBlue,
            backgroundImage: user.profileImageUrl != null
                ? NetworkImage(user.profileImageUrl!)
                : null,
            child: user.profileImageUrl == null
                ? const Icon(Icons.person, color: Colors.white, size: 20)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.displayName ?? user.alias,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user.isVerifiedUser) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded,
                          color: AppConstants.primaryBlue, size: 14),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '@${user.alias}',
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: inFlight ? null : () => _toggleFollow(user.id),
            style: TextButton.styleFrom(
              backgroundColor:
                  isFollowing ? AppConstants.lightGray : AppConstants.primaryBlue,
              foregroundColor: isFollowing ? Colors.white70 : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isFollowing ? 'Following' : 'Follow'),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions() {
    return Row(
      children: [
        TextButton(
          onPressed: () => _finishSetup(skipped: true),
          child: const Text(
            'Skip for now',
            style: TextStyle(
              color: AppConstants.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: _isSaving ? null : () => _finishSetup(skipped: false),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Finish',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ],
    );
  }
}
