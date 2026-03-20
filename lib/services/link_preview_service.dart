import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LinkPreviewData {
  LinkPreviewData({
    required this.url,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.domain,
  });

  final String url;
  final String title;
  final String description;
  final String imageUrl;
  final String domain;

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'domain': domain,
      };

  static LinkPreviewData fromJson(Map<String, dynamic> json) {
    return LinkPreviewData(
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
    );
  }
}

class LinkPreviewService {
  static const String _cacheKey = 'link_preview_cache_v1';
  static const Duration _cacheTtl = Duration(hours: 12);
  static final Map<String, _CacheEntry> _memoryCache = {};
  static bool _loaded = false;

  static String? extractUrlIfOnlyLink(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'https?://[^\s]+').firstMatch(trimmed);
    if (match == null) return null;
    final url = match.group(0);
    if (url == null) return null;
    return trimmed == url ? url : null;
  }

  static String? sanitizeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri.toString();
  }

  static Future<LinkPreviewData?> fetch(String url) async {
    final safeUrl = sanitizeUrl(url);
    if (safeUrl == null) return null;

    await _loadCache();
    final cached = _memoryCache[safeUrl];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

    final data = await _fetchFromNetwork(safeUrl);
    if (data == null) return null;

    _memoryCache[safeUrl] = _CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(_cacheTtl),
    );
    await _persistCache();
    return data;
  }

  static Future<LinkPreviewData?> _fetchFromNetwork(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'AnonPro/1.0'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return LinkPreviewData(
          url: url,
          title: '',
          description: '',
          imageUrl: '',
          domain: Uri.parse(url).host,
        );
      }

      final body = response.body;
      final title = _firstMeta(body, 'og:title') ?? _titleTag(body);
      final description =
          _firstMeta(body, 'og:description') ?? _firstMeta(body, 'description');
      final imageUrl = _firstMeta(body, 'og:image') ?? '';
      final domain = Uri.parse(url).host;

      return LinkPreviewData(
        url: url,
        title: title ?? '',
        description: description ?? '',
        imageUrl: imageUrl,
        domain: domain,
      );
    } catch (_) {
      return LinkPreviewData(
        url: url,
        title: '',
        description: '',
        imageUrl: '',
        domain: Uri.parse(url).host,
      );
    }
  }

  static String? _firstMeta(String html, String key) {
    final patterns = [
      RegExp(
        '<meta[^>]+property=["\']$key["\'][^>]+content=["\']([^"\']+)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']$key["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+name=["\']$key["\'][^>]+content=["\']([^"\']+)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']$key["\']',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null && match.groupCount >= 1) {
        return _decodeHtml(match.group(1) ?? '');
      }
    }
    return null;
  }

  static String? _titleTag(String html) {
    final match = RegExp('<title[^>]*>([^<]+)</title>',
            caseSensitive: false)
        .firstMatch(html);
    if (match == null || match.groupCount < 1) return null;
    return _decodeHtml(match.group(1) ?? '');
  }

  static String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  static Future<void> _loadCache() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final data = LinkPreviewData.fromJson(
            (entry.value as Map<String, dynamic>)['data']
                as Map<String, dynamic>);
        final expiresAt =
            DateTime.parse((entry.value as Map<String, dynamic>)['expiresAt']);
        if (expiresAt.isAfter(DateTime.now())) {
          _memoryCache[entry.key] = _CacheEntry(
            data: data,
            expiresAt: expiresAt,
          );
        }
      }
    } catch (_) {
      _memoryCache.clear();
    }
  }

  static Future<void> _persistCache() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    _memoryCache.forEach((key, entry) {
      if (!entry.isExpired) {
        data[key] = {
          'data': entry.data.toJson(),
          'expiresAt': entry.expiresAt.toIso8601String(),
        };
      }
    });
    await prefs.setString(_cacheKey, jsonEncode(data));
  }
}

class _CacheEntry {
  _CacheEntry({required this.data, required this.expiresAt});

  final LinkPreviewData data;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
