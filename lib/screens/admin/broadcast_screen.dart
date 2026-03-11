import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/constants.dart';
import '../../main.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  bool _isSending = false;
  bool _sendSuccess = false;
  String _selectedType = 'announcement';

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  final List<Map<String, dynamic>> _broadcastTypes = [
    {
      'key': 'announcement',
      'label': 'Announcement',
      'icon': Icons.campaign_rounded,
      'emoji': '📢',
      'color': const Color(0xFF007AFF),
    },
    {
      'key': 'update',
      'label': 'Update',
      'icon': Icons.system_update_rounded,
      'emoji': '🔄',
      'color': const Color(0xFF34C759),
    },
    {
      'key': 'warning',
      'label': 'Warning',
      'icon': Icons.warning_amber_rounded,
      'emoji': '⚠️',
      'color': const Color(0xFFFF9500),
    },
    {
      'key': 'event',
      'label': 'Event',
      'icon': Icons.celebration_rounded,
      'emoji': '🎉',
      'color': const Color(0xFFAF52DE),
    },
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentType =>
      _broadcastTypes.firstWhere((t) => t['key'] == _selectedType);

  Future<void> _sendBroadcast() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Please fill in both title and message'),
              ),
            ],
          ),
          backgroundColor: AppConstants.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    HapticFeedback.lightImpact();

    try {
      // Build the broadcast content with emoji prefix
      final emoji = _currentType['emoji'] as String;
      final typeLabel = (_currentType['label'] as String).toUpperCase();
      final broadcastContent = '$emoji [$typeLabel] $title\n\n$body';

      // Store as a post visible to all users in their feed
      await supabase.from('posts').insert({
        'user_id': supabase.auth.currentUser!.id,
        'content': broadcastContent,
        'is_anonymous': false,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Show success state
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _isSending = false;
          _sendSuccess = true;
        });
        _animController.forward();

        // Reset after animation
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _sendSuccess = false);
            _animController.reset();
            _titleController.clear();
            _bodyController.clear();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Failed to send: $e')),
              ],
            ),
            backgroundColor: AppConstants.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _currentType['color'] as Color;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Broadcast',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // ── Header illustration ──
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        typeColor.withValues(alpha: 0.3),
                        typeColor.withValues(alpha: 0.1),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: typeColor.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    _currentType['icon'] as IconData,
                    color: typeColor,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Send to all users',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Broadcast type selector ──
              const Text(
                'TYPE',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: _broadcastTypes.map((type) {
                  final isSelected = _selectedType == type['key'];
                  final color = type['color'] as Color;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedType = type['key'] as String);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.15)
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? color.withValues(alpha: 0.5)
                                : const Color(0xFF2C2C2E),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              type['icon'] as IconData,
                              color:
                                  isSelected ? color : const Color(0xFF8E8E93),
                              size: 22,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              type['label'] as String,
                              style: TextStyle(
                                color: isSelected
                                    ? color
                                    : const Color(0xFF8E8E93),
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

              // ── Title field ──
              const Text(
                'TITLE',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF2C2C2E),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _titleController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter broadcast title...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 16,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(
                        Icons.title_rounded,
                        color: typeColor.withValues(alpha: 0.6),
                        size: 22,
                      ),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Message field ──
              const Text(
                'MESSAGE',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF2C2C2E),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _bodyController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.5,
                  ),
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: 'Write your broadcast message...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Character count
              Align(
                alignment: Alignment.centerRight,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _bodyController,
                  builder: (_, value, __) {
                    return Text(
                      '${value.text.length} characters',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // ── Preview card ──
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _titleController,
                builder: (_, titleVal, __) {
                  return ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _bodyController,
                    builder: (_, bodyVal, __) {
                      if (titleVal.text.isEmpty && bodyVal.text.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PREVIEW',
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  typeColor.withValues(alpha: 0.08),
                                  const Color(0xFF1C1C1E),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: typeColor.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _currentType['emoji'] as String,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '[${(_currentType['label'] as String).toUpperCase()}]',
                                      style: TextStyle(
                                        color: typeColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                                if (titleVal.text.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    titleVal.text,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                if (bodyVal.text.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    bodyVal.text,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                      );
                    },
                  );
                },
              ),

              // ── Send button ──
              SizedBox(
                width: double.infinity,
                height: 54,
                child: _sendSuccess
                    ? ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    color: Colors.white, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Broadcast Sent!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _isSending ? null : _sendBroadcast,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: typeColor,
                          disabledBackgroundColor:
                              typeColor.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _currentType['icon'] as IconData,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Send Broadcast',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
