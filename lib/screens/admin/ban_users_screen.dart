import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase client
final supabase = Supabase.instance.client;

class BanUsersScreen extends StatefulWidget {
  const BanUsersScreen({super.key});

  @override
  State<BanUsersScreen> createState() => _BanUsersScreenState();
}

class _BanUsersScreenState extends State<BanUsersScreen> {
  List<UserModel> _users = [];
  bool _isLoading = false;
  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    try {
      final response = await supabase
          .from('users')
          .select()
          .neq('role', 'admin')
          .order('created_at', ascending: false)
          .limit(50);

      final users = (response as List)
          .map((userData) => UserModel.fromJson(userData as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      _loadUsers();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await supabase
          .from('users')
          .select()
          .neq('role', 'admin')
          .or('alias.ilike.%$query%,display_name.ilike.%$query%')
          .order('created_at', ascending: false)
          .limit(50);

      final users = (response as List)
          .map((userData) => UserModel.fromJson(userData as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleBan(UserModel user) async {
    final newBanStatus = !user.isBanned;

    try {
      await supabase
          .from('users')
          .update({'is_banned': newBanStatus})
          .eq('id', user.id);

      // Log activity
      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        await supabase.from('activity_logs').insert({
          'admin_id': currentUser.id,
          'action': newBanStatus ? 'Banned user' : 'Unbanned user',
          'details': {'user_id': user.id, 'alias': user.alias},
        });
      }

      if (mounted) {
        setState(() {
          final index = _users.indexWhere((u) => u.id == user.id);
          if (index != -1) {
            _users[index] = user.copyWith(isBanned: newBanStatus);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.alias} has been ${newBanStatus ? 'banned' : 'unbanned'}'),
            backgroundColor: newBanStatus ? AppConstants.red : AppConstants.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling ban: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${newBanStatus ? 'ban' : 'unban'} user: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Ban Users'),
        backgroundColor: AppConstants.black,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search users by name or alias...',
                hintStyle: TextStyle(
                  color: AppConstants.textSecondary.withOpacity(0.6),
                ),
                filled: true,
                fillColor: AppConstants.darkGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppConstants.textSecondary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppConstants.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          _searchUsers('');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _searchUsers(value);
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppConstants.primaryBlue),
                  )
                : _users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_rounded,
                              size: 64,
                              color: AppConstants.textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No users found',
                              style: TextStyle(
                                color: AppConstants.textSecondary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppConstants.darkGray,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppConstants.lightGray.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: AppConstants.primaryBlue,
                                backgroundImage: user.profileImageUrl != null
                                    ? NetworkImage(user.profileImageUrl!)
                                    : null,
                                child: user.profileImageUrl == null
                                    ? const Icon(Icons.person, color: Colors.white)
                                    : null,
                              ),
                              title: Text(
                                user.displayName ?? user.alias,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '@${user.alias}',
                                    style: const TextStyle(
                                      color: AppConstants.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        user.isVerified ? Icons.verified_rounded : Icons.verified_outlined,
                                        size: 16,
                                        color: user.isVerified ? AppConstants.primaryBlue : AppConstants.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        user.isVerified ? 'Verified' : 'Unverified',
                                        style: TextStyle(
                                          color: user.isVerified ? AppConstants.primaryBlue : AppConstants.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: user.isBanned ? AppConstants.red.withOpacity(0.2) : AppConstants.green.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          user.isBanned ? 'Banned' : 'Active',
                                          style: TextStyle(
                                            color: user.isBanned ? AppConstants.red : AppConstants.green,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: ElevatedButton(
                                onPressed: () => _toggleBan(user),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: user.isBanned ? AppConstants.green : AppConstants.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                                child: Text(user.isBanned ? 'Unban' : 'Ban'),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
