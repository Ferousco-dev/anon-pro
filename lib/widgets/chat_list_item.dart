import 'package:flutter/material.dart';
import '../models/chat_model.dart';

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

  String _buildPreview() {
    final base = _formatMessagePreview(chat.lastMessageContent);
    final sender = chat.lastMessageSenderName;
    if (chat.isGroup && sender != null && sender.isNotEmpty) {
      return '$sender: $base';
    }
    return base;
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
    const bg = Color(0xFF0B0B0D);
    const border = Color(0xFF1F2226);
    const textPrimary = Color(0xFFFFFFFF);
    const textSecondary = Color(0xFF9AA0A6);
    const accent = Color(0xFF1E88E5);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(color: border),
          ),
        ),
        child: Row(
          children: [
            _buildAvatar(hasUnread),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.displayName,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (chat.isGroup && chat.isLocked) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.lock_rounded,
                            size: 14, color: textSecondary),
                      ],
                      if (chat.lastMessageTime != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatLastMessageTime(chat.lastMessageTime),
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _buildPreview(),
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 13.5,
                            fontWeight:
                                hasUnread ? FontWeight.w500 : FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 10),
                        _buildUnreadBadge(
                          badgeColor: accent,
                          textColor: Colors.white,
                        ),
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
        CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFF1A1D22),
          backgroundImage: chat.displayImageUrl != null
              ? NetworkImage(chat.displayImageUrl!)
              : null,
          child: chat.displayImageUrl == null
              ? Icon(
                  chat.isGroup ? Icons.group_rounded : Icons.person_rounded,
                  color: const Color(0xFF9AA0A6),
                  size: 22,
                )
              : null,
        ),
      ],
    );
  }

  // ── Gradient unread badge ──
  Widget _buildUnreadBadge({
    required Color badgeColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
