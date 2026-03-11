import 'package:flutter/material.dart';

import '../../main.dart';
import '../../models/chat_model.dart';
import '../../utils/constants.dart';
import '../inbox/conversation_screen.dart';

class ProfileDmLauncher extends StatefulWidget {
  final String otherUserId;
  final String otherAlias;
  final String? otherDisplayName;
  final String? otherProfileImageUrl;

  const ProfileDmLauncher({
    required this.otherUserId,
    required this.otherAlias,
    this.otherDisplayName,
    this.otherProfileImageUrl,
  });

  @override
  State<ProfileDmLauncher> createState() => _ProfileDmLauncherState();
}

class _ProfileDmLauncherState extends State<ProfileDmLauncher> {
  bool _isCreating = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startConversation();
  }

  Future<void> _startConversation() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _error = 'You must be logged in to send a message';
        _isCreating = false;
      });
      return;
    }

    try {
      // ── PRIVACY CHECK ──
      // Fetch both users to check if the currentUser is allowed to DM the target
      final currentUserProfileRes = await supabase
          .from('users')
          .select('is_verified, role')
          .eq('id', currentUser.id)
          .single();
          
      final targetUserProfileRes = await supabase
          .from('users')
          .select('dm_privacy')
          .eq('id', widget.otherUserId)
          .single();

      final dmPrivacy = targetUserProfileRes['dm_privacy'] as String? ?? 'everyone';
      final isCurrentUserVerified = (currentUserProfileRes['is_verified'] as bool? ?? false) || 
                                    (currentUserProfileRes['role'] == 'admin') || 
                                    (currentUserProfileRes['role'] == 'premium');

      if (dmPrivacy == 'verified_only' && !isCurrentUserVerified) {
        if (mounted) {
          setState(() {
            _error = 'This user only receives messages from Verified members.';
            _isCreating = false;
          });
        }
        return;
      }

      // Check for existing 1:1 conversation between currentUser and otherUser
      final existingConversations = await supabase
          .from('conversation_participants')
          .select('conversation_id, conversations!inner(is_group)')
          .eq('user_id', currentUser.id);

      String? existingConversationId;

      for (final item in existingConversations as List) {
        final conversationId = item['conversation_id'] as String;
        final isGroup = item['conversations']['is_group'] as bool? ?? false;
        if (isGroup) continue;

        final otherInConversation = await supabase
            .from('conversation_participants')
            .select('id')
            .eq('conversation_id', conversationId)
            .eq('user_id', widget.otherUserId);

        if (otherInConversation.isNotEmpty) {
          existingConversationId = conversationId;
          break;
        }
      }

      String conversationId;

      if (existingConversationId != null) {
        conversationId = existingConversationId;
      } else {
        final name = widget.otherDisplayName ?? '@${widget.otherAlias}';

        final newConversation = await supabase
            .from('conversations')
            .insert({
              'name': name,
              'is_group': false,
              'created_by': currentUser.id,
            })
            .select('id')
            .single();

        conversationId = newConversation['id'] as String;

        await supabase.from('conversation_participants').insert([
          {
            'conversation_id': conversationId,
            'user_id': currentUser.id,
          },
          {
            'conversation_id': conversationId,
            'user_id': widget.otherUserId,
          },
        ]);
      }

      if (!mounted) return;

      final chat = ChatModel(
        id: conversationId,
        name: widget.otherDisplayName ?? widget.otherAlias,
        isGroup: false,
        otherUserId: widget.otherUserId,
        otherUserAlias: widget.otherAlias,
        otherUserDisplayName: widget.otherDisplayName,
        otherUserProfileImageUrl: widget.otherProfileImageUrl,
        participantIds: [currentUser.id, widget.otherUserId],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ConversationScreen(chat: chat),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to start conversation: $e';
        _isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCreating && _error != null) {
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
            'Message',
            style: TextStyle(color: AppConstants.white),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppConstants.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppConstants.black,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppConstants.primaryBlue),
            SizedBox(height: 16),
            Text(
              'Opening chat...',
              style: TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
