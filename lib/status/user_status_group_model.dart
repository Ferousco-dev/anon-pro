import 'user_model.dart';
import 'post_model.dart';

class UserStatusGroup {
  final User user;
  final List<Post> posts;
  final bool isPremium;
  final bool isMuted;

  const UserStatusGroup({
    required this.user,
    required this.posts,
    this.isPremium = false,
    this.isMuted = false,
  });

  bool get hasMultiplePosts => posts.length > 1;
  bool get hasUnseen => posts.any((p) => !p.isViewed);
  int get postCount => posts.length;
}
