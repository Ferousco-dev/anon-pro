import 'package:flutter/material.dart';

/// Enum to select the skeleton variant.
enum InboxSkeletonVariant { chat, notification }

/// Premium shimmer skeleton loader for the Inbox screen.
/// Displays realistic placeholders while conversations or notifications load.
class InboxSkeletonLoader extends StatelessWidget {
  final InboxSkeletonVariant variant;
  final int itemCount;

  const InboxSkeletonLoader({
    super.key,
    this.variant = InboxSkeletonVariant.chat,
    this.itemCount = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (variant == InboxSkeletonVariant.notification) {
          return _NotificationSkeletonItem(index: index);
        }
        return _ChatSkeletonItem(index: index);
      },
    );
  }
}

// ─────────────────────── Chat Skeleton ───────────────────────

class _ChatSkeletonItem extends StatelessWidget {
  final int index;
  const _ChatSkeletonItem({required this.index});

  @override
  Widget build(BuildContext context) {
    // Vary widths for a more organic feel
    final nameWidth = 90.0 + (index % 3) * 30.0;
    final msgWidth = 140.0 + (index % 4) * 25.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2226)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D22),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),

          // Text placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Name
                    Container(
                      width: nameWidth,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D22),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const Spacer(),
                    // Time
                    Container(
                      width: 32,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D22),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Message preview
                Container(
                  width: msgWidth,
                  height: 11,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D22),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: msgWidth * 0.6,
                  height: 11,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D22),
                    borderRadius: BorderRadius.circular(5),
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

// ─────────────────────── Notification Skeleton ───────────────────────

class _NotificationSkeletonItem extends StatelessWidget {
  final int index;
  const _NotificationSkeletonItem({required this.index});

  @override
  Widget build(BuildContext context) {
    final textWidth = 160.0 + (index % 3) * 30.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2226)),
      ),
      child: Row(
        children: [
          // Avatar with badge overlay
          SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D22),
                    shape: BoxShape.circle,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D22),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Body text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: textWidth,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D22),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: textWidth * 0.5,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D22),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),

          // Action placeholder
          Container(
            width: 60,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D22),
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ],
      ),
    );
  }
}
