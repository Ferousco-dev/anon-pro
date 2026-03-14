import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import '../screens/profile/profile_screen.dart';
import 'tappable_mention_text.dart';
import 'verified_badge.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'full_screen_image.dart';

class PostCard extends StatefulWidget {
  final PostModel post;
  final UserModel? currentUser;
  final VoidCallback? onLikeToggle;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onComment;
  final VoidCallback? onRepost;
  final VoidCallback? onShare;
  final VoidCallback? onForward;

  const PostCard({
    super.key,
    required this.post,
    this.currentUser,
    this.onLikeToggle,
    this.onDelete,
    this.onEdit,
    this.onComment,
    this.onRepost,
    this.onShare,
    this.onForward,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  // Optimistic UI state
  late bool _isLiked;
  late int _likesCount;
  late bool _isReposted;
  late int _repostsCount;

  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;

  // Share button tap animation
  double _shareScale = 1.0;
  double _forwardScale = 1.0;

  ScreenshotController screenshotController = ScreenshotController();

  final GlobalKey shareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Initialize with current values
    _isLiked = widget.post.isLikedByCurrentUser ?? false;
    _likesCount = widget.post.likesCount;
    _isReposted = widget.post.isRepostedByCurrentUser ?? false;
    _repostsCount = widget.post.repostsCount;

    // Setup like animation
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _likeScaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _likeAnimationController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update state when post data changes from parent
    if (oldWidget.post.isLikedByCurrentUser !=
        widget.post.isLikedByCurrentUser) {
      setState(() {
        _isLiked = widget.post.isLikedByCurrentUser ?? false;
      });
    }
    if (oldWidget.post.likesCount != widget.post.likesCount) {
      setState(() {
        _likesCount = widget.post.likesCount;
      });
    }
    if (oldWidget.post.sharesCount != widget.post.sharesCount) {
      // Shares count updated, no need to track locally since we don't display it
    }
  }

  @override
  void dispose() {
    _likeAnimationController.dispose();
    super.dispose();
  }

  void _handleLikeToggle() {
    if (widget.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to like posts'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Optimistic UI update
    setState(() {
      _isLiked = !_isLiked;
      _likesCount = _isLiked ? _likesCount + 1 : _likesCount - 1;
    });

    // Animate like
    if (_isLiked) {
      _likeAnimationController.forward().then((_) {
        _likeAnimationController.reverse();
      });
    }

    HapticFeedback.lightImpact();

    // Call the actual API
    widget.onLikeToggle?.call();
  }

  Future<void> _handleShare() async {
    // Tap bounce animation
    setState(() => _shareScale = 0.85);
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) setState(() => _shareScale = 1.0);

    HapticFeedback.lightImpact();

    final RenderBox? box =
        shareKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect? sharePositionOrigin =
        box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;

    if (widget.onShare != null) {
      widget.onShare!();
      return;
    }

    // Default: share as image
    try {
      Uint8List? image = await screenshotController.capture();
      if (image != null) {
        Directory tempDir = await getTemporaryDirectory();
        File file = File('${tempDir.path}/anonpro_post.png');
        await file.writeAsBytes(image);

        Share.shareXFiles([XFile(file.path)],
            text: 'Check out this post on ANONPRO',
            sharePositionOrigin: sharePositionOrigin);
      } else {
        // Fallback to text share
        final shareText = '''
${widget.post.displayAuthorName} (@${widget.post.isAnonymous ? 'anonymous' : (widget.post.user?.alias ?? 'unknown')})

${widget.post.originalContent ?? widget.post.content}

Posted on ANONPRO
''';
        Share.share(shareText,
            subject: 'Check out this post on ANONPRO',
            sharePositionOrigin: sharePositionOrigin);
      }
    } catch (e) {
      debugPrint('Error sharing: $e');
      // Fallback to text
      final shareText = '''
${widget.post.displayAuthorName} (@${widget.post.isAnonymous ? 'anonymous' : (widget.post.user?.alias ?? 'unknown')})

${widget.post.originalContent ?? widget.post.content}

Posted on ANONPRO
''';
      Share.share(shareText,
          subject: 'Check out this post on ANONPRO',
          sharePositionOrigin: sharePositionOrigin);
    }
  }

  void _handleForward() async {
    // Tap bounce animation
    setState(() => _forwardScale = 0.85);
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) setState(() => _forwardScale = 1.0);

    HapticFeedback.lightImpact();
    widget.onForward?.call();
  }

  void _handleRepost() {
    if (widget.currentUser == null) {
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
    if (widget.currentUser?.id == widget.post.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot repost your own post'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();

    // Optimistic UI update
    setState(() {
      if (_isReposted) {
        _isReposted = false;
        _repostsCount--;
      } else {
        _isReposted = true;
        _repostsCount++;
      }
    });

    if (widget.onRepost != null) {
      widget.onRepost!();
      return;
    }

    // Show repost options dialog
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.darkGray,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppConstants.lightGray.withOpacity(0.6),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.repeat_rounded,
                  color: AppConstants.primaryBlue),
              title:
                  const Text('Repost', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Repost feature coming soon!'),
                    backgroundColor: AppConstants.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded,
                  color: AppConstants.primaryBlue),
              title: const Text('Quote Post',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Quote post feature coming soon!'),
                    backgroundColor: AppConstants.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = widget.currentUser?.id == widget.post.userId ||
        widget.currentUser?.isAdmin == true;
    final canEdit = widget.currentUser?.id == widget.post.userId &&
        widget.post.originalPostId == null &&
        widget.onEdit != null;

    return Screenshot(
      controller: screenshotController,
      child: Container(
        decoration: const BoxDecoration(
          color: AppConstants.black,
          border: Border(
            bottom: BorderSide(
              color: AppConstants.dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Image
              GestureDetector(
                onTap: () {
                  if (widget.post.isAnonymous) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProfileScreen(userId: widget.post.userId),
                    ),
                  );
                },
                child: _buildAvatar(
                  imageUrl: widget.post.displayAuthorImage,
                  isAnonymous: widget.post.isAnonymous,
                  radius: 20,
                ),
              ),
              const SizedBox(width: 10),

              // Post Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Name · @handle · time
                    Row(
                      children: [
                        Flexible(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.post.displayAuthorName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppConstants.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.post.showVerifiedBadge) ...[
                                const SizedBox(width: 4),
                                VerifiedBadge(
                                  user: widget.post.user,
                                  size: 16,
                                ),
                              ],
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '@${widget.post.isAnonymous ? 'anonymous' : (widget.post.user?.alias ?? 'unknown')}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppConstants.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                ' · ${timeago.format(widget.post.createdAt, locale: 'en_short')}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppConstants.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (canDelete || canEdit)
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_horiz,
                              color: AppConstants.textSecondary,
                              size: 18,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: AppConstants.darkGray,
                            itemBuilder: (context) => [
                              if (canEdit)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined,
                                          color: AppConstants.primaryBlue,
                                          size: 20),
                                      SizedBox(width: 12),
                                      Text(
                                        'Edit',
                                        style: TextStyle(
                                            color: AppConstants.white),
                                      ),
                                    ],
                                  ),
                                ),
                              if (canDelete)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline,
                                          color: AppConstants.red, size: 20),
                                      SizedBox(width: 12),
                                      Text(
                                        'Delete',
                                        style:
                                            TextStyle(color: AppConstants.red),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            onSelected: (value) {
                              if (value == 'delete' &&
                                  widget.onDelete != null) {
                                _showDeleteConfirmation(context);
                              } else if (value == 'edit' &&
                                  widget.onEdit != null) {
                                widget.onEdit!();
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Post Content
                    if (widget.post.originalPostId != null) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.repeat_rounded,
                            size: 14,
                            color: AppConstants.primaryBlue,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Reposted',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppConstants.primaryBlue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    TappableMentionText(
                      text: widget.post.originalContent ?? widget.post.content,
                      aliasToUserId: widget.post.taggedUsers,
                    ),
                    if ((widget.post.postCategory ?? '').isNotEmpty ||
                        widget.post.customTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if ((widget.post.postCategory ?? '').isNotEmpty)
                            _buildMetaChip(widget.post.postCategory!),
                          for (final tag in widget.post.customTags)
                            _buildMetaChip('#$tag'),
                        ],
                      ),
                    ],

                    // Post Image
                    if (widget.post.hasImage) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FullScreenImage(
                                imageUrl: widget.post.imageUrl!,
                                tag: 'post_image_${widget.post.id}',
                              ),
                            ),
                          );
                        },
                        child: Hero(
                          tag: 'post_image_${widget.post.id}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 280),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppConstants.darkGray,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppConstants.dividerColor,
                                  width: 0.5,
                                ),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: widget.post.imageUrl!,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    Shimmer.fromColors(
                                  baseColor: AppConstants.darkGray,
                                  highlightColor: AppConstants.mediumGray,
                                  child: Container(
                                    height: 200,
                                    width: double.infinity,
                                    color: AppConstants.darkGray,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  height: 200,
                                  color: AppConstants.darkGray,
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      color: AppConstants.textSecondary,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Actions Row — 5 buttons: Comment, Like, Repost, Forward, Export
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Comment
                        _buildActionButton(
                          Icons.chat_bubble_outline_rounded,
                          widget.post.commentsCount.toString(),
                          AppConstants.textSecondary,
                          () {
                            HapticFeedback.lightImpact();
                            widget.onComment?.call();
                          },
                        ),
                        // Like
                        ScaleTransition(
                          scale: _likeScaleAnimation,
                          child: _buildActionButton(
                            _isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            _likesCount.toString(),
                            _isLiked
                                ? AppConstants.red
                                : AppConstants.textSecondary,
                            _handleLikeToggle,
                          ),
                        ),
                        // Repost
                        _buildActionButton(
                          Icons.repeat_rounded,
                          _repostsCount.toString(),
                          _isReposted
                              ? AppConstants.primaryBlue
                              : AppConstants.textSecondary,
                          _handleRepost,
                        ),
                        // Forward
                        AnimatedScale(
                          scale: _forwardScale,
                          duration: const Duration(milliseconds: 150),
                          child: _buildActionButton(
                            Icons.shortcut_rounded,
                            '',
                            AppConstants.textSecondary,
                            _handleForward,
                          ),
                        ),
                        // Export / Share
                        AnimatedScale(
                          scale: _shareScale,
                          duration: const Duration(milliseconds: 150),
                          child: _buildActionButton(
                            Icons.upload_outlined,
                            '',
                            AppConstants.textSecondary,
                            _handleShare,
                            key: shareKey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a circular avatar that correctly shows a shimmer placeholder while
  /// the network image loads and falls back to an icon if it fails.
  Widget _buildAvatar({
    required String? imageUrl,
    required bool isAnonymous,
    required double radius,
  }) {
    final size = radius * 2;

    // No image URL → plain icon avatar
    if (imageUrl == null || imageUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppConstants.primaryBlue,
        child: Icon(
          isAnonymous ? Icons.person_off : Icons.person,
          size: radius,
          color: Colors.white,
        ),
      );
    }

    // Local file (optimistic post with a local image path)
    final isLocal = !imageUrl.startsWith('http');
    if (isLocal) {
      return ClipOval(
        child: Image.file(
          File(imageUrl),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => CircleAvatar(
            radius: radius,
            backgroundColor: AppConstants.primaryBlue,
            child: Icon(Icons.person, size: radius, color: Colors.white),
          ),
        ),
      );
    }

    // Remote URL → shimmer while loading, icon on error
    return ClipOval(
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Shimmer.fromColors(
            baseColor: AppConstants.darkGray,
            highlightColor: AppConstants.mediumGray,
            child: Container(
              width: size,
              height: size,
              color: AppConstants.darkGray,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: size,
            height: size,
            color: AppConstants.primaryBlue,
            child: Icon(
              isAnonymous ? Icons.person_off : Icons.person,
              size: radius,
              color: Colors.white,
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, String count, Color color, VoidCallback onTap,
      {Key? key}) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            if (count.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                count,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppConstants.primaryBlue.withOpacity(0.2),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppConstants.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Post?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This action cannot be undone.',
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
              widget.onDelete!();
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppConstants.red),
            ),
          ),
        ],
      ),
    );
  }
}
