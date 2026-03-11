import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'dart:ui';
import '../main.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../utils/constants.dart';
import '../services/image_upload_service.dart';

class CreatePostSheet extends StatefulWidget {
  final UserModel? currentUser;
  final VoidCallback? onPostCreated;

  /// Optional callback that receives the optimistic post immediately so
  /// the home feed can prepend it before the network finishes.
  final void Function(PostModel optimisticPost)? onOptimisticPost;

  final bool isAnonymous;

  const CreatePostSheet({
    super.key,
    this.currentUser,
    this.onPostCreated,
    this.onOptimisticPost,
    this.isAnonymous = false,
  });

  @override
  State<CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<CreatePostSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _imageNameController = TextEditingController();
  File? _selectedImage;
  bool _isCompressing = false;
  bool _isUploading = false;

  // Identity mode
  // 'anonymous' | 'verified_anonymous' | 'public'
  late String _identityMode;

  // Poll fields
  bool _isPoll = false;
  final TextEditingController _pollQuestionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  // Animation
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  // Glass colors — no gradients, pure frosted glass on black
  static const _kGlass = Color(0xFF1A1A1A);
  static const _kGlassBorder = Color(0xFF2A2A2A);
  static const _kGlassHighlight = Color(0xFF333333);
  static const _kDimText = Color(0xFF8E8E93);
  static const _kSubtleWhite = Color(0xFFE5E5EA);

  @override
  void initState() {
    super.initState();
    _identityMode = widget.isAnonymous ? 'anonymous' : 'public';

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _imageNameController.dispose();
    _pollQuestionController.dispose();
    _animController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _isVerifiedUser => widget.currentUser?.isVerifiedUser ?? false;

  Future<void> _pickImage() async {
    if (!kIsWeb) {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          compressQuality: 90,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Image',
              toolbarColor: AppConstants.primaryBlue,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: false,
            ),
            IOSUiSettings(
              title: 'Crop Image',
            ),
          ],
        );

        if (croppedFile != null) {
          if (mounted) {
            setState(() {
              _selectedImage = File(croppedFile.path);
              _imageNameController.clear();
            });
          }
        }
      }
    }
  }

  Future<void> _createPost() async {
    if (_contentController.text.trim().isEmpty && _selectedImage == null) {
      _showError('Please add some content');
      return;
    }

    if (_contentController.text.length > AppConstants.maxPostLength) {
      _showError(
          'Post is too long (max ${AppConstants.maxPostLength} characters)');
      return;
    }

    // Validate poll if enabled
    // DISABLED FOR NOW - Polls causing issues
    // if (_isPoll) {
    //   if (_pollQuestionController.text.trim().isEmpty) {
    //     _showError('Please enter a poll question');
    //     return;
    //   }
    //   final validOptions =
    //       _optionControllers.where((c) => c.text.trim().isNotEmpty).toList();
    //   if (validOptions.length < 2) {
    //     _showError('Please add at least 2 poll options');
    //     return;
    //   }
    // }

    HapticFeedback.mediumImpact();

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showError('Not authenticated');
      return;
    }

    final content = _contentController.text.trim();
    final now = DateTime.now();
    final isAnonymous =
        _identityMode == 'anonymous' || _identityMode == 'verified_anonymous';

    // ── GATHER DATA BEFORE DISPOSE ──
    final customImageName = _imageNameController.text.trim();

    // ── OPTIMISTIC POST ──
    final optimisticPost = PostModel(
      id: 'optimistic_${now.millisecondsSinceEpoch}',
      userId: userId,
      content: content,
      imageUrl: _selectedImage != null ? _selectedImage!.path : null,
      isAnonymous: isAnonymous,
      postIdentityMode: _identityMode,
      likesCount: 0,
      commentsCount: 0,
      sharesCount: 0,
      viewsCount: 0,
      createdAt: now,
      updatedAt: now,
      originalPostId: null,
      repostsCount: 0,
      originalContent: null,
      user: widget.currentUser,
      isLikedByCurrentUser: false,
      isRepostedByCurrentUser: false,
      taggedUsers: const {},
      postType: 'regular',
      relatedConfessionRoomId: null,
    );

    // Close sheet and show optimistic post
    if (mounted) {
      Navigator.pop(context);
      widget.onOptimisticPost?.call(optimisticPost);
    }

    // ── BACKGROUND NETWORK WORK ──
    try {
      final postResponse = await supabase
          .from('posts')
          .insert({
            'user_id': userId,
            'content': content,
            'image_url': null,
            'is_anonymous': isAnonymous,
            'post_identity_mode': _identityMode,
          })
          .select()
          .single();

      final postId = postResponse['id'] as String;

      // Upload image if selected
      String? imageUrl;
      if (_selectedImage != null) {
        try {
          File imageToUpload = _selectedImage!;
          imageToUpload = await ImageUploadService.compressImage(imageToUpload);

          imageUrl = await ImageUploadService.uploadPostImageWithName(
            imageFile: imageToUpload,
            postId: postId,
            customName: customImageName.isNotEmpty ? customImageName : null,
          );

          await supabase
              .from('posts')
              .update({'image_url': imageUrl}).eq('id', postId);
        } catch (e) {
          debugPrint('Failed to upload image: $e');
        }
      }

      // Parse @mentions and insert post_tags (only for non-anonymous posts)
      if (!isAnonymous) {
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
                  'post_id': postId,
                  'tagged_user_id': taggedUserId,
                });
              }
            }
          } catch (_) {}
        }
      }

      widget.onPostCreated?.call();
    } catch (e) {
      debugPrint('Failed to create post in background: $e');
    }
  }

  Set<String> _parseMentions(String content) {
    final regex = RegExp(r'@([a-zA-Z0-9_]+)');
    return regex.allMatches(content).map((m) => m.group(1)!).toSet();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppConstants.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  // ═══════════════════════════════ BUILD ═══════════════════════════════

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final remainingChars =
        AppConstants.maxPostLength - _contentController.text.length;

    return ScaleTransition(
      scale: _scaleAnim,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: _kGlassBorder.withOpacity(0.6),
                width: 0.5,
              ),
            ),
            padding: EdgeInsets.only(
              bottom:
                  keyboardHeight + MediaQuery.of(context).padding.bottom + 12,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Drag Handle ──
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _kDimText.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ── Header ──
                  _buildHeader(),

                  // ── Identity Mode Picker ──
                  _buildIdentityModePicker(),

                  // ── Content Area ──
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Text Input
                        _buildTextInput(),

                        // Character counter
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(
                            '$remainingChars',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: remainingChars < 20
                                  ? AppConstants.red
                                  : _kDimText.withOpacity(0.5),
                            ),
                          ),
                        ),

                        // Selected Image Preview
                        if (_selectedImage != null) _buildImagePreview(),

                        // Poll Section
                        if (_isPoll) _buildPollSection(),

                        // ── Bottom Toolbar ──
                        _buildBottomToolbar(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════ HEADER ═══════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Close button — glass pill
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kGlass.withOpacity(0.8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _kGlassBorder.withOpacity(0.5),
                  width: 0.5,
                ),
              ),
              child: const Icon(Icons.close_rounded,
                  color: _kSubtleWhite, size: 18),
            ),
          ),

          const Spacer(),

          // Post button — frosted glass pill
          GestureDetector(
            onTap: _createPost,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.primaryBlue.withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'Post',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════ IDENTITY MODE PICKER ═══════════════════

  Widget _buildIdentityModePicker() {
    // Build the available modes
    final List<_IdentityOption> modes = [];

    if (widget.isAnonymous) {
      // On anonymous page — only anonymous mode, no picker needed
      return const SizedBox.shrink();
    }

    modes.add(_IdentityOption(
      mode: 'public',
      icon: Icons.person_rounded,
      label: 'Public',
    ));

    modes.add(_IdentityOption(
      mode: 'anonymous',
      icon: Icons.person_off_rounded,
      label: 'Anonymous',
    ));

    if (_isVerifiedUser) {
      modes.add(_IdentityOption(
        mode: 'verified_anonymous',
        icon: Icons.verified_user_rounded,
        label: 'Verified Anon',
      ));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kGlass.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kGlassBorder.withOpacity(0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        children: modes.map((opt) {
          final isSelected = _identityMode == opt.mode;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _identityMode = opt.mode);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _kGlassHighlight.withOpacity(0.9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Colors.white.withOpacity(0.1)
                        : Colors.transparent,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      opt.icon,
                      size: 15,
                      color: isSelected ? Colors.white : _kDimText,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        opt.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? Colors.white : _kDimText,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════ TEXT INPUT ═══════════════════

  Widget _buildTextInput() {
    String hintText;
    switch (_identityMode) {
      case 'anonymous':
        hintText = 'Share anonymously…';
        break;
      case 'verified_anonymous':
        hintText = 'Post as verified anonymous…';
        break;
      default:
        hintText = 'What\'s happening?';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _kGlass.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kGlassBorder.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: TextField(
        controller: _contentController,
        maxLines: 5,
        maxLength: AppConstants.maxPostLength,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.45,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: _kDimText.withOpacity(0.6),
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          counterText: '',
        ),
        onChanged: (value) => setState(() {}),
      ),
    );
  }

  // ═══════════════════ IMAGE PREVIEW ═══════════════════

  Widget _buildImagePreview() {
    return Column(
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                _selectedImage!,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
              ),
            ),
            // Frosted remove button
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => setState(() => _selectedImage = null),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                          width: 0.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isCompressing || _isUploading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isCompressing ? 'Compressing…' : 'Uploading…',
                          style: const TextStyle(
                            color: _kSubtleWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Image name — glass style
        Container(
          decoration: BoxDecoration(
            color: _kGlass.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _kGlassBorder.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: TextField(
            controller: _imageNameController,
            maxLength: 30,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Name your image (optional)',
              hintStyle: TextStyle(color: _kDimText.withOpacity(0.5)),
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: InputBorder.none,
              prefixIcon: Icon(
                Icons.label_outline_rounded,
                color: _kDimText.withOpacity(0.4),
                size: 18,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ═══════════════════ POLL SECTION ═══════════════════

  Widget _buildPollSection() {
    return Column(
      children: [
        const SizedBox(height: 4),
        // Poll question — glass input
        _buildGlassInput(
          controller: _pollQuestionController,
          hint: 'Ask a question…',
          maxLines: 2,
          fontSize: 15,
        ),
        const SizedBox(height: 8),

        // Poll options
        ..._optionControllers.asMap().entries.map((entry) {
          final idx = entry.key;
          final controller = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _buildGlassInput(
              controller: controller,
              hint: 'Option ${idx + 1}',
              suffix: _optionControllers.length > 2 && idx >= 2
                  ? GestureDetector(
                      onTap: () {
                        setState(() {
                          _optionControllers.removeAt(idx);
                          controller.dispose();
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.remove_circle_outline_rounded,
                          color: AppConstants.red.withOpacity(0.7),
                          size: 18,
                        ),
                      ),
                    )
                  : null,
            ),
          );
        }),

        if (_optionControllers.length < 4)
          GestureDetector(
            onTap: () {
              setState(() => _optionControllers.add(TextEditingController()));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kGlass.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kGlassBorder.withOpacity(0.4),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded,
                      size: 16, color: _kDimText.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Text(
                    'Add Option',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _kDimText.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildGlassInput({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    double fontSize = 14,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kGlass.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _kGlassBorder.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(color: Colors.white, fontSize: fontSize),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _kDimText.withOpacity(0.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
          suffixIcon: suffix,
        ),
      ),
    );
  }

  // ═══════════════════ BOTTOM TOOLBAR ═══════════════════

  Widget _buildBottomToolbar() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: _kGlassBorder.withOpacity(0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildToolbarButton(
            icon: Icons.photo_library_rounded,
            label: 'Media',
            onTap: _pickImage,
          ),
          const SizedBox(width: 8),
          _buildToolbarButton(
            icon: _isPoll ? Icons.poll_rounded : Icons.poll_outlined,
            label: 'Poll',
            onTap: () => setState(() => _isPoll = !_isPoll),
            isActive: _isPoll,
          ),
          const Spacer(),
          // Identity indicator
          _buildIdentityIndicator(),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? _kGlassHighlight.withOpacity(0.6)
              : _kGlass.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Colors.white.withOpacity(0.12)
                : _kGlassBorder.withOpacity(0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : _kDimText,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? Colors.white : _kDimText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityIndicator() {
    IconData icon;
    String label;
    Color indicatorColor;

    switch (_identityMode) {
      case 'anonymous':
        icon = Icons.person_off_rounded;
        label = 'Anon';
        indicatorColor = _kDimText;
        break;
      case 'verified_anonymous':
        icon = Icons.verified_user_rounded;
        label = 'V-Anon';
        indicatorColor = AppConstants.primaryBlue;
        break;
      default:
        icon = Icons.person_rounded;
        label = 'Public';
        indicatorColor = _kDimText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _kGlass.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kGlassBorder.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: indicatorColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: indicatorColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════ HELPER CLASS ═══════════════════════
class _IdentityOption {
  final String mode;
  final IconData icon;
  final String label;

  const _IdentityOption({
    required this.mode,
    required this.icon,
    required this.label,
  });
}
