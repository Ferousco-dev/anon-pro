import 'package:flutter/material.dart';
import '../models/post_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewPostsProvider extends ChangeNotifier {
  final List<PostModel> _newPosts = [];
  bool _showNotification = false;
  late RealtimeChannel _channel;
  final supabase = Supabase.instance.client;

  List<PostModel> get newPosts => _newPosts;
  bool get showNotification => _showNotification;
  int get newPostsCount => _newPosts.length;

  /// Initialize real-time listener for new posts
  void initializeRealtimeListener() {
    try {
      _channel = supabase.channel('public:posts').onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'posts',
            callback: (payload) {
              _handleNewPost(payload);
            },
          );
      _channel.subscribe();
    } catch (e) {
      print('Error initializing realtime listener: $e');
    }
  }

  /// Handle new post from real-time event
  void _handleNewPost(PostgresChangePayload payload) {
    try {
      final newPostData = payload.newRecord;
      if (newPostData.isEmpty) return;

      // Filter out anonymous posts
      bool isAnonymous = newPostData['is_anonymous'] as bool? ?? false;
      if (isAnonymous) return;

      final newPost = PostModel.fromJson(newPostData);

      // Add new post to the beginning of the list
      _newPosts.insert(0, newPost);
      _showNotification = true;

      notifyListeners();
    } catch (e) {
      print('Error handling new post: $e');
    }
  }

  /// Get new posts and clear the notification
  List<PostModel> getAndResetNewPosts() {
    final posts = List<PostModel>.from(_newPosts);
    _newPosts.clear();
    _showNotification = false;
    notifyListeners();
    return posts;
  }

  /// Manually add a new post (useful for testing or when loading posts from API)
  void addNewPost(PostModel post) {
    _newPosts.insert(0, post);
    _showNotification = true;
    notifyListeners();
  }

  /// Clear new posts
  void clearNewPosts() {
    _newPosts.clear();
    _showNotification = false;
    notifyListeners();
  }

  /// Hide notification without clearing posts
  void hideNotification() {
    _showNotification = false;
    notifyListeners();
  }

  /// Show notification
  void showNotificationBar() {
    if (_newPosts.isNotEmpty) {
      _showNotification = true;
      notifyListeners();
    }
  }

  /// Dispose real-time listener
  void disposeRealtimeListener() {
    try {
      supabase.removeChannel(_channel);
    } catch (e) {
      print('Error disposing realtime listener: $e');
    }
  }

  @override
  void dispose() {
    disposeRealtimeListener();
    super.dispose();
  }
}
