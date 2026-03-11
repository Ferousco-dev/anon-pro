class PollModel {
  final String id;
  final String postId;
  final String question;
  final List<PollOptionModel> options;
  final DateTime createdAt;
  final int totalVotes;

  PollModel({
    required this.id,
    required this.postId,
    required this.question,
    required this.options,
    required this.createdAt,
    this.totalVotes = 0,
  });

  factory PollModel.fromJson(Map<String, dynamic> json, {List<Map<String, dynamic>>? optionsData}) {
    final opts = optionsData ?? (json['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final parsedOptions = opts.map((o) => PollOptionModel.fromJson(o)).toList();
    final total = parsedOptions.fold<int>(0, (sum, o) => sum + o.voteCount);

    return PollModel(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      question: json['question'] as String,
      options: parsedOptions,
      createdAt: DateTime.parse(json['created_at'] as String),
      totalVotes: total,
    );
  }
}

class PollOptionModel {
  final String id;
  final String pollId;
  final String optionText;
  final int voteCount;

  PollOptionModel({
    required this.id,
    required this.pollId,
    required this.optionText,
    this.voteCount = 0,
  });

  factory PollOptionModel.fromJson(Map<String, dynamic> json) {
    return PollOptionModel(
      id: json['id'] as String,
      pollId: json['poll_id'] as String,
      optionText: json['option_text'] as String,
      voteCount: json['vote_count'] as int? ?? 0,
    );
  }

  double percentage(int totalVotes) {
    if (totalVotes == 0) return 0.0;
    return (voteCount / totalVotes) * 100;
  }
}
