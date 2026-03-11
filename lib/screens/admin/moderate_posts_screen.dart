import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../models/post_model.dart';
import '../../models/user_model.dart';
import '../../services/image_upload_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase client
final supabase = Supabase.instance.client;

class ModeratePostsScreen extends StatefulWidget {
  const ModeratePostsScreen({super.key});

  @override
  State<ModeratePostsScreen> createState() => _ModeratePostsScreenState();
}

class _ModeratePostsScreenState extends State<ModeratePostsScreen> {
  List<PostModel> _posts = [];
  bool _isLoading = false;
  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);

    try {
      final query = supabase
          .from('posts')
          .select('''
            *,
            users (
              id,
              email,
              alias,
              display_name,
              bio,
              profile_image_url,
              cover_image_url,
              role,
              is_banned,
              is_verified,
              followers_count,
              following_count,
              posts_count,
              created_at,
              updated_at
            )
          ''')
          .eq('is_anonymous', false)
          .order('created_at', ascending: false)
          .limit(50);

      final response = await query;
      final posts = (response as List)
          .map((postData) =>
              PostModel.fromJson(postData as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _searchPosts(String query) async {
    if (query.isEmpty) {
      _loadPosts();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await supabase
          .from('posts')
          .select('''
            *,
            users (
              id,
              email,
              alias,
              display_name,
              bio,
              profile_image_url,
              cover_image_url,
              role,
              is_banned,
              is_verified,
              followers_count,
              following_count,
              posts_count,
              created_at,
              updated_at
            )
          ''')
          .eq('is_anonymous', false)
          .or('content.ilike.%$query%,users.alias.ilike.%$query%,users.display_name.ilike.%$query%')
          .order('created_at', ascending: false)
          .limit(50);

      final posts = (response as List)
          .map((postData) =>
              PostModel.fromJson(postData as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching posts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deletePost(PostModel post) async {
    try {
      // Delete via secure backend (handles ImageKit deletion + DB deletion)
      await ImageUploadService.deletePostImage(post.id);

      // Log activity
      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        await supabase.from('activity_logs').insert({
          'admin_id': currentUser.id,
          'action': 'Deleted post',
          'details': {'post_id': post.id, 'user_id': post.userId},
        });
      }

      if (mounted) {
        setState(() {
          _posts.removeWhere((p) => p.id == post.id);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Post deleted'),
            backgroundColor: AppConstants.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting post: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete post: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Moderate Posts'),
        backgroundColor: AppConstants.black,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search posts by content or user...',
                hintStyle: TextStyle(
                  color: AppConstants.textSecondary.withOpacity(0.6),
                ),
                filled: true,
                fillColor: AppConstants.darkGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppConstants.textSecondary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppConstants.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          _searchPosts('');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _searchPosts(value);
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryBlue),
                  )
                : _posts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.article_rounded,
                              size: 64,
                              color:
                                  AppConstants.textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No posts found',
                              style: TextStyle(
                                color: AppConstants.textSecondary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          final post = _posts[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppConstants.darkGray,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppConstants.lightGray.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor:
                                            AppConstants.primaryBlue,
                                        backgroundImage:
                                            post.user?.profileImageUrl != null
                                                ? NetworkImage(
                                                    post.user!.profileImageUrl!)
                                                : null,
                                        child:
                                            post.user?.profileImageUrl == null
                                                ? const Icon(Icons.person,
                                                    size: 16,
                                                    color: Colors.white)
                                                : null,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          post.user?.displayName ??
                                              post.user?.alias ??
                                              'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        post.createdAt
                                            .toLocal()
                                            .toString()
                                            .split(' ')[0],
                                        style: const TextStyle(
                                          color: AppConstants.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: AppConstants.red),
                                        onPressed: () => _deletePost(post),
                                        iconSize: 20,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    post.content,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
