import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/post_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../services/notification_service.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/post_card.dart';
import '../../widgets/confession_room_post_card.dart';
import '../../widgets/create_post_sheet.dart';
import '../../widgets/comments_sheet.dart';
import '../../widgets/new_posts_notification_bar.dart';
import '../../widgets/shareable_post_card.dart';
import '../../providers/new_posts_provider.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';
import '../confession_rooms/confession_rooms_screen.dart';

// Supabase client getter
final supabase = Supabase.instance.client;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  List<PostModel> _posts = [];
  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isRefreshing = false;
  int _selectedTab = 0;
  late TabController _tabController;
  RealtimeChannel? _channel;
  final Map<String, UserModel> _authorCache = {};
  final Set<String> _repostedPostIds = {};
  final Set<String> _likeInFlight = {};
  final Set<String> _repostInFlight = {};
  Timer? _refreshTimer;
  final ScreenshotController _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCurrentUser();
    _loadPosts();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _silentRefresh());
    // Initialize new posts real-time listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final newPostsProvider =
            Provider.of<NewPostsProvider>(context, listen: false);
        newPostsProvider.initializeRealtimeListener();
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final userData =
            await supabase.from('users').select().eq('id', userId).single();

        setState(() {
          _currentUser = UserModel.fromJson(userData);
        });
      }
    } catch (e) {
      print('Error loading user: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAndPrependNewPosts() async {
    try {
      final newPostsProvider =
          Provider.of<NewPostsProvider>(context, listen: false);
      final newPosts = newPostsProvider.getAndResetNewPosts();

      if (newPosts.isEmpty) return;

      // Load author information for new posts
      final authorIds = newPosts.map((p) => p.userId).toSet().toList();
      if (authorIds.isNotEmpty) {
        final authorsResponse =
            await supabase.from('users').select().inFilter('id', authorIds);

        final authors = (authorsResponse as List)
            .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
            .toList();

        final authorById = {for (final u in authors) u.id: u};
        _authorCache.addAll(authorById);
        for (final post in newPosts) {
          post.user = authorById[post.userId];
        }
      }

      // Prepend new posts to the existing feed
      if (mounted) {
        setState(() {
          _posts.insertAll(0, newPosts);
        });

        // Scroll to top with animation
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      print('Error loading new posts: $e');
    }
  }

  Future<void> _loadPosts({bool showLoading = true}) async {
    try {
      if (showLoading) {
        if (mounted) setState(() => _isLoading = true);
      }
      double savedOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      // Try the new schema first
      List response;
      try {
        response = await supabase
            .from('posts')
            .select('''
              *,
              users!posts_user_id_fkey (
                id, display_name, alias, avatar_url
              ),
              likes!left (
                id, user_id
              )
            ''')
            .eq('is_anonymous', false)
            .order('created_at', ascending: false)
            .limit(AppConstants.postsPerPage);
      } catch (e) {
        // Fallback to old schema if new schema doesn't exist
        response = await supabase
            .from('posts')
            .select('*')
            .order('created_at', ascending: false)
            .limit(AppConstants.postsPerPage);
      }

      final posts = (response as List).map((post) {
        final postData = post as Map<String, dynamic>;

        // Handle both new and old schema
        int likesCount = 0;
        bool isLiked = false;

        if (postData.containsKey('likes')) {
          // New schema with likes
          final likes = postData['likes'] as List? ?? [];
          likesCount = likes.length;

          if (_currentUser != null) {
            isLiked = likes.any((like) => like['user_id'] == _currentUser!.id);
          }
        } else {
          // Old schema - use likes_count field if available
          likesCount = postData['likes_count'] as int? ?? 0;
        }

        return PostModel.fromJson(postData).copyWith(
          likesCount: likesCount,
          isLikedByCurrentUser: isLiked,
        );
      }).toList();

      // Load user's repost status
      if (_currentUser != null) {
        final repostsResponse = await supabase
            .from('reposts')
            .select('post_id')
            .eq('user_id', _currentUser!.id);

        _repostedPostIds.clear();
        _repostedPostIds.addAll(
          (repostsResponse as List).map((r) => r['post_id'] as String),
        );
      }

      // Attach author profiles
      final authorIds = posts.map((p) => p.userId).toSet().toList();
      if (authorIds.isNotEmpty) {
        final authorsResponse =
            await supabase.from('users').select().inFilter('id', authorIds);

        final authors = (authorsResponse as List)
            .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
            .toList();

        final authorById = {for (final u in authors) u.id: u};
        _authorCache.addAll(authorById);
        for (final post in posts) {
          post.user = authorById[post.userId];
        }
      }

      setState(() {
        _posts = posts;
        if (showLoading) _isLoading = false;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
            savedOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
      }
    } catch (e) {
      print('Error loading posts: $e');
      setState(() {
        if (showLoading) _isLoading = false;
      });
    }
  }

  void _showCreatePost() {
    if (_currentUser == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreatePostSheet(
        currentUser: _currentUser!,
        onPostCreated: () {
          _loadPosts();
        },
      ),
    );
  }

  void _showComments(PostModel post) {
    if (_currentUser == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsSheet(
        post: post,
        currentUser: _currentUser!,
        onCommentCreated: () {
          if (!mounted) return;
          setState(() {
            final idx = _posts.indexWhere((p) => p.id == post.id);
            if (idx != -1) {
              final current = _posts[idx];
              _posts[idx] =
                  current.copyWith(commentsCount: current.commentsCount + 1);
            }
          });
        },
      ),
    );
  }

  Future<void> _handleShare(PostModel post) async {
    final bool isAnonymous = post.isAnonymous == true;

    // Show share dialog with beautiful card
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Screenshot(
                controller: _screenshotController,
                child: ShareablePostCard(
                  post: post,
                  isAnonymous: isAnonymous,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        // Capture screenshot
                        final image = await _screenshotController.capture();

                        if (image != null && mounted) {
                          // Save to temporary directory
                          final directory = await getTemporaryDirectory();
                          final imagePath =
                              '${directory.path}/anonpro_post_${DateTime.now().millisecondsSinceEpoch}.png';
                          final imageFile = File(imagePath);
                          await imageFile.writeAsBytes(image);

                          // Share the image
                          await Share.shareXFiles(
                            [XFile(imagePath)],
                            text: 'Check out this post on ANONPRO!',
                            sharePositionOrigin: Rect.fromLTWH(0, 0, 100, 100),
                          );

                          if (mounted) {
                            Navigator.pop(context);
                          }
                        }
                      } catch (e) {
                        debugPrint('Error capturing screenshot: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to share: ${e.toString()}'),
                              backgroundColor: Color(0xFFFF3B30),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF007AFF),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.share),
                    label: const Text('Share Card'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRepostToggle(PostModel post) async {
    if (_currentUser == null || !mounted) return;

    if (_repostInFlight.contains(post.id)) return;
    _repostInFlight.add(post.id);

    try {
      final isReposted = _repostedPostIds.contains(post.id);
      if (isReposted) {
        await supabase
            .from('reposts')
            .delete()
            .eq('post_id', post.id)
            .eq('user_id', _currentUser!.id);

        _repostedPostIds.remove(post.id);

        if (mounted) {
          setState(() {
            final idx = _posts.indexWhere((p) => p.id == post.id);
            if (idx != -1) {
              _posts[idx] =
                  _posts[idx].copyWith(sharesCount: post.sharesCount - 1);
            }
          });
        }
      } else {
        await supabase.from('reposts').insert({
          'post_id': post.id,
          'user_id': _currentUser!.id,
        });

        _repostedPostIds.add(post.id);

        if (mounted) {
          setState(() {
            final idx = _posts.indexWhere((p) => p.id == post.id);
            if (idx != -1) {
              _posts[idx] =
                  _posts[idx].copyWith(sharesCount: post.sharesCount + 1);
            }
          });
        }
      }
    } catch (e) {
      print('Error toggling repost: $e');
    } finally {
      _repostInFlight.remove(post.id);
    }
  }

  Future<void> _handleLikeToggle(PostModel post) async {
    if (_currentUser == null || !mounted) return;

    if (_likeInFlight.contains(post.id)) return;
    _likeInFlight.add(post.id);

    try {
      if (post.isLikedByCurrentUser == true) {
        // Unlike
        await supabase
            .from('likes')
            .delete()
            .eq('post_id', post.id)
            .eq('user_id', _currentUser!.id);

        if (mounted) {
          setState(() {
            post.isLikedByCurrentUser = false;
            final index = _posts.indexWhere((p) => p.id == post.id);
            if (index != -1) {
              _posts[index] = _posts[index].copyWith(
                likesCount: post.likesCount - 1,
                isLikedByCurrentUser: false,
              );
            }
          });
        }
      } else {
        // Like
        await supabase.from('likes').insert({
          'post_id': post.id,
          'user_id': _currentUser!.id,
        });

        if (mounted) {
          setState(() {
            post.isLikedByCurrentUser = true;
            final index = _posts.indexWhere((p) => p.id == post.id);
            if (index != -1) {
              _posts[index] = _posts[index].copyWith(
                likesCount: post.likesCount + 1,
                isLikedByCurrentUser: true,
              );
            }
          });
        }
      }
    } catch (e) {
      print('Error toggling like: $e');
    } finally {
      _likeInFlight.remove(post.id);
    }
  }

  Future<void> _handleDeletePost(PostModel post) async {
    if (_currentUser == null) return;

    // Only allow deletion if user is admin or post owner
    if (_currentUser!.id != post.userId && !_currentUser!.isAdmin) return;

    try {
      // Delete via secure backend (handles ImageKit deletion + DB deletion)
      await ImageUploadService.deletePostImage(post.id);

      setState(() {
        _posts.removeWhere((p) => p.id == post.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted')),
        );
      }
    } catch (e) {
      print('Error deleting post: $e');
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

  void _navigateToConfessionRoom(String? roomId) {
    if (roomId == null || _currentUser == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConfessionRoomsScreen(
          userId: _currentUser!.id,
          initialRoomId: roomId,
        ),
      ),
    );
  }

  void _silentRefresh() {
    print('Auto-refreshing posts...');
    try {
      _loadPosts(showLoading: false);
    } catch (e) {
      print('Silent refresh error: $e');
    }
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.black,
        border: Border(
          top: BorderSide(
            color: AppConstants.lightGray,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_rounded, 'Home', 0, '/home'),
              _buildNavItem(
                  Icons.person_off_rounded, 'Anonymous', 1, '/anonymous'),
              _buildNavItem(Icons.group_rounded, 'Inbox', 2, '/groups'),
              _buildNavItem(Icons.person_rounded, 'Profile', 3, '/stories'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index, String route) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedTab = index);
        if (route != '/home') {
          Navigator.pushNamed(context, route);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppConstants.primaryBlue
                  : AppConstants.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AppConstants.primaryBlue
                    : AppConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/images/anon.png',
              height: 32,
            ),
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
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SearchScreen(currentUser: _currentUser),
              ),
            ),
            icon: const Icon(Icons.search, color: AppConstants.white),
          ),
          IconButton(
            onPressed: () async {
              // If user not loaded yet, try to load them
              if (_currentUser == null) {
                await _loadCurrentUser();
              }

              final currentUser = _currentUser;
              if (currentUser != null && currentUser.id.isNotEmpty) {
                Navigator.pushNamed(context, '/profile',
                    arguments: currentUser.id);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please log in to view profile'),
                    backgroundColor: AppConstants.red,
                  ),
                );
              }
            },
            icon: CircleAvatar(
              radius: 16,
              backgroundImage: _currentUser?.profileImageUrl != null
                  ? NetworkImage(_currentUser!.profileImageUrl!)
                  : null,
              child: _currentUser?.profileImageUrl == null
                  ? const Icon(Icons.person, size: 20, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppConstants.primaryBlue,
              ),
            )
          : Stack(
              children: [
                // Main feed ListView
                ListView.builder(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _posts.length,
                  itemBuilder: (context, index) {
                    final post = _posts[index];

                    // Check if this is a confession room post
                    if (post.postType == 'confession_room') {
                      return ConfessionRoomPostCard(
                        post: post,
                        currentUser: _currentUser,
                        onLikeToggle: () => _handleLikeToggle(post),
                        onComment: () => _showComments(post),
                        onTapRoom: () => _navigateToConfessionRoom(
                            post.relatedConfessionRoomId),
                      );
                    }

                    // Regular post card
                    return PostCard(
                      post: post,
                      currentUser: _currentUser,
                      onLikeToggle: () => _handleLikeToggle(post),
                      onComment: () => _showComments(post),
                      onRepost: () => _handleRepostToggle(post),
                      onShare: () => _handleShare(post),
                      onDelete: () => _handleDeletePost(post),
                    );
                  },
                ),
                // New Posts Notification Bar (floating at the top)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: NewPostsNotificationBar(
                    onTap: _loadAndPrependNewPosts,
                    autoHideDuration: const Duration(seconds: 0),
                    enableHapticFeedback: true,
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePost,
        backgroundColor: AppConstants.primaryBlue,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    _tabController.dispose();
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
    // Dispose new posts provider real-time listener
    if (mounted) {
      final newPostsProvider =
          Provider.of<NewPostsProvider>(context, listen: false);
      newPostsProvider.disposeRealtimeListener();
    }
    super.dispose();
  }
}
