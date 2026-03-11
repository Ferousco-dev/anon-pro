import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase client
final supabase = Supabase.instance.client;

class ManageAdminsScreen extends StatefulWidget {
  const ManageAdminsScreen({super.key});

  @override
  State<ManageAdminsScreen> createState() => _ManageAdminsScreenState();
}

class _ManageAdminsScreenState extends State<ManageAdminsScreen> {
  List<UserModel> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final response = await supabase
          .from('users')
          .select()
          .order('role', ascending: false)
          .order('created_at', ascending: false);

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

  Future<void> _toggleAdmin(UserModel user) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null || currentUser.id == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot modify your own admin status'),
          backgroundColor: AppConstants.red,
        ),
      );
      return;
    }

    final newRole = user.isAdmin ? 'user' : 'admin';

    try {
      await supabase
          .from('users')
          .update({'role': newRole})
          .eq('id', user.id);

      // Log activity
      await supabase.from('activity_logs').insert({
        'admin_id': currentUser.id,
        'action': user.isAdmin ? 'Removed admin role' : 'Granted admin role',
        'details': {'user_id': user.id, 'alias': user.alias, 'new_role': newRole},
      });

      if (mounted) {
        setState(() {
          final index = _users.indexWhere((u) => u.id == user.id);
          if (index != -1) {
            _users[index] = user.copyWith(role: newRole);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.alias} ${user.isAdmin ? 'is no longer an admin' : 'is now an admin'}'),
            backgroundColor: AppConstants.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling admin: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update admin status: $e'),
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
        title: const Text('Manage Admins'),
        backgroundColor: AppConstants.black,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final currentUser = supabase.auth.currentUser;
                final isCurrentUser = currentUser?.id == user.id;
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
                      backgroundColor: user.isAdmin ? AppConstants.primaryBlue : AppConstants.textSecondary,
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: user.isAdmin ? AppConstants.primaryBlue.withOpacity(0.2) : AppConstants.textSecondary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            user.isAdmin ? 'Admin' : 'User',
                            style: TextStyle(
                              color: user.isAdmin ? AppConstants.primaryBlue : AppConstants.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: isCurrentUser
                        ? const Text(
                            'You',
                            style: TextStyle(
                              color: AppConstants.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : ElevatedButton(
                            onPressed: () => _toggleAdmin(user),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: user.isAdmin ? AppConstants.red : AppConstants.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            child: Text(user.isAdmin ? 'Remove Admin' : 'Make Admin'),
                          ),
                  ),
                );
              },
            ),
    );
  }
}
