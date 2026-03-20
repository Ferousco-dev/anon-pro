import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/constants.dart';
import '../../utils/app_error_handler.dart';
import '../../main.dart';

class GroupCreationScreen extends StatefulWidget {
  const GroupCreationScreen({super.key});

  @override
  State<GroupCreationScreen> createState() => _GroupCreationScreenState();
}

class _GroupCreationScreenState extends State<GroupCreationScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupImageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  final Set<String> _selectedUserIds = {};
  bool _isLoading = false;
  bool _isCreating = false;
  String? _error;
  bool _isPrivate = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = q.isEmpty
          ? _allUsers
          : _allUsers.where((u) {
              final alias = (u['alias'] as String? ?? '').toLowerCase();
              final display =
                  (u['display_name'] as String? ?? '').toLowerCase();
              return alias.contains(q) || display.contains(q);
            }).toList();
    });
  }

  Future<void> _loadUsers() async {
    try {
      setState(() => _isLoading = true);
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final response = await supabase
          .from('users')
          .select('id, alias, display_name, profile_image_url')
          .neq('id', currentUser.id)
          .order('alias');

      setState(() {
        _allUsers = List<Map<String, dynamic>>.from(response as List);
        _filteredUsers = _allUsers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = AppErrorHandler.userMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a group name'),
          backgroundColor: AppConstants.red,
        ),
      );
      return;
    }
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one member'),
          backgroundColor: AppConstants.red,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      // 1. Create a conversation for the group
      final conversationResponse = await supabase
          .from('conversations')
          .insert({
            'name': groupName,
            'is_group': true,
            'is_private': _isPrivate,
            'created_by': currentUser.id,
            'group_image_url': _groupImageController.text.trim().isNotEmpty
                ? _groupImageController.text.trim()
                : null,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final conversationId = conversationResponse['id'] as String;

      // 2. Add all participants (including creator as admin)
      final allParticipants = [
        {
          'conversation_id': conversationId,
          'user_id': currentUser.id,
          'role': 'admin',
          'joined_at': DateTime.now().toIso8601String(),
        },
        ..._selectedUserIds.map((userId) => {
              'conversation_id': conversationId,
              'user_id': userId,
              'role': 'member',
              'joined_at': DateTime.now().toIso8601String(),
            }),
      ];

      await supabase.from('conversation_participants').insert(allParticipants);

      // 3. Send system message
      await supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': currentUser.id,
        'content': '${currentUser.email ?? 'Someone'} created this group',
        'message_type': 'system',
        'is_system_message': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Group "$groupName" created!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating group: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['id'] as String;
    final isSelected = _selectedUserIds.contains(userId);
    final displayName = user['display_name'] as String? ??
        user['alias'] as String? ??
        'Unknown';
    final alias = user['alias'] as String?;
    final imageUrl = user['profile_image_url'] as String?;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppConstants.primaryBlue,
            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
            child: imageUrl == null
                ? Text(
                    displayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          if (isSelected)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppConstants.primaryBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppConstants.darkGray, width: 1.5),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 10),
              ),
            ),
        ],
      ),
      title: Text(
        displayName,
        style: const TextStyle(
          color: AppConstants.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: alias != null
          ? Text(
              '@$alias',
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 12,
              ),
            )
          : null,
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppConstants.primaryBlue)
          : const Icon(Icons.circle_outlined,
              color: AppConstants.textSecondary),
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedUserIds.remove(userId);
          } else {
            _selectedUserIds.add(userId);
          }
        });
      },
    );
  }

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
        title: const Text(
          'Create Group',
          style:
              TextStyle(color: AppConstants.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppConstants.primaryBlue,
                    ),
                  )
                : const Text(
                    'Create',
                    style: TextStyle(
                      color: AppConstants.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Group Details Section
          Container(
            padding: const EdgeInsets.all(16),
            color: AppConstants.darkGray,
            child: Column(
              children: [
                // Group Image & Name row
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        // Show image URL input
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppConstants.darkGray,
                            title: const Text(
                              'Group Image URL',
                              style: TextStyle(color: AppConstants.white),
                            ),
                            content: TextField(
                              controller: _groupImageController,
                              style: const TextStyle(color: AppConstants.white),
                              decoration: InputDecoration(
                                hintText: 'Paste catbox.moe link...',
                                hintStyle: const TextStyle(
                                    color: AppConstants.textSecondary),
                                filled: true,
                                fillColor: AppConstants.black,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Done',
                                    style: TextStyle(
                                        color: AppConstants.primaryBlue)),
                              ),
                            ],
                          ),
                        );
                      },
                      child: ValueListenableBuilder(
                        valueListenable: _groupImageController,
                        builder: (context, value, child) {
                          return CircleAvatar(
                            radius: 32,
                            backgroundColor: AppConstants.lightGray,
                            backgroundImage:
                                _groupImageController.text.isNotEmpty
                                    ? NetworkImage(_groupImageController.text)
                                    : null,
                            child: _groupImageController.text.isEmpty
                                ? const Icon(Icons.camera_alt,
                                    color: AppConstants.white, size: 28)
                                : null,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _groupNameController,
                        style: const TextStyle(
                            color: AppConstants.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Group name',
                          hintStyle: const TextStyle(
                              color: AppConstants.textSecondary),
                          filled: true,
                          fillColor: AppConstants.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_selectedUserIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_selectedUserIds.length} member${_selectedUserIds.length > 1 ? 's' : ''} selected',
                      style: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _isPrivate,
                  activeColor: AppConstants.primaryBlue,
                  onChanged: (value) {
                    setState(() => _isPrivate = value);
                  },
                  title: const Text('Private group'),
                  subtitle: const Text(
                    'People must request to join',
                    style: TextStyle(color: AppConstants.textSecondary),
                  ),
                ),
              ],
            ),
          ),

          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppConstants.black,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppConstants.white),
              decoration: InputDecoration(
                hintText: 'Search users...',
                hintStyle: const TextStyle(color: AppConstants.textSecondary),
                prefixIcon:
                    const Icon(Icons.search, color: AppConstants.textSecondary),
                filled: true,
                fillColor: AppConstants.darkGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // User List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryBlue))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppConstants.textSecondary)))
                    : _filteredUsers.isEmpty
                        ? const Center(
                            child: Text('No users found',
                                style: TextStyle(
                                    color: AppConstants.textSecondary)))
                        : ListView.builder(
                            itemCount: _filteredUsers.length,
                            itemBuilder: (context, index) =>
                                _buildUserTile(_filteredUsers[index]),
                          ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupImageController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
