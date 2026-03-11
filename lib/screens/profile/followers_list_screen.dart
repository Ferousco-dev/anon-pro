import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../models/user_model.dart';
import '../../main.dart';
import 'profile_screen.dart';

class FollowersListScreen extends StatefulWidget {
  final String userId;
  final String type; // 'followers' or 'following'
  final String displayName;

  const FollowersListScreen({
    super.key,
    required this.userId,
    required this.type,
    required this.displayName,
  });

  @override
  State<FollowersListScreen> createState() => _FollowersListScreenState();
}

class _FollowersListScreenState extends State<FollowersListScreen> {
  List<UserModel> _users = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      List<String> userIds = [];

      if (widget.type == 'followers') {
        // Get all follower IDs
        final response = await supabase
            .from('follows')
            .select('follower_id')
            .eq('following_id', widget.userId);

        userIds = List<String>.from(
          (response as List).map((item) => item['follower_id'] as String),
        );
      } else {
        // Get all following IDs
        final response = await supabase
            .from('follows')
            .select('following_id')
            .eq('follower_id', widget.userId);

        userIds = List<String>.from(
          (response as List).map((item) => item['following_id'] as String),
        );
      }

      // Fetch user data for all IDs
      List<UserModel> users = [];
      if (userIds.isNotEmpty) {
        final usersResponse =
            await supabase.from('users').select().inFilter('id', userIds);

        for (var userData in usersResponse as List) {
          try {
            users.add(UserModel.fromJson(userData as Map<String, dynamic>));
          } catch (e) {
            debugPrint('Error parsing user: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == 'followers'
        ? '${widget.displayName}\'s Followers'
        : '${widget.displayName} is Following';

    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${_users.length} ${widget.type == 'followers' ? 'follower' : 'following'}${_users.length != 1 ? 's' : ''}',
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadList,
        color: AppConstants.primaryBlue,
        backgroundColor: AppConstants.darkGray,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppConstants.primaryBlue,
                ),
              )
            : _error != null
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
                            'Failed to load list',
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
                              color: AppConstants.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadList,
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
                : _users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 48,
                                color: AppConstants.textSecondary
                                    .withOpacity(0.4)),
                            const SizedBox(height: 12),
                            Text(
                              'No ${widget.type} yet',
                              style: const TextStyle(
                                color: AppConstants.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          return _buildUserTile(user);
                        },
                      ),
      ),
    );
  }

  Widget _buildUserTile(UserModel user) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isCurrentUser = currentUserId == user.id;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: user.id),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppConstants.darkGray.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.lightGray.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppConstants.primaryBlue.withOpacity(0.5),
                    AppConstants.primaryBlue.withOpacity(0.1),
                  ],
                ),
                border: Border.all(
                  color: AppConstants.primaryBlue.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: user.profileImageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: Image.network(
                        user.profileImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppConstants.darkGray,
                            child: Center(
                              child: Text(
                                user.alias[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Center(
                      child: Text(
                        user.alias[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.displayName ?? user.alias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (user.isVerifiedUser)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: user.role == 'admin'
                                ? const Color(0xFFFFD700).withOpacity(0.2)
                                : AppConstants.primaryBlue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            user.role == 'admin' ? '👑' : '✓',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.alias}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppConstants.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Action button
            if (!isCurrentUser)
              SizedBox(
                width: 80,
                height: 36,
                child: _buildFollowButton(user),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowButton(UserModel user) {
    return FutureBuilder<dynamic>(
      future: _checkFollowStatus(user.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            decoration: BoxDecoration(
              color: AppConstants.darkGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }

        final isFollowing = snapshot.data as bool? ?? false;

        return Container(
          decoration: BoxDecoration(
            gradient: isFollowing
                ? null
                : LinearGradient(
                    colors: [
                      AppConstants.primaryBlue,
                      AppConstants.primaryBlue.withOpacity(0.7),
                    ],
                  ),
            color: isFollowing ? AppConstants.darkGray : null,
            borderRadius: BorderRadius.circular(8),
            border: isFollowing
                ? Border.all(
                    color: AppConstants.lightGray.withOpacity(0.2),
                    width: 1,
                  )
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleFollow(user),
              borderRadius: BorderRadius.circular(8),
              child: Center(
                child: Text(
                  isFollowing ? 'Following' : 'Follow',
                  style: TextStyle(
                    color:
                        isFollowing ? AppConstants.textSecondary : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _checkFollowStatus(String userId) async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return false;

      final response = await supabase
          .from('follows')
          .select()
          .eq('follower_id', currentUser.id)
          .eq('following_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> _toggleFollow(UserModel user) async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final isFollowing = await _checkFollowStatus(user.id);

      if (isFollowing) {
        await supabase
            .from('follows')
            .delete()
            .eq('follower_id', currentUser.id)
            .eq('following_id', user.id);
      } else {
        await supabase.from('follows').insert({
          'follower_id': currentUser.id,
          'following_id': user.id,
        });
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }
}
