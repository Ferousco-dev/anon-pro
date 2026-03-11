import 'package:flutter/material.dart';

class PostHeader extends StatelessWidget {
  final String profileImage;
  final String displayName;
  final String username;
  final bool isVerified;
  final String timestamp;

  const PostHeader({
    super.key,
    required this.profileImage,
    required this.displayName,
    required this.username,
    required this.isVerified,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundImage: NetworkImage(profileImage),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified,
                      color: Color(0xFF1DA1F2),
                      size: 16,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '@$username · $timestamp',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.more_vert,
            color: Colors.grey,
          ),
          onPressed: () {
            // Handle menu press
          },
        ),
      ],
    );
  }
}
