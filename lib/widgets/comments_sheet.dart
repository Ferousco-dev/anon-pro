import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../main.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import 'tappable_mention_text.dart';
import 'verified_badge.dart';

class CommentsSheet extends StatefulWidget {
  final PostModel post;
  final UserModel? currentUser;
  final VoidCallback? onCommentCreated;

  const CommentsSheet({
    super.key,
    required this.post,
    this.currentUser,
    this.onCommentCreated,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  ScrollController? _sheetScrollController;
  bool _autoScrollEnabled = true;

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _startRealtime();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_channel != null) {
      supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  DateTime _parseCreatedAt(Map<String, dynamic> row) {
    final raw = row['created_at'];
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _scrollToBottom() {
    final controller = _sheetScrollController;
    if (controller == null || !controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _startRealtime() {
    if (_channel != null) return;

    _channel = supabase.channel('comments:${widget.post.id}').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: widget.post.id,
          ),
          callback: (payload) {
            if (!mounted) return;

            if (payload.eventType == PostgresChangeEvent.insert) {
              final id = payload.newRecord['id'] as String?;
              if (id == null) return;
              setState(() {
                final exists = _comments.any((c) => c['id'] == id);
                if (!exists) {
                  _comments.add(payload.newRecord);
                  _comments.sort((a, b) =>
                      _parseCreatedAt(a).compareTo(_parseCreatedAt(b)));
                }
              });

              if (_autoScrollEnabled) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());
              }
              return;
            }

            if (payload.eventType == PostgresChangeEvent.update) {
              final id = payload.newRecord['id'] as String?;
              if (id == null) return;
              setState(() {
                final idx = _comments.indexWhere((c) => c['id'] == id);
                if (idx != -1) _comments[idx] = payload.newRecord;
                _comments.sort(
                    (a, b) => _parseCreatedAt(a).compareTo(_parseCreatedAt(b)));
              });
              return;
            }

            if (payload.eventType == PostgresChangeEvent.delete) {
              final id = payload.oldRecord['id'] as String?;
              if (id == null) return;
              setState(() {
                _comments.removeWhere((c) => c['id'] == id);
              });
            }
          },
        );

    _channel!.subscribe();
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load comments with user info
      final res = await supabase
          .from('comments')
          .select('''
            *,
            user:users!comments_user_id_fkey(
              id,
              alias,
              display_name,
              avatar_url,
              profile_image_url
            )
          ''')
          .eq('post_id', widget.post.id)
          .order('created_at', ascending: true);

      setState(() {
        _comments = (res as List).cast<Map<String, dynamic>>();
        _comments
            .sort((a, b) => _parseCreatedAt(a).compareTo(_parseCreatedAt(b)));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendComment() async {
    if (widget.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to comment'),
          backgroundColor: AppConstants.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);

    try {
      await supabase.from('comments').insert({
        'post_id': widget.post.id,
        'user_id': widget.currentUser?.id,
        'content': text,
        'is_anonymous': widget.post.isAnonymous,
      });

      // Update the post's comment count
      await supabase
          .from('posts')
          .update({'comments_count': widget.post.commentsCount + 1}).eq(
              'id', widget.post.id);

      if (!mounted) return;
      _controller.clear();
      widget.onCommentCreated?.call();

      if (_autoScrollEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to comment: $e'),
          backgroundColor: AppConstants.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        _sheetScrollController = controller;
        return Container(
          decoration: const BoxDecoration(
            color: AppConstants.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppConstants.lightGray.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Comments (${_comments.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppConstants.primaryBlue),
                        )
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _error!,
                                      style: const TextStyle(
                                          color: AppConstants.textSecondary),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: _loadComments,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppConstants.primaryBlue,
                                      ),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _comments.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline_rounded,
                                          size: 48,
                                          color: AppConstants.textSecondary,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No comments yet',
                                          style: TextStyle(
                                            color: AppConstants.textSecondary,
                                            fontSize: 16,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Be the first to comment!',
                                          style: TextStyle(
                                            color: AppConstants.textSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  controller: controller,
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  itemCount: _comments.length,
                                  itemBuilder: (context, index) {
                                    final c = _comments[index];
                                    final content =
                                        (c['content'] as String?) ?? '';
                                    final isAnonymousComment =
                                        (c['is_anonymous'] as bool?) ?? false;
                                    final user =
                                        c['user'] as Map<String, dynamic>?;
                                    final alias = isAnonymousComment
                                        ? 'anonymous'
                                        : (user?['alias'] as String? ??
                                            'unknown');
                                    final displayName = isAnonymousComment
                                        ? 'Anonymous'
                                        : (user?['display_name'] as String? ??
                                            alias);
                                    final avatarUrl = isAnonymousComment
                                        ? null
                                        : (user?['profile_image_url']
                                                as String? ??
                                            user?['avatar_url'] as String?);
                                    final createdAt = _parseCreatedAt(c);

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // User avatar
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor:
                                                AppConstants.primaryBlue,
                                            backgroundImage: avatarUrl != null
                                                ? NetworkImage(avatarUrl)
                                                : null,
                                            child: avatarUrl == null
                                                ? const Icon(
                                                    Icons.person,
                                                    size: 16,
                                                    color: Colors.white,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          // Comment content
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppConstants.darkGray,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          displayName,
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '@$alias',
                                                        style: const TextStyle(
                                                          color: AppConstants
                                                              .textSecondary,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  TappableMentionText(
                                                    text: content,
                                                    baseStyle: const TextStyle(
                                                      color: Colors.white,
                                                      height: 1.35,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    timeago.format(createdAt,
                                                        locale: 'en_short'),
                                                    style: const TextStyle(
                                                      color: AppConstants
                                                          .textSecondary,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                ),
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.axis != Axis.vertical) return false;
                    final distance =
                        n.metrics.maxScrollExtent - n.metrics.pixels;
                    final atBottom = distance < 120;
                    if (atBottom != _autoScrollEnabled) {
                      setState(() => _autoScrollEnabled = atBottom);
                    }
                    return false;
                  },
                  child: const SizedBox.shrink(),
                ),
                Padding(
                  padding:
                      EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom : 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Write a comment…',
                            hintStyle: const TextStyle(
                                color: AppConstants.textSecondary),
                            filled: true,
                            fillColor: AppConstants.darkGray,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: _isSending ? null : _sendComment,
                        icon: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppConstants.primaryBlue,
                                ),
                              )
                            : const Icon(Icons.send_rounded,
                                color: AppConstants.primaryBlue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
