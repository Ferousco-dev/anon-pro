import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../main.dart';
import '../models/post_model.dart';
import '../utils/constants.dart';
import '../services/image_upload_service.dart';

class EditPostSheet extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onPostUpdated;

  const EditPostSheet({
    super.key,
    required this.post,
    this.onPostUpdated,
  });

  @override
  State<EditPostSheet> createState() => _EditPostSheetState();
}

class _EditPostSheetState extends State<EditPostSheet> {
  late TextEditingController _contentController;
  File? _selectedImage;
  String? _existingImageUrl;
  bool _removeImage = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.post.content);
    _existingImageUrl = widget.post.imageUrl;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Set<String> _parseMentions(String content) {
    final regex = RegExp(r'@([a-zA-Z0-9_]+)');
    return regex.allMatches(content).map((m) => m.group(1)!).toSet();
  }

  Future<void> _savePost() async {
    if (_contentController.text.trim().isEmpty &&
        _selectedImage == null &&
        !_removeImage &&
        _existingImageUrl == null) {
      _showError('Please add some content');
      return;
    }

    if (_contentController.text.length > AppConstants.maxPostLength) {
      _showError(
          'Post is too long (max ${AppConstants.maxPostLength} characters)');
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      String? imageUrl;

      if (_removeImage) {
        imageUrl = null;
      } else if (_selectedImage != null) {
        // Upload new image
        imageUrl = await ImageUploadService.uploadPostImage(
          imageFile: _selectedImage!,
          postId: widget.post.id,
        );
      } else {
        imageUrl = widget.post.imageUrl;
      }

      final content = _contentController.text.trim();
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      await supabase.from('posts').update({
        'content': content,
        'image_url': imageUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.post.id);

      // Update post_tags: delete old, insert new
      if (!widget.post.isAnonymous) {
        await supabase.from('post_tags').delete().eq('post_id', widget.post.id);

        final mentions = _parseMentions(content);
        for (final alias in mentions) {
          try {
            final userRes = await supabase
                .from('users')
                .select('id')
                .eq('alias', alias)
                .maybeSingle();
            if (userRes != null) {
              final taggedUserId = userRes['id'] as String;
              if (taggedUserId != userId) {
                await supabase.from('post_tags').insert({
                  'post_id': widget.post.id,
                  'tagged_user_id': taggedUserId,
                });
              }
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onPostUpdated?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post updated'),
            backgroundColor: AppConstants.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12))),
            margin: EdgeInsets.all(20),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to update post: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppConstants.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  Future<void> _pickImage() async {
    if (kIsWeb) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _removeImage = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final remainingChars =
        AppConstants.maxPostLength - _contentController.text.length;
    final hasImage = _selectedImage != null ||
        (_existingImageUrl != null &&
            _existingImageUrl!.isNotEmpty &&
            !_removeImage);

    return Container(
      decoration: const BoxDecoration(
        color: AppConstants.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppConstants.lightGray.withOpacity(0.3),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  const Text(
                    'Edit Post',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isSaving
                          ? AppConstants.primaryBlue.withOpacity(0.5)
                          : AppConstants.primaryBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : GestureDetector(
                            onTap: _savePost,
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _contentController,
                      maxLines: 8,
                      maxLength: AppConstants.maxPostLength,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'What\'s on your mind? Tag with @username',
                        hintStyle: TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        counterText: '',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    Text(
                      '$remainingChars characters remaining',
                      style: TextStyle(
                        fontSize: 12,
                        color: remainingChars < 20
                            ? AppConstants.red
                            : AppConstants.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Image preview
                    if (hasImage) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _selectedImage != null
                                ? Image.file(
                                    _selectedImage!,
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  )
                                : Image.network(
                                    _existingImageUrl!,
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 200,
                                      color: AppConstants.darkGray,
                                      child: const Center(
                                        child: Icon(Icons.broken_image,
                                            color: AppConstants.textSecondary),
                                      ),
                                    ),
                                  ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImage = null;
                                  _removeImage = true;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Add/change image
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            hasImage
                                ? Icons.edit_rounded
                                : Icons.image_outlined,
                            color: AppConstants.primaryBlue,
                          ),
                          onPressed: _pickImage,
                        ),
                        Text(
                          hasImage ? 'Change image' : 'Add image',
                          style: const TextStyle(
                            color: AppConstants.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
