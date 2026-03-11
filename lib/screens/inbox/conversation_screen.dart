import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../models/message_model.dart';
import '../../models/chat_model.dart';
import '../../utils/constants.dart';
import '../../widgets/message_bubble.dart';
import '../../main.dart';
import 'group_management_screen.dart';
import '../profile/profile_screen.dart';

class ConversationScreen extends StatefulWidget {
  final ChatModel chat;

  const ConversationScreen({
    super.key,
    required this.chat,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<MessageModel> _messages = [];

  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  // Realtime subscriptions
  RealtimeChannel? _messageSubscription;
  RealtimeChannel? _reactionSubscription;
  RealtimeChannel? _groupSubscription;
  RealtimeChannel? _participantsSubscription;

  // Reply state
  MessageModel? _replyingTo;

  // Mention state
  bool _showMentionSuggestions = false;
  List<Map<String, dynamic>> _groupMembers = [];
  List<Map<String, dynamic>> _filteredMembers = [];

  late ChatModel _chat;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _loadMessages();
    _subscribeToMessages();
    _subscribeToReactions();
    _markMessagesAsRead();
    if (_chat.isGroup) {
      _loadGroupMembers();
      _subscribeToGroupChanges();
    }
    _messageController.addListener(_onTextChanged);
  }

  // ─── Text / Mention Logic ─────────────────────────────────────────────────────

  void _onTextChanged() {
    final text = _messageController.text;
    final cursor = _messageController.selection.baseOffset;
    if (cursor < 0) return;

    final textBeforeCursor = text.substring(0, cursor);
    final atIndex = textBeforeCursor.lastIndexOf('@');

    if (atIndex >= 0) {
      final query = textBeforeCursor.substring(atIndex + 1);
      if (!query.contains(' ')) {
        setState(() {
          _showMentionSuggestions = true;
          _filteredMembers = _groupMembers
              .where((m) =>
                  (m['alias'] as String? ?? '')
                      .toLowerCase()
                      .contains(query.toLowerCase()) ||
                  (m['display_name'] as String? ?? '')
                      .toLowerCase()
                      .contains(query.toLowerCase()))
              .toList();
        });
        return;
      }
    }
    setState(() => _showMentionSuggestions = false);
  }

  void _insertMention(Map<String, dynamic> member) {
    final text = _messageController.text;
    final cursor = _messageController.selection.baseOffset;
    final textBeforeCursor = text.substring(0, cursor);
    final atIndex = textBeforeCursor.lastIndexOf('@');

    if (atIndex >= 0) {
      final alias =
          member['alias'] as String? ?? member['display_name'] as String? ?? '';
      final newText =
          '${text.substring(0, atIndex)}@$alias ${text.substring(cursor)}';
      _messageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: atIndex + alias.length + 2),
      );
    }
    setState(() => _showMentionSuggestions = false);
  }

  // ─── Data Loading ─────────────────────────────────────────────────────────────

  Future<void> _loadGroupMembers() async {
    try {
      final response = await supabase
          .from('conversation_participants')
          .select('users:user_id(id, alias, display_name, profile_image_url)')
          .eq('conversation_id', _chat.id);

      if (mounted) {
        setState(() {
          _groupMembers = (response as List)
              .map((e) => e['users'] as Map<String, dynamic>)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading group members: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final response = await supabase
          .from('messages')
          .select('''
            *,
            users:sender_id (
              alias,
              display_name,
              profile_image_url
            ),
            reply_message:reply_to_id (
              content,
              sender_id,
              users:sender_id (alias, display_name)
            )
          ''')
          .eq('conversation_id', _chat.id)
          .order('created_at', ascending: true)
          .limit(100);

      final messageIds =
          (response as List).map((m) => m['id'] as String).toList();
      Map<String, Map<String, List<String>>> allReactions = {};

      if (messageIds.isNotEmpty) {
        final reactionsResponse = await supabase
            .from('message_reactions')
            .select('message_id, reaction, user_id')
            .inFilter('message_id', messageIds);

        for (var r in reactionsResponse as List) {
          final messageId = r['message_id'] as String;
          final emoji = r['reaction'] as String;
          final userId = r['user_id'] as String;
          allReactions.putIfAbsent(messageId, () => {});
          allReactions[messageId]!.putIfAbsent(emoji, () => []).add(userId);
        }
      }

      if (mounted) {
        setState(() {
          _messages.clear();
          for (var messageData in response) {
            _messages.add(_parseMessage({
              ...messageData,
              'reactions': allReactions[messageData['id']] ?? {},
            }));
          }
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _reloadReactions() async {
    try {
      final messageIds = _messages.map((m) => m.id).toList();
      if (messageIds.isEmpty) return;

      final reactionsResponse = await supabase
          .from('message_reactions')
          .select('message_id, reaction, user_id')
          .inFilter('message_id', messageIds);

      Map<String, Map<String, List<String>>> allReactions = {};
      for (var r in reactionsResponse as List) {
        final messageId = r['message_id'] as String;
        final emoji = r['reaction'] as String;
        final userId = r['user_id'] as String;
        allReactions.putIfAbsent(messageId, () => {});
        allReactions[messageId]!.putIfAbsent(emoji, () => []).add(userId);
      }

      if (mounted) {
        setState(() {
          for (int i = 0; i < _messages.length; i++) {
            _messages[i] = _messages[i].copyWith(
              reactions: allReactions[_messages[i].id] ?? {},
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error reloading reactions: $e');
    }
  }

  MessageModel _parseMessage(Map<String, dynamic> messageData) {
    final userData = messageData['users'] as Map<String, dynamic>?;

    String? replyToContent;
    String? replyToSenderName;
    final replyMessage = messageData['reply_message'] as Map<String, dynamic>?;
    if (replyMessage != null) {
      replyToContent = replyMessage['content'] as String?;
      final replyUser = replyMessage['users'] as Map<String, dynamic>?;
      replyToSenderName = replyUser?['display_name'] as String? ??
          replyUser?['alias'] as String?;
    }

    return MessageModel.fromJson({
      ...messageData,
      'sender_alias': userData?['alias'],
      'sender_display_name': userData?['display_name'],
      'sender_profile_image_url': userData?['profile_image_url'],
      'reply_to_content': replyToContent,
      'reply_to_sender_name': replyToSenderName,
      'reactions': messageData['reactions'] ?? {},
    });
  }

  // ─── Realtime Subscriptions ───────────────────────────────────────────────────

  void _subscribeToMessages() {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    _messageSubscription = supabase
        .channel('messages:${_chat.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: _chat.id,
          ),
          callback: (payload) async {
            try {
              final senderId = payload.newRecord['sender_id'] as String;
              final userData = await supabase
                  .from('users')
                  .select('alias, display_name, profile_image_url')
                  .eq('id', senderId)
                  .single();

              if (mounted) {
                setState(() {
                  _messages.add(MessageModel.fromJson({
                    ...payload.newRecord,
                    'sender_alias': userData['alias'],
                    'sender_display_name': userData['display_name'],
                    'sender_profile_image_url': userData['profile_image_url'],
                  }));
                });
                _scrollToBottom();
                if (senderId != currentUser.id) _markMessagesAsRead();
              }
            } catch (e) {
              debugPrint('Error fetching sender info: $e');
            }
          },
        )
        .subscribe();
  }

  void _subscribeToReactions() {
    _reactionSubscription = supabase
        .channel('reactions:${_chat.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) => _reloadReactions(),
        )
        .subscribe();
  }

  void _subscribeToGroupChanges() {
    _groupSubscription = supabase
        .channel('group_info:${_chat.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _chat.id,
          ),
          callback: (payload) {
            final updated = payload.newRecord;
            if (mounted) {
              setState(() {
                _chat = _chat.copyWith(
                  name: updated['name'] as String?,
                  isLocked: updated['is_locked'] as bool? ?? _chat.isLocked,
                  groupImageUrl: updated['group_image_url'] as String?,
                );
              });
            }
          },
        )
        .subscribe();

    _participantsSubscription = supabase
        .channel('participants:${_chat.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: _chat.id,
          ),
          callback: (payload) {
            _loadGroupMembers();

            final currentUserId = supabase.auth.currentUser?.id;
            if (payload.eventType == PostgresChangeEvent.delete) {
              final removedUserId = payload.oldRecord['user_id'] as String?;
              if (removedUserId == currentUserId && mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You were removed from this group'),
                    backgroundColor: AppConstants.red,
                  ),
                );
              }
            }

            if (payload.eventType == PostgresChangeEvent.update) {
              final updatedUserId = payload.newRecord['user_id'] as String?;
              if (updatedUserId == currentUserId && mounted) {
                final newRole =
                    payload.newRecord['role'] as String? ?? 'member';
                setState(() {
                  _chat = _chat.copyWith(currentUserRole: newRole);
                });
              }
            }
          },
        )
        .subscribe();
  }

  // ─── Core Actions ─────────────────────────────────────────────────────────────

  Future<void> _markMessagesAsRead() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;
      await supabase
          .from('conversation_participants')
          .update({'last_read_at': DateTime.now().toIso8601String()})
          .eq('conversation_id', _chat.id)
          .eq('user_id', currentUser.id);
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    if (!_chat.canSendMessages) return;

    setState(() => _isSending = true);

    try {
      final mentions = RegExp(r'@(\w+)')
          .allMatches(content)
          .map((m) => m.group(1)!)
          .toList();

      await supabase.from('messages').insert({
        'conversation_id': _chat.id,
        'sender_id': currentUser.id,
        'content': content,
        'message_type': 'text',
        'reply_to_id': _replyingTo?.id,
        'mentions': mentions,
        'created_at': DateTime.now().toIso8601String(),
      });

      _messageController.clear();
      setState(() {
        _replyingTo = null;
        _showMentionSuggestions = false;
      });
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: ${e.toString()}'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleReaction(MessageModel message, String emoji) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    final existingReactions = message.reactions[emoji] ?? [];
    final alreadyReacted = existingReactions.contains(currentUser.id);

    try {
      if (alreadyReacted) {
        await supabase
            .from('message_reactions')
            .delete()
            .eq('message_id', message.id)
            .eq('user_id', currentUser.id)
            .eq('reaction', emoji);
      } else {
        await supabase.from('message_reactions').insert({
          'message_id': message.id,
          'user_id': currentUser.id,
          'reaction': emoji,
        });
      }
    } catch (e) {
      debugPrint('Error toggling reaction: $e');
    }
  }

  Future<void> _toggleGroupLock() async {
    try {
      await supabase
          .from('conversations')
          .update({'is_locked': !_chat.isLocked}).eq('id', _chat.id);
    } catch (e) {
      debugPrint('Error toggling lock: $e');
    }
  }

  // ─── DM Actions ───────────────────────────────────────────────────────────────

  /// Delete a message — only works for the current user's own messages.
  Future<void> _deleteMessage(MessageModel message) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    // senderId is non-nullable; guard against deleting others' messages
    if (message.senderId != currentUser.id) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Message',
          style: TextStyle(color: AppConstants.white),
        ),
        content: const Text(
          'This message will be permanently deleted.',
          style: TextStyle(color: AppConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppConstants.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: AppConstants.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await supabase.from('messages').delete().eq('id', message.id);
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == message.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            backgroundColor: AppConstants.darkGray,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete message'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  /// Shows the block / report dialog for the sender of [message].
  void _showBlockReportDialog(MessageModel message) {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    final otherUserId = message.senderId; // non-nullable String
    // Don't allow blocking yourself
    if (otherUserId == currentUser.id) return;

    String? selectedReason;
    final reasons = [
      'Spam',
      'Harassment',
      'Inappropriate content',
      'Fake account',
      'Other',
    ];
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppConstants.darkGray,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Block / Report Account',
            style: TextStyle(color: AppConstants.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a reason to report (optional for block only):',
                  style: TextStyle(
                      color: AppConstants.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...reasons.map(
                  (reason) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppConstants.primaryBlue,
                    title: Text(
                      reason,
                      style: const TextStyle(
                          color: AppConstants.white, fontSize: 14),
                    ),
                    value: reason,
                    groupValue: selectedReason,
                    onChanged: (v) => setDialogState(() => selectedReason = v),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: AppConstants.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Additional details (optional)',
                    hintStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                    filled: true,
                    fillColor: AppConstants.black,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppConstants.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _blockUser(blockerId: currentUser.id, blockedId: otherUserId);
              },
              child: const Text(
                'Block Only',
                style: TextStyle(color: AppConstants.red),
              ),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _blockAndReportUser(
                        reporterId: currentUser.id,
                        reportedId: otherUserId,
                        reason: selectedReason!,
                        description: descController.text.trim().isEmpty
                            ? null
                            : descController.text.trim(),
                      );
                    },
              child: Text(
                'Block & Report',
                style: TextStyle(
                  color: selectedReason == null
                      ? AppConstants.textSecondary
                      : AppConstants.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _blockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      await supabase.from('blocked_users').insert({
        'blocker_id': blockerId,
        'blocked_id': blockedId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User blocked'),
            backgroundColor: AppConstants.darkGray,
          ),
        );
        Navigator.pop(context); // Exit the conversation
      }
    } catch (e) {
      debugPrint('Error blocking user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to block user'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  Future<void> _blockAndReportUser({
    required String reporterId,
    required String reportedId,
    required String reason,
    String? description,
  }) async {
    try {
      await Future.wait([
        supabase.from('blocked_users').insert({
          'blocker_id': reporterId,
          'blocked_id': reportedId,
        }),
        supabase.from('user_reports').insert({
          'reporter_id': reporterId,
          'reported_id': reportedId,
          'reason': reason,
          if (description != null) 'description': description,
        }),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User blocked and reported'),
            backgroundColor: AppConstants.darkGray,
          ),
        );
        Navigator.pop(context); // Exit the conversation
      }
    } catch (e) {
      debugPrint('Error blocking/reporting user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to block/report user'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  void _navigateToAbout(MessageModel message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: message.senderId),
      ),
    );
  }

  // ─── UI Builders ──────────────────────────────────────────────────────────────

  Widget _buildReplyBanner() {
    if (_replyingTo == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppConstants.darkGray,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppConstants.primaryBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${_replyingTo!.senderDisplayName ?? _replyingTo!.senderAlias ?? 'Unknown'}',
                  style: const TextStyle(
                    color: AppConstants.primaryBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _replyingTo!.content,
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: AppConstants.textSecondary, size: 18),
            onPressed: () => setState(() => _replyingTo = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildMentionSuggestions() {
    if (!_showMentionSuggestions || _filteredMembers.isEmpty) {
      return const SizedBox.shrink();
    }

    final suggestions = <Map<String, dynamic>>[
      if (_chat.isAdmin)
        {'alias': 'all', 'display_name': 'Everyone', 'isAll': true},
      ..._filteredMembers,
    ];

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      color: AppConstants.darkGray,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final member = suggestions[index];
          final isAll = member['isAll'] == true;
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor:
                  isAll ? AppConstants.primaryBlue : AppConstants.lightGray,
              backgroundImage: member['profile_image_url'] != null
                  ? NetworkImage(member['profile_image_url'] as String)
                  : null,
              child: member['profile_image_url'] == null
                  ? Icon(isAll ? Icons.group : Icons.person,
                      size: 16, color: Colors.white)
                  : null,
            ),
            title: Text(
              member['display_name'] as String? ??
                  member['alias'] as String? ??
                  '',
              style: const TextStyle(color: AppConstants.white, fontSize: 13),
            ),
            subtitle: isAll
                ? null
                : Text(
                    '@${member['alias']}',
                    style: const TextStyle(
                        color: AppConstants.textSecondary, fontSize: 11),
                  ),
            onTap: () => _insertMention(member),
          );
        },
      ),
    );
  }

  Widget _buildMessageInput() {
    final isLocked = !_chat.canSendMessages;

    return Column(
      children: [
        _buildReplyBanner(),
        _buildMentionSuggestions(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppConstants.black,
            border: Border(
              top: BorderSide(
                color: AppConstants.lightGray.withOpacity(0.2),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppConstants.darkGray,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      enabled: !isLocked,
                      style: const TextStyle(color: AppConstants.white),
                      decoration: InputDecoration(
                        hintText: isLocked
                            ? 'Only admins can message...'
                            : 'Message...',
                        hintStyle:
                            const TextStyle(color: AppConstants.textSecondary),
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Lock icon when locked, send button otherwise
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLocked
                        ? AppConstants.darkGray
                        : _messageController.text.trim().isEmpty
                            ? AppConstants.darkGray
                            : AppConstants.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                  child: isLocked
                      ? const Icon(Icons.lock,
                          color: AppConstants.textSecondary, size: 20)
                      : GestureDetector(
                          onTap: _isSending ? null : _sendMessage,
                          child: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send,
                                  color: Colors.white, size: 20),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryBlue),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Error loading messages',
                style: TextStyle(color: AppConstants.white, fontSize: 18)),
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(
                    color: AppConstants.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadMessages, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 64, color: AppConstants.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text('No messages yet',
                style: TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Start the conversation!',
                style:
                    TextStyle(color: AppConstants.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    final currentUserId = supabase.auth.currentUser?.id;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isCurrentUser = message.senderId == currentUserId;
        final showSenderInfo = _chat.isGroup &&
            !isCurrentUser &&
            (index == 0 || _messages[index - 1].senderId != message.senderId);

        return MessageBubble(
          message: message,
          isCurrentUser: isCurrentUser,
          showSenderInfo: showSenderInfo,
          isDirectChat: !_chat.isGroup,
          currentUserId: currentUserId,
          onReply: (msg) => setState(() => _replyingTo = msg),
          onReact: _toggleReaction,
          onDelete: _deleteMessage,
          onBlockReport: _showBlockReportDialog,
          onAbout: _navigateToAbout,
        );
      },
    );
  }

  void _showDmOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.darkGray,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.lightGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              _DmMenuTile(
                icon: Icons.info_outline,
                label: 'About',
                color: AppConstants.white,
                onTap: () {
                  Navigator.pop(ctx);
                  // Build a fake message with the other user's ID to reuse _navigateToAbout
                  if (_chat.otherUserId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProfileScreen(userId: _chat.otherUserId!),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              _DmMenuTile(
                icon: Icons.block,
                label: 'Block / Report',
                color: AppConstants.white,
                onTap: () {
                  Navigator.pop(ctx);
                  final currentUser = supabase.auth.currentUser;
                  if (currentUser == null || _chat.otherUserId == null) return;
                  _showBlockReportFromAppBar(
                    currentUserId: currentUser.id,
                    otherUserId: _chat.otherUserId!,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockReportFromAppBar({
    required String currentUserId,
    required String otherUserId,
  }) {
    String? selectedReason;
    final reasons = [
      'Spam',
      'Harassment',
      'Inappropriate content',
      'Fake account',
      'Other'
    ];
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppConstants.darkGray,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Block / Report Account',
              style: TextStyle(color: AppConstants.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a reason to report (optional for block only):',
                  style: TextStyle(
                      color: AppConstants.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...reasons.map((reason) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppConstants.primaryBlue,
                      title: Text(reason,
                          style: const TextStyle(
                              color: AppConstants.white, fontSize: 14)),
                      value: reason,
                      groupValue: selectedReason,
                      onChanged: (v) =>
                          setDialogState(() => selectedReason = v),
                    )),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: AppConstants.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Additional details (optional)',
                    hintStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                    filled: true,
                    fillColor: AppConstants.black,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppConstants.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _blockUser(blockerId: currentUserId, blockedId: otherUserId);
              },
              child: const Text('Block Only',
                  style: TextStyle(color: AppConstants.red)),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _blockAndReportUser(
                        reporterId: currentUserId,
                        reportedId: otherUserId,
                        reason: selectedReason!,
                        description: descController.text.trim().isEmpty
                            ? null
                            : descController.text.trim(),
                      );
                    },
              child: Text(
                'Block & Report',
                style: TextStyle(
                  color: selectedReason == null
                      ? AppConstants.textSecondary
                      : AppConstants.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.darkGray,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppConstants.lightGray,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.group, color: AppConstants.white),
            title: const Text('Group Info',
                style: TextStyle(color: AppConstants.white)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupManagementScreen(chat: _chat),
                ),
              );
            },
          ),
          if (_chat.isAdmin) ...[
            ListTile(
              leading: Icon(
                _chat.isLocked ? Icons.lock_open : Icons.lock,
                color: AppConstants.white,
              ),
              title: Text(
                _chat.isLocked ? 'Unlock Group' : 'Lock Group',
                style: const TextStyle(color: AppConstants.white),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _toggleGroupLock();
              },
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppConstants.primaryBlue,
              backgroundImage: _chat.displayImageUrl != null
                  ? NetworkImage(_chat.displayImageUrl!)
                  : null,
              child: _chat.displayImageUrl == null
                  ? Icon(
                      _chat.isGroup ? Icons.group : Icons.person,
                      color: Colors.white,
                      size: 20,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _chat.displayName,
                          style: const TextStyle(
                            color: AppConstants.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_chat.isGroup && _chat.isLocked) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.lock,
                            color: AppConstants.textSecondary, size: 14),
                      ],
                    ],
                  ),
                  if (_chat.isGroup)
                    Text(
                      '${_chat.participantIds.length} members',
                      style: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppConstants.white),
            // Only group chats use the options menu for now
            onPressed: _chat.isGroup ? _showGroupOptions : _showDmOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessagesList()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _messageSubscription?.unsubscribe();
    _reactionSubscription?.unsubscribe();
    _groupSubscription?.unsubscribe();
    _participantsSubscription?.unsubscribe();
    super.dispose();
  }
}

// ─── Private Widget: DM App Bar Menu Tile ────────────────────────────────────

class _DmMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DmMenuTile({
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
          color: AppConstants.black,
          borderRadius: BorderRadius.circular(14),
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
