import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../utils/constants.dart';

class GroupDiscoverScreen extends StatefulWidget {
  const GroupDiscoverScreen({super.key});

  @override
  State<GroupDiscoverScreen> createState() => _GroupDiscoverScreenState();
}

class _GroupDiscoverScreenState extends State<GroupDiscoverScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _filteredGroups = [];
  Map<String, String> _requestStatus = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearch);
    _loadGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filteredGroups = q.isEmpty
          ? _groups
          : _groups.where((g) {
              final name = (g['name'] as String? ?? '').toLowerCase();
              return name.contains(q);
            }).toList();
    });
  }

  Future<void> _loadGroups() async {
    try {
      setState(() => _isLoading = true);
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final participantRes = await supabase
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', currentUser.id);
      final existingIds = (participantRes as List)
          .map((row) => row['conversation_id'] as String)
          .toList();

      var query = supabase
          .from('conversations')
          .select('id, name, description, group_image_url, is_private')
          .eq('is_group', true);

      if (existingIds.isNotEmpty) {
        query = query.not('id', 'in', '(${existingIds.join(',')})');
      }

      final groupsRes = await query.order('updated_at', ascending: false);
      final groups = List<Map<String, dynamic>>.from(groupsRes as List);

      final requestsRes = await supabase
          .from('group_join_requests')
          .select('conversation_id, status')
          .eq('user_id', currentUser.id);
      final requestMap = <String, String>{};
      for (final row in requestsRes as List) {
        requestMap[row['conversation_id'] as String] =
            row['status'] as String? ?? 'pending';
      }

      setState(() {
        _groups = groups;
        _filteredGroups = groups;
        _requestStatus = requestMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load groups';
        _isLoading = false;
      });
    }
  }

  Future<void> _requestJoin(Map<String, dynamic> group) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    final groupId = group['id'] as String;
    final isPrivate = group['is_private'] as bool? ?? false;

    try {
      if (isPrivate) {
        await supabase.from('group_join_requests').upsert({
          'conversation_id': groupId,
          'user_id': currentUser.id,
          'status': 'pending',
        });
        setState(() => _requestStatus[groupId] = 'pending');
      } else {
        await supabase.from('conversation_participants').insert({
          'conversation_id': groupId,
          'user_id': currentUser.id,
          'role': 'member',
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Joined group'),
            backgroundColor: AppConstants.green,
          ),
        );
        await _loadGroups();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to join: $e'),
          backgroundColor: AppConstants.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Discover Groups'),
        backgroundColor: AppConstants.black,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search groups...',
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
                        onRefresh: _loadGroups,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredGroups.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final group = _filteredGroups[index];
                            final groupId = group['id'] as String;
                            final name = group['name'] as String? ?? 'Group';
                            final isPrivate =
                                group['is_private'] as bool? ?? false;
                            final status = _requestStatus[groupId];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppConstants.darkGray,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppConstants.lightGray.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: AppConstants.primaryBlue,
                                    backgroundImage:
                                        (group['group_image_url'] as String?)
                                                    ?.isNotEmpty ==
                                                true
                                            ? NetworkImage(
                                                group['group_image_url'] as String)
                                            : null,
                                    child:
                                        (group['group_image_url'] as String?)
                                                    ?.isNotEmpty ==
                                                true
                                            ? null
                                            : const Icon(Icons.group,
                                                color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(width: 6),
                                            if (isPrivate)
                                              const Icon(Icons.lock,
                                                  size: 14,
                                                  color: Colors.white70),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          (group['description'] as String?) ??
                                              'Join the conversation',
                                          style: const TextStyle(
                                              color: Colors.white60, fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (status == 'pending')
                                    const Text(
                                      'Requested',
                                      style: TextStyle(color: Colors.white70),
                                    )
                                  else
                                    ElevatedButton(
                                      onPressed: () => _requestJoin(group),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppConstants.primaryBlue,
                                      ),
                                      child: Text(isPrivate ? 'Request' : 'Join'),
                                    ),
                                ],
                              ),
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
