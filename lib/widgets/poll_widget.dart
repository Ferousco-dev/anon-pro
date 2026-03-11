import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/poll_model.dart';
import '../utils/constants.dart';

class PollWidget extends StatefulWidget {
  final String postId;
  final String? currentUserId;

  const PollWidget({
    super.key,
    required this.postId,
    this.currentUserId,
  });

  @override
  State<PollWidget> createState() => _PollWidgetState();
}

class _PollWidgetState extends State<PollWidget> {
  final _supabase = Supabase.instance.client;
  PollModel? _poll;
  String? _userVotedOptionId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPollData();
    // Setup realtime subscription
    _setupRealtime();
  }

  void _setupRealtime() {
    _supabase
        .channel('public:poll_votes')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'poll_votes',
            callback: (payload) {
              // If a new vote comes in, refetch to get updated counts
              // We could also do this locally to save reads, but a quick refetch is safer for accurate counts
              _fetchPollData();
            })
        .subscribe();
  }

  @override
  void dispose() {
    _supabase.removeAllChannels();
    super.dispose();
  }

  Future<void> _fetchPollData() async {
    try {
      if (!mounted) return;
      
      // 1. Fetch poll
      final pollRes = await _supabase
          .from('polls')
          .select()
          .eq('post_id', widget.postId)
          .maybeSingle();

      if (pollRes == null) {
        if (mounted) {
          setState(() {
            _poll = null;
            _isLoading = false;
          });
        }
        return;
      }

      final pollId = pollRes['id'] as String;

      // 2. Fetch options
      final optionsRes = await _supabase
          .from('poll_options')
          .select()
          .eq('poll_id', pollId)
          .order('created_at', ascending: true);

      // 3. Fetch votes count for each option (we can do this by counting locally if we fetch all votes, or use an RPC. Since we don't have an RPC, we will fetch votes for this poll)
      final votesRes = await _supabase
          .from('poll_votes')
          .select('option_id, user_id')
          .eq('poll_id', pollId);

      final votesList = votesRes as List<dynamic>;
      
      // Calculate counts and check if current user voted
      final Map<String, int> voteCounts = {};
      String? userVotedId;
      
      for (var v in votesList) {
        final optId = v['option_id'] as String;
        final voterId = v['user_id'] as String;
        
        voteCounts[optId] = (voteCounts[optId] ?? 0) + 1;
        
        if (widget.currentUserId != null && voterId == widget.currentUserId) {
          userVotedId = optId;
        }
      }

      // 4. Construct Models
      final options = (optionsRes as List<dynamic>).map((optMap) {
        final id = optMap['id'] as String;
        return PollOptionModel(
          id: id,
          pollId: pollId,
          optionText: optMap['option_text'] as String,
          voteCount: voteCounts[id] ?? 0,
        );
      }).toList();

      final totalVotes = votesList.length;

      final poll = PollModel(
        id: pollId,
        postId: widget.postId,
        question: pollRes['question'] as String,
        options: options,
        createdAt: DateTime.parse(pollRes['created_at'] as String),
        totalVotes: totalVotes,
      );

      if (mounted) {
        setState(() {
          _poll = poll;
          _userVotedOptionId = userVotedId;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching poll: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitVote(String optionId) async {
    if (widget.currentUserId == null) return;
    if (_poll == null) return;
    if (_userVotedOptionId == optionId) return; // already voted for this option

    final previousOptionId = _userVotedOptionId;

    // Optimistic update
    setState(() {
      _userVotedOptionId = optionId;
      
      // Update local counts
      final currOptions = _poll!.options;
      final newOptions = currOptions.map((opt) {
        int newCount = opt.voteCount;
        if (opt.id == previousOptionId) newCount = newCount > 0 ? newCount - 1 : 0;
        if (opt.id == optionId) newCount++;
        
        return PollOptionModel(
          id: opt.id,
          pollId: opt.pollId,
          optionText: opt.optionText,
          voteCount: newCount,
        );
      }).toList();
      
      _poll = PollModel(
        id: _poll!.id,
        postId: _poll!.postId,
        question: _poll!.question,
        options: newOptions,
        createdAt: _poll!.createdAt,
        totalVotes: previousOptionId == null ? _poll!.totalVotes + 1 : _poll!.totalVotes,
      );
    });

    try {
      if (previousOptionId != null) {
        // User is changing their vote
        await _supabase
            .from('poll_votes')
            .update({'option_id': optionId})
            .eq('poll_id', _poll!.id)
            .eq('user_id', widget.currentUserId!);
      } else {
        // New vote
        await _supabase.from('poll_votes').insert({
          'poll_id': _poll!.id,
          'option_id': optionId,
          'user_id': widget.currentUserId,
        });
      }
      // the real-time listener will fetch the fresh counts
    } catch (e) {
      debugPrint('Error inserting vote: $e');
      // Ideally revert optimistic update on failure
      _fetchPollData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Center(
          child: SizedBox(
            width: 20, 
            height: 20, 
            child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryBlue)
          ),
        ),
      );
    }

    if (_poll == null) {
      return const SizedBox.shrink(); // No poll for this post
    }

    final hasVoted = _userVotedOptionId != null;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question
          Row(
            children: [
              const Icon(Icons.poll_rounded, size: 18, color: AppConstants.primaryBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _poll!.question,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Options
          ..._poll!.options.map((option) {
            final isSelected = option.id == _userVotedOptionId;
            final percentage = _poll!.totalVotes > 0 
                ? (option.voteCount / _poll!.totalVotes) 
                : 0.0;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: hasVoted 
                  ? _buildVotedOption(option, percentage, isSelected)
                  : _buildUnvotedOption(option),
            );
          }),
          
          // Total votes
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              '${_poll!.totalVotes} vote${_poll!.totalVotes == 1 ? '' : 's'}',
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 12,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildUnvotedOption(PollOptionModel option) {
    return GestureDetector(
      onTap: () => _submitVote(option.id),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.primaryBlue.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Text(
          option.optionText,
          style: const TextStyle(
            color: AppConstants.primaryBlue,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildVotedOption(PollOptionModel option, double percentage, bool isSelected) {
    return GestureDetector(
      onTap: () => _submitVote(option.id),
      child: Stack(
        children: [
        // Background bar
        Container(
          height: 40,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppConstants.mediumGray,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        // Fill bar
        FractionallySizedBox(
          widthFactor: percentage,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: isSelected 
                  ? AppConstants.primaryBlue.withOpacity(0.5) 
                  : AppConstants.lightGray.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        // Text & Percentage
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    option.optionText,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppConstants.textSecondary,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                  ]
                ],
              ),
              Text(
                '${(percentage * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: isSelected ? Colors.white : AppConstants.textSecondary,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
   );
  }
}
