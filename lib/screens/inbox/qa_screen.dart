import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _QaScreenState extends State<QaScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  List<AnonymousQuestionModel> _receivedQuestions = [];
  List<AnonymousQuestionModel> _sentQuestions = [];
  bool _isLoading = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllQuestions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    return Column(
      children: [
        // TabBar
        Container(
          height: 46,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppConstants.darkGray,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppConstants.dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppConstants.mediumGray,
                borderRadius: BorderRadius.circular(8),
              ),
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppConstants.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Received'),
                Tab(text: 'Sent'),
              ],
            ),
          ),
        ),
        // TabBarView
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppConstants.primaryBlue))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildReceivedTab(),
                    _buildSentTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildReceivedTab() {
    if (_receivedQuestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 60, color: AppConstants.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'Your Q&A is empty',
              style: TextStyle(color: AppConstants.textSecondary, fontSize: 16),
            ),
            if (!widget.isVerified) ...[
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Only verified users can receive and answer anonymous questions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppConstants.textSecondary, fontSize: 13),
                ),
              )
            ]
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppConstants.primaryBlue,
      backgroundColor: AppConstants.darkGray,
      onRefresh: _loadAllQuestions,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _receivedQuestions.length,
        itemBuilder: (context, index) {
          final q = _receivedQuestions[index];
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      backgroundColor:
                          AppConstants.primaryBlue.withOpacity(0.1),
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
        },
      ),
    );
  }

  Widget _buildSentTab() {
    if (_sentQuestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_outlined,
                size: 60, color: AppConstants.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'No questions sent',
              style: TextStyle(color: AppConstants.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Questions you ask others will appear here.',
              style: TextStyle(color: AppConstants.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppConstants.primaryBlue,
      backgroundColor: AppConstants.darkGray,
      onRefresh: _loadAllQuestions,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _sentQuestions.length,
        itemBuilder: (context, index) {
          final q = _sentQuestions[index];
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
                // Target User Row
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
                // The Question
                Text(
                  q.question,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // The Answer or Pending State
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
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
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
        },
      ),
    );
  }
}
