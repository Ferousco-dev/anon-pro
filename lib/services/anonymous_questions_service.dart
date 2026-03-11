import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/anonymous_question_model.dart';

class AnonymousQuestionsService {
  static final AnonymousQuestionsService _instance =
      AnonymousQuestionsService._internal();

  factory AnonymousQuestionsService() {
    return _instance;
  }

  AnonymousQuestionsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Submit an anonymous question to a user
  Future<String> submitQuestion({
    required String targetUserId,
    required String question,
  }) async {
    try {
      final res = await _supabase
          .from('anonymous_questions')
          .insert({
            'target_user_id': targetUserId,
            'asker_user_id': _supabase.auth.currentUser?.id,
            'question': question,
          })
          .select()
          .single();

      return res['id'] as String;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all questions for a user (only callable by the user or admin)
  Future<List<AnonymousQuestionModel>> getUserQuestions(
      String targetUserId) async {
    try {
      final res = await _supabase
          .from('anonymous_questions')
          .select('*')
          .eq('target_user_id', targetUserId)
          .order('created_at', ascending: false);

      return (res as List)
          .map((q) => AnonymousQuestionModel.fromJson(q))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Get unanswered questions
  Future<List<AnonymousQuestionModel>> getUnansweredQuestions(
      String targetUserId) async {
    try {
      final res = await _supabase
          .from('anonymous_questions')
          .select('*')
          .eq('target_user_id', targetUserId)
          .eq('answered', false)
          .order('created_at', ascending: false);

      return (res as List)
          .map((q) => AnonymousQuestionModel.fromJson(q))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Get questions I have sent to others
  Future<List<AnonymousQuestionModel>> getSentQuestions(String askerId) async {
    try {
      final res = await _supabase
          .from('anonymous_questions')
          .select('*, target:users!target_user_id(alias, profile_image_url)')
          .eq('asker_user_id', askerId)
          .order('created_at', ascending: false);

      return (res as List)
          .map((q) => AnonymousQuestionModel.fromJson(q))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Answer a question and notify the asker
  Future<void> answerQuestion({
    required String questionId,
    required String answer,
    required bool publishAnswer,
  }) async {
    try {
      // First, get the question to know who asked it
      final question = await _supabase
          .from('anonymous_questions')
          .select('*')
          .eq('id', questionId)
          .single();

      final askerUserId = question['asker_user_id'];
      final targetUserId = question['target_user_id'];

      // Update the question with answer
      await _supabase.from('anonymous_questions').update({
        'answer': answer,
        'answered': true,
        'answered_at': DateTime.now().toIso8601String(),
        'is_public': publishAnswer,
      }).eq('id', questionId);

      // Send notification to the asker if they exist
      if (askerUserId != null) {
        try {
          await _supabase.from('qa_answer_notifications').insert({
            'asker_id': askerUserId,
            'answerer_id': targetUserId,
            'question_id': questionId,
            'question_text': question['question'],
            'is_read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (notificationError) {
          // Log but don't fail the answer if notification fails
          print('Error sending Q&A notification: $notificationError');
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a question
  Future<void> deleteQuestion(String questionId) async {
    try {
      await _supabase.from('anonymous_questions').delete().eq('id', questionId);
    } catch (e) {
      rethrow;
    }
  }

  /// Get all public answers from a user
  Future<List<AnonymousQuestionModel>> getPublicAnswers(
      String targetUserId) async {
    try {
      final res = await _supabase
          .from('anonymous_questions')
          .select('*')
          .eq('target_user_id', targetUserId)
          .eq('is_public', true)
          .eq('answered', true)
          .order('answered_at', ascending: false);

      return (res as List)
          .map((q) => AnonymousQuestionModel.fromJson(q))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Check if user has Q&A mode enabled
  Future<bool> isQAEnabled(String userId) async {
    try {
      final res = await _supabase
          .from('users')
          .select('qa_enabled')
          .eq('id', userId)
          .single();

      return res['qa_enabled'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Enable/disable Q&A mode
  Future<void> setQAEnabled(String userId, bool enabled) async {
    try {
      await _supabase
          .from('users')
          .update({'qa_enabled': enabled}).eq('id', userId);
    } catch (e) {
      rethrow;
    }
  }

  /// Get Q&A answer notifications for a user
  Future<List<Map<String, dynamic>>> getAnswerNotifications(
      String askerId) async {
    try {
      final res = await _supabase
          .from('qa_answer_notifications')
          .select('*')
          .eq('asker_id', askerId)
          .eq('is_read', false)
          .order('created_at', ascending: false);

      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error fetching notifications: $e');
      return [];
    }
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _supabase
          .from('qa_answer_notifications')
          .update({'is_read': true}).eq('id', notificationId);
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  /// Get answered questions for the person who asked
  Future<List<AnonymousQuestionModel>> getMyAnsweredQuestions(
      String askerId) async {
    try {
      final res = await _supabase
          .from('anonymous_questions')
          .select('*')
          .eq('asker_user_id', askerId)
          .eq('answered', true)
          .order('answered_at', ascending: false);

      return (res as List)
          .map((q) => AnonymousQuestionModel.fromJson(q))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Subscribe to answer notifications
  RealtimeChannel subscribeToAnswerNotifications(String askerId) {
    return _supabase
        .channel('answers:$askerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'qa_answer_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'asker_id',
            value: askerId,
          ),
          callback: (payload) {
            // Handled by the caller
          },
        )
        .subscribe();
  }

  /// Subscribe to new questions
  RealtimeChannel subscribeToQuestions(String targetUserId) {
    return _supabase
        .channel('questions:$targetUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'anonymous_questions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'target_user_id',
            value: targetUserId,
          ),
          callback: (payload) {
            // Handled by the caller
          },
        )
        .subscribe();
  }
}
