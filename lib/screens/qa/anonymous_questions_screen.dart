import 'package:flutter/material.dart';
import '../../models/anonymous_question_model.dart';
import '../../services/anonymous_questions_service.dart';
import '../../utils/constants.dart';

class AnonymousQuestionsScreen extends StatefulWidget {
  final String userId;
  final bool isOwner;

  const AnonymousQuestionsScreen({
    super.key,
    required this.userId,
    required this.isOwner,
  });

  @override
  State<AnonymousQuestionsScreen> createState() =>
      _AnonymousQuestionsScreenState();
}

class _AnonymousQuestionsScreenState extends State<AnonymousQuestionsScreen> {
  final AnonymousQuestionsService _qaService = AnonymousQuestionsService();
  List<AnonymousQuestionModel> _questions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    try {
      final questions = widget.isOwner
          ? await _qaService.getUserQuestions(widget.userId)
          : await _qaService.getPublicAnswers(widget.userId);

      if (mounted) {
        setState(() {
          _questions = questions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading questions: $e')),
        );
      }
    }
  }

  Future<void> _answerQuestion(
    String questionId,
    String answer,
    bool publish,
  ) async {
    try {
      await _qaService.answerQuestion(
        questionId: questionId,
        answer: answer,
        publishAnswer: publish,
      );

      if (mounted) {
        _loadQuestions();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Question answered!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error answering question: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  void _showAnswerDialog(AnonymousQuestionModel question) {
    final controller = TextEditingController();
    bool publish = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppConstants.darkGray,
          title: const Text('Answer Question',
              style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  question.question,
                  style: const TextStyle(color: AppConstants.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Your answer...',
                    hintStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                    border: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: AppConstants.darkGray),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: publish,
                  onChanged: (v) {
                    setState(() => publish = v ?? false);
                  },
                  title: const Text(
                    'Publish answer publicly',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  checkColor: Colors.white,
                  activeColor: AppConstants.primaryBlue,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppConstants.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  _answerQuestion(question.id, controller.text, publish);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Post Answer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        title: Text(
          widget.isOwner ? 'Questions for You' : 'Public Q&A',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppConstants.primaryBlue),
              ),
            )
          : _questions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.isOwner
                            ? Icons.mail_outline
                            : Icons.help_outline,
                        size: 48,
                        color: AppConstants.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.isOwner
                            ? 'No questions yet'
                            : 'No public answers',
                        style: const TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _questions.length,
                  itemBuilder: (ctx, idx) {
                    final q = _questions[idx];
                    return Card(
                      color: AppConstants.darkGray,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.question,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (q.answered)
                              Container(
                                decoration: BoxDecoration(
                                  color:
                                      AppConstants.primaryBlue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Answer:',
                                      style: TextStyle(
                                        color: AppConstants.primaryBlue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      q.answer ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (widget.isOwner)
                              ElevatedButton.icon(
                                onPressed: () => _showAnswerDialog(q),
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text('Answer'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppConstants.primaryBlue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
