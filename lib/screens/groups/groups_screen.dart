import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../main.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _error = 'User not logged in';
        });
        return;
      }

      // Try to load conversations via RPC first
      List response;
      try {
        response = await supabase.rpc('get_user_conversations',
            params: {'user_uuid': currentUser.id});
      } catch (e) {
        // Fallback to empty list if RPC doesn't exist yet
        response = [];
      }

      if (mounted) {
        setState(() {
          _conversations = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToConversation(Map<String, dynamic> conversation) {
    // TODO: Navigate to conversation detail screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Opening conversation: ${conversation['name'] ?? 'Chat'}')),
    );
  }

  void _startNewChat() {
    // TODO: Show user search to start new conversation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New chat coming soon!')),
    );
  }

  String _formatLastMessageTime(String? timeStr) {
    if (timeStr == null) return '';

    try {
      final time = DateTime.parse(timeStr);
      final now = DateTime.now();
      final difference = now.difference(time);

      if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/images/anon.png',
              height: 32,
            ),
            const SizedBox(width: 8),
            const Text(
              'ANONPRO',
              style: TextStyle(
                color: AppConstants.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () {
              // TODO: Navigate to search screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search coming soon!')),
              );
            },
            icon: const Icon(Icons.search, color: AppConstants.white),
          ),
          IconButton(
            onPressed: () {
              final currentUser = supabase.auth.currentUser;
              if (currentUser != null && currentUser.id.isNotEmpty) {
                Navigator.pushNamed(context, '/profile',
                    arguments: currentUser.id);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please log in to view profile'),
                    backgroundColor: AppConstants.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.person, color: AppConstants.white),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Error loading conversations',
                          style: TextStyle(
                            color: AppConstants.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppConstants.textSecondary,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadConversations,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _conversations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: AppConstants.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No conversations yet',
                            style: TextStyle(
                              color: AppConstants.textSecondary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start a new conversation to see it here',
                            style: TextStyle(
                              color: AppConstants.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _startNewChat,
                            icon: const Icon(Icons.add),
                            label: const Text('Start New Chat'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.primaryBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadConversations,
                      color: AppConstants.primaryBlue,
                      backgroundColor: AppConstants.darkGray,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final conversation = _conversations[index];
                          final unreadCount =
                              conversation['unread_count'] as int? ?? 0;
                          final lastMessage =
                              conversation['last_message_content'] as String?;
                          final lastMessageTime =
                              conversation['last_message_time'] as String?;

                          return ListTile(
                            onTap: () => _navigateToConversation(conversation),
                            leading: CircleAvatar(
                              radius: 28,
                              backgroundColor: AppConstants.primaryBlue,
                              child: conversation['is_group'] == true
                                  ? const Icon(Icons.group,
                                      color: Colors.white, size: 28)
                                  : const Icon(Icons.person,
                                      color: Colors.white, size: 28),
                            ),
                            title: Text(
                              conversation['name'] as String? ?? 'Unknown',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: lastMessage != null
                                ? Text(
                                    lastMessage.length > 50
                                        ? '${lastMessage.substring(0, 50)}...'
                                        : lastMessage,
                                    style: TextStyle(
                                      color: AppConstants.textSecondary,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Text(
                                    'No messages yet',
                                    style: TextStyle(
                                      color: AppConstants.textSecondary
                                          .withOpacity(0.7),
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (lastMessageTime != null)
                                  Text(
                                    _formatLastMessageTime(lastMessageTime),
                                    style: TextStyle(
                                      color: AppConstants.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (unreadCount > 0) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppConstants.primaryBlue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      unreadCount > 99
                                          ? '99+'
                                          : unreadCount.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: AppConstants.primaryBlue,
        child: const Icon(Icons.add_comment),
      ),
    );
  }
}
