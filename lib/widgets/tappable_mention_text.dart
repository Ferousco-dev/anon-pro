import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../utils/constants.dart';

/// Renders post/comment content with tappable @mentions.
/// When user taps @username, navigates to that user's profile.
class TappableMentionText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final TextStyle? mentionStyle;
  final Map<String, String>? aliasToUserId;
  final VoidCallback? onMentionTap;

  const TappableMentionText({
    super.key,
    required this.text,
    this.baseStyle,
    this.mentionStyle,
    this.aliasToUserId,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultBase = baseStyle ??
        const TextStyle(
          fontSize: 15,
          color: AppConstants.white,
          height: 1.4,
        );
    final defaultMention = mentionStyle ??
        const TextStyle(
          fontSize: 15,
          color: AppConstants.primaryBlue,
          fontWeight: FontWeight.w600,
          height: 1.4,
        );

    final spans = _parseContent(context, defaultBase, defaultMention);
    return RichText(
      text: TextSpan(children: spans),
    );
  }

  Future<void> _navigateToProfile(BuildContext context, String alias) async {
    var userId = aliasToUserId?[alias];
    if (userId == null) {
      try {
        final res = await supabase
            .from('users')
            .select('id')
            .eq('alias', alias)
            .maybeSingle();
        userId = res?['id'] as String?;
      } catch (_) {}
    }
    if (userId != null && context.mounted) {
      onMentionTap?.call();
      Navigator.pushNamed(context, '/profile', arguments: userId);
    }
  }

  List<InlineSpan> _parseContent(
    BuildContext context,
    TextStyle baseStyle,
    TextStyle mentionStyle,
  ) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'@([a-zA-Z0-9_]+)');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }

      final alias = match.group(1) ?? '';
      final fullMention = '@$alias';

      spans.add(TextSpan(
        text: fullMention,
        style: mentionStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _navigateToProfile(context, alias),
      ));

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }

    return spans.isEmpty
        ? [TextSpan(text: text, style: baseStyle)]
        : spans;
  }
}
