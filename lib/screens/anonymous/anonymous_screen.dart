import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
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
import '../../utils/app_error_handler.dart';

class AnonymousScreen extends StatefulWidget {
  const AnonymousScreen({super.key});

  @override
  State<AnonymousScreen> createState() => _AnonymousScreenState();
}

class _AnonymousScreenState extends State<AnonymousScreen> {
  List<PostModel> _posts = [];
  bool _isLoading = true;
  bool _isFetchingPosts = false;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  DateTime? _oldestPostCursor;
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
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadFromCacheThenNetwork() async {
    // 1) Instantly load cached anonymous feed
    final cachedPosts = _cache.getAnonFeed();
    if (cachedPosts != null && cachedPosts.isNotEmpty && mounted) {
      final anonymousUser = _buildAnonymousUser();
      final posts = cachedPosts.map((p) => PostModel.fromJson(p)).toList();
      for (final post in posts) {
        post.user = anonymousUser;
      }
      setState(() {
        _posts = posts;
        _isLoading = false;
        _hasMorePosts = posts.length >= AppConstants.postsPerPage;
        _oldestPostCursor = posts.isNotEmpty ? posts.last.createdAt : null;
      });
      _prefetchPostImages(posts, limit: 4);
    }

    // 2) Refresh from network
    _loadCurrentUser();
    _loadPosts(showLoading: _posts.isEmpty);
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || _isFetchingPosts || !_hasMorePosts) return;
    if (_scrollController.position.extentAfter < 500) {
      unawaited(_loadMorePosts());
    }
  }

  void _prefetchPostImages(List<PostModel> posts, {int limit = 6}) {
    if (!mounted) return;
    final urls = posts
        .map((p) => p.imageUrl)
        .where((url) => url != null && url.startsWith('http'))
        .take(limit);
    for (final url in urls) {
      precacheImage(CachedNetworkImageProvider(url!), context);
    }
  }

  UserModel _buildAnonymousUser() {
    return UserModel(
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
  }

  Future<List<PostModel>> _fetchAnonPostsPage(
      {DateTime? before, int limit = AppConstants.postsPerPage}) async {
    final nowIso = DateTime.now().toIso8601String();

    List response;
    try {
      var query = supabase
          .from('posts')
          .select('''
              *,
              likes!left (
                id, user_id
              )
            ''')
          .eq('is_anonymous', true)
          .or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
          .or('expires_at.is.null,expires_at.gt.$nowIso');

      if (before != null) {
        query = query.lt('created_at', before.toIso8601String());
      }

      response = await query
          .order('created_at', ascending: false)
          .limit(limit);
    } catch (e) {
      var fallbackQuery = supabase
          .from('posts')
          .select('*')
          .eq('is_anonymous', true)
          .or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
          .or('expires_at.is.null,expires_at.gt.$nowIso');

      if (before != null) {
        fallbackQuery =
            fallbackQuery.lt('created_at', before.toIso8601String());
      }

      response = await fallbackQuery
          .order('created_at', ascending: false)
          .limit(limit);
    }

    final posts = response.map((post) {
      final postData = post as Map<String, dynamic>;

      int likesCount = 0;
      bool isLiked = false;

      if (postData.containsKey('likes')) {
        final likes = postData['likes'] as List? ?? [];
        likesCount = likes.length;
        if (_currentUser != null) {
          isLiked = likes.any((like) => like['user_id'] == _currentUser!.id);
        }
      } else {
        likesCount = postData['likes_count'] as int? ?? 0;
      }

      return PostModel.fromJson(postData).copyWith(
        likesCount: likesCount,
        isLikedByCurrentUser: isLiked,
      );
    }).toList();

    final anonymousUser = _buildAnonymousUser();
    for (final post in posts) {
      post.user = anonymousUser;
    }

    return posts;
  }

  Future<void> _loadPosts({bool showLoading = true}) async {
    if (_isFetchingPosts) return;
    _isFetchingPosts = true;
    try {
      if (showLoading) {
        if (mounted) setState(() => _isLoading = true);
      }
      final savedOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      final posts = await _fetchAnonPostsPage();

      if (mounted) {
        setState(() {
          _error = null;
          _posts = posts;
          if (showLoading) _isLoading = false;
          _hasMorePosts = posts.length >= AppConstants.postsPerPage;
          _oldestPostCursor = posts.isNotEmpty ? posts.last.createdAt : null;
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(savedOffset.clamp(
              0.0, _scrollController.position.maxScrollExtent));
        }

        // Save to cache for next time
        final cacheData = posts.map((p) => p.toJson()).toList();
        _cache.saveAnonFeed(cacheData);
      }

      _prefetchPostImages(posts);
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
    } finally {
      _isFetchingPosts = false;
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMorePosts) return;
    if (_oldestPostCursor == null) return;
    _isLoadingMore = true;
    if (mounted) setState(() {});

    try {
      final morePosts = await _fetchAnonPostsPage(
        before: _oldestPostCursor,
        limit: AppConstants.postsPerPage,
      );

      if (morePosts.isEmpty) {
        if (mounted) {
          setState(() {
            _hasMorePosts = false;
          });
        }
        return;
      }

      final existingIds = _posts.map((p) => p.id).toSet();
      final newPosts =
          morePosts.where((p) => !existingIds.contains(p.id)).toList();

      if (newPosts.isEmpty) {
        if (mounted) {
          setState(() {
            _hasMorePosts = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _posts.addAll(newPosts);
          _oldestPostCursor = _posts.last.createdAt;
          _hasMorePosts = newPosts.length >= AppConstants.postsPerPage;
        });
      }

      _prefetchPostImages(newPosts);

      final cacheData = _posts.map((p) => p.toJson()).toList();
      _cache.saveAnonFeed(cacheData);
    } catch (e) {
      debugPrint('Error loading more anonymous posts: $e');
    } finally {
      _isLoadingMore = false;
      if (mounted) setState(() {});
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
                              content: Text(AppErrorHandler.userMessage(e)),
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
            content: Text(AppErrorHandler.userMessage(e)),
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
                onRefresh: () => _loadPosts(showLoading: false),
                color: AppConstants.primaryBlue,
                backgroundColor: AppConstants.darkGray,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  itemCount:
                      _posts.length + (_isLoadingMore || _hasMorePosts ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _posts.length) {
                      if (_isLoadingMore) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppConstants.primaryBlue,
                              ),
                            ),
                          ),
                        );
                      }
                      if (!_hasMorePosts) {
                        return const SizedBox(height: 24);
                      }
                      return const SizedBox.shrink();
                    }
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
