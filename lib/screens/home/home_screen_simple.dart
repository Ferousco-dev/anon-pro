import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/post_model.dart';
import '../../models/user_model.dart';
import '../../models/status_model.dart';
import '../../utils/constants.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/post_card.dart';
import '../../widgets/comments_sheet.dart';
import '../../widgets/create_post_sheet.dart';
import '../../widgets/edit_post_sheet.dart';
import '../../widgets/new_posts_notification_bar.dart';
import '../../widgets/shareable_post_card.dart';
import '../../widgets/feed_skeleton_loader.dart';
import '../../widgets/forward_post_sheet.dart';
import '../../providers/new_posts_provider.dart';
import '../search/search_screen.dart';
import '../../status/status_bar.dart';
import '../../status/user_status_group_model.dart';
import '../../status/user_model.dart' as StatusUser;
import '../../status/post_model.dart' as StatusPost;
import '../../status/status_controller.dart';
import '../../status/post_viewer.dart';
import '../anonymous/anonymous_screen.dart';
import '../../services/feed_cache_service.dart';
import '../../services/broadcast_service.dart';
import '../../widgets/broadcast_modal.dart';
import '../../widgets/liquid_glass_nav_bar.dart';
import '../../services/widget_data_service.dart';
// Supabase client getter
final supabase = Supabase.instance.client;

class HomeScreenSimple extends StatefulWidget {
  const HomeScreenSimple({super.key});

  @override
  State<HomeScreenSimple> createState() => _HomeScreenSimpleState();
}

class _HomeScreenSimpleState extends State<HomeScreenSimple>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late PageController _pageController;
  List<PostModel> _posts = [];
  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isLoadingStatuses = false;
  bool _isCreatingStatus = false;
  double _uploadProgress = 0.0;
  int _selectedTab = 0;
  final Set<String> _likeInFlight = {};
  final ImagePicker _imagePicker = ImagePicker();
  List<StatusModel> _statuses = [];
  List<UserStatusGroup> _statusGroups = [];
  bool _isNavBarVisible = true;

  // Scroll animation properties
  late AnimationController _navBarAnimationController;
  late Animation<Offset> _navBarOffsetAnimation;
  late Animation<double> _navBarSizeAnimation;
  double _lastScrollOffset = 0;
  static const double _scrollDeltaThreshold =
      15.0; // Hide after scrolling 15px down
  static const int _animationDuration = 300; // Apple-style duration

  // Cache service
  final FeedCacheService _cache = FeedCacheService();

  // Screenshot controller for sharing
  final ScreenshotController _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();

    // Initialize page controller for swipe navigation
    _pageController = PageController(initialPage: 0);
    _pageController.addListener(_onPageChanged);

    // Initialize navbar animation controller
    _navBarAnimationController = AnimationController(
      duration: const Duration(milliseconds: _animationDuration),
      vsync: this,
    );

    _navBarOffsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1),
    ).animate(
      CurvedAnimation(
          parent: _navBarAnimationController, curve: Curves.easeInOut),
    );

    _navBarSizeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _navBarAnimationController, curve: Curves.easeInOut),
    );

    // Load from cache first (instant), then from network
    _loadFromCacheThenNetwork();

    // Initialize new posts real-time listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final newPostsProvider =
            Provider.of<NewPostsProvider>(context, listen: false);
        newPostsProvider.initializeRealtimeListener();

        // Initialize broadcast service and check for unseen broadcasts
        _initializeBroadcasts();
      }
    });

    _scrollController.addListener(_onScroll);
  }

  void _onPageChanged() {
    final newTab = (_pageController.page ?? 0).round();
    if (newTab != _selectedTab && mounted) {
      setState(() => _selectedTab = newTab);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSelectedTabFromRoute();
  }

  void _updateSelectedTabFromRoute() {
    final route = ModalRoute.of(context)?.settings.name;
    if (route != null && route != '/home') {
      setState(() {
        switch (route) {
          case '/anonymous':
            _selectedTab = 1;
            break;
          case '/groups':
            _selectedTab = 2;
            break;
          case '/stories':
            _selectedTab = 3;
            break;
        }
      });
    }
  }

  // Initialize broadcasts and show unseen ones
  Future<void> _initializeBroadcasts() async {
    try {
      await broadcastService.init();
      final unseenBroadcasts = await broadcastService.getUnseenBroadcasts();

      if (unseenBroadcasts.isNotEmpty && mounted) {
        // Show broadcasts one by one
        for (final broadcast in unseenBroadcasts) {
          if (mounted) {
            await _showBroadcastModal(broadcast);
          }
        }
      }
    } catch (e) {
      debugPrint('Error initializing broadcasts: $e');
    }
  }

  Future<void> _showBroadcastModal(BroadcastMessage broadcast) async {
    final Color typeColor = _parseColorFromHex(broadcast.typeColor);

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return BroadcastModal(
          emoji: broadcast.emoji,
          type: broadcast.type,
          title: broadcast.title,
          message: broadcast.body,
          typeColor: typeColor,
          onDismiss: () {
            broadcastService.markAsSeen(broadcast.id);
            Navigator.pop(ctx);
          },
        );
      },
    );
  }

  Color _parseColorFromHex(String hexColor) {
    try {
      final hex = hexColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return AppConstants.primaryBlue;
    }
  }

  /// Load cached data instantly, then refresh from network
  Future<void> _loadFromCacheThenNetwork() async {
    // 1) Instantly load cached current user
    final cachedUser = _cache.getCurrentUser();
    if (cachedUser != null && mounted) {
      setState(() {
        _currentUser = UserModel.fromJson(cachedUser);
      });
    }

    // 2) Instantly load cached home feed
    final cachedPosts = _cache.getHomeFeed();
    if (cachedPosts != null && cachedPosts.isNotEmpty && mounted) {
      final posts = cachedPosts.map((p) => PostModel.fromJson(p)).toList();
      setState(() {
        _posts = posts;
        _isLoading = false; // Show cached data immediately
      });
    }

    // 3) Refresh from network in background
    await _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final userData =
            await supabase.from('users').select().eq('id', userId).single();

        // Save to cache
        _cache.saveCurrentUser(userData);

        if (mounted) {
          setState(() {
            _currentUser = UserModel.fromJson(userData);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    } finally {
      // Load posts and statuses after user is loaded
      await Future.wait([
        _loadPosts(),
        _loadStatuses(),
      ]);
    }
  }

  void _onScroll() {
    if (!mounted) return;

    final currentOffset = _scrollController.offset;
    final scrollDelta = currentOffset - _lastScrollOffset;

    bool shouldHideNavbar = false;

    // Scrolling down - hide navbar if scrolled more than threshold
    if (scrollDelta > _scrollDeltaThreshold && currentOffset > 0) {
      shouldHideNavbar = true;
    }
    // Scrolling up - always show navbar
    else if (scrollDelta < 0) {
      shouldHideNavbar = false;
    }
    // If standing still or at top, keep current state
    else {
      shouldHideNavbar = !_isNavBarVisible;
    }

    _lastScrollOffset = currentOffset;

    // Update navbar visibility with animation
    if (shouldHideNavbar != !_isNavBarVisible) {
      setState(() {
        _isNavBarVisible = !shouldHideNavbar;
      });

      // Trigger the animation
      if (shouldHideNavbar) {
        _navBarAnimationController.forward();
      } else {
        _navBarAnimationController.reverse();
      }
    }
  }

  Future<void> _loadStatuses() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      setState(() {
        _isLoadingStatuses = true;
      });

      final response = await supabase.rpc(
        'get_user_status_feed',
        params: {'user_uuid': currentUser.id},
      );




      final statuses = (response as List<dynamic>)
          .map(
            (row) => StatusModel.fromJson(row as Map<String, dynamic>),
          )
          .toList();



      // Group statuses by user to build proper story-style sequences
      final Map<String, List<StatusModel>> grouped = {};
      for (final status in statuses) {
        grouped.putIfAbsent(status.userId, () => []).add(status);
      }

      final String? currentUserId = currentUser.id;
      final List<UserStatusGroup> groups = [];

      grouped.forEach((userId, userStatuses) {
        // Sort each user's statuses by creation time
        userStatuses.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final first = userStatuses.first;
        final user = StatusUser.User(
          id: userId,
          username: first.displayName ?? first.alias,
          avatarUrl: first.profileImageUrl ?? '',
        );
        final posts = userStatuses
            .map((s) => StatusPost.Post(
                  id: s.id,
                  userId: s.userId,
                  mediaUrl: s.mediaPath,
                  createdAt: s.createdAt,
                  isVideo: s.mediaType == 'video',
                ))
            .toList();
        groups.add(UserStatusGroup(user: user, posts: posts));
      });

      // Sort groups by most recent status so the freshest appear first
      groups.sort((a, b) {
        final aLatest = a.posts.last.createdAt;
        final bLatest = b.posts.last.createdAt;
        return bLatest.compareTo(aLatest);
      });

      // Always include current user, even if no statuses
      final currentUserGroup = groups.firstWhere(
        (g) => g.user.id == currentUserId,
        orElse: () => UserStatusGroup(
          user: StatusUser.User(
            id: currentUserId!,
            username: _currentUser?.displayName ?? _currentUser?.alias ?? 'You',
            avatarUrl: _currentUser?.profileImageUrl ?? '',
          ),
          posts: [],
        ),
      );
      if (!groups.contains(currentUserGroup)) {
        groups.insert(0, currentUserGroup); // Insert at beginning
      }

      if (mounted) {
        setState(() {
          _statuses = statuses;
          _statusGroups = groups;
        });
      }
    } catch (e) {
      debugPrint('Error loading statuses: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStatuses = false;
        });
      }
    }
  }

  Future<void> _loadPosts() async {
    try {

      // COMPLETE QUERY: Include all fields needed by UserModel
      final response = await supabase.from('posts').select('''
            *,
            users (
              id,
              email,
              alias,
              display_name,
              bio,
              profile_image_url,
              cover_image_url,
              role,
              is_banned,
              is_verified,
              followers_count,
              following_count,
              posts_count,
              created_at,
              updated_at
            )
          ''').order('created_at', ascending: false).limit(50);


      final posts = (response as List).map((postData) {
        return PostModel.fromJson(postData as Map<String, dynamic>);
      }).toList();



      final postIds = posts.map((p) => p.id).toList();

      // Load post_tags for @mention navigation (alias -> userId) - for all users
      final taggedMap = <String, Map<String, String>>{};
      if (postIds.isNotEmpty) {
        try {
          final tagsResponse = await supabase
              .from('post_tags')
              .select('post_id, tagged_user_id')
              .inFilter('post_id', postIds);

          final taggedUserIds = (tagsResponse as List)
              .map((r) => r['tagged_user_id'] as String)
              .toSet()
              .toList();

          Map<String, String> idToAlias = {};
          if (taggedUserIds.isNotEmpty) {
            final usersRes = await supabase
                .from('users')
                .select('id, alias')
                .inFilter('id', taggedUserIds);
            for (final u in usersRes as List) {
              final alias = u['alias'] as String?;
              if (alias != null) {
                idToAlias[u['id'] as String] = alias;
              }
            }
          }

          for (final row in tagsResponse) {
            final postId = row['post_id'] as String;
            final taggedUserId = row['tagged_user_id'] as String;
            final alias = idToAlias[taggedUserId];
            if (alias != null) {
              taggedMap.putIfAbsent(postId, () => {})[alias] = taggedUserId;
            }
          }
        } catch (e) {
          debugPrint('Error loading post_tags: $e');
        }
      }

      // Load likes for current user
      if (_currentUser != null && posts.isNotEmpty) {
        final likesResponse = await supabase
            .from('likes')
            .select('post_id, user_id')
            .eq('user_id', _currentUser!.id)
            .inFilter('post_id', postIds);

        final likedPostIds = (likesResponse as List)
            .map((like) => like['post_id'] as String)
            .toSet();

        // Load reposts for current user
        final repostsResponse = await supabase
            .from('posts')
            .select('original_post_id')
            .eq('user_id', _currentUser!.id)
            .inFilter('original_post_id', postIds);

        final repostedPostIds = (repostsResponse as List)
            .map((repost) => repost['original_post_id'] as String)
            .toSet();

        // Load all likes count
        final allLikesResponse = await supabase
            .from('likes')
            .select('post_id')
            .inFilter('post_id', postIds);

        final likesCountMap = <String, int>{};
        for (var like in allLikesResponse as List) {
          final postId = like['post_id'] as String;
          likesCountMap[postId] = (likesCountMap[postId] ?? 0) + 1;
        }

        // Update posts with like status, repost status, counts, and tagged users
        for (int i = 0; i < posts.length; i++) {
          posts[i] = posts[i].copyWith(
            isLikedByCurrentUser: likedPostIds.contains(posts[i].id),
            isRepostedByCurrentUser: repostedPostIds.contains(posts[i].id),
            likesCount: likesCountMap[posts[i].id] ?? 0,
            taggedUsers: taggedMap[posts[i].id],
          );
        }
      } else if (posts.isNotEmpty) {
        // No current user - still apply tagged users for display
        for (int i = 0; i < posts.length; i++) {
          posts[i] = posts[i].copyWith(taggedUsers: taggedMap[posts[i].id]);
        }
      }

      if (mounted) {

        setState(() {
          _posts = posts;
          _isLoading = false;
        });

        // Save to cache for next time
        final cacheData = posts.map((p) => p.toJson()).toList();
        // Include user data in cache
        for (int i = 0; i < posts.length; i++) {
          if (posts[i].user != null) {
            cacheData[i]['users'] = posts[i].user!.toJson();
          }
        }
        _cache.saveHomeFeed(cacheData);

        // Sync native widgets with latest data
        WidgetDataService.updateWidgetData();


      }
    } catch (e) {
      debugPrint('Error loading posts: $e');
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

      debugPrint('Loading metadata for ${newPosts.length} new posts...');

      // Load full user data for new posts
      final postIds = newPosts.map((p) => p.id).toList();
      final postDetailsResponse = await supabase.from('posts').select('''
            *,
            users (
              id,
              email,
              alias,
              display_name,
              bio,
              profile_image_url,
              cover_image_url,
              role,
              is_banned,
              is_verified,
              followers_count,
              following_count,
              posts_count,
              created_at,
              updated_at
            )
          ''').inFilter('id', postIds);

      final enrichedPosts = (postDetailsResponse as List).map((postData) {
        return PostModel.fromJson(postData as Map<String, dynamic>);
      }).toList();

      // Load post_tags for new posts
      final taggedMap = <String, Map<String, String>>{};
      try {
        final tagsResponse = await supabase
            .from('post_tags')
            .select('post_id, tagged_user_id')
            .inFilter('post_id', postIds);

        final taggedUserIds = (tagsResponse as List)
            .map((r) => r['tagged_user_id'] as String)
            .toSet()
            .toList();

        Map<String, String> idToAlias = {};
        if (taggedUserIds.isNotEmpty) {
          final usersRes = await supabase
              .from('users')
              .select('id, alias')
              .inFilter('id', taggedUserIds);
          for (final u in usersRes as List) {
            final alias = u['alias'] as String?;
            if (alias != null) {
              idToAlias[u['id'] as String] = alias;
            }
          }
        }

        for (final row in tagsResponse) {
          final postId = row['post_id'] as String;
          final taggedUserId = row['tagged_user_id'] as String;
          final alias = idToAlias[taggedUserId];
          if (alias != null) {
            taggedMap.putIfAbsent(postId, () => {})[alias] = taggedUserId;
          }
        }
      } catch (e) {
        debugPrint('Error loading tags for new posts: $e');
      }

      // Load likes info for current user on new posts
      if (_currentUser != null && enrichedPosts.isNotEmpty) {
        final likesResponse = await supabase
            .from('likes')
            .select('post_id, user_id')
            .eq('user_id', _currentUser!.id)
            .inFilter('post_id', postIds);

        final likedPostIds = (likesResponse as List)
            .map((like) => like['post_id'] as String)
            .toSet();

        // Load all likes count for new posts
        final allLikesResponse = await supabase
            .from('likes')
            .select('post_id')
            .inFilter('post_id', postIds);

        final likesCountMap = <String, int>{};
        for (var like in allLikesResponse as List) {
          final postId = like['post_id'] as String;
          likesCountMap[postId] = (likesCountMap[postId] ?? 0) + 1;
        }

        // Update new posts with like info
        for (int i = 0; i < enrichedPosts.length; i++) {
          enrichedPosts[i] = enrichedPosts[i].copyWith(
            isLikedByCurrentUser: likedPostIds.contains(enrichedPosts[i].id),
            likesCount: likesCountMap[enrichedPosts[i].id] ?? 0,
            taggedUsers: taggedMap[enrichedPosts[i].id],
          );
        }
      }

      // Prepend new posts to feed
      if (mounted) {
        setState(() {
          _posts.insertAll(0, enrichedPosts);
        });

        // Smooth scroll to top
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      debugPrint('Error loading new posts: $e');
    }
  }

  Future<void> _createStatus() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to post a status'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      if (!mounted) return;

      // Start upload in background - begin showing progress
      setState(() {
        _isCreatingStatus = true;
        _uploadProgress = 0.1;
      });

      final bytes = await picked.readAsBytes();
      final fileExt = picked.name.split('.').last.toLowerCase();
      final contentType = 'image/$fileExt';

      final objectPath =
          'statuses/${_currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}_${picked.name}';

      // Update progress during file upload
      if (mounted) {
        setState(() {
          _uploadProgress = 0.5;
        });
      }

      await supabase.storage.from('statuses').uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: false,
            ),
          );

      // Update progress after file upload
      if (mounted) {
        setState(() {
          _uploadProgress = 0.8;
        });
      }

      await supabase.from('user_statuses').insert({
        'user_id': _currentUser!.id,
        'media_path': objectPath,
        'media_type': 'image',
      });

      // Update progress after database insert
      if (mounted) {
        setState(() {
          _uploadProgress = 0.95;
        });
      }

      await _loadStatuses();

      if (mounted) {
        // Final progress
        setState(() {
          _uploadProgress = 1.0;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status posted'),
            backgroundColor: AppConstants.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Reset progress after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _uploadProgress = 0.0;
              _isCreatingStatus = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error creating status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post status: $e'),
            backgroundColor: AppConstants.red,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Reset progress on error
        setState(() {
          _uploadProgress = 0.0;
          _isCreatingStatus = false;
        });
      }
    }
  }

  void _showCreatePost() {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to create posts'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreatePostSheet(
        currentUser: _currentUser!,
        // Called IMMEDIATELY when user taps Post — sheet is already closing
        onOptimisticPost: (optimisticPost) {
          if (!mounted) return;
          setState(() {
            // Prepend the optimistic post so it's visible right away
            _posts.insert(0, optimisticPost);
          });
          // Scroll to top so the user sees their new post
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        // Called after background DB work completes — replaces optimistic post
        // with the real server record (proper ID, final image URL, etc.)
        onPostCreated: () {
          _loadPosts();
        },
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
        onPostUpdated: _loadPosts,
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
                       foregroundColor: Colors.white, // makes icon + text visible
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

  Future<void> _handleLikeToggle(PostModel post) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to like posts'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;

    // Prevent multiple simultaneous like requests
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
            final index = _posts.indexWhere((p) => p.id == post.id);
            if (index != -1) {
              _posts[index] = _posts[index].copyWith(
                likesCount: _posts[index].likesCount - 1,
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
            final index = _posts.indexWhere((p) => p.id == post.id);
            if (index != -1) {
              _posts[index] = _posts[index].copyWith(
                likesCount: _posts[index].likesCount + 1,
                isLikedByCurrentUser: true,
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to like post: ${e.toString()}'),
            backgroundColor: AppConstants.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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

  Future<void> _handleRepost(PostModel post) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to repost'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Don't allow reposting your own post
    if (post.userId == _currentUser!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot repost your own post'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Don't allow reposting if already reposted
    if (post.isRepostedByCurrentUser == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already reposted this'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      // Create repost
      final repostData = {
        'user_id': _currentUser!.id,
        'content': post.content, // Copy the original content
        'image_url': post.imageUrl, // Copy the image if any
        'is_anonymous': false,
        'original_post_id': post.id,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await supabase.from('posts').insert(repostData).select();

      if (response.isNotEmpty && mounted) {
        // Update original post's repost count
        await supabase
            .from('posts')
            .update({'reposts_count': post.repostsCount + 1}).eq('id', post.id);

        // Update local state
        setState(() {
          final index = _posts.indexWhere((p) => p.id == post.id);
          if (index != -1) {
            _posts[index] = _posts[index].copyWith(
              repostsCount: _posts[index].repostsCount + 1,
              isRepostedByCurrentUser: true,
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post reposted successfully'),
            backgroundColor: AppConstants.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Refresh posts to show the new repost
        await _loadPosts();
      }
    } catch (e) {
      debugPrint('Error reposting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to repost: ${e.toString()}'),
            backgroundColor: AppConstants.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAnonymousCreatePost() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreatePostSheet(
        currentUser: _currentUser,
        isAnonymous: true,
        onOptimisticPost: (optimisticPost) {
          if (!mounted) return;
          setState(() {
            _posts.insert(0, optimisticPost);
          });
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        onPostCreated: () {
          _loadPosts();
        },
      ),
    );
  }

  void _handleForward(PostModel post) {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to forward posts'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ForwardPostSheet(
        post: post,
        currentUser: _currentUser!,
      ),
    );
  }

  Widget _buildAnimatedBottomNav() {
    return SizeTransition(
      sizeFactor: _navBarSizeAnimation,
      axisAlignment: 1.0,
      child: SlideTransition(
        position: _navBarOffsetAnimation,
        child: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    return LiquidGlassNavBar(
      selectedIndex: _selectedTab,
      profileImageUrl: _currentUser?.profileImageUrl,
      onTap: (index) {
        setState(() => _selectedTab = index);
        if (index == 0 || index == 1) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else if (index == 2) {
          Navigator.pushNamed(context, '/groups');
        } else if (index == 3) {
          if (_currentUser != null) {
            Navigator.pushNamed(context, '/profile',
                arguments: _currentUser!.id);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please log in to view profile'),
                backgroundColor: AppConstants.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildHomePage() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Stack(
          children: [
            // Main Feed
            RefreshIndicator(
              color: AppConstants.primaryBlue,
              onRefresh: () async {
                await Future.wait([
                  _loadPosts(),
                  _loadStatuses(),
                ]);
              },
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: 1 + _posts.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildStatusBar();
                  }

                  final post = _posts[index - 1];

                  return PostCard(
                    post: post,
                    currentUser: _currentUser,
                    onLikeToggle: () => _handleLikeToggle(post),
                    onComment: () => _showComments(post),
                    onShare: () => _handleShare(post),
                    onRepost: () => _handleRepost(post),
                    onForward: () => _handleForward(post),
                    onDelete: _currentUser?.id == post.userId ||
                            _currentUser?.isAdmin == true
                        ? () => _handleDeletePost(post)
                        : null,
                    onEdit: _currentUser?.id == post.userId &&
                            post.originalPostId == null
                        ? () => _editPost(post)
                        : null,
                  );
                },
              ),
            ),
            // New Posts Notification Bar (floating overlay)
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
      ),
    );
  }

  Widget _buildStatusBar() {
    return StatusBar(
      currentUserId: _currentUser?.id ?? '',
      userGroups: _statusGroups,
      onUserTap: (group) {
        if (group.posts.isEmpty && group.user.id == _currentUser?.id) {
          // Create status for current user
          _createStatus();
          return;
        }
        final index = _statusGroups.indexOf(group);
        final controller = StatusController(
            _statusGroups, _currentUser?.id ?? '',
            currentUserIndex: index);
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => PostViewer(controller: controller),
              ),
            )
            .then((_) => _loadStatuses());
      },
      onCreateStatus: _createStatus,
      uploadProgress: _uploadProgress,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: _selectedTab == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _selectedTab != 0) {
            setState(() => _selectedTab = 0);
            _pageController.animateToPage(0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut);
          }
        },
        child: Scaffold(
          backgroundColor: AppConstants.black,
          appBar: AppBar(
            backgroundColor: AppConstants.black,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              _selectedTab == 0 ? 'ANONPRO' : 'Anonymous',
              style: const TextStyle(
                color: AppConstants.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                onPressed: () async {
                  await Future.wait([
                    _loadPosts(),
                    _loadStatuses(),
                  ]);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Feed refreshed'),
                        backgroundColor: AppConstants.green,
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.refresh, color: AppConstants.white),
              ),
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        SearchScreen(currentUser: _currentUser),
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
                  if (currentUser != null) {
                    Navigator.pushNamed(context, '/profile',
                        arguments: currentUser.id);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please log in to view profile'),
                        backgroundColor: AppConstants.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppConstants.primaryBlue,
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
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: const FeedSkeletonLoader(itemCount: 5),
                  ),
                )
              : PageView(
                  controller: _pageController,
                  physics: const ClampingScrollPhysics(),
                  onPageChanged: (page) {
                    setState(() => _selectedTab = page);
                  },
                  children: [
                    // Page 0: Home Feed
                    _buildHomePage(),
                    // Page 1: Anonymous Feed
                    const AnonymousScreen(),
                  ],
                ),
          floatingActionButton: FloatingActionButton(
            onPressed:
                _selectedTab == 0 ? _showCreatePost : _showAnonymousCreatePost,
            backgroundColor: AppConstants.primaryBlue,
            elevation: 4,
            child: Icon(
                _selectedTab == 0
                    ? Icons.edit_rounded
                    : Icons.person_off_rounded,
                size: 24),
          ),
          bottomNavigationBar: _buildAnimatedBottomNav(),
        ));
  }

  void _cleanupUserData() {
    setState(() {
      _currentUser = null;
      _posts.clear();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    _navBarAnimationController.dispose();
    _cleanupUserData();
    // Dispose new posts provider real-time listener
    if (mounted) {
      final newPostsProvider =
          Provider.of<NewPostsProvider>(context, listen: false);
      newPostsProvider.disposeRealtimeListener();
    }
    super.dispose();
  }
}
