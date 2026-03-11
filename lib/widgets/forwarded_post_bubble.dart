import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/message_model.dart';
import '../utils/constants.dart';

/// Renders a forwarded post preview inside a chat message bubble.
/// Parses the JSON content from a 'forwarded_post' message type.
class ForwardedPostBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;

  const ForwardedPostBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? postData;
    try {
      postData = jsonDecode(message.content) as Map<String, dynamic>;
    } catch (e) {
      // Fallback: show raw content if JSON parsing fails
      return Text(
        message.content,
        style: TextStyle(
          color: isMe ? Colors.white : AppConstants.textPrimary,
          fontSize: 15,
        ),
      );
    }

    final authorName = postData['author_name'] as String? ?? 'Unknown';
    final authorAlias = postData['author_alias'] as String? ?? 'unknown';
    final authorAvatar = postData['author_avatar'] as String? ?? '';
    final previewText = postData['preview_text'] as String? ?? '';
    final imageUrl = postData['image_url'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Shared from Feed" label
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shortcut_rounded,
              size: 12,
              color: isMe
                  ? Colors.white.withOpacity(0.7)
                  : AppConstants.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              'Shared from Feed',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isMe
                    ? Colors.white.withOpacity(0.7)
                    : AppConstants.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Post preview card
        Container(
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withOpacity(0.1)
                : AppConstants.mediumGray,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMe
                  ? Colors.white.withOpacity(0.15)
                  : AppConstants.dividerColor,
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author row
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppConstants.primaryBlue,
                    backgroundImage: authorAvatar.isNotEmpty
                        ? NetworkImage(authorAvatar)
                        : null,
                    child: authorAvatar.isEmpty
                        ? const Icon(Icons.person,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  // Author name + handle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authorName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color:
                                isMe ? Colors.white : AppConstants.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '@$authorAlias',
                          style: TextStyle(
                            fontSize: 12,
                            color: isMe
                                ? Colors.white.withOpacity(0.6)
                                : AppConstants.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Post preview text
              if (previewText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  previewText,
                  style: TextStyle(
                    fontSize: 14,
                    color: isMe ? Colors.white : AppConstants.textPrimary,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Image thumbnail
              if (imageUrl.isNotEmpty) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: 120,
                      color: AppConstants.darkGray,
                    ),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
