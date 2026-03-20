import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/user_model.dart';
import '../../models/post_model.dart';
import '../../utils/constants.dart';
import '../../widgets/post_card.dart';
import '../../widgets/comments_sheet.dart';
import '../../services/confession_rooms_service.dart';
import '../confession_rooms/confession_rooms_screen.dart';
import '../../models/confession_room_model.dart';
import '../admin_terminal/logs_passkey_page.dart';

class SearchScreen extends StatefulWidget {
  final UserModel? currentUser;

  const SearchScreen({super.key, this.currentUser});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;

  List<UserModel> _userResults = [];
  List<PostModel> _postResults = [];
  bool _isSearching = false;
  Timer? _debounce;
  String _lastQuery = '';
  ConfessionRoomModel? _matchedRoom;
  final ConfessionRoomsService _roomsService = ConfessionRoomsService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed == _lastQuery) return;

    // Hidden admin terminal trigger — exact match only
    if (trimmed.toLowerCase() == 'logs') {
      _controller.clear();
      setState(() {
        _userResults.clear();
        _postResults.clear();
        _matchedRoom = null;
        _isSearching = false;
        _lastQuery = '';
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LogsPasskeyPage(),
        ),
      );
      return;
    }

    if (trimmed.isEmpty) {
      setState(() {
        _userResults.clear();
        _postResults.clear();
        _matchedRoom = null;
        _isSearching = false;
        _lastQuery = '';
      });
      return;
    }

    setState(() => _isSearching = true);
    _ensureSearchFocus(force: true);

    _debounce = Timer(const Duration(milliseconds: 450), () {
      _executeSearch(trimmed);
    });
  }

  void _ensureSearchFocus({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (force || !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _executeSearch(String query) async {
    _lastQuery = query;
    try {
      ConfessionRoomModel? matchedRoom;
      // If query is a 4-digit number, check if it's a room join code
      if (RegExp(r'^\d{4}$').hasMatch(query)) {
        matchedRoom = await _roomsService.getRoomByCode(query);
      }

      final results = await Future.wait([
        _searchUsers(query),
        _searchPosts(query),
      ]);
      if (mounted && _lastQuery == query) {
        setState(() {
          _userResults = results[0] as List<UserModel>;
          _postResults = results[1] as List<PostModel>;
          _matchedRoom = matchedRoom;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<List<UserModel>> _searchUsers(String query) async {
    try {
      final res = await supabase
          .from('users')
          .select(
              'id, email, alias, display_name, bio, profile_image_url, cover_image_url, role, is_banned, is_verified, followers_count, following_count, posts_count, created_at, updated_at')
          .or('display_name.ilike.%$query%,alias.ilike.%$query%')
          .limit(20);
      return (res as List)
          .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<PostModel>> _searchPosts(String query) async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      final res = await supabase.from('posts').select('''
            *,
            users (
              id, email, alias, display_name, bio,
              profile_image_url, cover_image_url, role,
              is_banned, is_verified,
              followers_count, following_count, posts_count,
              created_at, updated_at
            )
          ''')
          .ilike('content', '%$query%')
          .or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
          .or('expires_at.is.null,expires_at.gt.$nowIso')
          .order('created_at', ascending: false)
          .limit(20);
      return (res as List)
          .map((p) => PostModel.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _showComments(PostModel post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsSheet(
        post: post,
        currentUser: widget.currentUser,
      ),
    );
  }

  Widget _buildUserTile(UserModel user) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/profile', arguments: user.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppConstants.primaryBlue,
              backgroundImage: user.profileImageUrl != null
                  ? NetworkImage(user.profileImageUrl!)
                  : null,
              child: user.profileImageUrl == null
                  ? const Icon(Icons.person, color: Colors.white, size: 22)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName ?? user.alias,
                          style: const TextStyle(
                            color: AppConstants.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isVerifiedUser) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded,
                            color: AppConstants.primaryBlue, size: 15),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.alias}',
                    style: const TextStyle(
                        color: AppConstants.textSecondary, fontSize: 13),
                  ),
                  if (user.followersCount > 0)
                    Text(
                      '${user.followersCount} followers',
                      style: const TextStyle(
                          color: AppConstants.textTertiary, fontSize: 12),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppConstants.textSecondary.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded,
              size: 60, color: AppConstants.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
                color: AppConstants.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.manage_search_rounded,
              size: 72, color: AppConstants.primaryBlue.withOpacity(0.3)),
          const SizedBox(height: 20),
          const Text(
            'Search ANONPRO',
            style: TextStyle(
              color: AppConstants.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Find people, posts, and more',
            style: TextStyle(color: AppConstants.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        elevation: 0,
        leadingWidth: 40,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppConstants.white, size: 20),
        ),
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppConstants.darkGray,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: const TextStyle(color: AppConstants.white, fontSize: 15),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search users and posts…',
              hintStyle: TextStyle(
                  color: AppConstants.textSecondary.withOpacity(0.7),
                  fontSize: 15),
              prefixIcon: const Icon(Icons.search,
                  color: AppConstants.textSecondary, size: 20),
              suffixIcon: hasQuery
                  ? IconButton(
                      onPressed: () {
                        _controller.clear();
                        _onQueryChanged('');
                      },
                      icon: const Icon(Icons.close,
                          color: AppConstants.textSecondary, size: 18),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        bottom: hasQuery
            ? PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppConstants.primaryBlue,
                  labelColor: AppConstants.primaryBlue,
                  unselectedLabelColor: AppConstants.textSecondary,
                  tabs: [
                    Tab(
                        text:
                            'People (${_isSearching ? '…' : _userResults.length})'),
                    Tab(
                        text:
                            'Posts (${_isSearching ? '…' : _postResults.length})'),
                  ],
                ),
              )
            : null,
      ),
      body: !hasQuery
          ? _buildInitialState()
          : _isSearching
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppConstants.primaryBlue),
                )
              : Column(
                  children: [
                    if (_matchedRoom != null)
                      _buildRoomResultCard(_matchedRoom!),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // ── People ──
                          _userResults.isEmpty && _matchedRoom == null
                              ? _buildEmptyState(
                                  'No people found for "$_lastQuery"')
                              : ListView.separated(
                                  itemCount: _userResults.length,
                                  separatorBuilder: (_, __) => Divider(
                                    color:
                                        AppConstants.lightGray.withOpacity(0.3),
                                    height: 1,
                                    indent: 68,
                                  ),
                                  itemBuilder: (_, i) =>
                                      _buildUserTile(_userResults[i]),
                                ),
                          // ── Posts ──
                          _postResults.isEmpty
                              ? _buildEmptyState(
                                  'No posts found for "$_lastQuery"')
                              : ListView.builder(
                                  itemCount: _postResults.length,
                                  itemBuilder: (_, i) => PostCard(
                                    post: _postResults[i],
                                    currentUser: widget.currentUser,
                                    onLikeToggle: () {},
                                    onComment: () =>
                                        _showComments(_postResults[i]),
                                    onShare: () {},
                                    onRepost: () {},
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildRoomResultCard(ConfessionRoomModel room) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppConstants.primaryBlue.withOpacity(0.2),
            AppConstants.primaryBlue.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.primaryBlue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppConstants.primaryBlue,
          child: const Icon(Icons.favorite, color: Colors.white, size: 20),
        ),
        title: Text(
          room.roomName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          'Confession Room Matched!',
          style: TextStyle(color: AppConstants.primaryBlue, fontSize: 12),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => ConfessionRoomChatScreen(
                  roomId: room.id,
                  roomName: room.roomName,
                ),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          icon: const Icon(Icons.login_rounded, size: 16),
          label: const Text(
            'Enter',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
