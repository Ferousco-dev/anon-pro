import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/chat_model.dart';
import '../../utils/constants.dart';
import '../../main.dart';

class GroupManagementScreen extends StatefulWidget {
  final ChatModel chat;

  const GroupManagementScreen({super.key, required this.chat});

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  late ChatModel _chat;
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTogglingLock = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _imageController = TextEditingController();
  final TextEditingController _pinnedController = TextEditingController();

  // Add member search
  final TextEditingController _addMemberSearchController =
      TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  List<Map<String, dynamic>> _joinRequests = [];
  bool _isLoadingRequests = false;

  String? currentUserId;

  // Realtime subscription
  RealtimeChannel? _participantsSubscription;
  RealtimeChannel? _groupSubscription;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    currentUserId = supabase.auth.currentUser?.id;
    _nameController.text = _chat.name;
    _imageController.text = _chat.groupImageUrl ?? '';
    _pinnedController.text = _chat.pinnedMessage ?? '';
    _loadMembers();
    _loadJoinRequests();
    _subscribeToChanges();
  }

  // ─── Realtime ────────────────────────────────────────────────────────────────

  void _subscribeToChanges() {
    // Live member list updates
    _participantsSubscription = supabase
        .channel('mgmt_participants:${_chat.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: _chat.id,
          ),
          callback: (_) => _loadMembers(),
        )
        .subscribe();

    // Live group info updates
    _groupSubscription = supabase
        .channel('mgmt_group_info:${_chat.id}')
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
                _nameController.text = _chat.name;
                _imageController.text = _chat.groupImageUrl ?? '';
                _pinnedController.text = _chat.pinnedMessage ?? '';
              });
            }
          },
        )
        .subscribe();
  }

  // ─── Data Loading ────────────────────────────────────────────────────────────

  Future<void> _loadMembers() async {
    try {
      if (!_isLoading) setState(() => _isLoading = true);
      final response =
          await supabase.from('conversation_participants').select('''
            user_id,
            role,
            joined_at,
            users:user_id (
              id,
              alias,
              display_name,
              profile_image_url
            )
          ''').eq('conversation_id', _chat.id).order('joined_at');

      if (mounted) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(response as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading members: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadJoinRequests() async {
    if (!_chat.isAdmin) return;
    try {
      setState(() => _isLoadingRequests = true);
      final response =
          await supabase.from('group_join_requests').select('''
            id,
            status,
            created_at,
            users:user_id (
              id,
              alias,
              display_name,
              profile_image_url
            )
          ''').eq('conversation_id', _chat.id).eq('status', 'pending');

      if (mounted) {
        setState(() {
          _joinRequests = List<Map<String, dynamic>>.from(response as List);
          _isLoadingRequests = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading join requests: $e');
      if (mounted) setState(() => _isLoadingRequests = false);
    }
  }

  Future<void> _searchUsersToAdd(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      // Get existing member IDs to exclude them
      final existingIds = _members.map((m) => m['user_id'] as String).toList();

      final response = await supabase
          .from('users')
          .select('id, alias, display_name, profile_image_url')
          .or('alias.ilike.%$query%,display_name.ilike.%$query%')
          .neq('id', currentUserId ?? '')
          .limit(10);

      if (mounted) {
        setState(() {
          _searchResults = (response as List)
              .map((u) => u as Map<String, dynamic>)
              .where((u) => !existingIds.contains(u['id'] as String))
              .toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ─── Admin Actions ───────────────────────────────────────────────────────────

  Future<void> _saveGroupInfo() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Group name cannot be empty', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final pinnedMessage = _pinnedController.text.trim();
      await supabase.from('conversations').update({
        'name': name,
        'group_image_url': _imageController.text.trim().isNotEmpty
            ? _imageController.text.trim()
            : null,
        'pinned_message': pinnedMessage.isEmpty ? null : pinnedMessage,
        'pinned_by': pinnedMessage.isEmpty ? null : currentUserId,
        'pinned_at':
            pinnedMessage.isEmpty ? null : DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _chat.id);

      // State updates via realtime subscription
      _showSnack('Group updated successfully', isSuccess: true);
    } catch (e) {
      _showSnack('Failed to update: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleLock() async {
    setState(() => _isTogglingLock = true);
    try {
      await supabase.from('conversations').update({
        'is_locked': !_chat.isLocked,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _chat.id);

      // State updates via realtime subscription
      _showSnack(
        _chat.isLocked ? 'Group unlocked' : 'Group locked',
        isSuccess: true,
      );
    } catch (e) {
      _showSnack('Failed to toggle lock: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isTogglingLock = false);
    }
  }

  Future<void> _toggleMemberRole(
      String userId, String currentRole, String displayName) async {
    final newRole = currentRole == 'admin' ? 'member' : 'admin';
    final action = newRole == 'admin' ? 'promote' : 'demote';

    final confirm = await _showConfirmDialog(
      title: newRole == 'admin' ? 'Promote to Admin' : 'Demote to Member',
      message: newRole == 'admin'
          ? 'Make $displayName an admin? They will be able to manage the group.'
          : 'Remove admin from $displayName? They will become a regular member.',
      confirmText: action == 'promote' ? 'Promote' : 'Demote',
      confirmColor: newRole == 'admin' ? Colors.amber : Colors.orange,
    );

    if (confirm != true) return;

    try {
      await supabase
          .from('conversation_participants')
          .update({'role': newRole})
          .eq('conversation_id', _chat.id)
          .eq('user_id', userId);

      _showSnack(
        newRole == 'admin'
            ? '$displayName promoted to admin'
            : '$displayName demoted to member',
        isSuccess: true,
      );
      // Members reload via realtime
    } catch (e) {
      _showSnack('Failed to change role: $e', isError: true);
    }
  }

  Future<void> _removeMember(String userId, String displayName) async {
    final confirm = await _showConfirmDialog(
      title: 'Remove Member',
      message: 'Remove $displayName from this group?',
      confirmText: 'Remove',
      confirmColor: AppConstants.red,
    );

    if (confirm != true) return;

    try {
      await supabase
          .from('conversation_participants')
          .delete()
          .eq('conversation_id', _chat.id)
          .eq('user_id', userId);

      _showSnack('$displayName removed', isSuccess: true);
      // Members reload via realtime
    } catch (e) {
      _showSnack('Failed to remove: $e', isError: true);
    }
  }

  Future<void> _addMember(Map<String, dynamic> user) async {
    final userId = user['id'] as String;
    final displayName =
        user['display_name'] as String? ?? user['alias'] as String? ?? 'User';

    try {
      await supabase.from('conversation_participants').insert({
        'conversation_id': _chat.id,
        'user_id': userId,
        'role': 'member',
        'joined_at': DateTime.now().toIso8601String(),
      });

      // Send system message
      await supabase.from('messages').insert({
        'conversation_id': _chat.id,
        'sender_id': currentUserId,
        'content': '$displayName was added to the group',
        'message_type': 'system',
        'is_system_message': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      setState(() {
        _searchResults.removeWhere((u) => u['id'] == userId);
        _addMemberSearchController.clear();
      });

      _showSnack('$displayName added to group', isSuccess: true);
      // Members reload via realtime
    } catch (e) {
      _showSnack('Failed to add member: $e', isError: true);
    }
  }

  Future<void> _approveJoinRequest(Map<String, dynamic> request) async {
    final user = request['users'] as Map<String, dynamic>? ?? {};
    final userId = user['id'] as String?;
    if (userId == null) return;
    try {
      await supabase.from('conversation_participants').insert({
        'conversation_id': _chat.id,
        'user_id': userId,
        'role': 'member',
      });
      await supabase
          .from('group_join_requests')
          .update({'status': 'approved'}).eq('id', request['id'] as String);
      await _loadMembers();
      await _loadJoinRequests();
      _showSnack('Request approved', isSuccess: true);
    } catch (e) {
      _showSnack('Failed to approve: $e', isError: true);
    }
  }

  Future<void> _denyJoinRequest(Map<String, dynamic> request) async {
    try {
      await supabase
          .from('group_join_requests')
          .update({'status': 'denied'}).eq('id', request['id'] as String);
      await _loadJoinRequests();
      _showSnack('Request denied', isSuccess: true);
    } catch (e) {
      _showSnack('Failed to deny: $e', isError: true);
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await _showConfirmDialog(
      title: 'Delete Group',
      message:
          'Delete "${_chat.name}"? All messages will be lost. This cannot be undone.',
      confirmText: 'Delete',
      confirmColor: AppConstants.red,
    );

    if (confirm != true) return;

    try {
      await supabase.from('conversations').delete().eq('id', _chat.id);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showSnack('Failed to delete group: $e', isError: true);
    }
  }

  Future<void> _leaveGroup() async {
    if (currentUserId == null) return;

    final confirm = await _showConfirmDialog(
      title: 'Leave Group',
      message: 'Are you sure you want to leave this group?',
      confirmText: 'Leave',
      confirmColor: Colors.orange,
    );

    if (confirm != true) return;

    try {
      await supabase
          .from('conversation_participants')
          .delete()
          .eq('conversation_id', _chat.id)
          .eq('user_id', currentUserId!);

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showSnack('Failed to leave group: $e', isError: true);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? AppConstants.red
            : isSuccess
                ? Colors.green
                : null,
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        title: Text(title, style: const TextStyle(color: AppConstants.white)),
        content: Text(message,
            style: const TextStyle(color: AppConstants.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppConstants.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText,
                style: TextStyle(
                    color: confirmColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showImageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        title: const Text('Group Image URL',
            style: TextStyle(color: AppConstants.white)),
        content: TextField(
          controller: _imageController,
          style: const TextStyle(color: AppConstants.white),
          decoration: InputDecoration(
            hintText: 'Paste catbox.moe link...',
            hintStyle: const TextStyle(color: AppConstants.textSecondary),
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
            child: const Text('Cancel',
                style: TextStyle(color: AppConstants.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveGroupInfo();
            },
            child: const Text('Save',
                style: TextStyle(
                    color: AppConstants.primaryBlue,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddMemberSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.darkGray,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
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
              const Text(
                'Add Member',
                style: TextStyle(
                  color: AppConstants.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _addMemberSearchController,
                  style: const TextStyle(color: AppConstants.white),
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search by name or alias...',
                    hintStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                    prefixIcon: const Icon(Icons.search,
                        color: AppConstants.textSecondary),
                    filled: true,
                    fillColor: AppConstants.black,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (q) async {
                    await _searchUsersToAdd(q);
                    setSheetState(() {});
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      color: AppConstants.primaryBlue),
                )
              else if (_searchResults.isEmpty &&
                  _addMemberSearchController.text.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No users found',
                      style: TextStyle(color: AppConstants.textSecondary)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (_, index) {
                      final user = _searchResults[index];
                      final displayName = user['display_name'] as String? ??
                          user['alias'] as String? ??
                          'Unknown';
                      final alias = user['alias'] as String?;
                      final imageUrl = user['profile_image_url'] as String?;

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppConstants.primaryBlue,
                          backgroundImage:
                              imageUrl != null ? NetworkImage(imageUrl) : null,
                          child: imageUrl == null
                              ? Text(
                                  displayName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        title: Text(displayName,
                            style: const TextStyle(
                                color: AppConstants.white,
                                fontWeight: FontWeight.w500)),
                        subtitle: alias != null
                            ? Text('@$alias',
                                style: const TextStyle(
                                    color: AppConstants.textSecondary,
                                    fontSize: 12))
                            : null,
                        trailing: TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _addMember(user);
                          },
                          style: TextButton.styleFrom(
                            backgroundColor:
                                AppConstants.primaryBlue.withOpacity(0.15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Add',
                              style: TextStyle(
                                  color: AppConstants.primaryBlue,
                                  fontWeight: FontWeight.bold)),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ─── UI Builders ─────────────────────────────────────────────────────────────

  Widget _buildGroupHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      color: AppConstants.darkGray,
      child: Column(
        children: [
          // Group image
          GestureDetector(
            onTap: _chat.isAdmin ? _showImageDialog : null,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: AppConstants.primaryBlue,
                  backgroundImage: _chat.groupImageUrl != null
                      ? NetworkImage(_chat.groupImageUrl!)
                      : null,
                  child: _chat.groupImageUrl == null
                      ? const Icon(Icons.group, color: Colors.white, size: 52)
                      : null,
                ),
                if (_chat.isAdmin)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryBlue,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppConstants.darkGray, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.white, size: 14),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Group name
          if (_chat.isAdmin) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: IntrinsicWidth(
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(
                        color: AppConstants.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'Group name',
                        hintStyle:
                            const TextStyle(color: AppConstants.textSecondary),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: AppConstants.primaryBlue.withOpacity(0.4)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: AppConstants.primaryBlue),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: AppConstants.lightGray.withOpacity(0.3)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              _chat.name,
              style: const TextStyle(
                color: AppConstants.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatChip(
                icon: Icons.people,
                label: '${_members.length} members',
                color: AppConstants.textSecondary,
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: _chat.isLocked ? Icons.lock : Icons.lock_open,
                label: _chat.isLocked ? 'Locked' : 'Open',
                color: _chat.isLocked ? Colors.orange : Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppConstants.lightGray.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pinned message',
                  style: TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                _chat.isAdmin
                    ? TextField(
                        controller: _pinnedController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Add a pinned message for members...',
                          hintStyle:
                              TextStyle(color: AppConstants.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      )
                    : Text(
                        _chat.pinnedMessage?.isNotEmpty == true
                            ? _chat.pinnedMessage!
                            : 'No pinned message',
                        style: const TextStyle(color: Colors.white),
                      ),
              ],
            ),
          ),

          // Admin action buttons
          if (_chat.isAdmin) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AdminActionButton(
                  icon: Icons.save_rounded,
                  label: 'Save',
                  color: AppConstants.primaryBlue,
                  isLoading: _isSaving,
                  onTap: _saveGroupInfo,
                ),
                const SizedBox(width: 16),
                _AdminActionButton(
                  icon: _chat.isLocked ? Icons.lock_open : Icons.lock,
                  label: _chat.isLocked ? 'Unlock' : 'Lock',
                  color: _chat.isLocked ? Colors.green : Colors.orange,
                  isLoading: _isTogglingLock,
                  onTap: _toggleLock,
                ),
                const SizedBox(width: 16),
                _AdminActionButton(
                  icon: Icons.person_add,
                  label: 'Add',
                  color: Colors.teal,
                  onTap: _showAddMemberSheet,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> participant) {
    final userData = participant['users'] as Map<String, dynamic>? ?? {};
    final userId =
        userData['id'] as String? ?? participant['user_id'] as String;
    final role = participant['role'] as String? ?? 'member';
    final displayName = userData['display_name'] as String? ??
        userData['alias'] as String? ??
        'Unknown';
    final alias = userData['alias'] as String?;
    final imageUrl = userData['profile_image_url'] as String?;
    final isMe = userId == currentUserId;
    final isAdmin = role == 'admin';

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppConstants.lightGray.withOpacity(0.1),
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                          color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            if (isAdmin)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppConstants.darkGray, width: 1.5),
                  ),
                  child: const Icon(Icons.star, color: Colors.white, size: 9),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                displayName,
                style: const TextStyle(
                  color: AppConstants.white,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isMe) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppConstants.primaryBlue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('You',
                    style: TextStyle(
                        color: AppConstants.primaryBlue, fontSize: 10)),
              ),
            ],
          ],
        ),
        subtitle: Row(
          children: [
            if (alias != null)
              Text('@$alias',
                  style: const TextStyle(
                      color: AppConstants.textSecondary, fontSize: 12)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isAdmin
                    ? Colors.amber.withOpacity(0.15)
                    : AppConstants.lightGray.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isAdmin ? 'Admin' : 'Member',
                style: TextStyle(
                  color: isAdmin ? Colors.amber : AppConstants.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: _chat.isAdmin && !isMe
            ? PopupMenuButton<String>(
                color: AppConstants.darkGray,
                icon: const Icon(Icons.more_vert,
                    color: AppConstants.textSecondary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  if (value == 'toggle_role') {
                    _toggleMemberRole(userId, role, displayName);
                  } else if (value == 'remove') {
                    _removeMember(userId, displayName);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'toggle_role',
                    child: Row(
                      children: [
                        Icon(
                          isAdmin ? Icons.arrow_downward : Icons.star,
                          color: isAdmin ? Colors.orange : Colors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isAdmin ? 'Demote to Member' : 'Promote to Admin',
                          style: TextStyle(
                            color: isAdmin ? Colors.orange : Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: const [
                        Icon(Icons.person_remove,
                            color: AppConstants.red, size: 18),
                        SizedBox(width: 10),
                        Text('Remove from Group',
                            style: TextStyle(color: AppConstants.red)),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            'ACTIONS',
            style: TextStyle(
              color: AppConstants.textSecondary.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        Container(
          color: AppConstants.darkGray,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.orange),
                title: const Text('Leave Group',
                    style: TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right,
                    color: AppConstants.textSecondary, size: 18),
                onTap: _leaveGroup,
              ),
              if (_chat.isAdmin) ...[
                Divider(
                    height: 1, color: AppConstants.lightGray.withOpacity(0.15)),
                ListTile(
                  leading:
                      const Icon(Icons.delete_forever, color: AppConstants.red),
                  title: const Text('Delete Group',
                      style: TextStyle(
                          color: AppConstants.red,
                          fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppConstants.textSecondary, size: 18),
                  onTap: _deleteGroup,
                ),
              ],
            ],
          ),
        ),
      ],
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
        title: const Text(
          'Group Info',
          style:
              TextStyle(color: AppConstants.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with image, name, stats, admin buttons
                  _buildGroupHeader(),

                  // Members section
                  if (_chat.isAdmin) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text(
                        'JOIN REQUESTS',
                        style: TextStyle(
                          color: AppConstants.textSecondary.withOpacity(0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    Container(
                      color: AppConstants.darkGray,
                      child: _isLoadingRequests
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: AppConstants.primaryBlue),
                              ),
                            )
                          : _joinRequests.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'No pending requests',
                                    style: TextStyle(
                                        color: AppConstants.textSecondary),
                                  ),
                                )
                              : Column(
                                  children: _joinRequests.map((request) {
                                    final user =
                                        request['users'] as Map<String, dynamic>? ??
                                            {};
                                    final displayName =
                                        user['display_name'] as String? ??
                                            user['alias'] as String? ??
                                            'Unknown';
                                    final imageUrl =
                                        user['profile_image_url'] as String?;
                                    return ListTile(
                                      leading: CircleAvatar(
                                        radius: 20,
                                        backgroundColor:
                                            AppConstants.primaryBlue,
                                        backgroundImage: imageUrl != null
                                            ? NetworkImage(imageUrl)
                                            : null,
                                        child: imageUrl == null
                                            ? Text(
                                                displayName
                                                    .substring(0, 1)
                                                    .toUpperCase(),
                                                style: const TextStyle(
                                                    color: Colors.white),
                                              )
                                            : null,
                                      ),
                                      title: Text(displayName,
                                          style: const TextStyle(
                                              color: Colors.white)),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.close,
                                                color: Colors.redAccent),
                                            onPressed: () =>
                                                _denyJoinRequest(request),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.check,
                                                color: Colors.greenAccent),
                                            onPressed: () =>
                                                _approveJoinRequest(request),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'MEMBERS (${_members.length})',
                          style: TextStyle(
                            color: AppConstants.textSecondary.withOpacity(0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        if (_chat.isAdmin)
                          GestureDetector(
                            onTap: _showAddMemberSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    AppConstants.primaryBlue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.add,
                                      color: AppConstants.primaryBlue,
                                      size: 14),
                                  SizedBox(width: 4),
                                  Text('Add',
                                      style: TextStyle(
                                          color: AppConstants.primaryBlue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    color: AppConstants.darkGray,
                    child: Column(
                      children: _members.map(_buildMemberTile).toList(),
                    ),
                  ),

                  // Leave / Delete
                  _buildActionsSection(),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameController.dispose();
    _imageController.dispose();
    _pinnedController.dispose();
    _addMemberSearchController.dispose();
    _participantsSubscription?.unsubscribe();
    _groupSubscription?.unsubscribe();
    super.dispose();
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AdminActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;

  const _AdminActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3), width: 1),
            ),
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
