import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/message_model.dart';
import 'forwarded_post_bubble.dart';

const _kTextPrimary = Color(0xFFFFFFFF);
const _kTextSecondary = Color(0xFF9AA0A6);
const _kAccent = Color(0xFF1E88E5);
const _kBubbleSent = Color(0xFF1E88E5);
const _kBubbleReceived = Color(0xFF141518);
const _kBubbleBorder = Color(0xFF1F2226);
const _kActionBg = Color(0xFF0F1114);
const _kDanger = Color(0xFFFF4D4F);

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isCurrentUser;
  final bool showSenderInfo;
  final bool isDirectChat;
  final String? currentUserId;

  // Callbacks
  final Function(MessageModel)? onReply;
  final Function(MessageModel, String)? onReact;
  final Function(MessageModel)? onDelete;
  final Function(MessageModel)? onBlockReport;
  final Function(MessageModel)? onAbout;
  final Function(MessageModel)? onRetry;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    this.showSenderInfo = false,
    this.isDirectChat = false,
    this.currentUserId,
    this.onReply,
    this.onReact,
    this.onDelete,
    this.onBlockReport,
    this.onAbout,
    this.onRetry,
  });

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    if (diff.inDays > 0) return '$hh:$mm • ${time.day}/${time.month}';
    return '$hh:$mm';
  }

  // ─── Bottom Sheets ────────────────────────────────────────────────────────────

  void _showDirectMessageActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kBubbleReceived,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _kBubbleBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Delete — own messages only
              if (isCurrentUser) ...[
                _DmActionTile(
                  icon: Icons.delete_outline,
                  label: 'Delete Message',
                  color: _kDanger,
                  onTap: () {
                    Navigator.pop(ctx);
                    onDelete?.call(message);
                  },
                ),
                const SizedBox(height: 10),
              ],

              // Block/Report + About — other user's messages only
              if (!isCurrentUser) ...[
                _DmActionTile(
                  icon: Icons.block,
                  label: 'Block / Report Account',
                  color: _kTextPrimary,
                  onTap: () {
                    Navigator.pop(ctx);
                    onBlockReport?.call(message);
                  },
                ),
                const SizedBox(height: 10),
                _DmActionTile(
                  icon: Icons.info_outline,
                  label: 'About',
                  color: _kTextPrimary,
                  onTap: () {
                    Navigator.pop(ctx);
                    onAbout?.call(message);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showReactionPicker(BuildContext context) {
    const emojis = ['❤️', '😂', '😮', '😢', '😡', '👍', '👎', '🔥'];
    showModalBottomSheet(
      context: context,
      backgroundColor: _kBubbleReceived,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _kBubbleBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: emojis
                  .map(
                    (emoji) => GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        onReact?.call(message, emoji);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _kActionBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.reply,
                  label: 'Reply',
                  onTap: () {
                    Navigator.pop(ctx);
                    onReply?.call(message);
                  },
                ),
                _ActionButton(
                  icon: Icons.copy,
                  label: 'Copy',
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: message.content));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Sub-Builders ─────────────────────────────────────────────────────────────

  Widget _buildReplyPreview() {
    if (message.replyToId == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kActionBg,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: _kAccent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyToSenderName ?? 'Unknown',
            style: const TextStyle(
              color: _kAccent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToContent ?? '',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildReactions() {
    if (message.reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: message.reactions.entries.map((entry) {
          final emoji = entry.key;
          final users = entry.value;
          final iReacted =
              currentUserId != null && users.contains(currentUserId);
          return GestureDetector(
            onTap: () => onReact?.call(message, emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: iReacted ? _kAccent.withOpacity(0.12) : _kActionBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: iReacted ? _kAccent : _kBubbleBorder,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 3),
                  Text(
                    '${users.length}',
                    style: TextStyle(
                      color: iReacted ? _kAccent : _kTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSystemMessage() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _kActionBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content,
          style: const TextStyle(
            color: _kTextSecondary,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildMessageContent() {
    // Handle forwarded post messages
    if (message.messageType == 'forwarded_post') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReplyPreview(),
          ForwardedPostBubble(
            message: message,
            isMe: isCurrentUser,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReplyPreview(),
        if (message.imageUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              message.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 200,
                color: _kActionBg,
                child: const Center(
                  child: Icon(Icons.broken_image,
                      color: _kTextSecondary),
                ),
              ),
            ),
          ),
          if (message.content.isNotEmpty) const SizedBox(height: 8),
        ],
        if (message.content.isNotEmpty) _buildStyledText(),
      ],
    );
  }

  Widget _buildStyledText() {
    if (!message.content.contains('@')) {
      return Text(
        message.content,
        style: TextStyle(
          color: isCurrentUser ? _kTextPrimary : _kTextPrimary,
          fontSize: 15,
          height: 1.4,
        ),
      );
    }

    final words = message.content.split(' ');
    final spans = <TextSpan>[];
    for (final word in words) {
      if (word.startsWith('@')) {
        spans.add(TextSpan(
          text: '$word ',
          style: TextStyle(
            color: isCurrentUser ? _kTextPrimary : _kAccent,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            height: 1.4,
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: '$word ',
          style: TextStyle(
            color: isCurrentUser ? _kTextPrimary : _kTextPrimary,
            fontSize: 15,
            height: 1.4,
          ),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (message.isSystemMessage) return _buildSystemMessage();

    return GestureDetector(
      onLongPress: () => isDirectChat
          ? _showDirectMessageActions(context)
          : _showReactionPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          mainAxisAlignment:
              isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar for other users (group chat sender info)
            if (!isCurrentUser) ...[
              if (showSenderInfo)
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF1A1D22),
                  backgroundImage: message.senderProfileImageUrl != null
                      ? NetworkImage(message.senderProfileImageUrl!)
                      : null,
                  child: message.senderProfileImageUrl == null
                      ? Text(
                          (message.senderDisplayName ??
                                  message.senderAlias ??
                                  '?')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                )
              else
                const SizedBox(width: 32),
              const SizedBox(width: 8),
            ],

            Flexible(
              child: Column(
                crossAxisAlignment: isCurrentUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isCurrentUser && showSenderInfo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 8),
                      child: Text(
                        message.senderDisplayName ??
                            message.senderAlias ??
                            'Unknown',
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          isCurrentUser ? _kBubbleSent : _kBubbleReceived,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isCurrentUser ? 20 : 4),
                        bottomRight: Radius.circular(isCurrentUser ? 4 : 20),
                      ),
                      border: Border.all(color: _kBubbleBorder),
                    ),
                    child: _buildMessageContent(),
                  ),
                  _buildReactions(),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(message.createdAt),
                          style: TextStyle(
                            color: _kTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 4),
                          _buildDeliveryIcon(context),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryIcon(BuildContext context) {
    switch (message.deliveryStatus) {
      case MessageDeliveryStatus.sending:
        return Icon(
          Icons.access_time,
          size: 14,
          color: _kTextSecondary,
        );
      case MessageDeliveryStatus.failed:
        return GestureDetector(
          onTap: () => onRetry?.call(message),
          child: const Icon(
            Icons.error_outline,
            size: 14,
            color: _kDanger,
          ),
        );
      case MessageDeliveryStatus.read:
        return const Icon(
          Icons.done_all,
          size: 14,
          color: _kAccent,
        );
      case MessageDeliveryStatus.sent:
      default:
        return Icon(
          message.isRead ? Icons.done_all : Icons.done,
          size: 14,
          color: message.isRead ? _kAccent : _kTextSecondary,
        );
    }
  }
}

// ─── Private Widget: DM Action Tile ──────────────────────────────────────────

class _DmActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DmActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _kActionBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBubbleBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Private Widget: Reaction Picker Action Button ────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kActionBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBubbleBorder),
            ),
            child: Icon(icon, color: _kTextPrimary, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
                color: _kTextSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
