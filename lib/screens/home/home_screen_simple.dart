import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
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
import '../../utils/app_error_handler.dart';
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
import '../../widgets/liquid_glass_nav_bar.dart';
import '../../services/widget_data_service.dart';
import '../../widgets/ai_floating_button.dart';
import '../status/status_editor_screen.dart';
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
  List<PostModel> _trendingPosts = [];
  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isFetchingPosts = false;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  DateTime? _oldestPostCursor;
  bool _isLoadingStatuses = false;
  bool _hasInboxDot = false;
  bool _isCreatingStatus = false;
  double _uploadProgress = 0.0;
  int _selectedTab = 0;
  final Set<String> _likeInFlight = {};
  final ImagePicker _imagePicker = ImagePicker();
  List<StatusModel> _statuses = [];
  List<UserStatusGroup> _statusGroups = [];
  bool _isNavBarVisible = true;
  bool _isTitlePulsing = false;
  bool _isTitlePressed = false;
  late AnimationController _titlePulseController;
  late Animation<Color?> _titleColorAnimation;

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

    _titlePulseController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _titleColorAnimation = ColorTween(
      begin: AppConstants.white,
      end: AppConstants.primaryBlue,
    ).animate(
      CurvedAnimation(parent: _titlePulseController, curve: Curves.easeInOut),
    );

    // Load from cache first (instant), then from network
    _loadFromCacheThenNetwork();
    unawaited(_refreshInboxDot());

    // Initialize new posts real-time listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final newPostsProvider =
            Provider.of<NewPostsProvider>(context, listen: false);
        newPostsProvider.initializeRealtimeListener();

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

  void _setTitlePulse(bool enable) {
    if (enable == _isTitlePulsing) return;
    _isTitlePulsing = enable;
    if (enable) {
      _titlePulseController.repeat(reverse: true);
    } else {
      _titlePulseController.stop();
      _titlePulseController.value = 0.0;
    }
  }

  Future<void> _handleTitleRefresh(NewPostsProvider provider) async {
    if (_selectedTab != 0) return;
    HapticFeedback.selectionClick();
    await Future.wait([
      _loadPosts(showLoading: false, clearNewPosts: true),
      _loadStatuses(),
    ]);
    provider.clearNewPosts();
    _setTitlePulse(false);
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
  }

  Future<void> _refreshInboxDot() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;
    try {
      final userRes = await supabase
          .from('users')
          .select(
              'last_activity_seen_at, last_dm_seen_at, last_group_seen_at, last_qa_seen_at')
          .eq('id', me.id)
          .single();

      DateTime _parseOrEpoch(String? raw) {
        return DateTime.tryParse(raw ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }

      final lastActivity =
          _parseOrEpoch(userRes['last_activity_seen_at'] as String?);
      final lastDm = _parseOrEpoch(userRes['last_dm_seen_at'] as String?);
      final lastGroup =
          _parseOrEpoch(userRes['last_group_seen_at'] as String?);

      final activityRes = await supabase
          .from('notification_events')
          .select('id')
          .eq('user_id', me.id)
          .gt('created_at', lastActivity.toIso8601String())
          .limit(1);
      final hasActivity = (activityRes as List).isNotEmpty;

      final qaRes = await supabase
          .from('qa_answer_notifications')
          .select('id')
          .eq('asker_id', me.id)
          .eq('is_read', false)
          .limit(1);
      final hasQa = (qaRes as List).isNotEmpty;

      final convRes = await supabase
          .from('conversation_participants')
          .select('conversation_id, conversations!inner(is_group)')
          .eq('user_id', me.id);
      final directIds = <String>[];
      final groupIds = <String>[];
      for (final row in convRes as List) {
        final convo = row['conversations'] as Map<String, dynamic>?;
        final isGroup = convo?['is_group'] == true;
        final convoId = row['conversation_id'] as String?;
        if (convoId == null) continue;
        if (isGroup) {
          groupIds.add(convoId);
        } else {
          directIds.add(convoId);
        }
      }

      bool hasDm = false;
      if (directIds.isNotEmpty) {
        final dmRes = await supabase
            .from('messages')
            .select('id')
            .inFilter('conversation_id', directIds)
            .neq('sender_id', me.id)
            .gt('created_at', lastDm.toIso8601String())
            .limit(1);
        hasDm = (dmRes as List).isNotEmpty;
      }

      bool hasGroup = false;
      if (groupIds.isNotEmpty) {
        final groupRes = await supabase
            .from('messages')
            .select('id')
            .inFilter('conversation_id', groupIds)
            .neq('sender_id', me.id)
            .gt('created_at', lastGroup.toIso8601String())
            .limit(1);
        hasGroup = (groupRes as List).isNotEmpty;
      }

      final hasDot = hasActivity || hasQa || hasDm || hasGroup;
      if (mounted) {
        setState(() => _hasInboxDot = hasDot);
      }
    } catch (_) {}
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
        _hasMorePosts = posts.length >= AppConstants.postsPerPage;
        _oldestPostCursor = posts.isNotEmpty ? posts.last.createdAt : null;
      });
      _prefetchPostImages(posts, limit: 4);
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
      final showLoading = _posts.isEmpty;
      // Load posts and statuses after user is loaded
      await Future.wait([
        _loadPosts(showLoading: showLoading, clearNewPosts: true),
        _loadStatuses(),
        _loadTrendingPosts(),
      ]);
    }
  }

  Future<void> _loadTrendingPosts() async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      final response = await supabase
          .from('posts')
          .select('''
            *,
            users (
              id,
              alias,
              display_name,
              profile_image_url,
              is_verified,
              role
            )
          ''')
          .eq('is_anonymous', false)
          .or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
          .or('expires_at.is.null,expires_at.gt.$nowIso')
          .order('likes_count', ascending: false)
          .order('comments_count', ascending: false)
          .order('shares_count', ascending: false)
          .limit(12);

      final posts = (response as List)
          .map((p) => PostModel.fromJson(p as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() => _trendingPosts = posts);
        _prefetchPostImages(posts, limit: 4);
      }
    } catch (e) {
      debugPrint('Error loading trending posts: $e');
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

    _maybeLoadMore();
  }

  void _maybeLoadMore() {
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

  Future<Map<String, Map<String, String>>> _loadTaggedUsers(
      List<String> postIds) async {
    final taggedMap = <String, Map<String, String>>{};
    if (postIds.isEmpty) return taggedMap;

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

    return taggedMap;
  }

  Future<List<PostModel>> _applyPostMetadata(List<PostModel> posts) async {
    if (posts.isEmpty) return posts;

    final postIds = posts.map((p) => p.id).toList();
    final taggedMap = await _loadTaggedUsers(postIds);

    if (_currentUser != null && posts.isNotEmpty) {
      final likesResponse = await supabase
          .from('likes')
          .select('post_id, user_id')
          .eq('user_id', _currentUser!.id)
          .inFilter('post_id', postIds);

      final likedPostIds = (likesResponse as List)
          .map((like) => like['post_id'] as String)
          .toSet();

      final repostsResponse = await supabase
          .from('posts')
          .select('original_post_id')
          .eq('user_id', _currentUser!.id)
          .inFilter('original_post_id', postIds);

      final repostedPostIds = (repostsResponse as List)
          .map((repost) => repost['original_post_id'] as String)
          .toSet();

      final allLikesResponse = await supabase
          .from('likes')
          .select('post_id')
          .inFilter('post_id', postIds);

      final likesCountMap = <String, int>{};
      for (var like in allLikesResponse as List) {
        final postId = like['post_id'] as String;
        likesCountMap[postId] = (likesCountMap[postId] ?? 0) + 1;
      }

      for (int i = 0; i < posts.length; i++) {
        posts[i] = posts[i].copyWith(
          isLikedByCurrentUser: likedPostIds.contains(posts[i].id),
          isRepostedByCurrentUser: repostedPostIds.contains(posts[i].id),
          likesCount: likesCountMap[posts[i].id] ?? 0,
          taggedUsers: taggedMap[posts[i].id],
        );
      }
    } else {
      for (int i = 0; i < posts.length; i++) {
        posts[i] = posts[i].copyWith(taggedUsers: taggedMap[posts[i].id]);
      }
    }

    return posts;
  }

  Future<List<PostModel>> _fetchPostsPage(
      {DateTime? before, int limit = AppConstants.postsPerPage}) async {
    final nowIso = DateTime.now().toIso8601String();

    var query = supabase.from('posts').select('''
            *,
            users (
              id,
              alias,
              display_name,
              profile_image_url,
              role,
              is_verified
            )
          ''')
      ..or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
      ..or('expires_at.is.null,expires_at.gt.$nowIso');

    if (before != null) {
      query = query.lt('created_at', before.toIso8601String());
    }

    final response = await query
        .order('created_at', ascending: false)
        .limit(limit);

    final posts = (response as List).map((postData) {
      return PostModel.fromJson(postData as Map<String, dynamic>);
    }).toList();

    return _applyPostMetadata(posts);
  }

  void _saveHomeFeedToCache(List<PostModel> posts) {
    final cacheData = posts.map((p) => p.toJson()).toList();
    for (int i = 0; i < posts.length; i++) {
      if (posts[i].user != null) {
        cacheData[i]['users'] = posts[i].user!.toJson();
      }
    }
    _cache.saveHomeFeed(cacheData);
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

      final hiddenResponse = await supabase
          .from('user_hidden_statuses')
          .select('status_id')
          .eq('user_id', currentUser.id);
      final hiddenIds = (hiddenResponse as List<dynamic>)
          .map((row) => row['status_id'] as String)
          .toSet();

      final statuses = (response as List<dynamic>)
          .map(
            (row) => StatusModel.fromJson(row as Map<String, dynamic>),
          )
          .where((status) => !hiddenIds.contains(status.id))
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

  Future<void> _loadPosts(
      {bool showLoading = true, bool clearNewPosts = false}) async {
    if (_isFetchingPosts) return;
    _isFetchingPosts = true;
    try {
      if (showLoading && mounted) {
        setState(() => _isLoading = true);
      }

      final posts = await _fetchPostsPage();

      if (!mounted) return;

      setState(() {
        _posts = posts;
        _isLoading = false;
        _hasMorePosts = posts.length >= AppConstants.postsPerPage;
        _oldestPostCursor = posts.isNotEmpty ? posts.last.createdAt : null;
      });

      if (clearNewPosts && mounted) {
        final newPostsProvider =
            Provider.of<NewPostsProvider>(context, listen: false);
        newPostsProvider.clearNewPosts();
      }

      _prefetchPostImages(posts);
      _saveHomeFeedToCache(posts);

      // Sync native widgets with latest data
      WidgetDataService.updateWidgetData();
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } finally {
      _isFetchingPosts = false;
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMorePosts) return;
    if (_oldestPostCursor == null) return;
    _isLoadingMore = true;
    if (mounted) {
      setState(() {});
    }

    try {
      final morePosts = await _fetchPostsPage(
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
      _saveHomeFeedToCache(_posts);
    } catch (e) {
      debugPrint('Error loading more posts: $e');
    } finally {
      _isLoadingMore = false;
      if (mounted) {
        setState(() {});
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
              alias,
              display_name,
              profile_image_url,
              role,
              is_verified
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
          if (_posts.isNotEmpty) {
            _oldestPostCursor = _posts.last.createdAt;
          }
        });

        _prefetchPostImages(enrichedPosts);
        _saveHomeFeedToCache(_posts);

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
      final editResult = await Navigator.push<StatusEditorResult>(
        context,
        MaterialPageRoute(
          builder: (_) => StatusEditorScreen(
            originalBytes: bytes,
            fileName: picked.name,
          ),
        ),
      );
      if (editResult == null) {
        setState(() {
          _uploadProgress = 0.0;
          _isCreatingStatus = false;
        });
        return;
      }
      final editedBytes = editResult.bytes;
      const contentType = 'image/jpeg';

      final objectPath =
          'statuses/${_currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}_status.jpg';

      // Update progress during file upload
      if (mounted) {
        setState(() {
          _uploadProgress = 0.5;
        });
      }

      await supabase.storage.from('statuses').uploadBinary(
            objectPath,
            editedBytes,
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
        onPostCreated: (createdPost, optimisticId) {
          if (!mounted) return;
          setState(() {
            if (optimisticId != null) {
              final idx = _posts.indexWhere((p) => p.id == optimisticId);
              if (idx != -1) {
                _posts[idx] = createdPost;
              } else {
                _posts.insert(0, createdPost);
              }
            } else {
              _posts.insert(0, createdPost);
            }
          });
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
        onPostUpdated: () =>
            _loadPosts(showLoading: false, clearNewPosts: true),
      ),
    );
  }

  void _showComments(PostModel post) {
    if (post.id.startsWith('optimistic_')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still posting. Try again in a moment.'),
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
            content: Text(AppErrorHandler.userMessage(e)),
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
            content: Text(AppErrorHandler.userMessage(e)),
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
        await _loadPosts(showLoading: false, clearNewPosts: true);
      }
    } catch (e) {
      debugPrint('Error reposting: $e');
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
        onPostCreated: (createdPost, optimisticId) {
          if (!mounted) return;
          setState(() {
            if (optimisticId != null) {
              final idx = _posts.indexWhere((p) => p.id == optimisticId);
              if (idx != -1) {
                _posts[idx] = createdPost;
              } else {
                _posts.insert(0, createdPost);
              }
            } else {
              _posts.insert(0, createdPost);
            }
          });
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
      showInboxDot: _hasInboxDot,
      onTap: (index) async {
        setState(() => _selectedTab = index);
        if (index == 0 || index == 1) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          return;
        }
        if (index == 2) {
          await Navigator.pushNamed(context, '/groups');
          await _refreshInboxDot();
        } else if (index == 3) {
          if (_currentUser != null) {
            await Navigator.pushNamed(context, '/profile',
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
        if (mounted) {
          final page = _pageController.page?.round() ?? 0;
          setState(() => _selectedTab = page.clamp(0, 1));
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
                  _loadPosts(showLoading: false, clearNewPosts: true),
                  _loadStatuses(),
                  _loadTrendingPosts(),
                ]);
              },
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: 1 +
                    _posts.length +
                    (_trendingPosts.isNotEmpty ? 1 : 0) +
                    (_isLoadingMore || _hasMorePosts ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildStatusBar();
                  }
                  final trendingInsertIndex =
                      1 +
                          (_posts.length > AppConstants.postsPerPage
                              ? AppConstants.postsPerPage
                              : _posts.length);
                  if (_trendingPosts.isNotEmpty &&
                      index == trendingInsertIndex) {
                    return _buildTrendingSection();
                  }

                  final loadMoreIndex = 1 +
                      _posts.length +
                      (_trendingPosts.isNotEmpty ? 1 : 0);
                  if (index == loadMoreIndex) {
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

                  var postIndex = index - 1;
                  if (_trendingPosts.isNotEmpty &&
                      index > trendingInsertIndex) {
                    postIndex -= 1;
                  }
                  final post = _posts[postIndex];

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

  Widget _buildTrendingSection() {
    if (_trendingPosts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trending Now',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _trendingPosts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final post = _trendingPosts[index];
                final author =
                    post.user?.displayName ?? post.user?.alias ?? 'Anon';

                return GestureDetector(
                  onTap: () => _showComments(post),
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppConstants.darkGray,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppConstants.primaryBlue.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (post.user?.isVerifiedUser ?? false)
                              const Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: AppConstants.primaryBlue,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            post.content.isNotEmpty
                                ? post.content
                                : 'Shared a moment',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppConstants.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.favorite_rounded,
                                size: 14, color: Colors.red),
                            const SizedBox(width: 4),
                            Text(
                              post.likesCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.chat_bubble_rounded,
                                size: 14, color: AppConstants.primaryBlue),
                            const SizedBox(width: 4),
                            Text(
                              post.commentsCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
            title: Consumer<NewPostsProvider>(
              builder: (context, provider, _) {
                final isHomeTab = _selectedTab == 0;
                final shouldPulse = provider.showNotification && isHomeTab;
                _setTitlePulse(shouldPulse);
                final titleText = isHomeTab ? 'ANONPRO' : 'Anonymous';

                return GestureDetector(
                  onTapDown: isHomeTab
                      ? (_) => setState(() => _isTitlePressed = true)
                      : null,
                  onTapUp: isHomeTab
                      ? (_) => setState(() => _isTitlePressed = false)
                      : null,
                  onTapCancel:
                      isHomeTab ? () => setState(() => _isTitlePressed = false) : null,
                  onTap: isHomeTab ? () => _handleTitleRefresh(provider) : null,
                  child: AnimatedScale(
                    scale: _isTitlePressed ? 0.97 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: AnimatedBuilder(
                      animation: _titlePulseController,
                      builder: (context, _) {
                        final color = shouldPulse
                            ? (_titleColorAnimation.value ??
                                AppConstants.white)
                            : AppConstants.white;
                        final glow = shouldPulse
                            ? _titlePulseController.value
                            : 0.0;
                        return Text(
                          titleText,
                          style: TextStyle(
                            color: color,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            shadows: glow > 0
                                ? [
                                    Shadow(
                                      color: AppConstants.primaryBlue
                                          .withOpacity(0.35 * glow),
                                      blurRadius: 8 * glow,
                                    ),
                                  ]
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            centerTitle: false,
            actions: [
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
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AiFloatingButton(),
              const SizedBox(height: 16),
              FloatingActionButton(
                heroTag: 'create_post_fab',
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
            ],
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
    _titlePulseController.dispose();
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
