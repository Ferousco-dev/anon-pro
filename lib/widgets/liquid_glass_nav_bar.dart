import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A modern bottom navigation bar with a liquid glass magnification effect
/// inspired by Apple VisionOS / dynamic dock style.
class LiquidGlassNavBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final String? profileImageUrl;
  final bool showInboxDot;

  const LiquidGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.profileImageUrl,
    this.showInboxDot = false,
  });

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar>
    with TickerProviderStateMixin {
  // Controls the bubble slide position between tabs
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  // Controls the bubble scale pop when switching tabs
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  // Tab press scale animation
  late AnimationController _tapController;
  late Animation<double> _tapAnimation;

  int _previousIndex = 0;

  static const int _itemCount = 4;
  static const List<String> _labels = ['Home', 'Anon', 'Inbox', 'You'];
  static const List<int> _iconIndices = [0, 1, 2, 3];

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.selectedIndex;

    // Slide controller — spring-like animation for bubble position
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _slideAnimation = Tween<double>(
      begin: widget.selectedIndex.toDouble(),
      end: widget.selectedIndex.toDouble(),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Scale controller — pops the bubble when changing tabs
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.96), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.03), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
    ));

    // Tap scale — quick pop on press
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _tapAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _tapController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void didUpdateWidget(LiquidGlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _previousIndex = oldWidget.selectedIndex;
      _slideAnimation = Tween<double>(
        begin: _previousIndex.toDouble(),
        end: widget.selectedIndex.toDouble(),
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      ));
      _slideController.forward(from: 0);
      _scaleController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _scaleController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact();
    _tapController.forward(from: 0);
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                color: Colors.white.withOpacity(0.06),
                border: Border.all(
                  color: Colors.white.withOpacity(0.12),
                  width: 0.8,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.10),
                    Colors.white.withOpacity(0.03),
                  ],
                ),
                boxShadow: const [],
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _slideAnimation,
                  _scaleAnimation,
                  _tapAnimation,
                ]),
                builder: (context, _) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // The floating glass bubble behind the selected item
                      _buildFloatingBubble(),
                      // The nav items row
                      _buildItemsRow(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBubble() {
    final itemWidth = _getItemWidth();
    final bubbleWidth = itemWidth - 12;
    final bubbleHeight = 52.0;
    final bubbleX =
        _slideAnimation.value * itemWidth + (itemWidth - bubbleWidth) / 2;
    final bubbleY = 8.0;

    final scale = _scaleAnimation.value;

    return Positioned(
      left: bubbleX,
      top: bubbleY,
      child: Transform.scale(
        scale: scale,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: bubbleWidth,
              height: bubbleHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: Colors.white.withOpacity(0.22),
                  width: 0.9,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.18),
                    Colors.white.withOpacity(0.04),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemsRow() {
    return Row(
      children: List.generate(_itemCount, (index) {
        return Expanded(
          child: _buildNavItem(index),
        );
      }),
    );
  }

  Widget _buildNavItem(int index) {
    final isSelected = widget.selectedIndex == index;

    // Compute how close this item is to the current animated position (0.0–1.0)
    final distance =
        (index - _slideAnimation.value).abs().clamp(0.0, 1.5);
    final proximity = (1.0 - (distance / 1.5)).clamp(0.0, 1.0);

    // Icons scale up with proximity to the bubble
    final iconScale = 1.0 + (proximity * 0.30);
    final labelOpacity = isSelected ? 1.0 : 0.5 + (proximity * 0.15);
    final iconOpacity = isSelected ? 1.0 : 0.4 + (proximity * 0.2);

    // Vertical lift for the selected item (floats into the bubble)
    final verticalOffset = isSelected ? -6.0 * _scaleAnimation.value : 0.0;

    final tapScale = isSelected ? _tapAnimation.value : 1.0;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 72,
        child: Transform.translate(
          offset: Offset(0, verticalOffset),
          child: Transform.scale(
            scale: tapScale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon area
                Transform.scale(
                  scale: iconScale,
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: _buildIconContent(index, isSelected, iconOpacity),
                  ),
                ),
                const SizedBox(height: 4),
                // Label
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: isSelected ? 10.0 : 9.5,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: Colors.white.withOpacity(labelOpacity),
                    letterSpacing: isSelected ? 0.3 : 0.1,
                  ),
                  child: Text(_labels[index]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconContent(int index, bool isSelected, double opacity) {
    final showDot = index == 2 && widget.showInboxDot;

    // Profile tab (index 3) — show avatar
    if (index == 3) {
      return _buildProfileIcon(isSelected, opacity);
    }

    // For other tabs, use the custom painted icons
    final icon = _LiquidNavIcon(
      index: _iconIndices[index],
      isSelected: isSelected,
      color: Colors.white.withOpacity(opacity),
    );
    if (!showDot) return icon;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -1,
          top: -1,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black,
                width: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileIcon(bool isSelected, double opacity) {
    final hasImage =
        widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty;

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? Colors.white.withOpacity(0.9)
              : Colors.white.withOpacity(0.25),
          width: isSelected ? 2.0 : 1.2,
        ),
        boxShadow: const [],
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
                widget.profileImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildDefaultAvatar(opacity),
              )
            : _buildDefaultAvatar(opacity),
      ),
    );
  }

  Widget _buildDefaultAvatar(double opacity) {
    return Container(
      color: const Color(0xFF007AFF).withOpacity(0.6),
      child: Icon(
        Icons.person,
        size: 16,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }

  double _getItemWidth() {
    // Calculate based on available width minus padding
    final screenWidth = MediaQuery.of(context).size.width;
    final barWidth = screenWidth - 32; // 16px padding on each side
    return barWidth / _itemCount;
  }
}

// ─── Custom painted nav icons ──────────────────────────────────────────────────

class _LiquidNavIcon extends StatefulWidget {
  final int index;
  final bool isSelected;
  final Color color;

  const _LiquidNavIcon({
    required this.index,
    required this.isSelected,
    required this.color,
  });

  @override
  State<_LiquidNavIcon> createState() => _LiquidNavIconState();
}

class _LiquidNavIconState extends State<_LiquidNavIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    if (widget.isSelected) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_LiquidNavIcon old) {
    super.didUpdateWidget(old);
    if (widget.isSelected && !old.isSelected) {
      _ctrl.forward(from: 0);
    } else if (!widget.isSelected && old.isSelected) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (_, __) => CustomPaint(
        size: const Size(22, 22),
        painter: _LiquidNavIconPainter(
          index: widget.index,
          isSelected: widget.isSelected,
          progress: _progress.value,
          color: widget.color,
        ),
      ),
    );
  }
}

class _LiquidNavIconPainter extends CustomPainter {
  final int index;
  final bool isSelected;
  final double progress;
  final Color color;

  _LiquidNavIconPainter({
    required this.index,
    required this.isSelected,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = isSelected ? PaintingStyle.fill : PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    switch (index) {
      case 0:
        _drawHome(canvas, paint, w, h);
        break;
      case 1:
        _drawMask(canvas, paint, w, h);
        break;
      case 2:
        _drawChat(canvas, paint, w, h);
        break;
      case 3:
        _drawPerson(canvas, paint, w, h);
        break;
    }
  }

  void _drawHome(Canvas canvas, Paint paint, double w, double h) {
    final roofPath = Path()
      ..moveTo(w * 0.5, h * 0.05)
      ..lineTo(w * 0.95, h * 0.48)
      ..lineTo(w * 0.05, h * 0.48)
      ..close();

    final doorPath = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.34, h * 0.55, w * 0.32, h * 0.40),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      ));

    final bodyPath = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.10, h * 0.44, w * 0.80, h * 0.52),
        bottomLeft: const Radius.circular(2.5),
        bottomRight: const Radius.circular(2.5),
      ));

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (isSelected) {
      canvas.drawPath(roofPath, fillPaint);
      canvas.drawPath(bodyPath, fillPaint);
      canvas.drawPath(doorPath, Paint()..color = Colors.transparent);
      final doorStroke = Paint()
        ..color = color.withOpacity(0.18)
        ..style = PaintingStyle.fill;
      canvas.drawPath(doorPath, doorStroke);
    } else {
      canvas.drawPath(roofPath, strokePaint);
      canvas.drawPath(bodyPath, strokePaint);
    }
  }

  void _drawMask(Canvas canvas, Paint paint, double w, double h) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = isSelected ? PaintingStyle.fill : PaintingStyle.stroke;

    final center = Offset(w / 2, h / 2);
    final radius = w * 0.44;
    canvas.drawCircle(center, radius, p);

    if (isSelected) {
      final eyePaint = Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(w * 0.35, h * 0.40), w * 0.09, eyePaint);
      canvas.drawCircle(Offset(w * 0.65, h * 0.40), w * 0.09, eyePaint);
      final smilePaint = Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      final smilePath = Path()
        ..moveTo(w * 0.30, h * 0.62)
        ..quadraticBezierTo(w * 0.50, h * 0.78, w * 0.70, h * 0.62);
      canvas.drawPath(smilePath, smilePaint);
    } else {
      final eyePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(w * 0.35, h * 0.40), w * 0.08, eyePaint);
      canvas.drawCircle(Offset(w * 0.65, h * 0.40), w * 0.08, eyePaint);
    }
  }

  void _drawChat(Canvas canvas, Paint paint, double w, double h) {
    final bubblePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, h * 0.04, w * 0.88, h * 0.68),
        Radius.circular(w * 0.22),
      ));

    final tailPath = Path()
      ..moveTo(w * 0.20, h * 0.70)
      ..lineTo(w * 0.10, h * 0.94)
      ..lineTo(w * 0.38, h * 0.72)
      ..close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (isSelected) {
      canvas.drawPath(bubblePath, fillPaint);
      canvas.drawPath(tailPath, fillPaint);
      final dotPaint = Paint()
        ..color = Colors.black.withOpacity(0.45)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(w * 0.32, h * 0.38), w * 0.07, dotPaint);
      canvas.drawCircle(Offset(w * 0.50, h * 0.38), w * 0.07, dotPaint);
      canvas.drawCircle(Offset(w * 0.68, h * 0.38), w * 0.07, dotPaint);
    } else {
      canvas.drawPath(bubblePath, strokePaint);
      canvas.drawPath(tailPath, strokePaint);
    }
  }

  void _drawPerson(Canvas canvas, Paint paint, double w, double h) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (isSelected) {
      canvas.drawCircle(Offset(w * 0.50, h * 0.30), w * 0.22, fillPaint);
    } else {
      canvas.drawCircle(Offset(w * 0.50, h * 0.30), w * 0.22, strokePaint);
    }

    final shoulderPath = Path()
      ..moveTo(w * 0.04, h * 0.97)
      ..quadraticBezierTo(w * 0.04, h * 0.60, w * 0.50, h * 0.60)
      ..quadraticBezierTo(w * 0.96, h * 0.60, w * 0.96, h * 0.97)
      ..close();

    if (isSelected) {
      canvas.drawPath(shoulderPath, fillPaint);
    } else {
      canvas.drawPath(shoulderPath, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_LiquidNavIconPainter old) =>
      old.progress != progress ||
      old.isSelected != isSelected ||
      old.color != color;
}
