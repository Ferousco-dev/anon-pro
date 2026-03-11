import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/post_card.dart';
import '../../widgets/comments_sheet.dart';
import '../../widgets/shareable_post_card.dart';
import '../../models/post_model.dart';
import '../../models/user_model.dart';
import '../../main.dart';
import '../../services/image_upload_service.dart';
import '../../services/feed_cache_service.dart';

class AnonymousScreen extends StatefulWidget {
  const AnonymousScreen({super.key});

  @override
  State<AnonymousScreen> createState() => _AnonymousScreenState();
}

class _AnonymousScreenState extends State<AnonymousScreen> {
  List<PostModel> _posts = [];
  bool _isLoading = true;
  String? _error;
  UserModel? _currentUser;
  final Set<String> _likeInFlight = {};
  final Set<String> _repostedPostIds = {};
  ScrollController _scrollController = ScrollController();
  final ScreenshotController _screenshotController = ScreenshotController();
  final FeedCacheService _cache = FeedCacheService();

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenNetwork();
  }

  Future<void> _loadFromCacheThenNetwork() async {
    // 1) Instantly load cached anonymous feed
    final cachedPosts = _cache.getAnonFeed();
    if (cachedPosts != null && cachedPosts.isNotEmpty && mounted) {
      final anonymousUser = UserModel(
        id: '',
        email: '',
        alias: 'Anonymous',
        displayName: 'Anonymous',
        role: 'user',
        isBanned: false,
        isVerified: false,
        followersCount: 0,
        followingCount: 0,
        postsCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final posts = cachedPosts.map((p) => PostModel.fromJson(p)).toList();
      for (final post in posts) {
        post.user = anonymousUser;
      }
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    }

    // 2) Refresh from network
    _loadCurrentUser();
    _loadPosts();
  }

  Future<void> _loadCurrentUser() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      final userId = user.id;
      final userData =
          await supabase.from('users').select().eq('id', userId).single();

      if (mounted) {
        setState(() {
          _currentUser = UserModel.fromJson(userData);
        });
      }
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
              likes!left (
                id, user_id
              )
            ''')
            .eq('is_anonymous', true)
            .order('created_at', ascending: false)
            .limit(AppConstants.postsPerPage);
      } catch (e) {
        // Fallback to old schema if new schema doesn't exist
        response = await supabase
            .from('posts')
            .select('*')
            .eq('is_anonymous', true)
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

      // Create anonymous user for all posts
      final anonymousUser = UserModel(
        id: '',
        email: '',
        alias: 'Anonymous',
        displayName: 'Anonymous',
        role: 'user',
        isBanned: false,
        isVerified: false,
        followersCount: 0,
        followingCount: 0,
        postsCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      for (final post in posts) {
        post.user = anonymousUser;
      }

      if (mounted) {
        setState(() {
          _posts = posts;
          if (showLoading) _isLoading = false;
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(savedOffset.clamp(
              0.0, _scrollController.position.maxScrollExtent));
        }

        // Save to cache for next time
        final cacheData = (response as List).cast<Map<String, dynamic>>().toList();
        _cache.saveAnonFeed(cacheData);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final errorStr = e.toString();
          if (errorStr.contains('SocketException') || errorStr.contains('Failed host lookup')) {
            _error = 'Connection failed. Please check your internet and retry.';
          } else {
            _error = errorStr;
          }
          if (showLoading) _isLoading = false;
        });
      }
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

  Future<void> _handleRepostToggle(PostModel post) async {
    if (_currentUser == null || !mounted) return;

    try {
      if (_repostedPostIds.contains(post.id)) {
        // Unrepost
        await supabase
            .from('reposts')
            .delete()
            .eq('post_id', post.id)
            .eq('user_id', _currentUser!.id);

        if (mounted) {
          setState(() {
            _repostedPostIds.remove(post.id);
          });
        }
      } else {
        // Repost
        await supabase.from('reposts').insert({
          'post_id': post.id,
          'user_id': _currentUser!.id,
        });

        if (mounted) {
          setState(() {
            _repostedPostIds.add(post.id);
          });
        }
      }
    } catch (e) {
      print('Error toggling repost: $e');
    }
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
                              backgroundColor: AppConstants.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryBlue,
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

  void _showComments(PostModel post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsSheet(
        post: post,
        currentUser: _currentUser,
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

  Future<void> _handleDeletePost(PostModel post) async {
    if (_currentUser == null) return;

    // Only allow deletion if user is admin
    if (!_currentUser!.isAdmin) return;

    try {
      // Delete via secure backend (handles ImageKit deletion + DB deletion)
      await ImageUploadService.deletePostImage(post.id);

      if (mounted) {
        setState(() {
          _posts.removeWhere((p) => p.id == post.id);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted'),
            backgroundColor: AppConstants.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting post: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete post: ${e.toString()}'),
            backgroundColor: AppConstants.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
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
                      Text(
                        'Error loading posts',
                        style: TextStyle(
                          color: AppConstants.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadPosts,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadPosts,
                color: AppConstants.primaryBlue,
                backgroundColor: AppConstants.darkGray,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  itemCount: _posts.length,
                  itemBuilder: (context, index) {
                    return PostCard(
                      post: _posts[index],
                      currentUser: _currentUser,
                      onLikeToggle: () => _handleLikeToggle(_posts[index]),
                      onComment: () => _showComments(_posts[index]),
                      onRepost: () => _handleRepostToggle(_posts[index]),
                      onShare: () => _handleShare(_posts[index]),
                      onDelete: _currentUser?.isAdmin == true
                          ? () => _handleDeletePost(_posts[index])
                          : null,
                    );
                  },
                ),
              );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
