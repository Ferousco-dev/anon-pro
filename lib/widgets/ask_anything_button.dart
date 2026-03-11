import 'package:flutter/material.dart';
import '../../services/anonymous_questions_service.dart';
import '../../utils/constants.dart';

class AskAnyThingButton extends StatefulWidget {
  final String targetUserId;
  final VoidCallback? onQuestionSubmitted;

  const AskAnyThingButton({
    super.key,
    required this.targetUserId,
    this.onQuestionSubmitted,
  });

  @override
  State<AskAnyThingButton> createState() => _AskAnyThingButtonState();
}

class _AskAnyThingButtonState extends State<AskAnyThingButton> {
  final AnonymousQuestionsService _qaService = AnonymousQuestionsService();
  bool _isSubmitting = false;

  void _showAskDialog() {
    final questionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.darkGray,
        title: const Text(
          'Ask a Question',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: questionController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Your anonymous question...',
            hintStyle: const TextStyle(color: AppConstants.textSecondary),
            border: OutlineInputBorder(
              borderSide: const BorderSide(color: AppConstants.darkGray),
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppConstants.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : () async {
                    if (questionController.text.isEmpty) return;

                    setState(() => _isSubmitting = true);

                    try {
                      await _qaService.submitQuestion(
                        targetUserId: widget.targetUserId,
                        question: questionController.text,
                      );

                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Question submitted!'),
                            backgroundColor: AppConstants.primaryBlue,
                          ),
                        );
                        widget.onQuestionSubmitted?.call();
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: AppConstants.red,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isSubmitting = false);
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryBlue,
              disabledBackgroundColor:
                  AppConstants.primaryBlue.withOpacity(0.5),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _showAskDialog,
      icon: const Icon(Icons.help_outline, size: 18),
      label: const Text('Ask Me Anything'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppConstants.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
