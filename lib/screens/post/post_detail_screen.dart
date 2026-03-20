import 'package:flutter/material.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/post_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../utils/app_error_handler.dart';
import '../../widgets/post_card.dart';
import '../../widgets/comments_sheet.dart';
import '../../widgets/shareable_post_card.dart';
import '../../main.dart';

/// Screen that displays a single post in full detail.
/// Used when navigating from activity notifications (likes, comments, tags).
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final bool openComments;

  const PostDetailScreen({
    super.key,
    required this.postId,
    this.openComments = false,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  PostModel? _post;
  UserModel? _currentUser;
  bool _isLoading = true;
  String? _error;
  bool _didOpenComments = false;
  final ScreenshotController _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadPost();
  }

  Future<void> _loadCurrentUser() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        final userData =
            await supabase.from('users').select().eq('id', user.id).single();
        if (mounted) {
          setState(() {
            _currentUser = UserModel.fromJson(userData);
          });
        }
      } catch (e) {
        debugPrint('Error loading current user: $e');
      }
    }
  }

  Future<void> _loadPost() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Fetch the post with user info
      final response = await supabase.from('posts').select('''
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
          ''').eq('id', widget.postId).maybeSingle();

      if (response == null) {
        if (mounted) {
          setState(() {
            _error = 'Post not found or has been deleted';
            _isLoading = false;
          });
        }
        return;
      }

      var post = PostModel.fromJson(response);

      // Load likes info
      if (_currentUser != null) {
        final likesResponse = await supabase
            .from('likes')
            .select('post_id')
            .eq('user_id', _currentUser!.id)
            .eq('post_id', widget.postId);

        final allLikesResponse = await supabase
            .from('likes')
            .select('post_id')
            .eq('post_id', widget.postId);

        post = post.copyWith(
          isLikedByCurrentUser: (likesResponse as List).isNotEmpty,
          likesCount: (allLikesResponse as List).length,
        );
      }

      // For anonymous posts, override user info
      if (post.isAnonymous) {
        post.user = UserModel(
          id: '',
          email: '',
          alias: 'Anonymous',
          displayName: 'Anonymous',
          role: 'user',
          isBanned: false,
          isVerified: false,
          followersCount: 0,
          followingCount: 0,
          postsCount: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      if (mounted) {
        setState(() {
          _post = post;
          _isLoading = false;
        });
        _maybeOpenComments();
      }
    } catch (e) {
      debugPrint('Error loading post: $e');
      if (mounted) {
        setState(() {
          _error = AppErrorHandler.userMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  void _maybeOpenComments() {
    if (!widget.openComments || _didOpenComments || _post == null) {
      return;
    }
    _didOpenComments = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showComments();
    });
  }

  Future<void> _handleLikeToggle() async {
    if (_currentUser == null || _post == null) return;

    try {
      if (_post!.isLikedByCurrentUser == true) {
        await supabase
            .from('likes')
            .delete()
            .eq('post_id', _post!.id)
            .eq('user_id', _currentUser!.id);

        if (mounted) {
          setState(() {
            _post = _post!.copyWith(
              likesCount: _post!.likesCount - 1,
              isLikedByCurrentUser: false,
            );
          });
        }
      } else {
        await supabase.from('likes').insert({
          'post_id': _post!.id,
          'user_id': _currentUser!.id,
        });

        if (mounted) {
          setState(() {
            _post = _post!.copyWith(
              likesCount: _post!.likesCount + 1,
              isLikedByCurrentUser: true,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
  }

  void _showComments() {
    if (_post == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsSheet(
        post: _post!,
        currentUser: _currentUser,
        onCommentCreated: () {
          if (!mounted) return;
          setState(() {
            _post = _post!.copyWith(
              commentsCount: _post!.commentsCount + 1,
            );
          });
        },
      ),
    );
  }

  Future<void> _handleShare() async {
    if (_post == null) return;
    final bool isAnonymous = _post!.isAnonymous == true;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Screenshot(
                controller: _screenshotController,
                child: ShareablePostCard(
                  post: _post!,
                  isAnonymous: isAnonymous,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final image = await _screenshotController.capture();
                        if (image != null && mounted) {
                          final directory = await getTemporaryDirectory();
                          final imagePath =
                              '${directory.path}/anonpro_post_${DateTime.now().millisecondsSinceEpoch}.png';
                          final imageFile = File(imagePath);
                          await imageFile.writeAsBytes(image);

                          await Share.shareXFiles(
                            [XFile(imagePath)],
                            text: 'Check out this post on ANONPRO!',
                            sharePositionOrigin:
                                const Rect.fromLTWH(0, 0, 100, 100),
                          );

                          if (mounted) Navigator.pop(context);
                        }
                      } catch (e) {
                        debugPrint('Error sharing: $e');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryBlue,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.share),
                    label: const Text('Share Card'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppConstants.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Post',
          style: TextStyle(
            color: AppConstants.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppConstants.primaryBlue,
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 64,
                          color: AppConstants.textSecondary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppConstants.textSecondary,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadPost,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryBlue,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _post != null
                  ? SingleChildScrollView(
                      child: PostCard(
                        post: _post!,
                        currentUser: _currentUser,
                        onLikeToggle: _handleLikeToggle,
                        onComment: _showComments,
                        onShare: _handleShare,
                        onRepost: () {},
                      ),
                    )
                  : const SizedBox.shrink(),
    );
  }
}
