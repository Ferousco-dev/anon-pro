import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../utils/constants.dart';
import '../../main.dart';
import '../../models/post_model.dart';
import '../../models/user_model.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/post_card.dart';
import '../../widgets/edit_post_sheet.dart';
import '../../widgets/profile_skeleton_loader.dart';
import '../../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_dm_launcher.dart';
import '../../models/user_analytics_model.dart';
import '../../services/feed_cache_service.dart';
import 'followers_list_screen.dart';
import '../../screens/qa/anonymous_questions_screen.dart';
import '../../screens/qa/qa_answers_inbox_screen.dart';
import '../../screens/confession_rooms/confession_rooms_screen.dart';
import '../../screens/profile/streak_progress_screen.dart';
import '../../widgets/ask_anything_button.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserModel? _user;
  UserAnalyticsModel? _analytics;
  List<PostModel> _posts = [];
  bool _isLoading = true;
  String? _error;

  bool _isSaving = false;
  bool _isFollowing = false;
  bool _isLoadingFollowStatus = false;
  // Separate flag just for profile-image upload — shows spinner ring on avatar
  bool _isUploadingProfileImage = false;

  RealtimeChannel? _channel;
  final FeedCacheService _cache = FeedCacheService();

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenNetwork();
    _startRealtime();
  }

  Future<void> _loadFromCacheThenNetwork() async {
    // 1) Instantly load cached profile
    final cachedProfile = _cache.getProfile(widget.userId);
    if (cachedProfile != null && mounted) {
      final user = UserModel.fromJson(cachedProfile);
      setState(() {
        _user = user;
      });
    }

    // 2) Instantly load cached profile posts
    final cachedPosts = _cache.getProfilePosts(widget.userId);
    if (cachedPosts != null && cachedPosts.isNotEmpty && mounted) {
      final posts = cachedPosts.map((p) => PostModel.fromJson(p)).toList();
      if (_user != null) {
        for (final post in posts) {
          post.user = _user;
        }
      }
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    }

    // 3) Refresh from network
    _loadProfile();
  }

  @override
  void dispose() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  bool get _isOwnProfile => supabase.auth.currentUser?.id == widget.userId;

  void _startRealtime() {
    // Ensure we don't create multiple channels
    if (_channel != null || widget.userId.isEmpty) return;

    _channel = supabase
        .channel('profile:${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (payload) {
            if (!mounted) return;

            // Check if post is anonymous - skip if anonymous
            final isAnonymous =
                payload.newRecord['is_anonymous'] as bool? ?? false;
            if (isAnonymous) return;

            // INSERT
            if (payload.eventType == PostgresChangeEvent.insert) {
              final record = payload.newRecord;
              final post = PostModel.fromJson(record);
              if (_user != null) post.user = _user;
              setState(() {
                // Prevent duplicates
                _posts.removeWhere((p) => p.id == post.id);
                _posts.insert(0, post);
              });
              return;
            }

            // UPDATE
            if (payload.eventType == PostgresChangeEvent.update) {
              final record = payload.newRecord;
              final updated = PostModel.fromJson(record);
              if (_user != null) updated.user = _user;
              setState(() {
                final idx = _posts.indexWhere((p) => p.id == updated.id);
                if (idx != -1) {
                  _posts[idx] = updated;
                }
              });
              return;
            }

            // DELETE
            if (payload.eventType == PostgresChangeEvent.delete) {
              final id = payload.oldRecord['id'] as String?;
              if (id == null) return;
              setState(() {
                _posts.removeWhere((p) => p.id == id);
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final record = payload.newRecord;
            final updatedUser = UserModel.fromJson(record);
            setState(() {
              _user = updatedUser;
              for (final post in _posts) {
                post.user = updatedUser;
              }
            });
          },
        );

    _channel!.subscribe();
  }

  Future<void> _loadProfile() async {
    if (widget.userId.isEmpty) {
      print('ProfileScreen: userId is empty: "${widget.userId}"');
      setState(() {
        _isLoading = false;
        _error = 'User ID is required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userData = await supabase
          .from('users')
          .select()
          .eq('id', widget.userId)
          .single();

      // Try the new schema first
      List postsResponse;
      try {
        postsResponse = await supabase
            .from('posts')
            .select('*')
            .eq('user_id', widget.userId)
            .eq('is_anonymous', false)
            .order('created_at', ascending: false)
            .limit(50);
      } catch (e) {
        // Fallback to old schema if is_anonymous column doesn't exist
        postsResponse = await supabase
            .from('posts')
            .select('*')
            .eq('user_id', widget.userId)
            .order('created_at', ascending: false)
            .limit(50);
      }

      final posts = postsResponse.map((p) => PostModel.fromJson(p)).toList();

      // Load analytics if user is verified
      UserAnalyticsModel? analytics;
      final user = UserModel.fromJson(userData);
      if (user.isVerifiedUser) {
        try {
          final analyticsRes = await supabase
              .from('user_analytics')
              .select('*')
              .eq('user_id', widget.userId)
              .maybeSingle();

          if (analyticsRes != null) {
            analytics = UserAnalyticsModel.fromJson(analyticsRes);
          }
        } catch (e) {
          debugPrint('Error loading analytics: $e');
        }
      }

      // Attach the profile user to posts so PostCard shows correct info
      for (final post in posts) {
        post.user = user;
      }

      if (mounted) {
        setState(() {
          _user = user;
          _posts = posts;
          _analytics = analytics;
          _isLoading = false;
        });

        // Save to cache for next time
        _cache.saveProfile(widget.userId, userData);
        final postsCacheData =
            postsResponse.cast<Map<String, dynamic>>().toList();
        _cache.saveProfilePosts(widget.userId, postsCacheData);

        // Load follow status after user is loaded
        _loadFollowStatus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFollowStatus() async {
    if (_isOwnProfile || _user == null) return;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final response = await supabase
          .from('follows')
          .select()
          .eq('follower_id', currentUser.id)
          .eq('following_id', widget.userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isFollowing = response != null;
        });
      }
    } catch (e) {
      print('Error loading follow status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_isOwnProfile || _user == null || _isLoadingFollowStatus) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    setState(() => _isLoadingFollowStatus = true);

    try {
      if (_isFollowing) {
        // Unfollow
        await supabase
            .from('follows')
            .delete()
            .eq('follower_id', currentUser.id)
            .eq('following_id', widget.userId);

        if (mounted) {
          setState(() {
            _isFollowing = false;
            if (_user != null) {
              _user = _user!.copyWith(
                followersCount: _user!.followersCount - 1,
              );
            }
          });
        }
      } else {
        // Follow
        await supabase.from('follows').insert({
          'follower_id': currentUser.id,
          'following_id': widget.userId,
        });

        if (mounted) {
          setState(() {
            _isFollowing = true;
            if (_user != null) {
              _user = _user!.copyWith(
                followersCount: _user!.followersCount + 1,
              );
            }
          });
        }
      }
    } catch (e) {
      print('Error toggling follow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error ${_isFollowing ? 'unfollowing' : 'following'} user'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingFollowStatus = false);
      }
    }
  }

  void _startMessage() {
    if (_isOwnProfile || _user == null) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to send a message'),
          backgroundColor: AppConstants.red,
        ),
      );
      return;
    }

    final otherUser = _user!;

    // Reuse the same logic as user search screen by pushing a small helper route
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ProfileDmLauncher(
          otherUserId: otherUser.id,
          otherAlias: otherUser.alias,
          otherDisplayName: otherUser.displayName,
          otherProfileImageUrl: otherUser.profileImageUrl,
        ),
      ),
    );
  }

  // ══════════════════════════ HELPER: format count ══════════════════════════
  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      body: _isLoading && _user == null
          ? const ProfileSkeletonLoader()
          : _error != null && _user == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: AppConstants.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppConstants.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadProfile,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadProfile,
                  color: AppConstants.primaryBlue,
                  backgroundColor: AppConstants.darkGray,
                  child: CustomScrollView(
                    slivers: [
                      // ── X-style flat app bar ──
                      SliverAppBar(
                        expandedHeight: 140,
                        floating: false,
                        pinned: true,
                        backgroundColor: AppConstants.black,
                        elevation: 0,
                        leading: IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppConstants.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 16),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        actions: [
                          if (_isOwnProfile)
                            IconButton(
                              onPressed: _isSaving ? null : _showFeedbackDialog,
                              icon: const Icon(Icons.feedback_rounded,
                                  size: 20, color: Colors.white),
                            ),
                          Theme(
                            data: Theme.of(context).copyWith(
                              popupMenuTheme: const PopupMenuThemeData(
                                color: AppConstants.darkGray,
                                textStyle: TextStyle(color: Colors.white),
                              ),
                            ),
                            child: PopupMenuButton<int>(
                              icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
                              offset: const Offset(0, 48),
                              onSelected: (value) {
                                if (value == 0) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => AnonymousQuestionsScreen(
                                        userId: _user!.id,
                                        isOwner: true,
                                      ),
                                    ),
                                  );
                                } else if (value == 1) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => ConfessionRoomsScreen(
                                        userId: _user!.id,
                                      ),
                                    ),
                                  );
                                } else if (value == 2) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => StreakProgressScreen(
                                        userId: _user!.id,
                                      ),
                                    ),
                                  );
                                } else if (value == 3) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => QAAnswersInboxScreen(
                                        userId: _user!.id,
                                      ),
                                    ),
                                  );
                                } else if (value == 4) {
                                  _reportUser();
                                }
                              },
                              itemBuilder: (context) => [
                                if (_isOwnProfile && (_user?.isVerified ?? false))
                                  const PopupMenuItem(
                                    value: 0,
                                    child: Row(
                                      children: [
                                        Icon(Icons.help_outline_rounded, color: Colors.white, size: 20),
                                        SizedBox(width: 12),
                                        Text('Q&A'),
                                      ],
                                    ),
                                  ),
                                if (_isOwnProfile && (_user?.isVerified ?? false))
                                  const PopupMenuItem(
                                    value: 1,
                                    child: Row(
                                      children: [
                                        Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                                        SizedBox(width: 12),
                                        Text('Rooms'),
                                      ],
                                    ),
                                  ),
                                if (_isOwnProfile)
                                  const PopupMenuItem(
                                    value: 2,
                                    child: Row(
                                      children: [
                                        Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 20),
                                        SizedBox(width: 12),
                                        Text('Streak'),
                                      ],
                                    ),
                                  ),
                                if (_isOwnProfile)
                                  const PopupMenuItem(
                                    value: 3,
                                    child: Row(
                                      children: [
                                        Icon(Icons.mail_outline_rounded, color: Colors.white, size: 20),
                                        SizedBox(width: 12),
                                        Text('Inbox'),
                                      ],
                                    ),
                                  ),
                                if (!_isOwnProfile)
                                  const PopupMenuItem(
                                    value: 4,
                                    child: Row(
                                      children: [
                                        Icon(Icons.report_problem_outlined, color: Colors.white, size: 20),
                                        SizedBox(width: 12),
                                        Text('Report User'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        flexibleSpace: FlexibleSpaceBar(
                          background: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppConstants.primaryBlue.withOpacity(0.25),
                                  AppConstants.black,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ── Profile Info Section (below cover) ──
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar row — left-aligned like X
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Avatar with upload ring
                                  Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppConstants.black,
                                            width: 4,
                                          ),
                                        ),
                                        child: GestureDetector(
                                          onTap: _isOwnProfile &&
                                                  !_isUploadingProfileImage
                                              ? _pickAndUploadProfileImage
                                              : null,
                                          child: Stack(
                                            children: [
                                              _buildProfileAvatar(_user!,
                                                  radius: 40),
                                              if (_isUploadingProfileImage)
                                                Positioned.fill(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.black
                                                          .withOpacity(0.5),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Center(
                                                      child: SizedBox(
                                                        width: 28,
                                                        height: 28,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2.5,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (_isOwnProfile &&
                                          !_isUploadingProfileImage)
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: AppConstants.primaryBlue,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: AppConstants.black,
                                                width: 2,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt_rounded,
                                              color: Colors.white,
                                              size: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const Spacer(),
                                  // Action buttons (top-right of info section)
                                  if (!_isOwnProfile) ...[
                                    _buildPillButton(
                                      onTap: _startMessage,
                                      icon: Icons.mail_outline_rounded,
                                      filled: false,
                                    ),
                                    const SizedBox(width: 8),
                                    // Ask Me Anything button for verified users with Q&A enabled
                                    if (_user?.qaEnabled ?? false)
                                      Flexible(
                                        child: AskAnyThingButton(
                                          targetUserId: _user!.id,
                                        ),
                                      ),
                                    if (_user?.qaEnabled ?? false)
                                      const SizedBox(width: 8),
                                    _buildPillButton(
                                      label:
                                          _isFollowing ? 'Following' : 'Follow',
                                      onTap: _isLoadingFollowStatus
                                          ? null
                                          : _toggleFollow,
                                      filled: !_isFollowing,
                                      isLoading: _isLoadingFollowStatus,
                                    ),
                                  ],
                                  if (_isOwnProfile)
                                    _buildPillButton(
                                      label: 'Edit profile',
                                      onTap: _isSaving
                                          ? null
                                          : _showEditProfileSheet,
                                      filled: false,
                                    ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Name + verified badge
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _user!.displayName ?? _user!.alias,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                  if (_user!.isVerifiedUser) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      _user!.role == 'admin'
                                          ? Icons.admin_panel_settings_rounded
                                          : Icons.verified_rounded,
                                      size: 18,
                                      color: _user!.role == 'admin'
                                          ? const Color(0xFFFFD700)
                                          : AppConstants.primaryBlue,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '@${_user!.alias}',
                                style: const TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),

                              // Bio
                              if ((_user!.bio ?? '').isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _user!.bio!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    height: 1.4,
                                  ),
                                ),
                              ],

                              // Banned badge
                              if (_user!.isBanned)
                                Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppConstants.red.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppConstants.red.withOpacity(0.5),
                                    ),
                                  ),
                                  child: const Text(
                                    '🚫 BANNED',
                                    style: TextStyle(
                                      color: AppConstants.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 14),

                              // ── Stats row — X-style inline ──
                              _buildInlineStatsRow(),

                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),

                      // ── Own-profile actions (admin panel, logout, delete) ──
                      if (_isOwnProfile)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              children: [
                                if (_user?.isAdmin == true) ...[
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFD700),
                                          Color(0xFFFFA500),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => Navigator.pushNamed(
                                            context, '/admin'),
                                        borderRadius: BorderRadius.circular(24),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                              vertical: 12),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons
                                                    .admin_panel_settings_rounded,
                                                size: 16,
                                                color: Colors.black,
                                              ),
                                              SizedBox(width: 6),
                                              Text(
                                                'Admin Panel',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildPillButton(
                                        label: 'Log out',
                                        onTap:
                                            _isSaving ? null : _confirmLogout,
                                        filled: false,
                                        expand: true,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildPillButton(
                                        label: 'Delete account',
                                        onTap: _isSaving
                                            ? null
                                            : _confirmDeleteAccount,
                                        filled: false,
                                        isDanger: true,
                                        expand: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ── Ask Anonymous Question Button (For Verified profiles) ──
                      if (_user!.isVerifiedUser && !_isOwnProfile)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: GestureDetector(
                              onTap: _showAskQuestionDialog,
                              child: Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppConstants.orange.withOpacity(0.8),
                                      const Color(0xFFFF8C00).withOpacity(0.8),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          AppConstants.orange.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.help_outline_rounded,
                                        color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Ask Anonymous Question',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // ── Analytics Dashboard (Verified Only) ──
                      if (_user!.isVerifiedUser && _analytics != null)
                        SliverToBoxAdapter(
                          child: _buildAnalyticsDashboard(),
                        ),

                      // ── Posts tab header ──
                      SliverToBoxAdapter(
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppConstants.dividerColor,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Text(
                              'Posts',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ── Posts list ──
                      if (_posts.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.article_outlined,
                                    size: 40,
                                    color: AppConstants.textSecondary
                                        .withOpacity(0.4)),
                                const SizedBox(height: 12),
                                const Text(
                                  'No posts yet',
                                  style: TextStyle(
                                    color: AppConstants.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final post = _posts[index];
                              return PostCard(
                                post: post,
                                currentUser: _isOwnProfile ? _user : null,
                                onDelete: _isOwnProfile
                                    ? () => _deletePost(post)
                                    : null,
                                onEdit:
                                    _isOwnProfile && post.originalPostId == null
                                        ? () => _editPost(post)
                                        : null,
                              );
                            },
                            childCount: _posts.length,
                          ),
                        ),
                      const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                    ],
                  ),
                ),
    );
  }

  // ══════════════════════ PILL BUTTON HELPER ══════════════════════
  Widget _buildPillButton({
    String? label,
    IconData? icon,
    VoidCallback? onTap,
    bool filled = true,
    bool isDanger = false,
    bool isLoading = false,
    bool expand = false,
  }) {
    final Color borderColor = isDanger
        ? AppConstants.red.withOpacity(0.5)
        : AppConstants.dividerColor;
    final Color bgColor = filled ? AppConstants.white : Colors.transparent;
    final Color textColor = isDanger
        ? AppConstants.red
        : filled
            ? AppConstants.black
            : AppConstants.white;

    Widget child;
    if (isLoading) {
      child = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: textColor,
        ),
      );
    } else if (icon != null && label == null) {
      child = Icon(icon, size: 18, color: textColor);
    } else {
      child = Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label ?? '',
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: icon != null && label == null ? 10 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }

  // ══════════════════════ INLINE STATS ROW (X-style) ══════════════════════
  Widget _buildInlineStatsRow() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _navigateToFollowersList('following'),
          child: Row(
            children: [
              Text(
                _formatCount(_user!.followingCount),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'Following',
                style: TextStyle(
                  color: AppConstants.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: () => _navigateToFollowersList('followers'),
          child: Row(
            children: [
              Text(
                _formatCount(_user!.followersCount),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'Followers',
                style: TextStyle(
                  color: AppConstants.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Text(
          _formatCount(_posts.length),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          'Posts',
          style: TextStyle(
            color: AppConstants.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  void _navigateToFollowersList(String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowersListScreen(
          userId: widget.userId,
          type: type,
          displayName: _user?.displayName ?? _user?.alias ?? 'User',
        ),
      ),
    );
  }

  void _editPost(PostModel post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditPostSheet(
        post: post,
        onPostUpdated: () {
          _loadProfile();
        },
      ),
    );
  }

  Future<void> _deletePost(PostModel post) async {
    try {
      // Delete via secure backend (handles ImageKit deletion + DB deletion)
      await ImageUploadService.deletePostImage(post.id);

      if (!mounted) return;
      setState(() {
        _posts.removeWhere((p) => p.id == post.id);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete post: $e'),
          backgroundColor: AppConstants.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You will need to sign in again.',
          style: TextStyle(color: AppConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      setState(() => _isSaving = true);
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to log out: $e'),
          backgroundColor: AppConstants.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete account?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This cannot be undone.',
          style: TextStyle(color: AppConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            child:
                const Text('Delete', style: TextStyle(color: AppConstants.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    try {
      setState(() => _isSaving = true);

      await supabase.rpc('delete_user');

      if (!mounted) return;
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete account: $e'),
          backgroundColor: AppConstants.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showEditProfileSheet() {
    if (_user == null) return;

    final displayNameController =
        TextEditingController(text: _user!.displayName ?? '');
    final aliasController = TextEditingController(text: _user!.alias);
    final bioController = TextEditingController(text: _user!.bio ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.darkGray,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: bottomInset,
                  left: 16,
                  right: 16,
                  top: 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // keep a max height so it can scroll when keyboard is open
                    maxHeight: constraints.maxHeight * 0.9,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Edit Profile',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _isSaving
                                  ? null
                                  : () async {
                                      await _pickAndUploadProfileImage();
                                    },
                              child: const Text('Change Photo'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildTextField('Full name', displayNameController,
                            maxLength: 40),
                        const SizedBox(height: 12),
                        _buildTextField('Username', aliasController,
                            maxLength: 20, prefixText: '@'),
                        const SizedBox(height: 12),
                        _buildTextField('Bio', bioController,
                            maxLength: AppConstants.maxBioLength, maxLines: 4),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.primaryBlue,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isSaving
                                ? null
                                : () async {
                                    final newAlias =
                                        aliasController.text.trim();
                                    final newName =
                                        displayNameController.text.trim();
                                    final newBio = bioController.text.trim();

                                    if (newAlias.isEmpty) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Username cannot be empty')),
                                      );
                                      return;
                                    }

                                    if (!RegExp(r'^[a-zA-Z0-9_]+$')
                                        .hasMatch(newAlias)) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Username can only contain letters, numbers and underscores')),
                                      );
                                      return;
                                    }

                                    await _saveProfileEdits(
                                      alias: newAlias,
                                      displayName:
                                          newName.isEmpty ? null : newName,
                                      bio: newBio.isEmpty ? null : newBio,
                                    );

                                    if (mounted) {
                                      Navigator.pop(context);
                                    }
                                  },
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Save',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int? maxLength,
    int maxLines = 1,
    String? prefixText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLength: maxLength,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            counterStyle: const TextStyle(color: AppConstants.textSecondary),
            prefixText: prefixText,
            prefixStyle: const TextStyle(color: AppConstants.textSecondary),
            filled: true,
            fillColor: AppConstants.mediumGray,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppConstants.primaryBlue),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveProfileEdits({
    required String alias,
    String? displayName,
    String? bio,
  }) async {
    setState(() => _isSaving = true);

    try {
      if (alias != _user!.alias) {
        final existing = await supabase
            .from('users')
            .select('id')
            .eq('alias', alias)
            .maybeSingle();

        if (existing != null && existing['id'] != widget.userId) {
          throw Exception('Username already taken');
        }
      }

      await AuthService().updateUserProfile(
        alias: alias,
        displayName: displayName,
        bio: bio,
      );

      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile: $e'),
          backgroundColor: AppConstants.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Builds an Analytics Dashboard for Verified Users
  Widget _buildAnalyticsDashboard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppConstants.mediumGray.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppConstants.dividerColor,
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.insert_chart_outlined_rounded,
                  color: AppConstants.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Profile Analytics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatBadge(
                    'Profile Views',
                    _analytics!.profileViews.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBadge(
                    'Post Views',
                    _analytics!.postViews.toString(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatBadge(
                    'Likes',
                    _analytics!.likesReceived.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBadge(
                    'Comments',
                    _analytics!.commentsReceived.toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.dividerColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════ Q&A HELPER ══════════════════════
  void _showAskQuestionDialog() {
    final questionController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: AppConstants.darkGray,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.help_outline_rounded,
                    color: AppConstants.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ask ${_user!.displayName ?? "@" + _user!.alias}',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your question will be sent anonymously. They can choose to answer it publicly on their profile.',
                  style: TextStyle(
                      color: AppConstants.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: questionController,
                  maxLines: 4,
                  maxLength: 250,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type your anonymous question...',
                    hintStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                    filled: true,
                    fillColor: AppConstants.mediumGray,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    counterStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: AppConstants.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final text = questionController.text.trim();
                        if (text.isEmpty) return;

                        setStateDialog(() => isSubmitting = true);

                        try {
                          final me = supabase.auth.currentUser;
                          await supabase.from('anonymous_questions').insert({
                            'target_user_id': widget.userId,
                            'asker_user_id':
                                me?.id, // Optional, but helps prevent spam
                            'question': text,
                            'answered': false,
                          });

                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    const Text('Question sent anonymously!'),
                                backgroundColor: AppConstants.green,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Error sending Q&A: $e');
                          setStateDialog(() => isSubmitting = false);
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Send Form',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Builds a circular profile avatar with a proper shimmer loading state
  /// and an icon fallback — avoids the silent blank of CircleAvatar.backgroundImage.
  Widget _buildProfileAvatar(UserModel user, {required double radius}) {
    final size = radius * 2;
    final imageUrl = user.profileImageUrl;

    if (imageUrl == null || imageUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppConstants.primaryBlue,
        child: Icon(Icons.person, color: Colors.white, size: radius),
      );
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          // Shimmer while bytes are downloading
          return Container(
            width: size,
            height: size,
            color: AppConstants.mediumGray,
            child: Center(
              child: SizedBox(
                width: radius,
                height: radius,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppConstants.primaryBlue.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: size,
            height: size,
            color: AppConstants.primaryBlue,
            child: Icon(Icons.person, color: Colors.white, size: radius),
          );
        },
      ),
    );
  }

  Future<void> _pickAndUploadProfileImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked == null) return;

      // Show the circular ring loader on the avatar — separate from _isSaving
      if (mounted) setState(() => _isUploadingProfileImage = true);

      final publicUrl = await ImageUploadService.uploadPostImage(
        imageFile: File(picked.path),
        postId: 'profile_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (publicUrl.isEmpty) {
        throw Exception('Image upload failed');
      }

      await AuthService().updateUserProfile(profileImageUrl: publicUrl);

      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload photo: $e'),
          backgroundColor: AppConstants.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploadingProfileImage = false;
        });
      }
    }
  }

  void _showFeedbackDialog() {
    final feedbackController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            const Text('Send Feedback', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: feedbackController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter your feedback...',
            hintStyle: TextStyle(color: AppConstants.textSecondary),
            border: InputBorder.none,
          ),
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final message = feedbackController.text.trim();
              if (message.isEmpty) return;

              try {
                await supabase.from('feedback').insert({
                  'user_id': supabase.auth.currentUser!.id,
                  'subject': message,
                  'message': message,
                });

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Feedback sent successfully'),
                      backgroundColor: AppConstants.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to send feedback: $e'),
                      backgroundColor: AppConstants.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _reportUser() {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Report User', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: reasonController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Reason for reporting...',
            hintStyle: TextStyle(color: AppConstants.textSecondary),
            border: InputBorder.none,
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;

              try {
                final currentUser = supabase.auth.currentUser!;
                final reportedUserId = widget.userId;

                // Insert report
                await supabase.from('reports').insert({
                  'reporter_id': currentUser.id,
                  'reported_user_id': reportedUserId,
                  'reason': reason,
                });

                // Insert feedback
                await supabase.from('feedback').insert({
                  'user_id': currentUser.id,
                  'subject': 'Report: $reason (reported user: $reportedUserId)',
                  'message': 'Report: $reason (reported user: $reportedUserId)',
                });

                // Check report count and ban if >= 10
                final reportsResponse = await supabase
                    .from('reports')
                    .select('id')
                    .eq('reported_user_id', reportedUserId);

                if (reportsResponse.length >= 10) {
                  await supabase
                      .from('users')
                      .update({'is_banned': true}).eq('id', reportedUserId);
                }

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('User reported successfully'),
                      backgroundColor: AppConstants.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to report user: $e'),
                      backgroundColor: AppConstants.red,
                    ),
                  );
                }
              }
            },
            child:
                const Text('Report', style: TextStyle(color: AppConstants.red)),
          ),
        ],
      ),
    );
  }
}
