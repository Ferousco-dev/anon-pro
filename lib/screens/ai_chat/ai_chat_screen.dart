import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/ai_chat_service.dart';
import '../../models/ai_message.dart';
import '../../utils/constants.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initChat();
    });
  }

  Future<void> _initChat() async {
    final aiService = Provider.of<AiChatService>(context, listen: false);
    await aiService.init();

    // Small delay to ensure Hive history loads
    await Future.delayed(const Duration(milliseconds: 100));

    // If chat is entirely empty, the empty state widget will handle the greeting
    if (aiService.getChatHistory().isEmpty) {
      // Logic for system greeting can go here if needed in the future
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    
    final aiService = Provider.of<AiChatService>(context, listen: false);
    
    // UI optimistic update scroll
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    
    await aiService.sendMessage(text);
    
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: Row(
          children: [
            // Safe network fallback for Lottie since asset might not exist yet
            SizedBox(
              height: 40,
              width: 40,
              child: Lottie.network(
                'https://lottie.host/8e31fc57-19d4-42b6-aae8-d4cbf23fe8d4/f7LpQd8b6n.json', // Placeholder cute robot
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.smart_toy, color: AppConstants.primaryBlue),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Anon AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final aiService = Provider.of<AiChatService>(context, listen: false);
              
              // Ensure user wants to clear
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppConstants.mediumGray,
                  title: const Text('Clear Chat?'),
                  content: const Text('Are you sure you want to delete all chat history with Anon AI?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await aiService.clearHistory();
              }
            },
          )
        ],
      ),
      body: SafeArea(
        child: Consumer<AiChatService>(
          builder: (context, aiService, child) {
            if (!aiService.isInitialized) {
              return const Center(child: CircularProgressIndicator());
            }

            final messages = aiService.getChatHistory();

            return Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? _buildEmptyState(aiService)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isLast = index == messages.length - 1;
                            final suggestions =
                                aiService.getSuggestedQuestions();
                            if (isLast &&
                                !msg.isUser &&
                                suggestions.isNotEmpty &&
                                !aiService.isTyping) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildMessageBubble(msg),
                                  _buildSuggestedQuestionsBar(suggestions),
                                ],
                              );
                            }
                            return _buildMessageBubble(msg);
                          },
                        ),
                ),
                if (aiService.isTyping)
                  Container(
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        SizedBox(
                          height: 30,
                          width: 30,
                          child: Lottie.network(
                            'https://lottie.host/8e31fc57-19d4-42b6-aae8-d4cbf23fe8d4/f7LpQd8b6n.json',
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.smart_toy, size: 20, color: AppConstants.primaryBlue),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Anon is typing...', 
                          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12)
                        ),
                      ],
                    ),
                  ),
                _buildMessageInput(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(AiChatService aiService) {
    final username = Supabase.instance.client.auth.currentUser?.userMetadata?['username'] as String?;
    final greeting = aiService.getGreeting(username);

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.network(
              'https://lottie.host/8e31fc57-19d4-42b6-aae8-d4cbf23fe8d4/f7LpQd8b6n.json', // Placeholder
              height: 200,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.smart_toy, size: 100, color: AppConstants.primaryBlue),
            ),
            const SizedBox(height: 20),
            Text(
              'Anon AI',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                greeting,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(AiMessage msg) {
    final isMe = msg.isUser;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppConstants.mediumGray,
              child: Icon(Icons.smart_toy, size: 18, color: AppConstants.primaryBlue),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? AppConstants.primaryBlue : AppConstants.mediumGray,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 0),
                  bottomRight: Radius.circular(isMe ? 0 : 20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(msg.timestamp),
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 32), // Add spacing for user messages
          if (!isMe) const SizedBox(width: 32), // Add spacing for AI messages
        ],
      ),
    );
  }

  Widget _buildSuggestedQuestionsBar(List<String> suggestions) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final question = suggestions[index];
            return ActionChip(
              label: Text(
                question,
                overflow: TextOverflow.ellipsis,
              ),
              backgroundColor: AppConstants.darkGray,
              labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
              onPressed: () {
                _textController.text = question;
                _sendMessage();
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.mediumGray,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppConstants.black,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ask Anon AI anything...',
                  hintStyle: TextStyle(color: Colors.grey.withOpacity(0.8)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppConstants.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
