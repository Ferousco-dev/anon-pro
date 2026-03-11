import 'package:flutter/material.dart';
import '../../services/anonymous_questions_service.dart';
import '../../utils/constants.dart';

class QAAnswersInboxScreen extends StatefulWidget {
  final String userId;

  const QAAnswersInboxScreen({
    super.key,
    required this.userId,
  });

  @override
  State<QAAnswersInboxScreen> createState() => _QAAnswersInboxScreenState();
}

class _QAAnswersInboxScreenState extends State<QAAnswersInboxScreen> {
  final AnonymousQuestionsService _qaService = AnonymousQuestionsService();
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final notifications =
          await _qaService.getAnswerNotifications(widget.userId);
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _qaService.markNotificationAsRead(notificationId);
      _loadNotifications();
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Question Answers'),
        backgroundColor: AppConstants.black,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mark_email_read_outlined,
                        size: 64,
                        color: AppConstants.textSecondary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No new answers yet',
                        style: TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We\'ll notify you when someone answers your questions',
                        style: TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  color: AppConstants.primaryBlue,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      final questionText =
                          notification['question_text'] as String? ?? '';
                      final createdAt =
                          DateTime.parse(notification['created_at'] as String);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppConstants.primaryBlue.withOpacity(0.15),
                              AppConstants.primaryBlue.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppConstants.primaryBlue.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppConstants.primaryBlue,
                                  AppConstants.primaryBlue.withOpacity(0.5),
                                ],
                              ),
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          title: Text(
                            'Question Answered! 🎉',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                questionText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${createdAt.toLocal().month}/${createdAt.toLocal().day} at ${createdAt.toLocal().hour}:${createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          trailing: ElevatedButton(
                            onPressed: () =>
                                _markAsRead(notification['id'] as String),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                            child: const Text(
                              'View',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
