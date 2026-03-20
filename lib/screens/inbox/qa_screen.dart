import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/anonymous_question_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import 'package:timeago/timeago.dart' as timeago;

class QaScreen extends StatefulWidget {
  final String currentUserId;
  final bool isVerified;

  const QaScreen({
    super.key,
    required this.currentUserId,
    required this.isVerified,
  });

  @override
  State<QaScreen> createState() => _QaScreenState();
}

class _QaScreenState extends State<QaScreen> {
  final _supabase = Supabase.instance.client;
  List<AnonymousQuestionModel> _receivedQuestions = [];
  List<AnonymousQuestionModel> _sentQuestions = [];
  bool _isLoading = true;
  String _qaFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAllQuestions();
  }

  Future<void> _loadAllQuestions() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      // 1. Fetch Received
      final recvRes = await _supabase
          .from('anonymous_questions')
          .select('*, asker:users!asker_user_id(id, alias, profile_image_url)')
          .eq('target_user_id', widget.currentUserId)
          .order('created_at', ascending: false);

      final received = (recvRes as List)
          .map((q) => AnonymousQuestionModel.fromJson(q))
          .toList();

      // 2. Fetch Sent
      final sentRes = await _supabase
          .from('anonymous_questions')
          .select('*, target:users!target_user_id(alias, profile_image_url)')
          .eq('asker_user_id', widget.currentUserId)
          .order('created_at', ascending: false);

      final sent =
          (sentRes as List).map((q) => AnonymousQuestionModel.fromJson(q)).toList();

      if (mounted) {
        setState(() {
          _receivedQuestions = received;
          _sentQuestions = sent;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading Q&A: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAnswerDialog(AnonymousQuestionModel question) {
    if (!widget.isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only verified members can answer Q&A')),
      );
      return;
    }

    final answerController = TextEditingController(text: question.answer ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        title: const Text('Answer Question',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.mediumGray,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${question.question}"',
                style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: answerController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type your answer...',
                hintStyle: const TextStyle(color: AppConstants.textSecondary),
                filled: true,
                fillColor: AppConstants.mediumGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppConstants.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryBlue,
            ),
            onPressed: () async {
              final answer = answerController.text.trim();
              if (answer.isEmpty) return;

              Navigator.pop(context);

              try {
                await _supabase.from('anonymous_questions').update({
                  'answer': answer,
                  'answered': true,
                  'answered_at': DateTime.now().toIso8601String(),
                }).eq('id', question.id);

                _loadAllQuestions(); // Reload list
              } catch (e) {
                debugPrint('Error answering question: $e');
              }
            },
            child: const Text('Post', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receivedAnswered = _receivedQuestions
        .where((q) => q.answered && q.answer != null)
        .toList();
    final receivedPending = _receivedQuestions
        .where((q) => !q.answered || q.answer == null)
        .toList();

    final counts = <String, int>{
      'all': _receivedQuestions.length + _sentQuestions.length,
      'inbox': _receivedQuestions.length,
      'answered': receivedAnswered.length,
      'pending': receivedPending.length,
      'sent': _sentQuestions.length,
    };

    final items = _buildFilteredItems(
      received: _receivedQuestions,
      receivedAnswered: receivedAnswered,
      receivedPending: receivedPending,
      sent: _sentQuestions,
    );

    return Column(
      children: [
        _buildQaFilters(counts),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppConstants.primaryBlue))
              : _buildQuestionsList(items),
        ),
      ],
    );
  }

  List<_QaItem> _buildFilteredItems({
    required List<AnonymousQuestionModel> received,
    required List<AnonymousQuestionModel> receivedAnswered,
    required List<AnonymousQuestionModel> receivedPending,
    required List<AnonymousQuestionModel> sent,
  }) {
    switch (_qaFilter) {
      case 'inbox':
        return received.map((q) => _QaItem(q, isSent: false)).toList();
      case 'answered':
        return receivedAnswered.map((q) => _QaItem(q, isSent: false)).toList();
      case 'pending':
        return receivedPending.map((q) => _QaItem(q, isSent: false)).toList();
      case 'sent':
        return sent.map((q) => _QaItem(q, isSent: true)).toList();
      default:
        final merged = <_QaItem>[
          ...received.map((q) => _QaItem(q, isSent: false)),
          ...sent.map((q) => _QaItem(q, isSent: true)),
        ];
        merged.sort((a, b) => b.question.createdAt.compareTo(a.question.createdAt));
        return merged;
    }
  }

  Widget _buildQaFilters(Map<String, int> counts) {
    final items = [
      const _QaFilterItem('all', 'All', Icons.inventory_2_rounded),
      const _QaFilterItem('inbox', 'Inbox', Icons.inbox_rounded),
      const _QaFilterItem('answered', 'Answered', Icons.check_circle_rounded),
      const _QaFilterItem('pending', 'Pending', Icons.schedule_rounded),
      const _QaFilterItem('sent', 'Sent', Icons.send_rounded),
    ];

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final isActive = _qaFilter == item.id;
          final count = counts[item.id] ?? 0;
          return GestureDetector(
            onTap: () {
              if (_qaFilter == item.id) return;
              setState(() => _qaFilter = item.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive
                    ? AppConstants.primaryBlue.withOpacity(0.18)
                    : AppConstants.darkGray,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? AppConstants.primaryBlue
                      : AppConstants.dividerColor,
                ),
              ),
              child: Row(
                children: [
                  Icon(item.icon,
                      size: 16,
                      color: isActive
                          ? AppConstants.primaryBlue
                          : AppConstants.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: isActive ? Colors.white : AppConstants.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppConstants.primaryBlue
                            : AppConstants.textSecondary.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionsList(List<_QaItem> items) {
    if (items.isEmpty) {
      return _buildQaEmptyState();
    }

    return RefreshIndicator(
      color: AppConstants.primaryBlue,
      backgroundColor: AppConstants.darkGray,
      onRefresh: _loadAllQuestions,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return item.isSent
              ? _buildSentCard(item.question)
              : _buildReceivedCard(item.question);
        },
      ),
    );
  }

  Widget _buildQaEmptyState() {
    String title = 'No questions yet';
    String subtitle = 'Questions will appear here as they arrive.';
    IconData icon = Icons.inventory_2_outlined;

    switch (_qaFilter) {
      case 'inbox':
        title = 'Inbox is empty';
        subtitle = 'New questions will show up here.';
        icon = Icons.inbox_rounded;
        break;
      case 'answered':
        title = 'No answered questions';
        subtitle = 'Your answered Q&A will show up here.';
        icon = Icons.check_circle_outline;
        break;
      case 'pending':
        title = 'No pending questions';
        subtitle = 'You are all caught up for now.';
        icon = Icons.schedule_rounded;
        break;
      case 'sent':
        title = 'No questions sent';
        subtitle = 'Questions you ask others will appear here.';
        icon = Icons.send_outlined;
        break;
      default:
        if (!widget.isVerified) {
          subtitle =
              'Only verified users can receive and answer anonymous questions.';
        }
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 56, color: AppConstants.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedCard(AnonymousQuestionModel q) {
    final isAnswered = q.answered && q.answer != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAnswered
              ? AppConstants.primaryBlue.withOpacity(0.3)
              : AppConstants.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isAnswered
                      ? AppConstants.primaryBlue.withOpacity(0.2)
                      : AppConstants.mediumGray,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isAnswered ? 'Answered' : 'New Question',
                  style: TextStyle(
                    color: isAnswered
                        ? AppConstants.primaryBlue
                        : AppConstants.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                timeago.format(q.createdAt),
                style: const TextStyle(
                    color: AppConstants.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            q.question,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isAnswered) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.mediumGray,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Answer:',
                    style: TextStyle(
                      color: AppConstants.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    q.answer!,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            )
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showAnswerDialog(q),
              style: TextButton.styleFrom(
                foregroundColor: AppConstants.primaryBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                backgroundColor: AppConstants.primaryBlue.withOpacity(0.1),
              ),
              child: Text(
                isAnswered ? 'Edit Answer' : 'Answer',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSentCard(AnonymousQuestionModel q) {
    final isAnswered = q.answered && q.answer != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppConstants.mediumGray,
                backgroundImage: q.targetUserProfileImageUrl != null
                    ? NetworkImage(q.targetUserProfileImageUrl!)
                    : null,
                child: q.targetUserProfileImageUrl == null
                    ? const Icon(Icons.person,
                        size: 16, color: Colors.white54)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'You asked @${q.targetUserAlias ?? 'unknown'}',
                style: const TextStyle(
                  color: AppConstants.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                timeago.format(q.createdAt),
                style: const TextStyle(
                    color: AppConstants.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            q.question,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (isAnswered)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppConstants.primaryBlue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 14, color: AppConstants.primaryBlue),
                      SizedBox(width: 6),
                      Text(
                        'Answered',
                        style: TextStyle(
                          color: AppConstants.primaryBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    q.answer!,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 14, color: Colors.white.withOpacity(0.4)),
                const SizedBox(width: 6),
                Text(
                  'Waiting for answer...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _QaItem {
  final AnonymousQuestionModel question;
  final bool isSent;

  const _QaItem(this.question, {required this.isSent});
}

class _QaFilterItem {
  final String id;
  final String label;
  final IconData icon;

  const _QaFilterItem(this.id, this.label, this.icon);
}
