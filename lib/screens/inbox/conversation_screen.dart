import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../models/message_model.dart';
import '../../models/chat_model.dart';
import '../../utils/app_error_handler.dart';
import '../../widgets/message_bubble.dart';
import '../../main.dart';
import '../../services/local_database_service.dart';
import '../../services/offline_sync_service.dart';
import '../../providers/connectivity_provider.dart';
import 'group_management_screen.dart';
import '../profile/profile_screen.dart';

const _kChatSurface = Color(0xFF0B0B0D);
const _kChatBorder = Color(0xFF1F2226);

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
  static const _kBg = Color(0xFF000000);
  static const _kSurface = Color(0xFF0B0B0D);
  static const _kBorder = Color(0xFF1F2226);
  static const _kTextPrimary = Color(0xFFFFFFFF);
  static const _kTextSecondary = Color(0xFF9AA0A6);
  static const _kAccent = Color(0xFF1E88E5);
  static const _kAccentBlue = Color(0xFF1E88E5);
  static const _kAccentRed = Color(0xFFFF4D4F);

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<MessageModel> _messages = [];
  final Map<String, String> _pendingLocalToServer = {};
  final LocalDatabaseService _localDb = LocalDatabaseService();

  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  // Realtime subscriptions
  RealtimeChannel? _messageSubscription;
  RealtimeChannel? _reactionSubscription;
  RealtimeChannel? _groupSubscription;
  RealtimeChannel? _participantsSubscription;
  RealtimeChannel? _presenceChannel;

  final Set<String> _onlineUserIds = {};
  bool _isTyping = false;
  bool _isOtherTyping = false;
  Timer? _typingDebounce;

  // Reply state
  MessageModel? _replyingTo;

  // Mention state
  bool _showMentionSuggestions = false;
  List<Map<String, dynamic>> _groupMembers = [];
  List<Map<String, dynamic>> _filteredMembers = [];

  late ChatModel _chat;

  DateTime? _oldestMessageTime;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _scrollController.addListener(_onScroll);
    _loadMessages();
    _subscribeToMessages();
    _subscribeToReactions();
    _setupPresenceAndTyping();
    _markMessagesAsRead();
    if (_chat.isGroup) {
      _loadConversationInfo();
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

    if (!_chat.canSendMessages) return;
    if (text.trim().isEmpty) {
      _typingDebounce?.cancel();
      _setTypingStatus(false);
      return;
    }

    _setTypingStatus(true);
    _typingDebounce?.cancel();
    _typingDebounce = Timer(
      const Duration(seconds: 2),
      () => _setTypingStatus(false),
    );
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

  void _setupPresenceAndTyping() {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    _presenceChannel = supabase.channel(
      'presence:${_chat.id}',
      opts: RealtimeChannelConfig(
        key: currentUser.id,
        enabled: true,
        self: true,
      ),
    );

    _presenceChannel!
        .onPresenceSync((_) => _updateOnlineUsers())
        .onPresenceJoin((_) => _updateOnlineUsers())
        .onPresenceLeave((_) => _updateOnlineUsers())
        .onBroadcast(event: 'typing', callback: _handleTypingEvent)
        .subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _presenceChannel?.track({
          'user_id': currentUser.id,
          'online_at': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  void _updateOnlineUsers() {
    final channel = _presenceChannel;
    if (channel == null) return;
    final state = channel.presenceState();
    final ids = <String>{};
    for (final presence in state) {
      for (final meta in presence.presences) {
        final id = meta.payload['user_id'] as String?;
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }
    }
    if (mounted) {
      setState(() {
        _onlineUserIds
          ..clear()
          ..addAll(ids);
      });
    }
  }

  void _handleTypingEvent(Map<String, dynamic> payload) {
    final currentUserId = supabase.auth.currentUser?.id;
    final senderId = payload['user_id'] as String?;
    if (senderId == null || senderId == currentUserId) return;
    final isTyping = payload['is_typing'] == true;
    if (mounted) {
      setState(() => _isOtherTyping = isTyping);
    }
  }

  void _setTypingStatus(bool isTyping) {
    if (_isTyping == isTyping) return;
    _isTyping = isTyping;
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    _presenceChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {
        'conversation_id': _chat.id,
        'user_id': currentUserId,
        'is_typing': isTyping,
      },
    );
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

  Future<void> _loadConversationInfo() async {
    try {
      final response = await supabase
          .from('conversations')
          .select(
              'name, is_locked, group_image_url, pinned_message, pinned_by, pinned_at')
          .eq('id', _chat.id)
          .maybeSingle();
      if (response == null) return;
      if (mounted) {
        setState(() {
          _chat = _chat.copyWith(
            name: response['name'] as String?,
            isLocked: response['is_locked'] as bool? ?? _chat.isLocked,
            groupImageUrl: response['group_image_url'] as String?,
            pinnedMessage: response['pinned_message'] as String?,
            pinnedBy: response['pinned_by'] as String?,
            pinnedAt: response['pinned_at'] != null
                ? DateTime.tryParse(response['pinned_at'] as String)
                : _chat.pinnedAt,
          );
        });
      }
    } catch (e) {
      debugPrint('Failed to load conversation info: $e');
    }
  }

  Future<void> _loadMessages() async {
    await _loadCachedMessages();
    await _loadMessagesFromNetwork();
  }

  Future<void> _loadCachedMessages() async {
    try {
      final cached = await _localDb.getCachedMessagesForConversation(
        _chat.id,
        limit: 40,
        offset: 0,
      );
      if (cached.isEmpty || !mounted) return;
      final sorted = cached.reversed.toList();
      setState(() {
        _messages
          ..clear()
          ..addAll(sorted.map(_messageFromCache));
        _isLoading = false;
      });
      _oldestMessageTime = _messages.isNotEmpty
          ? _messages.first.createdAt
          : _oldestMessageTime;
    } catch (e) {
      debugPrint('Error loading cached messages: $e');
    }
  }

  Future<void> _loadMessagesFromNetwork() async {
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
          .order('created_at', ascending: false)
          .limit(40);

      final rows = (response as List).reversed.toList();
      final messageIds = rows.map((m) => m['id'] as String).toList();
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
          _messages
            ..clear()
            ..addAll(rows.map((messageData) => _parseMessage({
                  ...messageData,
                  'reactions': allReactions[messageData['id']] ?? {},
                })));
          _isLoading = false;
          _error = null;
          _hasMore = rows.length == 40;
        });
        _oldestMessageTime =
            _messages.isNotEmpty ? _messages.first.createdAt : null;
        await _cacheMessages(rows);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _error = AppErrorHandler.userMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _oldestMessageTime == null) return;
    _isLoadingMore = true;

    try {
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
          .lt('created_at', _oldestMessageTime!.toIso8601String())
          .order('created_at', ascending: false)
          .limit(40);

      final rows = (response as List).reversed.toList();
      if (rows.isEmpty) {
        _hasMore = false;
        _isLoadingMore = false;
        return;
      }

      final prevMax = _scrollController.position.maxScrollExtent;
      setState(() {
        _messages.insertAll(
          0,
          rows.map((messageData) => _parseMessage(messageData)).toList(),
        );
        _oldestMessageTime = _messages.first.createdAt;
        _hasMore = rows.length == 40;
      });
      await _cacheMessages(rows);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final newMax = _scrollController.position.maxScrollExtent;
        final delta = newMax - prevMax;
        _scrollController.jumpTo(_scrollController.position.pixels + delta);
      });
    } catch (e) {
      debugPrint('Error loading more messages: $e');
    } finally {
      _isLoadingMore = false;
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

    final parsed = MessageModel.fromJson({
      ...messageData,
      'sender_alias': userData?['alias'],
      'sender_display_name': userData?['display_name'],
      'sender_profile_image_url': userData?['profile_image_url'],
      'reply_to_content': replyToContent,
      'reply_to_sender_name': replyToSenderName,
      'reactions': messageData['reactions'] ?? {},
    });
    final deliveryStatus = parsed.readAt != null
        ? MessageDeliveryStatus.read
        : MessageDeliveryStatus.sent;
    return parsed.copyWith(deliveryStatus: deliveryStatus);
  }

  MessageModel _messageFromCache(Map<String, dynamic> row) {
    final createdAt = row['created_at'];
    final created = createdAt is int
        ? DateTime.fromMillisecondsSinceEpoch(createdAt)
        : DateTime.now();
    final status = row['status'] as String?;
    final deliveryStatus = status == 'sending'
        ? MessageDeliveryStatus.sending
        : MessageDeliveryStatus.sent;
    return MessageModel(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      senderId: row['sender_id'] as String,
      content: row['content'] as String? ?? '',
      createdAt: created,
      messageType: row['message_type'] as String? ?? 'text',
      deliveryStatus: deliveryStatus,
    );
  }

  Future<void> _cacheMessages(List<dynamic> rows) async {
    if (rows.isEmpty) return;
    final mapped = rows.map((messageData) {
      final createdAt = DateTime.tryParse(
            messageData['created_at'] as String? ?? '',
          ) ??
          DateTime.now();
      return {
        'id': messageData['id'] as String,
        'conversation_id': messageData['conversation_id'] as String,
        'sender_id': messageData['sender_id'] as String,
        'receiver_id': null,
        'content': messageData['content'] as String? ?? '',
        'created_at': createdAt.millisecondsSinceEpoch,
        'status': 'sent',
        'is_deleted': 0,
        'is_local_only': 0,
      };
    }).toList();

    await _localDb.upsertMessages(mapped);
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
              await _cacheMessages([payload.newRecord]);
              final userData = await supabase
                  .from('users')
                  .select('alias, display_name, profile_image_url')
                  .eq('id', senderId)
                  .single();

              if (mounted) {
                final parsed = _parseMessage({
                  ...payload.newRecord,
                  'sender_alias': userData['alias'],
                  'sender_display_name': userData['display_name'],
                  'sender_profile_image_url': userData['profile_image_url'],
                });
                setState(() {
                  final existingIndex =
                      _messages.indexWhere((m) => m.id == parsed.id);
                  if (existingIndex != -1) {
                    _messages[existingIndex] = parsed;
                  } else if (senderId == currentUser.id) {
                    final optimisticIndex = _messages.indexWhere((m) =>
                        m.id.startsWith('local_') &&
                        m.senderId == senderId &&
                        m.content == parsed.content &&
                        m.replyToId == parsed.replyToId &&
                        m.deliveryStatus != MessageDeliveryStatus.sent &&
                        m.createdAt
                                .difference(parsed.createdAt)
                                .inSeconds
                                .abs() <=
                            3600);
                    if (optimisticIndex != -1) {
                      _pendingLocalToServer[_messages[optimisticIndex].id] =
                          parsed.id;
                      _messages[optimisticIndex] = parsed;
                    } else {
                      _messages.add(parsed);
                    }
                  } else {
                    _messages.add(parsed);
                  }
                });
                _scrollToBottom();
                if (senderId != currentUser.id) {
                  _markMessagesAsRead();
                  if (mounted) setState(() => _isOtherTyping = false);
                }
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
                  pinnedMessage: updated['pinned_message'] as String?,
                  pinnedBy: updated['pinned_by'] as String?,
                  pinnedAt: updated['pinned_at'] != null
                      ? DateTime.tryParse(updated['pinned_at'] as String)
                      : _chat.pinnedAt,
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
            backgroundColor: _kAccentRed,
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 120) {
      _loadMoreMessages();
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    if (!_chat.canSendMessages) return;

    final mentions = RegExp(r'@(\w+)')
        .allMatches(content)
        .map((m) => m.group(1)!)
        .toList();

    final optimisticId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMessage = MessageModel(
      id: optimisticId,
      conversationId: _chat.id,
      senderId: currentUser.id,
      content: content,
      createdAt: DateTime.now(),
      senderAlias: null,
      senderDisplayName: null,
      senderProfileImageUrl: null,
      replyToId: _replyingTo?.id,
      replyToContent: _replyingTo?.content,
      replyToSenderName:
          _replyingTo?.senderDisplayName ?? _replyingTo?.senderAlias,
      messageType: 'text',
      mentions: mentions,
      deliveryStatus: MessageDeliveryStatus.sending,
    );

    setState(() {
      _messages.add(optimisticMessage);
      _replyingTo = null;
      _showMentionSuggestions = false;
    });
    _messageController.clear();
    _scrollToBottom();
    _setTypingStatus(false);

    _sendMessageToBackend(
      optimisticId: optimisticId,
      content: content,
      mentions: mentions,
      replyToId: optimisticMessage.replyToId,
    );
  }

  Future<void> _sendMessageToBackend({
    required String optimisticId,
    required String content,
    required List<String> mentions,
    required String? replyToId,
  }) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    setState(() => _isSending = true);

    final isOnline = context.read<ConnectivityProvider>().isOnline;
    if (!isOnline) {
      final offlinePayload = {
        'conversation_id': _chat.id,
        'sender_id': currentUser.id,
        'content': content,
        'message_type': 'text',
        'reply_to_id': replyToId,
        'mentions': mentions,
        'created_at': DateTime.now().toIso8601String(),
      };
      await context.read<OfflineSyncService>().queueMessageInsert(offlinePayload);
      await _localDb.upsertMessages([
        {
          'id': optimisticId,
          'conversation_id': _chat.id,
          'sender_id': currentUser.id,
          'receiver_id': null,
          'content': content,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'status': 'sending',
          'is_deleted': 0,
          'is_local_only': 1,
        }
      ]);
      if (mounted) {
        setState(() => _isSending = false);
      }
      return;
    }

    try {
      await supabase.from('messages').insert({
        'conversation_id': _chat.id,
        'sender_id': currentUser.id,
        'content': content,
        'message_type': 'text',
        'reply_to_id': replyToId,
        'mentions': mentions,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == optimisticId);
        if (idx != -1) {
          _messages[idx] = _messages[idx]
              .copyWith(deliveryStatus: MessageDeliveryStatus.sent);
        }
        _isSending = false;
      });
    } catch (e, stack) {
      if (!mounted) return;
      await AppErrorHandler.report(
        error: e,
        stack: stack,
        context: 'send_message',
      );
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == optimisticId);
        if (idx != -1) {
          _messages[idx] = _messages[idx]
              .copyWith(deliveryStatus: MessageDeliveryStatus.failed);
        }
        _isSending = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.userMessage(e)),
            backgroundColor: _kAccentRed,
          ),
        );
      }
    } finally {
      if (mounted && _isSending) {
        setState(() => _isSending = false);
      }
    }
  }

  void _retrySend(MessageModel message) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == message.id);
      if (idx != -1) {
        _messages[idx] =
            _messages[idx].copyWith(deliveryStatus: MessageDeliveryStatus.sending);
      }
    });
    _sendMessageToBackend(
      optimisticId: message.id,
      content: message.content,
      mentions: message.mentions,
      replyToId: message.replyToId,
    );
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
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Message',
          style: TextStyle(color: _kTextPrimary),
        ),
        content: const Text(
          'This message will be permanently deleted.',
          style: TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: _kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: _kAccentRed, fontWeight: FontWeight.w600)),
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
            backgroundColor: _kTextPrimary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete message'),
            backgroundColor: _kAccentRed,
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
          backgroundColor: _kSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Block / Report Account',
            style: TextStyle(color: _kTextPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a reason to report (optional for block only):',
                  style: TextStyle(color: _kTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...reasons.map(
                  (reason) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: _kAccent,
                    title: Text(
                      reason,
                      style: const TextStyle(
                          color: _kTextPrimary, fontSize: 14),
                    ),
                    value: reason,
                    groupValue: selectedReason,
                    onChanged: (v) => setDialogState(() => selectedReason = v),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: _kTextPrimary),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Additional details (optional)',
                    hintStyle: const TextStyle(color: _kTextSecondary),
                    filled: true,
                    fillColor: const Color(0xFF1A1D22),
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
                style: TextStyle(color: _kTextSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _blockUser(blockerId: currentUser.id, blockedId: otherUserId);
              },
              child: const Text(
                'Block Only',
                style: TextStyle(color: _kAccentRed),
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
                      ? _kTextSecondary
                      : _kAccent,
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
            backgroundColor: _kTextPrimary,
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
            backgroundColor: _kAccentRed,
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
            backgroundColor: _kTextPrimary,
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
            backgroundColor: _kAccentRed,
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
      color: _kSurface,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: _kAccent,
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
                    color: _kAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _replyingTo!.content,
                  style: const TextStyle(
                    color: _kTextSecondary,
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
                color: _kTextSecondary, size: 18),
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
      color: _kSurface,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorder)),
        ),
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
                    isAll ? _kAccent : const Color(0xFF1A1D22),
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
                style: const TextStyle(color: _kTextPrimary, fontSize: 13),
              ),
              subtitle: isAll
                  ? null
                  : Text(
                      '@${member['alias']}',
                      style: const TextStyle(
                          color: _kTextSecondary, fontSize: 11),
                    ),
              onTap: () => _insertMention(member),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final isLocked = !_chat.canSendMessages;
    final hasText = _messageController.text.trim().isNotEmpty;

    return Column(
      children: [
        _buildReplyBanner(),
        _buildMentionSuggestions(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: _kSurface,
            border: Border(top: BorderSide(color: _kBorder)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D22),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _kBorder),
                    ),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      enabled: !isLocked,
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        hintText: isLocked
                            ? 'Only admins can message...'
                            : 'Message...',
                        hintStyle: const TextStyle(color: _kTextSecondary),
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
                GestureDetector(
                  onTap: isLocked || !hasText ? null : _sendMessage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? const Color(0xFF1A1D22)
                          : hasText
                              ? _kAccent
                              : const Color(0xFF1F2226),
                      shape: BoxShape.circle,
                    ),
                    child: isLocked
                        ? const Icon(Icons.lock,
                            color: _kTextSecondary, size: 20)
                        : _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(Icons.send,
                                color: hasText
                                    ? Colors.white
                                    : _kTextSecondary,
                                size: 20),
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
      return _buildMessageSkeleton();
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Error loading messages',
                style: TextStyle(color: _kTextPrimary, fontSize: 18)),
            const SizedBox(height: 8),
            Text(_error!,
                style:
                    const TextStyle(color: _kTextSecondary, fontSize: 14)),
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
                size: 64, color: _kTextSecondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text('No messages yet',
                style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Start the conversation!',
                style:
                    TextStyle(color: _kTextSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    final currentUserId = supabase.auth.currentUser?.id;
    final itemCount = _messages.length + (_isOtherTyping ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_isOtherTyping && index == itemCount - 1) {
          return _buildTypingIndicator();
        }
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
          onRetry: _retrySend,
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
          color: const Color(0xFF1A1D22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: const Text(
            'Typing…',
            style: TextStyle(color: _kTextSecondary, fontSize: 12.5),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      itemCount: 10,
      itemBuilder: (context, index) {
        final isMe = index.isEven;
        final width = isMe ? 180.0 : 220.0;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            width: width,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D22),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresenceStatus() {
    if (_chat.isGroup) {
      final onlineCount = _onlineUserIds.length;
      if (onlineCount == 0) return const SizedBox.shrink();
      return Text(
        '$onlineCount online',
        style: const TextStyle(color: _kTextSecondary, fontSize: 12),
      );
    }

    final otherId = _chat.otherUserId;
    if (otherId == null) return const SizedBox.shrink();
    final isOnline = _onlineUserIds.contains(otherId);
    return Text(
      isOnline ? 'Online' : 'Offline',
      style: TextStyle(
        color: isOnline ? _kAccent : _kTextSecondary,
        fontSize: 12,
      ),
    );
  }

  void _showDmOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
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
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              _DmMenuTile(
                icon: Icons.info_outline,
                label: 'About',
                color: _kTextPrimary,
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
                color: _kTextPrimary,
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
          backgroundColor: _kSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Block / Report Account',
              style: TextStyle(color: _kTextPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a reason to report (optional for block only):',
                  style: TextStyle(color: _kTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...reasons.map((reason) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: _kAccent,
                      title: Text(reason,
                          style: const TextStyle(
                              color: _kTextPrimary, fontSize: 14)),
                      value: reason,
                      groupValue: selectedReason,
                      onChanged: (v) =>
                          setDialogState(() => selectedReason = v),
                    )),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: _kTextPrimary),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Additional details (optional)',
                    hintStyle: const TextStyle(color: _kTextSecondary),
                    filled: true,
                    fillColor: const Color(0xFF1A1D22),
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
                  style: TextStyle(color: _kTextSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _blockUser(blockerId: currentUserId, blockedId: otherUserId);
              },
              child: const Text('Block Only',
                  style: TextStyle(color: _kAccentRed)),
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
                      ? _kTextSecondary
                      : _kAccent,
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
      backgroundColor: _kSurface,
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
              color: _kBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.group, color: _kTextPrimary),
            title: const Text('Group Info',
                style: TextStyle(color: _kTextPrimary)),
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
                color: _kTextPrimary,
              ),
              title: Text(
                _chat.isLocked ? 'Unlock Group' : 'Lock Group',
                style: const TextStyle(color: _kTextPrimary),
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
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF1A1D22),
              backgroundImage: _chat.displayImageUrl != null
                  ? NetworkImage(_chat.displayImageUrl!)
                  : null,
              child: _chat.displayImageUrl == null
                  ? Icon(
                      _chat.isGroup ? Icons.group : Icons.person,
                      color: _kTextSecondary,
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
                            color: _kTextPrimary,
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
                            color: _kTextSecondary, size: 14),
                      ],
                    ],
                  ),
                  _buildPresenceStatus(),
                  if (_chat.isGroup)
                    Text(
                      '${_chat.participantIds.length} members',
                      style: const TextStyle(
                        color: _kTextSecondary,
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
            icon: const Icon(Icons.more_vert, color: _kTextPrimary),
            // Only group chats use the options menu for now
            onPressed: _chat.isGroup ? _showGroupOptions : _showDmOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_chat.isGroup &&
              _chat.pinnedMessage != null &&
              _chat.pinnedMessage!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: _kSurface,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _kBorder)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.push_pin, color: _kAccentBlue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _chat.pinnedMessage!,
                      style: const TextStyle(
                          color: _kTextPrimary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
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
    _presenceChannel?.unsubscribe();
    _typingDebounce?.cancel();
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
          color: _kChatSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kChatBorder),
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
