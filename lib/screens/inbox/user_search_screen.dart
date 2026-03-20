import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../models/chat_model.dart';
import '../../utils/constants.dart';
import '../../utils/app_error_handler.dart';
import '../../main.dart';
import 'conversation_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _searchResults = [];
  bool _isSearching = false;
  bool _isCreatingChat = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      // Search for users by alias or display_name
      final response = await supabase
          .from('users')
          .select()
          .neq('id', currentUser.id) // Exclude current user
          .or('alias.ilike.%$query%,display_name.ilike.%$query%')
          .limit(20);

      if (mounted) {
        setState(() {
          _searchResults = (response as List)
              .map((userData) => UserModel.fromJson(userData))
              .toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to search users';
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _startConversation(UserModel otherUser) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to start a conversation'),
          backgroundColor: AppConstants.red,
        ),
      );
      return;
    }

    setState(() => _isCreatingChat = true);

    try {
      // Check if a conversation already exists between these two users
      final existingConversations = await supabase
          .from('conversation_participants')
          .select('conversation_id, conversations!inner(is_group)')
          .eq('user_id', currentUser.id);

      String? existingConversationId;

      for (var item in existingConversations as List) {
        final conversationId = item['conversation_id'] as String;
        final isGroup = item['conversations']['is_group'] as bool? ?? false;

        // Only check 1-on-1 conversations
        if (!isGroup) {
          // Check if other user is also in this conversation
          final otherUserInConvo = await supabase
              .from('conversation_participants')
              .select('id')
              .eq('conversation_id', conversationId)
              .eq('user_id', otherUser.id);

          if (otherUserInConvo.isNotEmpty) {
            existingConversationId = conversationId;
            break;
          }
        }
      }

      String conversationId;

      if (existingConversationId != null) {
        // Use existing conversation
        conversationId = existingConversationId;
        debugPrint('Found existing conversation: $conversationId');
      } else {
        // Create new conversation
        final newConversation = await supabase
            .from('conversations')
            .insert({
              'name': otherUser.displayName ?? otherUser.alias,
              'is_group': false,
              'created_by': currentUser.id,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();

        conversationId = newConversation['id'] as String;
        debugPrint('Created new conversation: $conversationId');

        // Add both users as participants
        await supabase.from('conversation_participants').insert([
          {
            'conversation_id': conversationId,
            'user_id': currentUser.id,
            'joined_at': DateTime.now().toIso8601String(),
          },
          {
            'conversation_id': conversationId,
            'user_id': otherUser.id,
            'joined_at': DateTime.now().toIso8601String(),
          },
        ]);
      }

      if (mounted) {
        // Create a ChatModel for navigation
        final chat = ChatModel(
          id: conversationId,
          name: otherUser.displayName ?? otherUser.alias,
          isGroup: false,
          otherUserId: otherUser.id,
          otherUserAlias: otherUser.alias,
          otherUserDisplayName: otherUser.displayName,
          otherUserProfileImageUrl: otherUser.profileImageUrl,
          participantIds: [currentUser.id, otherUser.id],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Navigate to conversation screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationScreen(chat: chat),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.userMessage(e)),
            backgroundColor: AppConstants.red,
          ),
        );
        setState(() => _isCreatingChat = false);
      }
    }
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
          'New Chat',
          style: TextStyle(
            color: AppConstants.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppConstants.darkGray,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: AppConstants.white),
                decoration: InputDecoration(
                  hintText: 'Search by username or name...',
                  hintStyle: const TextStyle(color: AppConstants.textSecondary),
                  border: InputBorder.none,
                  icon: const Icon(Icons.search,
                      color: AppConstants.textSecondary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: AppConstants.textSecondary),
                          onPressed: () {
                            _searchController.clear();
                            _searchUsers('');
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {}); // Update UI for clear button
                  _searchUsers(value);
                },
              ),
            ),
          ),

          // Search Results
          Expanded(
            child: _isCreatingChat
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                            color: AppConstants.primaryBlue),
                        SizedBox(height: 16),
                        Text(
                          'Starting conversation...',
                          style: TextStyle(
                            color: AppConstants.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppConstants.red,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppConstants.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _searchUsers(_searchController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryBlue,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryBlue),
      );
    }

    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: AppConstants.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Search for users',
              style: TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter a username or name to find people',
              style: TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search,
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
            const SizedBox(height: 8),
            const Text(
              'Try a different search term',
              style: TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return ListTile(
          onTap: () => _startConversation(user),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: AppConstants.primaryBlue,
            backgroundImage: user.profileImageUrl != null
                ? NetworkImage(user.profileImageUrl!)
                : null,
            child: user.profileImageUrl == null
                ? const Icon(Icons.person, color: Colors.white, size: 24)
                : null,
          ),
          title: Text(
            user.displayName ?? user.alias,
            style: const TextStyle(
              color: AppConstants.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: user.displayName != null
              ? Text(
                  '@${user.alias}',
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 14,
                  ),
                )
              : user.bio != null && user.bio!.isNotEmpty
                  ? Text(
                      user.bio!,
                      style: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
          trailing: const Icon(
            Icons.chat_bubble_outline,
            color: AppConstants.primaryBlue,
            size: 20,
          ),
        );
      },
    );
  }
}
