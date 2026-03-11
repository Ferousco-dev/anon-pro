import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/constants.dart';
import 'user_status_group_model.dart';

class StatusBar extends StatefulWidget {
  final String currentUserId;
  final List<UserStatusGroup> userGroups;
  final Function(UserStatusGroup) onUserTap;
  final VoidCallback? onCreateStatus;
  final double uploadProgress;

  const StatusBar({
    Key? key,
    required this.currentUserId,
    required this.userGroups,
    required this.onUserTap,
    this.onCreateStatus,
    this.uploadProgress = 0.0,
  }) : super(key: key);

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _pulseController;

  // Premium palette
  static const _kAccentBlue = Color(0xFF007AFF);
  static const _kAccentPurple = Color(0xFF5856D6);
  static const _kAccentGreen = Color(0xFF34C759);
  static const _kAccentPink = Color(0xFFFF375F);
  static const _kAccentCyan = Color(0xFF00C6FF);
  static const _kSurface = Color(0xFF0A0A0A);
  static const _kCardBg = Color(0xFF121212);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sort: current user first, then unmuted, then muted
    final sortedGroups = List<UserStatusGroup>.from(widget.userGroups)
      ..sort((a, b) {
        if (a.user.id == widget.currentUserId) return -1;
        if (b.user.id == widget.currentUserId) return 1;
        if (a.isMuted && !b.isMuted) return 1;
        if (!a.isMuted && b.isMuted) return -1;
        return 0;
      });

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kAccentBlue, _kAccentPurple],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [_kAccentBlue, _kAccentPurple],
                  ).createShader(bounds),
                  child: const Text(
                    'Stories',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const Spacer(),
                if (sortedGroups.length > 3)
                  Text(
                    'See all',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _kAccentBlue.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),

          // Stories row
          SizedBox(
            height: 110,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: sortedGroups.length + 1,
              itemBuilder: (context, index) {
                if (index == sortedGroups.length) {
                  return _buildAddStatusButton();
                }
                final group = sortedGroups[index];
                final isCurrentUser = group.user.id == widget.currentUserId;
                return _buildStatusItem(group, isCurrentUser: isCurrentUser);
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildStatusItem(UserStatusGroup group, {bool isCurrentUser = false}) {
    final hasUnseen = group.hasUnseen;
    final postCount = group.postCount;
    final isUploading = isCurrentUser &&
        widget.uploadProgress > 0 &&
        widget.uploadProgress < 1.0;

    // Choose ring gradient based on state
    List<Color> ringColors;
    if (isUploading) {
      ringColors = [_kAccentBlue, _kAccentCyan];
    } else if (hasUnseen) {
      ringColors = [_kAccentBlue, _kAccentPurple, _kAccentGreen];
    } else if (group.isPremium) {
      ringColors = [_kAccentPink, _kAccentPurple, _kAccentBlue];
    } else {
      ringColors = [
        Colors.white.withOpacity(0.12),
        Colors.white.withOpacity(0.06),
      ];
    }

    return GestureDetector(
      onTap: () => widget.onUserTap(group),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Avatar stack ──
            SizedBox(
              width: 78,
              height: 78,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Gradient ring / upload progress
                  if (isUploading)
                    SizedBox(
                      width: 78,
                      height: 78,
                      child: CircularProgressIndicator(
                        value: widget.uploadProgress,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_kAccentBlue),
                        strokeWidth: 3,
                        backgroundColor: Colors.white.withOpacity(0.08),
                      ),
                    )
                  else
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: ringColors,
                        ),
                        boxShadow: hasUnseen
                            ? [
                                BoxShadow(
                                  color: _kAccentBlue.withOpacity(0.25),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),

                  // Avatar image
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: _kCardBg,
                    backgroundImage: group.user.avatarUrl.isNotEmpty
                        ? CachedNetworkImageProvider(group.user.avatarUrl)
                        : null,
                    child: group.user.avatarUrl.isEmpty
                        ? Icon(
                            Icons.person_rounded,
                            color: AppConstants.textSecondary.withOpacity(0.6),
                            size: 26,
                          )
                        : null,
                  ),

                  // Add icon for current user without stories
                  if (isCurrentUser && group.posts.isEmpty && !isUploading)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_kAccentBlue, _kAccentPurple],
                          ),
                          border: Border.all(
                            color: Colors.black,
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _kAccentBlue.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),

                  // Post count indicators
                  if (postCount > 1 && !isUploading)
                    Positioned(
                      bottom: 2,
                      child: _buildPostIndicators(postCount, hasUnseen),
                    ),

                  // Premium badge
                  if (group.isPremium)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_kAccentBlue, _kAccentPurple],
                          ),
                          border: Border.all(
                            color: Colors.black,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _kAccentBlue.withOpacity(0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),

                  // Muted indicator
                  if (group.isMuted && !isUploading)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kCardBg,
                          border: Border.all(
                            color: Colors.black,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.volume_off_rounded,
                          size: 10,
                          color: AppConstants.textSecondary.withOpacity(0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Username
            SizedBox(
              width: 74,
              child: Text(
                isCurrentUser ? 'Your Story' : group.user.username,
                style: TextStyle(
                  fontSize: 11,
                  color: hasUnseen || isCurrentUser
                      ? AppConstants.white
                      : AppConstants.textSecondary.withOpacity(0.7),
                  fontWeight:
                      hasUnseen ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: -0.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddStatusButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: widget.onCreateStatus,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final glowOpacity =
                    0.15 + (_pulseController.value * 0.15);
                return Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _kAccentBlue.withOpacity(0.4),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccentBlue.withOpacity(glowOpacity),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kCardBg,
                      gradient: LinearGradient(
                        colors: [
                          _kAccentBlue.withOpacity(0.08),
                          _kAccentPurple.withOpacity(0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [_kAccentBlue, _kAccentPurple],
                      ).createShader(bounds),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 74,
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  _kAccentBlue.withOpacity(0.8),
                  _kAccentPurple.withOpacity(0.7),
                ],
              ).createShader(bounds),
              child: const Text(
                'Add Story',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostIndicators(int postCount, bool hasUnseen) {
    const maxDots = 5;
    final displayCount = postCount > maxDots ? maxDots : postCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(displayCount, (i) {
            return Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasUnseen
                    ? _kAccentBlue
                    : Colors.white.withOpacity(0.5),
              ),
            );
          }),
          if (postCount > maxDots)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                '+${postCount - maxDots}',
                style: TextStyle(
                  color: hasUnseen
                      ? _kAccentBlue
                      : Colors.white.withOpacity(0.5),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
