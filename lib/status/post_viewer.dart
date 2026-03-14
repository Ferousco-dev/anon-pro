import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../utils/constants.dart';
import '../services/status_media_cache.dart';
import 'status_controller.dart';
import 'user_status_group_model.dart';

class PostViewer extends StatefulWidget {
  final StatusController controller;

  const PostViewer({Key? key, required this.controller}) : super(key: key);

  @override
  _PostViewerState createState() => _PostViewerState();
}

class _PostViewerState extends State<PostViewer> with TickerProviderStateMixin {
  late PageController _pageController;
  late List<AnimationController> _postProgressControllers = [];
  double _dragOffset = 0.0;
  bool _showReactions = false;
  OverlayEntry? _floatingEmojiEntry;

  static const List<String> _reactions = ['❤️', '😂', '🔥', '😮', '👏'];

  @override
  void initState() {
    super.initState();
    _pageController =
        PageController(initialPage: widget.controller.currentPostIndex);
    widget.controller.addListener(_onControllerChanged);
    _initializeProgressControllers();

    // Clean up expired cache in background
    Future.microtask(() => StatusMediaCache.cleanupExpiredCache());
  }

  void _initializeProgressControllers() {
    for (var controller in _postProgressControllers) {
      controller.dispose();
    }
    final postCount = widget.controller.currentGroup.posts.length;
    _postProgressControllers = [];

    for (int i = 0; i < postCount; i++) {
      final duration = widget.controller.currentGroup.posts[i].isVideo
          ? const Duration(seconds: 15)
          : const Duration(seconds: 5);
      final controller = AnimationController(
        vsync: this,
        duration: duration,
      );
      _postProgressControllers.add(controller);
    }
    _startProgressAnimation();
  }

  void _startProgressAnimation() {
    if (widget.controller.currentPostIndex < _postProgressControllers.length) {
      _postProgressControllers[widget.controller.currentPostIndex].forward();
    }
  }

  String _getMediaUrl(String mediaPath) {
    // If it's already a full URL, return as-is
    if (mediaPath.startsWith('http://') || mediaPath.startsWith('https://')) {
      return mediaPath;
    }

    // Otherwise, construct the full Supabase public URL
    final supabase = Supabase.instance.client;
    try {
      final publicUrl =
          supabase.storage.from('statuses').getPublicUrl(mediaPath);
      return publicUrl;
    } catch (e) {
      debugPrint('Error getting public URL for $mediaPath: $e');
      return mediaPath;
    }
  }

  /// Load media with offline caching support
  /// First checks local cache, then downloads if needed
  Future<File?> _loadMediaWithCache(String mediaUrl) async {
    try {
      // Check if media is already in local cache
      final cachedFile = await StatusMediaCache.getCachedMedia(mediaUrl);
      if (cachedFile != null) {
        debugPrint('Using cached media: ${cachedFile.path}');
        return cachedFile;
      }

      // Download and cache the media
      final downloadedFile =
          await StatusMediaCache.downloadAndCacheMedia(mediaUrl);
      return downloadedFile;
    } catch (e) {
      debugPrint('Error loading media with cache: $e');
      return null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _pageController.dispose();
    for (var controller in _postProgressControllers) {
      controller.dispose();
    }
    _floatingEmojiEntry?.remove();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_pageController.page?.round() != widget.controller.currentPostIndex) {
      _pageController.jumpToPage(widget.controller.currentPostIndex);
    }
  }

  void _onPageChanged(int index) {
    for (int i = 0; i < _postProgressControllers.length; i++) {
      _postProgressControllers[i].reset();
    }
    widget.controller.currentPostIndex = index;
    _startProgressAnimation();
  }

  void _onTap(TapUpDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < screenWidth * 0.3) {
      widget.controller.prevPost();
    } else if (details.globalPosition.dx > screenWidth * 0.7) {
      widget.controller.nextPost();
    } else {
      setState(() {
        _showReactions = !_showReactions;
      });
    }
  }

  void _showFloatingReaction(String emoji) {
    if (_floatingEmojiEntry != null) {
      _floatingEmojiEntry!.remove();
    }

    final animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _floatingEmojiEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 180,
        right: 24,
        child: AnimatedBuilder(
          animation: animationController,
          builder: (context, child) {
            final offsetY = -100 * animationController.value;
            final opacity = 1 - animationController.value;
            return Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(0, offsetY),
                child: Text(emoji, style: const TextStyle(fontSize: 48)),
              ),
            );
          },
        ),
      ),
    );

    Overlay.of(context).insert(_floatingEmojiEntry!);
    animationController.forward().then((_) {
      _floatingEmojiEntry?.remove();
      _floatingEmojiEntry = null;
    });
  }

  Future<void> _sendReaction(String emoji) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;
    try {
      await Supabase.instance.client.from('status_reactions').upsert({
        'status_id': widget.controller.currentPost.id,
        'user_id': currentUser.id,
        'emoji': emoji,
      });
    } catch (e) {
      debugPrint('Failed to react to story: $e');
    }
  }

  Future<void> _hideCurrentStory() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;
    try {
      await Supabase.instance.client.from('user_hidden_statuses').insert({
        'status_id': widget.controller.currentPost.id,
        'user_id': currentUser.id,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Failed to hide story: $e');
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (details.velocity.pixelsPerSecond.dx > 300 &&
        widget.controller.currentPostIndex == 0) {
      widget.controller.prevUser();
    } else if (details.velocity.pixelsPerSecond.dx < -300 &&
        widget.controller.currentPostIndex ==
            widget.controller.currentGroup.posts.length - 1) {
      widget.controller.nextUser();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 100) {
      Navigator.pop(context);
    } else {
      setState(() {
        _dragOffset = 0.0;
      });
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        title: const Text('Delete Story',
            style: TextStyle(color: AppConstants.white)),
        content: const Text('Are you sure?',
            style: TextStyle(color: AppConstants.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: AppConstants.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.controller.deleteCurrentPost();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.controller.currentGroup;
    final postCount = group.posts.length;
    final scale = 1 - (_dragOffset.abs() / 1000).clamp(0.0, 0.1);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: _onTap,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        onLongPressStart: (_) {
          for (var controller in _postProgressControllers) {
            controller.stop();
          }
        },
        onLongPressEnd: (_) {
          _startProgressAnimation();
        },
        child: Transform.scale(
          scale: scale,
          child: Stack(
            children: [
              // Image/Video Display (center)
              PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemCount: postCount,
                itemBuilder: (context, index) {
                  final post = group.posts[index];
                  final mediaUrl = _getMediaUrl(post.mediaUrl);

                  return post.isVideo
                      ? Container(
                          color: AppConstants.darkGray,
                          child: const Center(
                            child: Icon(Icons.play_circle_outline,
                                size: 64, color: AppConstants.primaryBlue),
                          ),
                        )
                      : FutureBuilder<File?>(
                          future: _loadMediaWithCache(mediaUrl),
                          builder: (context, snapshot) {
                            // Cached file loaded successfully
                            if (snapshot.connectionState ==
                                    ConnectionState.done &&
                                snapshot.data != null) {
                              return Image.file(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildErrorWidget(
                                        'Failed to load cached image'),
                              );
                            }

                            // Loading or cache failed, use network with caching
                            return CachedNetworkImage(
                              imageUrl: mediaUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (context, url) => Container(
                                color: AppConstants.darkGray,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                      color: AppConstants.primaryBlue),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  _buildErrorWidget('Failed to load image'),
                            );
                          },
                        );
                },
              ),
              // Progress bars (top)
              Positioned(
                top: 50,
                left: 12,
                right: 12,
                child: Row(
                  children: List.generate(
                    postCount,
                    (index) => Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: AnimatedBuilder(
                          animation: _postProgressControllers[index],
                          builder: (context, child) {
                            return LinearProgressIndicator(
                              value: index < widget.controller.currentPostIndex
                                  ? 1.0
                                  : index == widget.controller.currentPostIndex
                                      ? _postProgressControllers[index].value
                                      : 0.0,
                              backgroundColor: Colors.white.withOpacity(0.3),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppConstants.primaryBlue),
                              borderRadius: BorderRadius.circular(1),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Header with user info (top)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildHeader(group),
              ),
              // Reactions (bottom)
              if (_showReactions)
                Positioned(
                  bottom: 20,
                  left: 16,
                  right: 16,
                  child: SafeArea(
                    top: false,
                    child: _buildReactionsBar(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(UserStatusGroup group) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.black.withOpacity(0.3)
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Back button (top-left)
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            // User info (top-center)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.user.username,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Text(
                      '${widget.controller.currentPostIndex + 1}/${widget.controller.currentGroup.posts.length}',
                      style: const TextStyle(
                          color: AppConstants.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            // User avatar
            CircleAvatar(
              radius: 18,
              backgroundColor: AppConstants.lightGray,
              backgroundImage: group.user.avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(group.user.avatarUrl)
                  : null,
              child: group.user.avatarUrl.isEmpty
                  ? const Icon(Icons.person, size: 20)
                  : null,
            ),
            const SizedBox(width: 12),
            // Delete button for owner
            if (widget.controller.isOwner)
              GestureDetector(
                onTap: _deletePost,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete,
                      color: AppConstants.red, size: 20),
                ),
              ),
            if (!widget.controller.isOwner) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final action = await showModalBottomSheet<String>(
                    context: context,
                    backgroundColor: AppConstants.darkGray,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (context) {
                      return SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.hide_source,
                                  color: Colors.white),
                              title: const Text('Hide this story',
                                  style: TextStyle(color: Colors.white)),
                              onTap: () => Navigator.pop(context, 'hide'),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.close,
                                  color: Colors.white70),
                              title: const Text('Cancel',
                                  style: TextStyle(color: Colors.white70)),
                              onTap: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                  if (action == 'hide') {
                    await _hideCurrentStory();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_vert,
                      color: Colors.white, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReactionsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppConstants.primaryBlue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _reactions
            .map((emoji) => GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showFloatingReaction(emoji);
                    _sendReaction(emoji);
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ))
            .toList(),
      ),
    );
  }

  /// Build error widget for failed image/video loading
  Widget _buildErrorWidget(String message) {
    return Container(
      color: AppConstants.darkGray,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: AppConstants.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
