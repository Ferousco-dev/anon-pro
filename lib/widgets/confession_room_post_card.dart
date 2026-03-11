import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import '../screens/profile/profile_screen.dart';
import 'verified_badge.dart';

class ConfessionRoomPostCard extends StatefulWidget {
  final PostModel post;
  final UserModel? currentUser;
  final VoidCallback? onLikeToggle;
  final VoidCallback? onComment;
  final VoidCallback? onTapRoom;

  const ConfessionRoomPostCard({
    super.key,
    required this.post,
    this.currentUser,
    this.onLikeToggle,
    this.onComment,
    this.onTapRoom,
  });

  @override
  State<ConfessionRoomPostCard> createState() => _ConfessionRoomPostCardState();
}

class _ConfessionRoomPostCardState extends State<ConfessionRoomPostCard>
    with SingleTickerProviderStateMixin {
  late bool _isLiked;
  late int _likesCount;
  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLikedByCurrentUser ?? false;
    _likesCount = widget.post.likesCount;

    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _likeScaleAnimation =
        Tween<double>(begin: 1.0, end: 0.8).animate(_likeAnimationController);
  }

  @override
  void dispose() {
    _likeAnimationController.dispose();
    super.dispose();
  }

  void _toggleLike() {
    setState(() {
      if (_isLiked) {
        _likesCount--;
      } else {
        _likesCount++;
      }
      _isLiked = !_isLiked;
    });

    _likeAnimationController.forward().then((_) {
      _likeAnimationController.reverse();
    });

    widget.onLikeToggle?.call();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.post.user;
    final displayName = user?.displayName ?? user?.alias ?? 'Anonymous User';
    final profileImage = user?.profileImageUrl;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.primaryBlue.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with avatar, name, and time
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar
                GestureDetector(
                  onTap: () {
                    if (user != null && user.id != widget.currentUser?.id) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ProfileScreen(userId: user.id),
                        ),
                      );
                    }
                  },
                  child: CircleAvatar(
                    radius: 24,
                    backgroundImage: profileImage != null
                        ? CachedNetworkImageProvider(profileImage)
                        : null,
                    backgroundColor: AppConstants.primaryBlue.withOpacity(0.3),
                    child: profileImage == null
                        ? const Icon(Icons.person,
                            color: AppConstants.primaryBlue, size: 20)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // Name, verified badge, and timestamp
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user?.isVerified == true)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: VerifiedBadge(size: 16),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeago.format(widget.post.createdAt),
                        style: const TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Confession room badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryBlue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.favorite,
                          color: AppConstants.primaryBlue, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Confession Room',
                        style: TextStyle(
                          color: AppConstants.primaryBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Divider(
            color: AppConstants.textSecondary.withOpacity(0.2),
            height: 1,
            thickness: 0.5,
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.post.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.5,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                // Call to action button
                GestureDetector(
                  onTap: widget.onTapRoom,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppConstants.primaryBlue,
                          Color(0xFF00D4FF),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.login, size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Join Room & Confess',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Interactions bar (like, comment, share)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppConstants.textSecondary.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Like button
                Expanded(
                  child: GestureDetector(
                    onTap: _toggleLike,
                    child: ScaleTransition(
                      scale: _likeScaleAnimation,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 18,
                            color: _isLiked
                                ? AppConstants.red
                                : AppConstants.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _likesCount > 0 ? '$_likesCount' : '0',
                            style: TextStyle(
                              color: _isLiked
                                  ? AppConstants.red
                                  : AppConstants.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Divider
                Container(
                  height: 20,
                  width: 1,
                  color: AppConstants.textSecondary.withOpacity(0.3),
                ),
                // Comment button
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onComment,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline,
                          size: 18,
                          color: AppConstants.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.post.commentsCount > 0
                              ? '${widget.post.commentsCount}'
                              : '0',
                          style: const TextStyle(
                            color: AppConstants.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Divider
                Container(
                  height: 20,
                  width: 1,
                  color: AppConstants.textSecondary.withOpacity(0.3),
                ),
                // Share button
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final roomId = widget.post.relatedConfessionRoomId;
                      if (roomId != null) {
                        final shareText = "Join my Anonymous Confession Room on ANONPRO!\n\nLink: anonpro://home?roomId=$roomId";
                        Share.share(shareText);
                      }
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.share_outlined,
                          size: 18,
                          color: AppConstants.textSecondary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Share',
                          style: TextStyle(
                            color: AppConstants.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
