import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../models/chat_model.dart';
import '../utils/constants.dart';

/// Bottom sheet for forwarding a post to a private chat or group chat.
/// Reuses the existing message insertion logic (messages table).
class ForwardPostSheet extends StatefulWidget {
  final PostModel post;
  final UserModel currentUser;

  const ForwardPostSheet({
    super.key,
    required this.post,
    required this.currentUser,
  });

  @override
  State<ForwardPostSheet> createState() => _ForwardPostSheetState();
}

class _ForwardPostSheetState extends State<ForwardPostSheet> {
  final TextEditingController _searchController = TextEditingController();
  final supabase = Supabase.instance.client;

  List<ChatModel> _allChats = [];
  List<ChatModel> _filteredChats = [];
  bool _isLoading = true;
  String? _sendingToChatId;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    try {
      final userId = widget.currentUser.id;

      // Use the same RPC as inbox to load conversations
      final response = await supabase.rpc(
        'get_user_conversations_optimized',
        params: {'user_uuid': userId},
      );

      final List<ChatModel> chats = [];
      for (var item in response as List) {
        try {
          List<String> participantIds = [];
          if (item['participant_ids'] != null) {
            participantIds =
                List<String>.from(item['participant_ids'] as List);
          }
          chats.add(ChatModel(
            id: item['conversation_id'] as String,
            name: item['conversation_name'] as String? ?? 'Unknown',
            isGroup: item['is_group'] as bool? ?? false,
            lastMessageContent: item['last_message_content'] as String?,
            lastMessageTime: item['last_message_time'] != null
                ? DateTime.parse(item['last_message_time'] as String)
                : null,
            unreadCount: (item['unread_count'] as num?)?.toInt() ?? 0,
            otherUserId: item['other_user_id'] as String?,
            otherUserAlias: item['other_user_alias'] as String?,
            otherUserDisplayName:
                item['other_user_display_name'] as String?,
            otherUserProfileImageUrl:
                item['other_user_profile_image_url'] as String?,
            participantIds: participantIds,
            createdAt: DateTime.parse(item['created_at'] as String),
            updatedAt: DateTime.parse(item['updated_at'] as String),
            groupImageUrl: item['group_image_url'] as String?,
            isLocked: item['is_locked'] as bool? ?? false,
            currentUserRole: item['current_user_role'] as String?,
          ));
        } catch (e) {
          debugPrint('Error parsing conversation for forward: $e');
        }
      }

      if (mounted) {
        setState(() {
          _allChats = chats;
          _filteredChats = chats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading chats for forward: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterChats(String query) {
    if (query.isEmpty) {
      setState(() => _filteredChats = _allChats);
      return;
    }
    final lower = query.toLowerCase();
    setState(() {
      _filteredChats = _allChats.where((chat) {
        return chat.displayName.toLowerCase().contains(lower);
      }).toList();
    });
  }

  Future<void> _forwardToChat(ChatModel chat) async {
    if (_sendingToChatId != null) return;

    setState(() => _sendingToChatId = chat.id);

    try {
      // Build forwarded post payload as JSON in content field
      final forwardedData = jsonEncode({
        'post_id': widget.post.id,
        'author_name': widget.post.displayAuthorName,
        'author_avatar': widget.post.displayAuthorImage ?? '',
        'author_alias': widget.post.isAnonymous
            ? 'anonymous'
            : (widget.post.user?.alias ?? 'unknown'),
        'preview_text': widget.post.content.length > 200
            ? '${widget.post.content.substring(0, 200)}...'
            : widget.post.content,
        'image_url': widget.post.imageUrl ?? '',
      });

      // Insert message using existing message pattern
      await supabase.from('messages').insert({
        'conversation_id': chat.id,
        'sender_id': widget.currentUser.id,
        'content': forwardedData,
        'message_type': 'forwarded_post',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Post forwarded to ${chat.displayName}'),
            backgroundColor: AppConstants.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error forwarding post: $e');
      if (mounted) {
        setState(() => _sendingToChatId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to forward: ${e.toString()}'),
            backgroundColor: AppConstants.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.7,
      decoration: const BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppConstants.lightGray.withOpacity(0.6),
              borderRadius: BorderRadius.circular(999),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Forward Post',
                  style: TextStyle(
                    color: AppConstants.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppConstants.textSecondary,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Post preview snippet
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppConstants.dividerColor,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.format_quote_rounded,
                    color: AppConstants.primaryBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.post.content.length > 80
                        ? '${widget.post.content.substring(0, 80)}...'
                        : widget.post.content,
                    style: const TextStyle(
                      color: AppConstants.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppConstants.mediumGray,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterChats,
                style: const TextStyle(
                    color: AppConstants.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  hintStyle: TextStyle(
                      color: AppConstants.textSecondary, fontSize: 14),
                  prefixIcon: Icon(Icons.search,
                      color: AppConstants.textSecondary, size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Chat list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppConstants.primaryBlue,
                      strokeWidth: 2,
                    ),
                  )
                : _filteredChats.isEmpty
                    ? const Center(
                        child: Text(
                          'No chats found',
                          style: TextStyle(
                            color: AppConstants.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _filteredChats.length,
                        itemBuilder: (context, index) {
                          final chat = _filteredChats[index];
                          final isSending = _sendingToChatId == chat.id;

                          return _buildChatItem(chat, isSending);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(ChatModel chat, bool isSending) {
    return InkWell(
      onTap: isSending ? null : () => _forwardToChat(chat),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: AppConstants.primaryBlue,
              backgroundImage: chat.displayImageUrl != null
                  ? NetworkImage(chat.displayImageUrl!)
                  : null,
              child: chat.displayImageUrl == null
                  ? Icon(
                      chat.isGroup ? Icons.group : Icons.person,
                      size: 20,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (chat.isGroup)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.group,
                              size: 14, color: AppConstants.textSecondary),
                        ),
                      Flexible(
                        child: Text(
                          chat.displayName,
                          style: const TextStyle(
                            color: AppConstants.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (chat.lastMessageContent != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      chat.lastMessageContent!,
                      style: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Send button
            isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: AppConstants.primaryBlue,
                      strokeWidth: 2,
                    ),
                  )
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryBlue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Send',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
