import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/poll_model.dart';

class PollsService {
  static final PollsService _instance = PollsService._internal();

  factory PollsService() {
    return _instance;
  }

  PollsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a new poll for a post
  Future<String> createPoll({
    required String postId,
    required String question,
    required List<String> options,
  }) async {
    try {
      // Insert poll
      final pollRes = await _supabase
          .from('polls')
          .insert({
            'post_id': postId,
            'question': question,
          })
          .select()
          .single();

      final pollId = pollRes['id'] as String;

      // Insert options
      for (final option in options) {
        await _supabase.from('poll_options').insert({
          'poll_id': pollId,
          'option_text': option,
          'vote_count': 0,
        });
      }

      return pollId;
    } catch (e) {
      rethrow;
    }
  }

  /// Get poll with options
  Future<PollModel> getPoll(String pollId) async {
    try {
      final pollRes =
          await _supabase.from('polls').select('*').eq('id', pollId).single();

      final optionsRes = await _supabase
          .from('poll_options')
          .select('*')
          .eq('poll_id', pollId);

      final optionsData = optionsRes.cast<Map<String, dynamic>>();
      return PollModel.fromJson(pollRes, optionsData: optionsData);
    } catch (e) {
      rethrow;
    }
  }

  /// Get polls for a post
  Future<List<PollModel>> getPollsByPost(String postId) async {
    try {
      final pollsRes =
          await _supabase.from('polls').select('*').eq('post_id', postId);

      final polls = <PollModel>[];
      for (final poll in pollsRes) {
        final optionsRes = await _supabase
            .from('poll_options')
            .select('*')
            .eq('poll_id', poll['id']);

        final optionsData = optionsRes.cast<Map<String, dynamic>>();
        polls.add(PollModel.fromJson(poll, optionsData: optionsData));
      }

      return polls;
    } catch (e) {
      rethrow;
    }
  }

  /// Vote on a poll option
  Future<void> votePoll({
    required String pollId,
    required String optionId,
    required String userId,
  }) async {
    try {
      // Insert vote
      await _supabase.from('poll_votes').insert({
        'poll_id': pollId,
        'option_id': optionId,
        'user_id': userId,
      });

      // Update vote count on option
      final currentOption = await _supabase
          .from('poll_options')
          .select('vote_count')
          .eq('id', optionId)
          .single();

      final currentCount = currentOption['vote_count'] as int? ?? 0;
      await _supabase
          .from('poll_options')
          .update({'vote_count': currentCount + 1}).eq('id', optionId);
    } catch (e) {
      rethrow;
    }
  }

  /// Check if user has voted on this poll
  Future<bool> userHasVoted({
    required String pollId,
    required String userId,
  }) async {
    try {
      final result = await _supabase
          .from('poll_votes')
          .select('id')
          .eq('poll_id', pollId)
          .eq('user_id', userId)
          .maybeSingle();

      return result != null;
    } catch (e) {
      return false;
    }
  }

  /// Get user's vote option (if any) on a poll
  Future<String?> getUserVote({
    required String pollId,
    required String userId,
  }) async {
    try {
      final result = await _supabase
          .from('poll_votes')
          .select('option_id')
          .eq('poll_id', pollId)
          .eq('user_id', userId)
          .maybeSingle();

      return result?['option_id'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Delete a poll (only creator should be able to do this)
  Future<void> deletePoll(String pollId) async {
    try {
      // Cascade delete is handled by database constraints
      await _supabase.from('polls').delete().eq('id', pollId);
    } catch (e) {
      rethrow;
    }
  }
}
