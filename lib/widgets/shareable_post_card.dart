import 'package:flutter/material.dart';
import '../models/post_model.dart';

class ShareablePostCard extends StatelessWidget {
  final PostModel post;
  final bool isAnonymous;

  const ShareablePostCard({
    super.key,
    required this.post,
    required this.isAnonymous,
  });

  Color _getBackgroundColor() {
    final colors = [
      const Color(0xFF667eea), // Purple
      const Color(0xFFf093fb), // Pink
      const Color(0xFF4facfe), // Blue
      const Color(0xFFfa709a), // Orange
      const Color(0xFF30cfd0), // Teal
      const Color(0xFFa8edea), // Green
      const Color(0xFFff9a56), // Orange
      const Color(0xFFfee140), // Yellow
    ];
    return colors[post.id.hashCode % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _getBackgroundColor();

    return Container(
      width: 400,
      height: 520,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top: Quote mark
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              '"',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 48,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          // Middle: Post content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    post.content.isEmpty ? '✨ Shared a moment ✨' : post.content,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom: Branding + CTA
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 2,
                  color: Colors.white.withOpacity(0.5),
                  margin: const EdgeInsets.only(bottom: 12),
                ),
                Text(
                  'ANON PRO ORACLES',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
