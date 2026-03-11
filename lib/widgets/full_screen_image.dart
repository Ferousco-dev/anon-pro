import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/constants.dart';

class FullScreenImage extends StatelessWidget {
  final String imageUrl;
  final String? tag;

  const FullScreenImage({
    super.key,
    required this.imageUrl,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            onPressed: () {
              // Implementation for download would go here if needed
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saving to gallery...')),
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! > 500 || details.primaryVelocity! < -500) {
            Navigator.pop(context);
          }
        },
        child: Center(
          child: Hero(
            tag: tag ?? imageUrl,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: AppConstants.primaryBlue),
                ),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white, size: 50),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
