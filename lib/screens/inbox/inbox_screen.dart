import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../models/chat_model.dart';
import '../../utils/app_error_handler.dart';
import '../../widgets/chat_list_item.dart';
import '../../widgets/inbox_skeleton_loader.dart';
import '../../main.dart';
import 'conversation_screen.dart';
import 'user_search_screen.dart';
import 'group_creation_screen.dart';
import 'qa_screen.dart';
import '../post/post_detail_screen.dart';
import '../../services/feed_cache_service.dart';
import '../../services/notification_service.dart';

// ─────────────────────────── Notification model ───────────────────────────
class _NotifItem {
  final String id;
  final String type; // 'follow','like','comment','repost'
  final String actorId;
  final String actorAlias;
  final String? actorDisplayName;
  final String? actorImageUrl;
  final String? postId;
  final String? commentText;
  final DateTime createdAt;
  final bool isRead;

  _NotifItem({
    required this.id,
    required this.type,
    required this.actorId,
    required this.actorAlias,
    this.actorDisplayName,
    this.actorImageUrl,
    this.postId,
    this.commentText,
    required this.createdAt,
    required this.isRead,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'actorId': actorId,
        'actorAlias': actorAlias,
        'actorDisplayName': actorDisplayName,
        'actorImageUrl': actorImageUrl,
        'postId': postId,
        'commentText': commentText,
        'createdAt': createdAt.toIso8601String(),
        'isRead': isRead,
      };

  factory _NotifItem.fromMap(Map<String, dynamic> m) => _NotifItem(
        id: m['id'] as String,
        type: m['type'] as String,
        actorId: m['actorId'] as String,
        actorAlias: m['actorAlias'] as String? ?? '',
        actorDisplayName: m['actorDisplayName'] as String?,
        actorImageUrl: m['actorImageUrl'] as String?,
        postId: m['postId'] as String?,
        commentText: m['commentText'] as String?,
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
            DateTime.now(),
        isRead: m['isRead'] as bool? ?? false,
      );
}

class _ActivityFilterItem {
  final String id;
  final String label;
  final IconData icon;

  const _ActivityFilterItem(this.id, this.label, this.icon);
}

// ─────────────────────────────── InboxScreen ──────────────────────────────
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  // ── conversations
  final List<ChatModel> _conversations = [];
  bool _convLoading = true;
  String? _convError;
  RealtimeChannel? _conversationSubscription;

  // ── notifications
  List<_NotifItem> _notifications = [];
  bool _notifLoading = true;
  final Set<String> _followingIds = {};
  final Set<String> _followInFlight = {};
  int _unreadNotifCount = 0;
  bool _activityDot = false;
  bool _qaDot = false;
  bool _directCleared = false;
  bool _groupCleared = false;
  String _activityFilter = 'all';

  late TabController _tabController;
  final FeedCacheService _cache = FeedCacheService();
  bool _isVerified = false;

  List<ChatModel> get _directChats =>
      _conversations.where((c) => !c.isGroup).toList();
  List<ChatModel> get _groupChats =>
      _conversations.where((c) => c.isGroup).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _loadFromCacheThenNetwork();
    _subscribeToConversations();
    _checkVerification();
  }

  Future<void> _checkVerification() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('users')
          .select('is_verified, role')
          .eq('id', user.id)
          .single();
      if (mounted) {
        setState(() {
          _isVerified = (res['is_verified'] == true) ||
              (res['role'] == 'admin') ||
              (res['role'] == 'premium');
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFromCacheThenNetwork() async {
    // 1) Instantly load cached notifications
    final cachedNotifs = _cache.getNotifications();
    if (cachedNotifs != null && cachedNotifs.isNotEmpty && mounted) {
      final notifs = cachedNotifs.map((m) => _NotifItem.fromMap(m)).toList();
      setState(() {
        _notifications = notifs;
        _unreadNotifCount = notifs.where((n) => !n.isRead).length;
        _notifLoading = false;
      });
    }

    // 2) Load cached following IDs
    final cachedFollowing = _cache.getFollowingIds();
    if (cachedFollowing != null) {
      _followingIds.addAll(cachedFollowing);
    }

    // 3) Load cached conversations
    final cachedConvos = _cache.getConversations();
    if (cachedConvos != null && cachedConvos.isNotEmpty && mounted) {
      final convos = cachedConvos.map((m) => ChatModel.fromJson(m)).toList();
      setState(() {
        _conversations
          ..clear()
          ..addAll(convos);
        _convLoading = false;
      });
    }

    // 4) Refresh from network
    _loadConversations();
    _loadNotifications();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    switch (_tabController.index) {
      case 0:
        _markActivitySeen();
        break;
      case 1:
        _markDmSeen();
        break;
      case 2:
        _markGroupSeen();
        break;
      case 3:
        _markQaSeen();
        break;
    }
  }

  Future<void> _markActivitySeen() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;
    try {
      await supabase.from('users').update({
        'last_activity_seen_at': DateTime.now().toIso8601String(),
      }).eq('id', me.id);
      if (mounted) {
        setState(() => _activityDot = false);
      }
    } catch (_) {}
  }

  Future<void> _markDmSeen() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;
    try {
      await supabase.from('users').update({
        'last_dm_seen_at': DateTime.now().toIso8601String(),
      }).eq('id', me.id);
      if (mounted) {
        setState(() => _directCleared = true);
      }
    } catch (_) {}
  }

  Future<void> _markGroupSeen() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;
    try {
      await supabase.from('users').update({
        'last_group_seen_at': DateTime.now().toIso8601String(),
      }).eq('id', me.id);
      if (mounted) {
        setState(() => _groupCleared = true);
      }
    } catch (_) {}
  }

  Future<void> _markQaSeen() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;
    try {
      await supabase.from('users').update({
        'last_qa_seen_at': DateTime.now().toIso8601String(),
      }).eq('id', me.id);
      await supabase
          .from('qa_answer_notifications')
          .update({'is_read': true})
          .eq('asker_id', me.id)
          .eq('is_read', false);
      if (mounted) {
        setState(() => _qaDot = false);
      }
    } catch (_) {}
  }

  Future<void> _refreshActivityAndQaDots() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;
    try {
      final userRes = await supabase
          .from('users')
          .select('last_activity_seen_at')
          .eq('id', me.id)
          .single();
      final lastActivityRaw = userRes['last_activity_seen_at'] as String?;
      final lastActivity = DateTime.tryParse(lastActivityRaw ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      final activityRes = await supabase
          .from('notification_events')
          .select('id')
          .eq('user_id', me.id)
          .gt('created_at', lastActivity.toIso8601String())
          .limit(1);

      final qaRes = await supabase
          .from('qa_answer_notifications')
          .select('id')
          .eq('asker_id', me.id)
          .eq('is_read', false)
          .limit(1);

      if (mounted) {
        setState(() {
          _activityDot = (activityRes as List).isNotEmpty;
          _qaDot = (qaRes as List).isNotEmpty;
        });
      }
    } catch (_) {}
  }

  // ══════════════════════════ CONVERSATIONS ══════════════════════════════

  Future<void> _loadConversations() async {
    try {
      setState(() => _convLoading = true);
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _convError = 'User not logged in';
          _convLoading = false;
        });
        return;
      }
      final response = await supabase.rpc(
        'get_user_conversations_optimized',
        params: {'user_uuid': currentUser.id},
      );
      if (mounted) {
        final List<ChatModel> loaded = [];
        for (var item in response as List) {
          try {
            List<String> participantIds = [];
            if (item['participant_ids'] != null) {
              participantIds =
                  List<String>.from(item['participant_ids'] as List);
            }
            loaded.add(ChatModel(
              id: item['conversation_id'] as String,
              name: item['conversation_name'] as String? ?? 'Unknown',
              isGroup: item['is_group'] as bool? ?? false,
              lastMessageContent: item['last_message_content'] as String?,
              lastMessageSenderName:
                  item['last_message_sender_name'] as String?,
              lastMessageTime: item['last_message_time'] != null
                  ? DateTime.parse(item['last_message_time'] as String)
                  : null,
              unreadCount: (item['unread_count'] as num?)?.toInt() ?? 0,
              otherUserId: item['other_user_id'] as String?,
              otherUserAlias: item['other_user_alias'] as String?,
              otherUserDisplayName: item['other_user_display_name'] as String?,
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
            debugPrint('Error parsing conversation: $e');
          }
        }
        setState(() {
          _conversations
            ..clear()
            ..addAll(loaded);
          _convLoading = false;
          _convError = null;
        });
        _cache.saveConversations(loaded.map((c) => c.toJson()).toList());
      }
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      if (mounted) {
        setState(() {
          _convError = AppErrorHandler.userMessage(e);
          _convLoading = false;
        });
      }
    }
  }

  void _updateConversationWithNewMessage(Map<String, dynamic> messageData) {
    final conversationId = messageData['conversation_id'] as String?;
    final senderId = messageData['sender_id'] as String?;
    final content = messageData['content'] as String? ?? '';
    final createdAt = messageData['created_at'] as String?;
    if (conversationId == null || createdAt == null) return;

    final currentUserId = supabase.auth.currentUser?.id;
    final isFromCurrentUser = senderId == currentUserId;
    final messageTime = DateTime.tryParse(createdAt) ?? DateTime.now();

    setState(() {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        final existing = _conversations[index];
        if (!isFromCurrentUser) {
          if (existing.isGroup) {
            _groupCleared = false;
          } else {
            _directCleared = false;
          }
        }
        final updated = existing.copyWith(
          lastMessageContent: content,
          lastMessageTime: messageTime,
          lastMessageSenderName:
              isFromCurrentUser ? 'You' : existing.lastMessageSenderName,
          unreadCount: isFromCurrentUser
              ? existing.unreadCount
              : existing.unreadCount + 1,
        );
        _conversations.removeAt(index);
        _conversations.insert(0, updated);
      } else {
        _silentReload();
      }
    });
  }

  Future<void> _silentReload() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;
      final response = await supabase.rpc(
        'get_user_conversations_optimized',
        params: {'user_uuid': currentUser.id},
      );
      if (mounted) {
        final List<ChatModel> loaded = [];
        for (var item in response as List) {
          try {
            List<String> participantIds = [];
            if (item['participant_ids'] != null) {
              participantIds =
                  List<String>.from(item['participant_ids'] as List);
            }
            loaded.add(ChatModel(
              id: item['conversation_id'] as String,
              name: item['conversation_name'] as String? ?? 'Unknown',
              isGroup: item['is_group'] as bool? ?? false,
              lastMessageContent: item['last_message_content'] as String?,
              lastMessageSenderName:
                  item['last_message_sender_name'] as String?,
              lastMessageTime: item['last_message_time'] != null
                  ? DateTime.parse(item['last_message_time'] as String)
                  : null,
              unreadCount: (item['unread_count'] as num?)?.toInt() ?? 0,
              otherUserId: item['other_user_id'] as String?,
              otherUserAlias: item['other_user_alias'] as String?,
              otherUserDisplayName: item['other_user_display_name'] as String?,
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
            debugPrint('Error parsing conversation: $e');
          }
        }
        setState(() {
          _conversations
            ..clear()
            ..addAll(loaded);
        });
        _cache.saveConversations(loaded.map((c) => c.toJson()).toList());
      }
    } catch (e) {
      debugPrint('Silent reload error: $e');
    }
  }

  void _subscribeToConversations() {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    _conversationSubscription = supabase
        .channel('user_conversations:${currentUser.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) =>
              _updateConversationWithNewMessage(payload.newRecord),
        )
        .subscribe();
  }

  void _navigateToConversation(ChatModel chat) {
    setState(() {
      final index = _conversations.indexWhere((c) => c.id == chat.id);
      if (index != -1) {
        _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
      }
    });
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ConversationScreen(chat: chat)),
    ).then((_) => _loadConversations());
  }

  void _startNewChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UserSearchScreen()),
    ).then((_) => _silentReload());
  }

  void _createGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GroupCreationScreen()),
    ).then((_) => _silentReload());
  }

  // ══════════════════════════ NOTIFICATIONS ══════════════════════════════

  Future<void> _loadNotifications() async {
    final me = supabase.auth.currentUser;
    if (me == null) {
      setState(() => _notifLoading = false);
      return;
    }

    try {
      final notifs = <_NotifItem>[];

      // ── followers ──
      try {
        final followersRes = await supabase
            .from('follows')
            .select('''
          follower_id, created_at,
          follower:users!follows_follower_id_fkey(
            id, alias, display_name, profile_image_url
          )
        ''')
            .eq('following_id', me.id)
            .order('created_at', ascending: false)
            .limit(30);

        for (var row in followersRes as List) {
          final actor = row['follower'] as Map<String, dynamic>?;
          if (actor == null) continue;
          notifs.add(_NotifItem(
            id: 'follow_${row['follower_id']}',
            type: 'follow',
            actorId: actor['id'] as String,
            actorAlias: actor['alias'] as String? ?? '',
            actorDisplayName: actor['display_name'] as String?,
            actorImageUrl: actor['profile_image_url'] as String?,
            createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            isRead: false,
          ));
        }
      } catch (e) {
        debugPrint('followers load error: $e');
      }

      // ── likes on my posts ──
      try {
        final likesRes = await supabase
            .from('likes')
            .select('''
          id, created_at, post_id,
          liker:users!likes_user_id_fkey(
            id, alias, display_name, profile_image_url
          )
        ''')
            .inFilter(
                'post_id',
                (await supabase.from('posts').select('id').eq('user_id', me.id))
                        is List
                    ? ((await supabase
                            .from('posts')
                            .select('id')
                            .eq('user_id', me.id)) as List)
                        .map((p) => p['id'] as String)
                        .toList()
                    : <String>[])
            .order('created_at', ascending: false)
            .limit(30);

        for (var row in likesRes as List) {
          final actor = row['liker'] as Map<String, dynamic>?;
          if (actor == null) continue;
          final actorId = actor['id'] as String;
          if (actorId == me.id) continue;
          notifs.add(_NotifItem(
            id: 'like_${row['id']}',
            type: 'like',
            actorId: actorId,
            actorAlias: actor['alias'] as String? ?? '',
            actorDisplayName: actor['display_name'] as String?,
            actorImageUrl: actor['profile_image_url'] as String?,
            postId: row['post_id'] as String?,
            createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            isRead: false,
          ));
        }
      } catch (e) {
        debugPrint('likes load error: $e');
      }

      // ── comments on my posts ──
      try {
        final myPostIds = ((await supabase
                .from('posts')
                .select('id')
                .eq('user_id', me.id)) as List)
            .map((p) => p['id'] as String)
            .toList();

        if (myPostIds.isNotEmpty) {
          final commentsRes = await supabase
              .from('comments')
              .select('''
            id, created_at, post_id, content,
            commenter:users!comments_user_id_fkey(
              id, alias, display_name, profile_image_url
            )
          ''')
              .inFilter('post_id', myPostIds)
              .order('created_at', ascending: false)
              .limit(30);

          for (var row in commentsRes as List) {
            final actor = row['commenter'] as Map<String, dynamic>?;
            if (actor == null) continue;
            final actorId = actor['id'] as String;
            if (actorId == me.id) continue;
            notifs.add(_NotifItem(
              id: 'comment_${row['id']}',
              type: 'comment',
              actorId: actorId,
              actorAlias: actor['alias'] as String? ?? '',
              actorDisplayName: actor['display_name'] as String?,
              actorImageUrl: actor['profile_image_url'] as String?,
              postId: row['post_id'] as String?,
              commentText: row['content'] as String?,
              createdAt:
                  DateTime.tryParse(row['created_at'] as String? ?? '') ??
                      DateTime.now(),
              isRead: false,
            ));
          }
        }
      } catch (e) {
        debugPrint('comments load error: $e');
      }

      // ── tagged in post ──
      try {
        final tagsRes = await supabase
            .from('post_tags')
            .select('id, post_id, created_at')
            .eq('tagged_user_id', me.id)
            .order('created_at', ascending: false)
            .limit(30);

        if ((tagsRes as List).isNotEmpty) {
          final postIds =
              (tagsRes as List).map((r) => r['post_id'] as String).toList();
          final postsRes = await supabase
              .from('posts')
              .select('id, user_id')
              .inFilter('id', postIds);
          final authorIds = (postsRes as List)
              .map((r) => r['user_id'] as String)
              .where((id) => id != me.id)
              .toSet()
              .toList();
          Map<String, Map<String, dynamic>> authorMap = {};
          if (authorIds.isNotEmpty) {
            final usersRes = await supabase
                .from('users')
                .select('id, alias, display_name, profile_image_url')
                .inFilter('id', authorIds);
            for (final u in usersRes as List) {
              authorMap[u['id'] as String] = u;
            }
          }
          final postToAuthor = <String, String>{};
          for (final p in postsRes as List) {
            postToAuthor[p['id'] as String] = p['user_id'] as String;
          }
          for (final row in tagsRes) {
            final postId = row['post_id'] as String;
            final authorId = postToAuthor[postId];
            if (authorId == null || authorId == me.id) continue;
            final author = authorMap[authorId];
            if (author == null) continue;
            notifs.add(_NotifItem(
              id: 'tag_${row['id']}',
              type: 'tag',
              actorId: authorId,
              actorAlias: author['alias'] as String? ?? '',
              actorDisplayName: author['display_name'] as String?,
              actorImageUrl: author['profile_image_url'] as String?,
              postId: postId,
              createdAt:
                  DateTime.tryParse(row['created_at'] as String? ?? '') ??
                      DateTime.now(),
              isRead: false,
            ));
          }
        }
      } catch (e) {
        debugPrint('post_tags load error: $e');
      }

      // Sort by newest first
      notifs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Load who I'm already following
      try {
        final followingRes = await supabase
            .from('follows')
            .select('following_id')
            .eq('follower_id', me.id);
        _followingIds.clear();
        _followingIds.addAll(
            (followingRes as List).map((r) => r['following_id'] as String));
      } catch (_) {}

      if (mounted) {
        setState(() {
          _notifications = notifs;
          _unreadNotifCount = notifs.where((n) => !n.isRead).length;
          _notifLoading = false;
        });

        // Save to cache for next time
        _cache.saveNotifications(notifs.map((n) => n.toMap()).toList());
        _cache.saveFollowingIds(_followingIds.toList());
        _refreshActivityAndQaDots();
      }
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted) setState(() => _notifLoading = false);
    }
  }

  Future<void> _toggleFollow(String targetId) async {
    final me = supabase.auth.currentUser;
    if (me == null || _followInFlight.contains(targetId)) return;

    _followInFlight.add(targetId);
    final isFollowing = _followingIds.contains(targetId);

    setState(() {
      if (isFollowing) {
        _followingIds.remove(targetId);
      } else {
        _followingIds.add(targetId);
      }
    });

    try {
      if (isFollowing) {
        await supabase
            .from('follows')
            .delete()
            .eq('follower_id', me.id)
            .eq('following_id', targetId);
        try {
          await NotificationService()
              .unsubscribeFromFollowersTopic(targetId);
        } catch (e) {
          debugPrint(
              'Failed to unsubscribe from followers topic for $targetId: $e');
        }
      } else {
        await supabase.from('follows').insert({
          'follower_id': me.id,
          'following_id': targetId,
        });
        try {
          await NotificationService().subscribeToFollowersTopic(targetId);
        } catch (e) {
          debugPrint(
              'Failed to subscribe to followers topic for $targetId: $e');
        }
      }
    } catch (e) {
      debugPrint('follow toggle error: $e');
      // revert
      setState(() {
        if (isFollowing) {
          _followingIds.add(targetId);
        } else {
          _followingIds.remove(targetId);
        }
      });
    } finally {
      _followInFlight.remove(targetId);
    }
  }

  // ══════════════════════════════ UI HELPERS ══════════════════════════════

  // ── Minimal light palette ──
  static const _kBg = Color(0xFF000000);
  static const _kSurface = Color(0xFF0B0B0D);
  static const _kBorder = Color(0xFF1F2226);
  static const _kTextPrimary = Color(0xFFFFFFFF);
  static const _kTextSecondary = Color(0xFF9AA0A6);
  static const _kAccent = Color(0xFF1E88E5);
  static const _kAccentBlue = Color(0xFF1E88E5);
  static const _kAccentOrange = Color(0xFFF97316);
  static const _kAccentRed = Color(0xFFFF4D4F);

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  Widget _buildAvatar(String? url, {double radius = 22}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kSurface,
        border: Border.all(color: _kBorder),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: _kSurface,
        backgroundImage: url != null ? NetworkImage(url) : null,
        child: url == null
            ? Icon(Icons.person_rounded,
                color: _kTextSecondary, size: radius * 0.9)
            : null,
      ),
    );
  }

  Widget _notifIcon(_NotifItem n) {
    late IconData icon;
    late Color bgColor;
    switch (n.type) {
      case 'follow':
        icon = Icons.person_add_rounded;
        bgColor = _kAccentBlue.withOpacity(0.12);
        break;
      case 'like':
        icon = Icons.favorite_rounded;
        bgColor = _kAccentRed.withOpacity(0.12);
        break;
      case 'comment':
        icon = Icons.chat_bubble_rounded;
        bgColor = _kAccent.withOpacity(0.12);
        break;
      case 'tag':
        icon = Icons.alternate_email_rounded;
        bgColor = _kAccentBlue.withOpacity(0.12);
        break;
      case 'repost':
        icon = Icons.repeat_rounded;
        bgColor = _kAccentOrange.withOpacity(0.14);
        break;
      default:
        icon = Icons.notifications_rounded;
        bgColor = _kBorder;
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 12, color: _kTextPrimary),
    );
  }

  String _notifBody(_NotifItem n) {
    final name = n.actorDisplayName ?? '@${n.actorAlias}';
    switch (n.type) {
      case 'follow':
        return '$name started following you';
      case 'like':
        return '$name liked your post';
      case 'comment':
        return '$name commented: "${n.commentText ?? ''}"';
      case 'tag':
        return '$name tagged you in a post';
      case 'repost':
        return '$name reposted your post';
      default:
        return '$name interacted with you';
    }
  }

  Widget _buildFollowButton(String targetId) {
    final isFollowing = _followingIds.contains(targetId);
    final inFlight = _followInFlight.contains(targetId);
    return GestureDetector(
      onTap: inFlight ? null : () => _toggleFollow(targetId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isFollowing ? _kSurface : _kAccent,
          border: Border.all(color: isFollowing ? _kBorder : _kAccent),
          borderRadius: BorderRadius.circular(16),
        ),
        child: inFlight
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Colors.white),
              )
            : Text(
                isFollowing ? 'Following' : 'Follow',
                style: TextStyle(
                  color: isFollowing ? _kTextSecondary : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildNotifTile(_NotifItem n) {
    final isFollow = n.type == 'follow';
    return GestureDetector(
      onTap: () {
        if ((n.type == 'like' ||
                n.type == 'comment' ||
                n.type == 'tag' ||
                n.type == 'repost') &&
            n.postId != null &&
            n.postId!.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PostDetailScreen(postId: n.postId!),
            ),
          );
        } else if (n.actorId.isNotEmpty) {
          Navigator.pushNamed(context, '/profile', arguments: n.actorId);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: n.isRead ? _kBorder : _kAccent.withOpacity(0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar with type badge
            Stack(
              children: [
                _buildAvatar(n.actorImageUrl, radius: 24),
                Positioned(
                  bottom: -1,
                  right: -1,
                  child: _notifIcon(n),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _notifBody(n),
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(n.createdAt),
                    style: TextStyle(
                      color: _kTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Follow button for follow type; else chevron
            if (isFollow)
              _buildFollowButton(n.actorId)
            else
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: Icon(Icons.chevron_right_rounded,
                    color: _kTextSecondary,
                    size: 18),
              ),
          ],
        ),
      ),
    );
  }

  // ── Notifications tab ──
  Widget _buildNotificationsTab() {
    if (_notifLoading) {
      return const InboxSkeletonLoader(
        variant: InboxSkeletonVariant.notification,
        itemCount: 8,
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Gradient icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kSurface,
                border: Border.all(color: _kBorder),
              ),
              child: Icon(Icons.notifications_none_rounded,
                  size: 40, color: _kTextSecondary),
            ),
            const SizedBox(height: 20),
            const Text(
              'No activity yet',
              style: TextStyle(
                color: _kTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When people follow, like, or comment\non your posts, you\'ll see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kTextSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final followers = _notifications.where((n) => n.type == 'follow').toList();
    final likes = _notifications.where((n) => n.type == 'like').toList();
    final comments = _notifications.where((n) => n.type == 'comment').toList();
    final tags = _notifications.where((n) => n.type == 'tag').toList();
    final filtered = _filterActivityNotifs(
      followers: followers,
      likes: likes,
      comments: comments,
      tags: tags,
    );

    final counts = <String, int>{
      'all': _notifications.length,
      'like': likes.length,
      'comment': comments.length,
      'tag': tags.length,
      'follow': followers.length,
    };

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: _kAccent,
      backgroundColor: _kSurface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        children: [
          _buildActivityFilters(counts),
          const SizedBox(height: 8),
          if (filtered.isEmpty) _buildEmptyActivityState(),
          for (final item in filtered) _buildNotifTile(item),
        ],
      ),
    );
  }

  List<_NotifItem> _filterActivityNotifs({
    required List<_NotifItem> followers,
    required List<_NotifItem> likes,
    required List<_NotifItem> comments,
    required List<_NotifItem> tags,
  }) {
    switch (_activityFilter) {
      case 'like':
        return likes;
      case 'comment':
        return comments;
      case 'tag':
        return tags;
      case 'follow':
        return followers;
      default:
        return _notifications;
    }
  }

  Widget _buildActivityFilters(Map<String, int> counts) {
    final items = [
      const _ActivityFilterItem('all', 'All', Icons.all_inbox_rounded),
      const _ActivityFilterItem('like', 'Likes', Icons.favorite_rounded),
      const _ActivityFilterItem(
          'comment', 'Comments', Icons.chat_bubble_rounded),
      const _ActivityFilterItem('tag', 'Mentions', Icons.alternate_email_rounded),
      const _ActivityFilterItem(
          'follow', 'Followers', Icons.person_add_alt_1_rounded),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final isActive = _activityFilter == item.id;
          final count = counts[item.id] ?? 0;
          return GestureDetector(
            onTap: () {
              if (_activityFilter == item.id) return;
              setState(() => _activityFilter = item.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? _kAccent.withOpacity(0.18) : _kSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive ? _kAccent : _kBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(item.icon,
                      size: 16,
                      color: isActive ? _kAccent : _kTextSecondary),
                  const SizedBox(width: 8),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: isActive ? _kTextPrimary : _kTextSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? _kAccent
                            : _kTextSecondary.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: isActive ? Colors.white : _kTextSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyActivityState() {
    String title = 'No activity yet';
    switch (_activityFilter) {
      case 'like':
        title = 'No likes yet';
        break;
      case 'comment':
        title = 'No comments yet';
        break;
      case 'tag':
        title = 'No mentions yet';
        break;
      case 'follow':
        title = 'No followers yet';
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, color: _kTextSecondary, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You\'ll see updates here as they happen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Chat list (Direct / Groups) ──
  Widget _buildChatList(List<ChatModel> chats, String emptyMessage,
      {required IconData emptyIcon}) {
    if (_convLoading) {
      return const InboxSkeletonLoader(
        variant: InboxSkeletonVariant.chat,
        itemCount: 8,
      );
    }

    if (chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kSurface,
                border: Border.all(color: _kBorder),
              ),
              child: Icon(emptyIcon,
                  size: 36, color: _kTextSecondary),
            ),
            const SizedBox(height: 20),
            Text(
              emptyMessage,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation to see it here',
              style: TextStyle(
                color: _kTextSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      color: _kAccent,
      backgroundColor: _kSurface,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        itemCount: chats.length,
        itemBuilder: (context, index) {
          final chat = chats[index];
          return ChatListItem(
            chat: chat,
            onTap: () => _navigateToConversation(chat),
          );
        },
      ),
    );
  }

  // ════════════════════════════════ BUILD ════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final directUnread = _directChats.fold(0, (sum, c) => sum + c.unreadCount);
    final groupUnread = _groupChats.fold(0, (sum, c) => sum + c.unreadCount);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _kTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Inbox',
          style: TextStyle(
            color: _kTextPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded,
                color: _kTextPrimary),
            onPressed: () {
              final currentUser = supabase.auth.currentUser;
              if (currentUser != null && currentUser.id.isNotEmpty) {
                Navigator.pushNamed(context, '/profile',
                    arguments: currentUser.id);
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _buildPremiumTabBar(directUnread, groupUnread),
        ),
      ),
      body: _convError != null && _tabController.index != 0
          ? _buildErrorState()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildNotificationsTab(),
                _buildChatList(_directChats, 'No direct messages',
                    emptyIcon: Icons.chat_bubble_outline_rounded),
                _buildChatList(_groupChats, 'No groups yet',
                    emptyIcon: Icons.groups_outlined),
                QaScreen(
                  currentUserId: supabase.auth.currentUser?.id ?? '',
                  isVerified: _isVerified,
                ),
              ],
            ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabController,
        builder: (_, __) {
          if (_tabController.index == 0) return const SizedBox.shrink();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Create group FAB
              FloatingActionButton(
                heroTag: 'create_group',
                onPressed: _createGroup,
                backgroundColor: _kSurface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: _kBorder),
                ),
                child: const Icon(Icons.group_add_rounded,
                    color: _kTextPrimary, size: 22),
              ),
              const SizedBox(height: 12),
              // New chat FAB
              FloatingActionButton(
                heroTag: 'new_chat',
                onPressed: _startNewChat,
                backgroundColor: _kAccent,
                elevation: 0,
                child: const Icon(Icons.edit_rounded,
                    color: Colors.white, size: 24),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Premium pill-style tab bar ──
  Widget _buildPremiumTabBar(int directUnread, int groupUnread) {
    final showDirectDot = directUnread > 0 && !_directCleared;
    final showGroupDot = groupUnread > 0 && !_groupCleared;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: _kAccent,
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: _kTextPrimary,
        unselectedLabelColor: _kTextSecondary,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        labelStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          _buildPremiumTab(
            icon: Icons.notifications_rounded,
            label: 'Activity',
            showDot: _activityDot,
            dotColor: _kAccentRed,
          ),
          _buildPremiumTab(
            icon: Icons.chat_bubble_rounded,
            label: 'Direct',
            showDot: showDirectDot,
            dotColor: _kAccent,
          ),
          _buildPremiumTab(
            icon: Icons.groups_rounded,
            label: 'Groups',
            showDot: showGroupDot,
            dotColor: _kAccentBlue,
          ),
          _buildPremiumTab(
            icon: Icons.inventory_2_rounded,
            label: 'Q&A',
            showDot: _qaDot,
            dotColor: _kAccentOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumTab({
    required IconData icon,
    required String label,
    required bool showDot,
    required Color dotColor,
  }) {
    return Tab(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (showDot) ...[
            const SizedBox(width: 5),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Error state ──
  Widget _buildErrorState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kAccentRed.withOpacity(0.12),
              ),
              child: Icon(Icons.wifi_off_rounded,
                  size: 28, color: _kAccentRed.withOpacity(0.7)),
            ),
            const SizedBox(height: 18),
            const Text(
              'Connection Error',
              style: TextStyle(
                color: _kTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _convError ?? 'Could not load conversations',
              style: TextStyle(
                color: _kTextSecondary,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _loadConversations,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: _kAccent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _conversationSubscription?.unsubscribe();
    super.dispose();
  }
}
