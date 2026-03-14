import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/constants.dart';

class ModerationQueueScreen extends StatefulWidget {
  const ModerationQueueScreen({super.key});

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _flags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    try {
      setState(() => _isLoading = true);
      final response = await _client.from('content_flags').select('*').order(
            'created_at',
            ascending: false,
          );
      setState(() {
        _flags = List<Map<String, dynamic>>.from(response as List);
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _applyStrike(String userId) async {
    try {
      await _client.rpc('apply_strike', params: {'p_user_id': userId});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Strike applied'),
          backgroundColor: AppConstants.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to apply strike: $e'),
          backgroundColor: AppConstants.red,
        ),
      );
    }
  }

  Future<void> _banUser(String userId, bool banned) async {
    try {
      await _client.from('users').update({'is_banned': banned}).eq('id', userId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(banned ? 'User banned' : 'User unbanned'),
          backgroundColor: banned ? AppConstants.red : AppConstants.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update ban: $e'),
          backgroundColor: AppConstants.red,
        ),
      );
    }
  }

  Future<void> _dismissFlag(String id) async {
    try {
      await _client.from('content_flags').delete().eq('id', id);
      await _loadFlags();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to dismiss flag: $e'),
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
        title: const Text('Moderation Queue'),
        backgroundColor: AppConstants.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFlags,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : RefreshIndicator(
              onRefresh: _loadFlags,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _flags.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final flag = _flags[index];
                  final userId = flag['user_id'] as String?;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppConstants.darkGray,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppConstants.lightGray.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${flag['content_type']} • ${flag['matched_keyword'] ?? 'keyword'}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Content ID: ${flag['content_id']}',
                          style: const TextStyle(
                              color: AppConstants.textSecondary),
                        ),
                        if (userId != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: () => _applyStrike(userId),
                                child: const Text('Apply Strike'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () => _banUser(userId, true),
                                child: const Text('Ban User'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () =>
                                    _banUser(userId, false),
                                child: const Text('Unban'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => _dismissFlag(flag['id'] as String),
                            child: const Text(
                              'Dismiss',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
