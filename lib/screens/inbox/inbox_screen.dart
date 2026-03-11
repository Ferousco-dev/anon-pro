import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:ui';
import '../../models/chat_model.dart';
import '../../utils/constants.dart';
import '../../widgets/chat_list_item.dart';
import '../../widgets/inbox_skeleton_loader.dart';
import '../../main.dart';
import 'conversation_screen.dart';
import 'user_search_screen.dart';
import 'group_creation_screen.dart';
import 'qa_screen.dart';
import '../post/post_detail_screen.dart';
import '../../services/feed_cache_service.dart';

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

    // 3) Refresh from network
    _loadConversations();
    _loadNotifications();
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
      }
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      if (mounted) {
        setState(() {
          _convError = e.toString();
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
        final updated = existing.copyWith(
          lastMessageContent: content,
          lastMessageTime: messageTime,
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
      } else {
        await supabase.from('follows').insert({
          'follower_id': me.id,
          'following_id': targetId,
        });
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

  // ── Accent colors for the premium palette ──
  static const _kBgDark = Color(0xFF000000);
  static const _kSurface = Color(0xFF0A0A0A);
  static const _kCardBg = Color(0xFF121212);
  static const _kAccentBlue = Color(0xFF007AFF);
  static const _kAccentPurple = Color(0xFF5856D6);
  static const _kAccentGreen = Color(0xFF34C759);
  static const _kAccentPink = Color(0xFFFF375F);

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
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            _kAccentBlue.withOpacity(0.5),
            _kAccentPurple.withOpacity(0.3),
          ],
        ),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: _kCardBg,
        backgroundImage: url != null ? NetworkImage(url) : null,
        child: url == null
            ? Icon(Icons.person_rounded,
                color: AppConstants.textSecondary, size: radius * 0.9)
            : null,
      ),
    );
  }

  Widget _notifIcon(_NotifItem n) {
    late IconData icon;
    late List<Color> gradColors;
    switch (n.type) {
      case 'follow':
        icon = Icons.person_add_rounded;
        gradColors = [_kAccentBlue, _kAccentPurple];
        break;
      case 'like':
        icon = Icons.favorite_rounded;
        gradColors = [_kAccentPink, const Color(0xFFFF6B8A)];
        break;
      case 'comment':
        icon = Icons.chat_bubble_rounded;
        gradColors = [_kAccentGreen, const Color(0xFF38EF7D)];
        break;
      case 'tag':
        icon = Icons.alternate_email_rounded;
        gradColors = [_kAccentBlue, const Color(0xFF00C6FF)];
        break;
      case 'repost':
        icon = Icons.repeat_rounded;
        gradColors = [AppConstants.orange, const Color(0xFFFFBF00)];
        break;
      default:
        icon = Icons.notifications_rounded;
        gradColors = [AppConstants.textSecondary, AppConstants.textTertiary];
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradColors),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: gradColors.first.withOpacity(0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 12, color: Colors.white),
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
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: isFollowing
              ? null
              : const LinearGradient(
                  colors: [_kAccentBlue, _kAccentPurple],
                ),
          color: isFollowing ? Colors.transparent : null,
          border: Border.all(
            color: isFollowing
                ? AppConstants.textSecondary.withOpacity(0.3)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isFollowing
              ? []
              : [
                  BoxShadow(
                    color: _kAccentBlue.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
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
                  color: isFollowing
                      ? AppConstants.textSecondary
                      : AppConstants.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              n.isRead ? _kSurface.withOpacity(0.5) : _kCardBg.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: n.isRead
                ? Colors.white.withOpacity(0.03)
                : _kAccentBlue.withOpacity(0.12),
          ),
          boxShadow: n.isRead
              ? []
              : [
                  BoxShadow(
                    color: _kAccentBlue.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
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
                      color: n.isRead
                          ? AppConstants.white.withOpacity(0.7)
                          : AppConstants.white,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(n.createdAt),
                    style: TextStyle(
                      color: AppConstants.textSecondary.withOpacity(0.6),
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
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
                child: Icon(Icons.chevron_right_rounded,
                    color: AppConstants.textSecondary.withOpacity(0.5),
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
                gradient: LinearGradient(
                  colors: [
                    _kAccentBlue.withOpacity(0.15),
                    _kAccentPurple.withOpacity(0.1),
                  ],
                ),
              ),
              child: Icon(Icons.notifications_none_rounded,
                  size: 40, color: _kAccentBlue.withOpacity(0.5)),
            ),
            const SizedBox(height: 20),
            const Text(
              'No activity yet',
              style: TextStyle(
                color: AppConstants.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When people follow, like, or comment\non your posts, you\'ll see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppConstants.textSecondary.withOpacity(0.6),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    // Group by type for sections
    final followers = _notifications.where((n) => n.type == 'follow').toList();
    final likes = _notifications.where((n) => n.type == 'like').toList();
    final comments = _notifications.where((n) => n.type == 'comment').toList();
    final tags = _notifications.where((n) => n.type == 'tag').toList();
    final others = _notifications
        .where((n) =>
            n.type != 'follow' &&
            n.type != 'like' &&
            n.type != 'comment' &&
            n.type != 'tag')
        .toList();

    final sections = <String, List<_NotifItem>>{
      if (followers.isNotEmpty) 'New Followers': followers,
      if (likes.isNotEmpty) 'Likes': likes,
      if (comments.isNotEmpty) 'Comments': comments,
      if (tags.isNotEmpty) 'Mentions': tags,
      if (others.isNotEmpty) 'Activity': others,
    };

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: _kAccentBlue,
      backgroundColor: _kSurface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        children: [
          for (final entry in sections.entries) ...[
            _buildSectionHeader(entry.key, entry.value.length),
            ...entry.value.map(_buildNotifTile),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Row(
        children: [
          // Gradient accent bar
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kAccentBlue, _kAccentPurple],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppConstants.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _kAccentBlue.withOpacity(0.2),
                  _kAccentPurple.withOpacity(0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: _kAccentBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
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
                gradient: LinearGradient(
                  colors: [
                    _kAccentBlue.withOpacity(0.12),
                    _kAccentPurple.withOpacity(0.08),
                  ],
                ),
              ),
              child: Icon(emptyIcon,
                  size: 36, color: _kAccentBlue.withOpacity(0.5)),
            ),
            const SizedBox(height: 20),
            Text(
              emptyMessage,
              style: const TextStyle(
                color: AppConstants.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation to see it here',
              style: TextStyle(
                color: AppConstants.textSecondary.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      color: _kAccentBlue,
      backgroundColor: _kSurface,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 100),
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
      backgroundColor: _kBgDark,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(120),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: _kBgDark.withOpacity(0.85),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.05),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Top row: logo + actions ──
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          // Back button
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.06),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: const Icon(Icons.arrow_back_rounded,
                                  color: AppConstants.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [_kAccentBlue, _kAccentPurple],
                            ).createShader(bounds),
                            child: const Text(
                              'Inbox',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Profile button
                          GestureDetector(
                            onTap: () {
                              final currentUser = supabase.auth.currentUser;
                              if (currentUser != null &&
                                  currentUser.id.isNotEmpty) {
                                Navigator.pushNamed(context, '/profile',
                                    arguments: currentUser.id);
                              }
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.06),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: const Icon(Icons.person_outline_rounded,
                                  color: AppConstants.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Tab bar ──
                    _buildPremiumTabBar(directUnread, groupUnread),
                  ],
                ),
              ),
            ),
          ),
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
              GestureDetector(
                onTap: _createGroup,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _kCardBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.group_add_rounded,
                      color: AppConstants.white, size: 22),
                ),
              ),
              const SizedBox(height: 14),
              // New chat FAB
              GestureDetector(
                onTap: _startNewChat,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_kAccentBlue, _kAccentPurple],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccentBlue.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.edit_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Premium pill-style tab bar ──
  Widget _buildPremiumTabBar(int directUnread, int groupUnread) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _kAccentBlue.withOpacity(0.25),
              _kAccentPurple.withOpacity(0.18),
            ],
          ),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _kAccentBlue.withOpacity(0.2)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppConstants.white,
        unselectedLabelColor: AppConstants.textSecondary.withOpacity(0.6),
        labelPadding: EdgeInsets.zero,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          _buildPremiumTab(
            icon: Icons.notifications_rounded,
            label: 'Activity',
            badgeCount: _unreadNotifCount,
            badgeColor: _kAccentPink,
          ),
          _buildPremiumTab(
            icon: Icons.chat_bubble_rounded,
            label: 'Direct',
            badgeCount: directUnread,
            badgeColor: _kAccentBlue,
          ),
          _buildPremiumTab(
            icon: Icons.groups_rounded,
            label: 'Groups',
            badgeCount: groupUnread,
            badgeColor: _kAccentGreen,
          ),
          _buildPremiumTab(
            icon: Icons.inventory_2_rounded,
            label: 'Q&A',
            badgeCount: 0,
            badgeColor: AppConstants.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumTab({
    required IconData icon,
    required String label,
    required int badgeCount,
    required Color badgeColor,
  }) {
    return Tab(
      height: 40,
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
          if (badgeCount > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: badgeColor.withOpacity(0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
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
          color: _kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.red.withOpacity(0.12),
              ),
              child: Icon(Icons.wifi_off_rounded,
                  size: 28, color: AppConstants.red.withOpacity(0.7)),
            ),
            const SizedBox(height: 18),
            const Text(
              'Connection Error',
              style: TextStyle(
                color: AppConstants.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _convError ?? 'Could not load conversations',
              style: TextStyle(
                color: AppConstants.textSecondary.withOpacity(0.6),
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
                  gradient: const LinearGradient(
                    colors: [_kAccentBlue, _kAccentPurple],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _kAccentBlue.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
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

// ─────────────────────────── Unread Badge ───────────────────────────────
class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppConstants.primaryBlue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
