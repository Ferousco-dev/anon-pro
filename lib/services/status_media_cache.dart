import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Manages offline caching of status media with 24-hour expiration
class StatusMediaCache {
  static const String _cachePrefix = 'status_cache_';
  static const String _timestampPrefix = 'status_timestamp_';
  static const int _cacheExpirationHours = 24;

  /// Get cached media file path if available and not expired
  /// Returns null if not cached or cache has expired
  static Future<File?> getCachedMedia(String mediaUrl) async {
    try {
      final fileName = _generateFileName(mediaUrl);
      final cacheDir = await _getCacheDirectory();
      final cachedFile = File('${cacheDir.path}/$fileName');

      // Check if file exists
      if (!await cachedFile.exists()) {
        return null;
      }

      // Check if cache has expired
      if (await _isCacheExpired(fileName)) {
        // Delete expired file
        await cachedFile.delete();
        return null;
      }

      return cachedFile;
    } catch (e) {
      debugPrint('Error reading cached media: $e');
      return null;
    }
  }

  /// Download and cache media from URL
  /// Returns path to cached file, null if download failed
  static Future<File?> downloadAndCacheMedia(String mediaUrl) async {
    try {
      final fileName = _generateFileName(mediaUrl);
      final cacheDir = await _getCacheDirectory();
      final cachedFile = File('${cacheDir.path}/$fileName');

      // If already cached and not expired, return it
      if (await cachedFile.exists() && !await _isCacheExpired(fileName)) {
        return cachedFile;
      }

      // Download the file
      debugPrint('Downloading status media from: $mediaUrl');
      final response = await http.get(Uri.parse(mediaUrl)).timeout(
            const Duration(minutes: 5),
            onTimeout: () => throw TimeoutException('Download timeout'),
          );

      if (response.statusCode != 200) {
        throw Exception('Failed to download media: ${response.statusCode}');
      }

      // Save to cache
      await cachedFile.writeAsBytes(response.bodyBytes);

      // Store timestamp
      await _setCacheTimestamp(fileName);

      debugPrint('Cached media at: ${cachedFile.path}');
      return cachedFile;
    } catch (e) {
      debugPrint('Error downloading and caching media: $e');
      return null;
    }
  }

  /// Check if a cached file has expired
  static Future<bool> _isCacheExpired(String fileName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampKey = '$_timestampPrefix$fileName';
      final timestamp = prefs.getInt(timestampKey);

      if (timestamp == null) {
        return true; // No timestamp, assume expired
      }

      final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final expiration = cachedTime.add(Duration(hours: _cacheExpirationHours));
      final isExpired = DateTime.now().isAfter(expiration);

      if (isExpired) {
        debugPrint('Cache expired for: $fileName');
      }

      return isExpired;
    } catch (e) {
      debugPrint('Error checking cache expiration: $e');
      return true; // Assume expired on error
    }
  }

  /// Set cache timestamp to current time
  static Future<void> _setCacheTimestamp(String fileName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampKey = '$_timestampPrefix$fileName';
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
      debugPrint('Timestamp set for: $fileName');
    } catch (e) {
      debugPrint('Error setting cache timestamp: $e');
    }
  }

  /// Clean up expired cache files
  static Future<void> cleanupExpiredCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final files = cacheDir.listSync();

      for (var fileEntity in files) {
        if (fileEntity is File) {
          final fileName = fileEntity.path.split('/').last;
          if (fileName.startsWith(_cachePrefix)) {
            if (await _isCacheExpired(fileName)) {
              await fileEntity.delete();
              debugPrint('Deleted expired cache: $fileName');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up expired cache: $e');
    }
  }

  /// Clear all cached status media
  static Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final prefs = await SharedPreferences.getInstance();

      // Delete all cache files
      final files = cacheDir.listSync();
      for (var fileEntity in files) {
        if (fileEntity is File) {
          final fileName = fileEntity.path.split('/').last;
          if (fileName.startsWith(_cachePrefix)) {
            await fileEntity.delete();
          }
        }
      }

      // Clear all timestamps
      final keys = prefs.getKeys();
      for (var key in keys) {
        if (key.startsWith(_timestampPrefix)) {
          await prefs.remove(key);
        }
      }

      debugPrint('All cache cleared');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Get cache size in MB
  static Future<double> getCacheSizeMB() async {
    try {
      final cacheDir = await _getCacheDirectory();
      int totalSize = 0;

      final files = cacheDir.listSync(recursive: true);
      for (var file in files) {
        if (file is File && file.path.contains(_cachePrefix)) {
          totalSize += file.lengthSync();
        }
      }

      return totalSize / (1024 * 1024); // Convert bytes to MB
    } catch (e) {
      debugPrint('Error calculating cache size: $e');
      return 0.0;
    }
  }

  /// Get cache directory for status media
  static Future<Directory> _getCacheDirectory() async {
    final baseDir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${baseDir.path}/status_media');

    // Create directory if it doesn't exist
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  /// Generate a safe file name from URL
  static String _generateFileName(String mediaUrl) {
    // Create a hash-based filename from the URL
    final hash = mediaUrl.hashCode.abs().toString();
    final extension = _getFileExtension(mediaUrl);
    return '$_cachePrefix$hash$extension';
  }

  /// Extract file extension from URL
  static String _getFileExtension(String mediaUrl) {
    try {
      final uri = Uri.parse(mediaUrl);
      final path = uri.path.toLowerCase();

      if (path.contains('.jpg') || path.contains('.jpeg')) {
        return '.jpg';
      } else if (path.contains('.png')) {
        return '.png';
      } else if (path.contains('.gif')) {
        return '.gif';
      } else if (path.contains('.webp')) {
        return '.webp';
      } else if (path.contains('.mp4')) {
        return '.mp4';
      } else if (path.contains('.mov')) {
        return '.mov';
      } else {
        return '.bin'; // Default binary extension
      }
    } catch (e) {
      return '.bin';
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
