import '../models/post_model.dart';

class FeedRankingService {
  static final FeedRankingService _instance = FeedRankingService._internal();

  factory FeedRankingService() {
    return _instance;
  }

  FeedRankingService._internal();

  /// Calculate engagement score for a post
  static double _calculateBaseScore(PostModel post) {
    return post.likesCount * 1.0 +
        post.commentsCount * 2.0 +
        post.sharesCount * 3.0;
  }

  /// Calculate ranking score with verified user boost
  static double calculateRankingScore(PostModel post) {
    double score = _calculateBaseScore(post);

    // Boost for verified users' posts
    if (post.user?.isVerified ?? false) {
      score += 20; // Boost verified posts
    }

    // Additional boost for premium verified users
    if (post.user?.isPremiumVerified ?? false) {
      score += 10; // Extra boost for premium
    }

    // Slightly reduce ranking for anonymous posts (visibility tradeoff)
    if (post.isAnonymous) {
      score *= 0.9; // 10% reduction for anonymous
    }

    // Time decay: recent posts score higher (24-hour window)
    final ageInHours =
        DateTime.now().difference(post.createdAt).inHours.toDouble();
    final timeDecay = 1.0 / (1.0 + (ageInHours / 12)); // Half-life is 12 hours
    score *= timeDecay;

    return score;
  }

  /// Rank a list of posts by engagement and verification status
  static List<PostModel> rankPosts(List<PostModel> posts,
      {bool includeAnonymous = true}) {
    List<PostModel> filtered = posts;

    if (!includeAnonymous) {
      filtered = posts.where((p) => !p.isAnonymous).toList();
    }

    // Sort by calculated score (highest first)
    filtered.sort(
        (a, b) => calculateRankingScore(b).compareTo(calculateRankingScore(a)));

    return filtered;
  }

  /// Separate posts into tiers for better feed organization
  static Map<String, List<PostModel>> tierPosts(List<PostModel> posts) {
    return {
      'verified_high_engagement': posts
          .where((p) =>
              (p.user?.isVerified ?? false) && _calculateBaseScore(p) > 50)
          .toList(),
      'verified_posts': posts
          .where((p) =>
              (p.user?.isVerified ?? false) && _calculateBaseScore(p) <= 50)
          .toList(),
      'high_engagement': posts
          .where((p) =>
              !(p.user?.isVerified ?? false) && _calculateBaseScore(p) > 30)
          .toList(),
      'normal': posts
          .where((p) =>
              !(p.user?.isVerified ?? false) && _calculateBaseScore(p) <= 30)
          .toList(),
    };
  }

  /// Get personalized ranking based on user follows (future enhancement)
  static List<PostModel> getPersonalizedRanking(
    List<PostModel> posts,
    List<String> followingIds,
  ) {
    // Separate followed vs unfollowed posts
    final followingPosts =
        posts.where((p) => followingIds.contains(p.userId)).toList();
    final unfollowingPosts =
        posts.where((p) => !followingIds.contains(p.userId)).toList();

    // Rank each group separately
    final rankedFollowing = rankPosts(followingPosts);
    final rankedUnfollowing = rankPosts(unfollowingPosts);

    // Combine: recent following posts first, then others
    return [...rankedFollowing, ...rankedUnfollowing];
  }
}
