import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase client
final supabase = Supabase.instance.client;

class VerifyUsersScreen extends StatefulWidget {
  const VerifyUsersScreen({super.key});

  @override
  State<VerifyUsersScreen> createState() => _VerifyUsersScreenState();
}

class _VerifyUsersScreenState extends State<VerifyUsersScreen>
    with SingleTickerProviderStateMixin {
  List<UserModel> _unverifiedUsers = [];
  List<UserModel> _verifiedUsers = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      // Load unverified users
      final unverifiedResponse = await supabase
          .from('users')
          .select()
          .eq('is_verified', false)
          .neq('role', 'admin')
          .order('created_at', ascending: false);

      final unverified = (unverifiedResponse as List)
          .map((userData) =>
              UserModel.fromJson(userData as Map<String, dynamic>))
          .toList();

      // Load verified users
      final verifiedResponse = await supabase
          .from('users')
          .select()
          .eq('is_verified', true)
          .neq('role', 'admin')
          .order('created_at', ascending: false);

      final verified = (verifiedResponse as List)
          .map((userData) =>
              UserModel.fromJson(userData as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _unverifiedUsers = unverified;
          _verifiedUsers = verified;
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

  Future<void> _verifyUser(UserModel user) async {
    try {
      await supabase
          .from('users')
          .update({'is_verified': true}).eq('id', user.id);

      // Log activity
      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        await supabase.from('activity_logs').insert({
          'admin_id': currentUser.id,
          'action': 'Verified user',
          'details': {'user_id': user.id, 'alias': user.alias},
        });
      }

      if (mounted) {
        setState(() {
          _unverifiedUsers.removeWhere((u) => u.id == user.id);
          _verifiedUsers.add(user);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.alias} has been verified'),
            backgroundColor: AppConstants.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error verifying user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to verify user: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  Future<void> _unverifyUser(UserModel user) async {
    try {
      await supabase
          .from('users')
          .update({'is_verified': false}).eq('id', user.id);

      // Log activity
      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        await supabase.from('activity_logs').insert({
          'admin_id': currentUser.id,
          'action': 'Unverified user',
          'details': {'user_id': user.id, 'alias': user.alias},
        });
      }

      if (mounted) {
        setState(() {
          _verifiedUsers.removeWhere((u) => u.id == user.id);
          _unverifiedUsers.add(user);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.alias} verification has been revoked'),
            backgroundColor: AppConstants.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error unverifying user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unverify user: $e'),
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
        title: const Text('Verify Users'),
        backgroundColor: AppConstants.black,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppConstants.primaryBlue,
          unselectedLabelColor: AppConstants.textSecondary,
          indicatorColor: AppConstants.primaryBlue,
          tabs: const [
            Tab(
              text: 'Unverified',
              icon: Icon(Icons.person_outline_rounded),
            ),
            Tab(
              text: 'Verified',
              icon: Icon(Icons.verified_rounded),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // Unverified users tab
                _buildUsersList(_unverifiedUsers, isVerified: false),
                // Verified users tab
                _buildUsersList(_verifiedUsers, isVerified: true),
              ],
            ),
    );
  }

  Widget _buildUsersList(List<UserModel> users, {required bool isVerified}) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isVerified
                  ? Icons.verified_rounded
                  : Icons.person_outline_rounded,
              size: 64,
              color: AppConstants.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isVerified ? 'No verified users' : 'All users are verified',
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
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
                Text(
                  'Joined ${user.createdAt.toLocal().toString().split(' ')[0]}',
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () =>
                  isVerified ? _unverifyUser(user) : _verifyUser(user),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isVerified ? AppConstants.red : AppConstants.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: Text(isVerified ? 'Unverify' : 'Verify'),
            ),
          ),
        );
      },
    );
  }
}
