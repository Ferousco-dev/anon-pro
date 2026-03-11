import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_status_group_model.dart';
import 'post_model.dart';

final supabase = Supabase.instance.client;

class StatusController extends ChangeNotifier {
  int currentUserIndex;
  int currentPostIndex;
  final List<UserStatusGroup> groups;
  final String currentUserId;

  StatusController(
    this.groups,
    this.currentUserId, {
    this.currentUserIndex = 0,
    this.currentPostIndex = 0,
  });

  UserStatusGroup get currentGroup => groups[currentUserIndex];
  Post get currentPost => currentGroup.posts[currentPostIndex];
  bool get isOwner => currentPost.userId == currentUserId;

  void nextPost() {
    if (currentPostIndex < currentGroup.posts.length - 1) {
      currentPostIndex++;
      notifyListeners();
    } else {
      nextUser();
    }
  }

  void prevPost() {
    if (currentPostIndex > 0) {
      currentPostIndex--;
      notifyListeners();
    } else {
      prevUser();
    }
  }

  void nextUser() {
    if (currentUserIndex < groups.length - 1) {
      currentUserIndex++;
      currentPostIndex = 0;
      notifyListeners();
    }
  }

  void prevUser() {
    if (currentUserIndex > 0) {
      currentUserIndex--;
      currentPostIndex = 0;
      notifyListeners();
    }
  }

  Future<void> deleteCurrentPost() async {
    if (!isOwner) return;

    try {
      await supabase.from('user_statuses').delete().eq('id', currentPost.id);
      currentGroup.posts.removeAt(currentPostIndex);
      if (currentGroup.posts.isEmpty) {
        groups.removeAt(currentUserIndex);
        if (currentUserIndex >= groups.length && groups.isNotEmpty) {
          currentUserIndex = groups.length - 1;
        }
      } else if (currentPostIndex >= currentGroup.posts.length) {
        currentPostIndex = currentGroup.posts.length - 1;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting post: $e');
      // Handle error, perhaps show snackbar
    }
  }
}
