import 'package:flutter/material.dart';
import '../models/chat_model.dart';
import '../utils/constants.dart';

class ChatListItem extends StatelessWidget {
  final ChatModel chat;
  final VoidCallback onTap;

  const ChatListItem({
    super.key,
    required this.chat,
    required this.onTap,
  });

  /// Detect forwarded-post JSON and return a friendly label.
  String _formatMessagePreview(String? content) {
    if (content == null || content.isEmpty) return 'No messages yet';
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{') && trimmed.contains('"post_id"')) {
      return '📎 Forwarded a post';
    }
    return content;
  }

  String _formatLastMessageTime(DateTime? time) {
    if (time == null) return '';

    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 7) {
      return '${time.day}/${time.month}/${time.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasUnread = chat.unreadCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // Glassmorphic card
          color: hasUnread
              ? const Color(0xFF0A1218).withOpacity(0.9)
              : const Color(0xFF0A0A0A).withOpacity(0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasUnread
                ? AppConstants.primaryBlue.withOpacity(0.25)
                : Colors.white.withOpacity(0.04),
            width: hasUnread ? 1.2 : 0.8,
          ),
          boxShadow: hasUnread
              ? [
                  BoxShadow(
                    color: AppConstants.primaryBlue.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // ── Avatar with gradient ring + online dot ──
            _buildAvatar(hasUnread),
            const SizedBox(width: 14),

            // ── Chat info ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Name
                      Expanded(
                        child: Text(
                          chat.displayName,
                          style: TextStyle(
                            color: hasUnread
                                ? AppConstants.white
                                : AppConstants.white.withOpacity(0.85),
                            fontSize: 15.5,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Group / lock badge
                      if (chat.isGroup && chat.isLocked) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.lock_rounded,
                            size: 13,
                            color: AppConstants.orange.withOpacity(0.7)),
                      ],
                      // Time
                      if (chat.lastMessageTime != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatLastMessageTime(chat.lastMessageTime),
                          style: TextStyle(
                            color: hasUnread
                                ? AppConstants.primaryBlue
                                : AppConstants.textSecondary.withOpacity(0.6),
                            fontSize: 12,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Last message + badge row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatMessagePreview(chat.lastMessageContent),
                          style: TextStyle(
                            color: hasUnread
                                ? AppConstants.white.withOpacity(0.75)
                                : AppConstants.textSecondary.withOpacity(0.55),
                            fontSize: 13.5,
                            fontWeight:
                                hasUnread ? FontWeight.w500 : FontWeight.w400,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 10),
                        _buildUnreadBadge(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Avatar with gradient ring for unread ──
  Widget _buildAvatar(bool hasUnread) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: hasUnread
                ? const LinearGradient(
                    colors: [
                      Color(0xFF007AFF),
                      Color(0xFF5856D6),
                      Color(0xFF34C759),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            border: !hasUnread
                ? Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 2,
                  )
                : null,
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF121212),
            backgroundImage: chat.displayImageUrl != null
                ? NetworkImage(chat.displayImageUrl!)
                : null,
            child: chat.displayImageUrl == null
                ? Icon(
                    chat.isGroup ? Icons.group_rounded : Icons.person_rounded,
                    color: AppConstants.textSecondary,
                    size: 24,
                  )
                : null,
          ),
        ),
        // Online / activity dot
        if (hasUnread)
          Positioned(
            bottom: 1,
            right: 1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF0A0A0A),
                  width: 2.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Gradient unread badge ──
  Widget _buildUnreadBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryBlue.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
