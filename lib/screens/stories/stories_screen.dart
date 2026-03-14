import 'package:flutter/material.dart';
import '../../main.dart' as app;
import '../../utils/constants.dart';
import '../../models/status_model.dart';
import '../../status/user_status_group_model.dart';
import '../../status/user_model.dart' as StatusUser;
import '../../status/post_model.dart' as StatusPost;
import '../../status/status_controller.dart' as status;
import '../../status/post_viewer.dart';

class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<UserStatusGroup> _groups = [];
  List<UserStatusGroup> _filteredGroups = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearch);
    _loadStories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredGroups = q.isEmpty
          ? _groups
          : _groups.where((group) {
              final name = group.user.username.toLowerCase();
              return name.contains(q);
            }).toList();
    });
  }

  Future<void> _loadStories() async {
    final currentUser = app.supabase.auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _error = 'User not logged in';
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() => _isLoading = true);

      final response = await app.supabase.rpc(
        'get_user_status_feed',
        params: {'user_uuid': currentUser.id},
      );

      final hiddenResponse = await app.supabase
          .from('user_hidden_statuses')
          .select('status_id')
          .eq('user_id', currentUser.id);
      final hiddenIds = (hiddenResponse as List<dynamic>)
          .map((row) => row['status_id'] as String)
          .toSet();

      final statuses = (response as List<dynamic>)
          .map((row) => StatusModel.fromJson(row as Map<String, dynamic>))
          .where((status) => !hiddenIds.contains(status.id))
          .toList();

      final Map<String, List<StatusModel>> grouped = {};
      for (final status in statuses) {
        grouped.putIfAbsent(status.userId, () => []).add(status);
      }

      final List<UserStatusGroup> groups = [];
      grouped.forEach((userId, userStatuses) {
        userStatuses.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final first = userStatuses.first;
        final user = StatusUser.User(
          id: userId,
          username: first.displayName ?? first.alias,
          avatarUrl: first.profileImageUrl ?? '',
        );
        final posts = userStatuses
            .map((s) => StatusPost.Post(
                  id: s.id,
                  userId: s.userId,
                  mediaUrl: s.mediaPath,
                  createdAt: s.createdAt,
                  isVideo: s.mediaType == 'video',
                ))
            .toList();
        groups.add(UserStatusGroup(user: user, posts: posts));
      });

      groups.sort((a, b) {
        final aLatest = a.posts.last.createdAt;
        final bLatest = b.posts.last.createdAt;
        return bLatest.compareTo(aLatest);
      });

      setState(() {
        _groups = groups;
        _filteredGroups = groups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load stories';
        _isLoading = false;
      });
    }
  }

  void _openStory(UserStatusGroup group) {
    final index = _groups.indexOf(group);
    final controller =
        status.StatusController(_groups, app.supabase.auth.currentUser?.id ?? '',
            currentUserIndex: index);
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PostViewer(controller: controller),
        ))
        .then((_) => _loadStories());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Stories Discover'),
        backgroundColor: AppConstants.black,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search stories...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: AppConstants.darkGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppConstants.primaryBlue),
                  )
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadStories,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredGroups.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final group = _filteredGroups[index];
                            final latest = group.posts.last;
                            return ListTile(
                              onTap: () => _openStory(group),
                              leading: CircleAvatar(
                                radius: 26,
                                backgroundColor: AppConstants.primaryBlue,
                                backgroundImage: group.user.avatarUrl.isNotEmpty
                                    ? NetworkImage(group.user.avatarUrl)
                                    : null,
                                child: group.user.avatarUrl.isEmpty
                                    ? Text(
                                        group.user.username
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              title: Text(
                                group.user.username,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${group.postCount} story${group.postCount > 1 ? 'ies' : ''} · ${latest.createdAt.toLocal()}',
                                style: const TextStyle(color: Colors.white60),
                              ),
                              trailing: const Icon(Icons.chevron_right,
                                  color: Colors.white70),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
