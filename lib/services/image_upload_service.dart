import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image/image.dart' as img;

class ImageUploadService {
  static const String _imageKitUploadUrl =
      'https://upload.imagekit.io/api/v1/files/upload';

  static const int _maxFileSizeBytes = 500 * 1024; // 500 KB threshold
  static const int _maxDimension = 2048; // Max width/height for resizing
  static const int _startQuality = 90; // Starting JPEG quality

  // Store fileIds in memory for deletion
  static final Map<String, String> _fileIdCache = {};

  /// Compress image if larger than 500KB
  /// Returns the compressed file or original if smaller
  static Future<File> compressImage(File imageFile) async {
    try {
      final fileSizeBytes = await imageFile.length();

      // If file is already small, return as-is
      if (fileSizeBytes <= _maxFileSizeBytes) {
        debugPrint(
            'Image size OK: ${(fileSizeBytes / 1024).toStringAsFixed(2)} KB');
        return imageFile;
      }

      debugPrint(
          'Compressing image from ${(fileSizeBytes / 1024).toStringAsFixed(2)} KB');

      // Read and decode image
      final imageBytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Could not decode image');
      }

      // Resize if too large
      if (image.width > _maxDimension || image.height > _maxDimension) {
        image = img.copyResize(
          image,
          width: image.width > image.height ? _maxDimension : null,
          height: image.height >= image.width ? _maxDimension : null,
        );
      }

      // Compress with progressive quality reduction
      List<int> compressedBytes = [];
      int quality = _startQuality;

      while (quality >= 50) {
        compressedBytes = img.encodeJpg(image, quality: quality);
        if (compressedBytes.length <= _maxFileSizeBytes) {
          debugPrint(
              'Compressed to ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB at quality $quality');
          break;
        }
        quality -= 5;
      }

      // Create temporary compressed file
      final compressedFile = File(
        '${imageFile.parent.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await compressedFile.writeAsBytes(compressedBytes);

      return compressedFile;
    } catch (e) {
      debugPrint('Image compression error: $e');
      return imageFile; // Return original on error
    }
  }

  /// Upload image with optional custom name
  /// Returns the image URL on success
  static Future<String> uploadPostImageWithName({
    required File imageFile,
    required String postId,
    String? customName,
  }) async {
    try {
      if (!imageFile.existsSync()) {
        throw Exception('Image file not found');
      }

      final fileSize = await imageFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('Image too large (max 10MB)');
      }

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      // Generate file name with optional custom prefix
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalName = imageFile.path.split('/').last;
      final fileName = customName != null && customName.isNotEmpty
          ? '${customName}_${timestamp}_$originalName'
          : '${timestamp}_$originalName';

      final folder = '/users/$userId/posts';

      final signature = await _fetchImageKitSignature();

      // Create multipart request
      final request =
          http.MultipartRequest('POST', Uri.parse(_imageKitUploadUrl));

      // Add form fields
      request.fields['fileName'] = fileName;
      request.fields['folder'] = folder;
      request.fields['useUniqueFileName'] = 'true';
      request.fields['publicKey'] = signature['publicKey'] as String;
      request.fields['signature'] = signature['signature'] as String;
      request.fields['token'] = signature['token'] as String;
      request.fields['expire'] = signature['expire'].toString();

      // Add file
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      final response = await request.send().timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('Upload timeout'),
          );

      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception('ImageKit upload failed: ${response.statusCode}');
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final fileId = data['fileId'] as String?;
      final url = data['url'] as String?;

      if (fileId == null || url == null) {
        throw Exception('Invalid ImageKit response');
      }

      // Cache fileId for deletion
      _fileIdCache[postId] = fileId;

      return url;
    } catch (e) {
      debugPrint('Image upload error: $e');
      rethrow;
    }
  }

  /// Upload image to ImageKit directly
  /// Returns the image URL on success
  static Future<String> uploadPostImage({
    required File imageFile,
    required String postId,
  }) async {
    return uploadPostImageWithName(
      imageFile: imageFile,
      postId: postId,
    );
  }

  /// Delete image from ImageKit and post from database
  static Future<void> deletePostImage(String postId) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      // Get post to verify ownership
      final post = await supabase
          .from('posts')
          .select('user_id')
          .eq('id', postId)
          .maybeSingle();

      if (post == null) {
        throw Exception('Post not found');
      }

      // Check authorization
      final isOwner = post['user_id'] == userId;
      final user = await supabase
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      final isAdmin = user?['role'] == 'admin';

      if (!isOwner && !isAdmin) {
        throw Exception('Unauthorized');
      }

      // Try to delete image from ImageKit if fileId is cached
      final fileId = _fileIdCache[postId];
      if (fileId != null && fileId.isNotEmpty) {
        await _deleteFromImageKit(fileId);
        _fileIdCache.remove(postId);
      } else if (post['image_url'] != null) {
        // Post has image but fileId not cached - try to extract from URL or skip
        debugPrint('Note: Image fileId not found in cache for post $postId');
      }

      // Delete post from database
      await supabase.from('posts').delete().eq('id', postId);
    } catch (e) {
      debugPrint('Image delete error: $e');
      rethrow;
    }
  }

  /// Internal: Delete file from ImageKit
  static Future<void> _deleteFromImageKit(String fileId) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'imagekit-delete',
        body: {'fileId': fileId},
      );
      if (response.data == null) {
        debugPrint('ImageKit delete warning: empty response');
      }
    } catch (e) {
      debugPrint('ImageKit deletion error: $e');
      // Don't fail post deletion if ImageKit fails
    }
  }

  /// Get cached fileId (for reference)
  static String? getCachedFileId(String postId) => _fileIdCache[postId];

  static Future<Map<String, dynamic>> _fetchImageKitSignature() async {
    final supabase = Supabase.instance.client;
    final response = await supabase.functions.invoke('imagekit-signature');
    if (response.data == null) {
      throw Exception(
        'ImageKit signature failed: empty response',
      );
    }
    final data = response.data as Map<String, dynamic>;
    return data;
  }
}
