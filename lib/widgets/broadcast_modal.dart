import 'package:flutter/material.dart';
import '../utils/constants.dart';

class BroadcastModal extends StatefulWidget {
  final String emoji;
  final String type;
  final String title;
  final String message;
  final Color typeColor;
  final VoidCallback onDismiss;

  const BroadcastModal({
    super.key,
    required this.emoji,
    required this.type,
    required this.title,
    required this.message,
    required this.typeColor,
    required this.onDismiss,
  });

  @override
  State<BroadcastModal> createState() => _BroadcastModalState();
}

class _BroadcastModalState extends State<BroadcastModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _closeModal() async {
    await _animController.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: () {}, // Prevent dismiss by tapping outside
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppConstants.darkGray,
                    AppConstants.darkGray.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: widget.typeColor.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.typeColor.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top accent line
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: widget.typeColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Emoji + Type Badge
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              widget.typeColor.withOpacity(0.2),
                              widget.typeColor.withOpacity(0.05),
                            ],
                          ),
                          border: Border.all(
                            color: widget.typeColor.withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          widget.emoji,
                          style: const TextStyle(fontSize: 36),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: widget.typeColor.withOpacity(0.15),
                          border: Border.all(
                            color: widget.typeColor.withOpacity(0.5),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.type.toUpperCase(),
                          style: TextStyle(
                            color: widget.typeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppConstants.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Message
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.6,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Okay Button
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.typeColor,
                              widget.typeColor.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: widget.typeColor.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 0,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _closeModal,
                            radius: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 32,
                              ),
                              child: const Text(
                                'Okay',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppConstants.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
