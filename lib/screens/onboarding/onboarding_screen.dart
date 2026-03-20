import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/constants.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String prefKey = 'onboarding_complete';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _pageIndex = 0;
  late final AnimationController _floatController;

  static const List<String> _slideArtSvgs = [
    '''
<svg width="96" height="96" viewBox="0 0 96 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="48" cy="48" r="30" stroke="currentColor" stroke-width="2" opacity="0.35"/>
  <circle cx="48" cy="48" r="18" stroke="currentColor" stroke-width="2" opacity="0.6"/>
  <circle cx="48" cy="48" r="6" fill="currentColor"/>
</svg>
''',
    '''
<svg width="96" height="96" viewBox="0 0 96 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M18 48C24 36 36 28 48 28C60 28 72 36 78 48" stroke="currentColor" stroke-width="2" opacity="0.5"/>
  <path d="M26 54C30 46 38 40 48 40C58 40 66 46 70 54" stroke="currentColor" stroke-width="2" opacity="0.75"/>
  <path d="M36 58C38 54 43 50 48 50C53 50 58 54 60 58" stroke="currentColor" stroke-width="2"/>
  <circle cx="48" cy="62" r="4" fill="currentColor"/>
</svg>
''',
    '''
<svg width="96" height="96" viewBox="0 0 96 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="22" y="22" width="52" height="52" rx="12" stroke="currentColor" stroke-width="2" opacity="0.6"/>
  <rect x="34" y="34" width="28" height="28" rx="8" stroke="currentColor" stroke-width="2"/>
  <circle cx="48" cy="48" r="4" fill="currentColor"/>
</svg>
''',
  ];

  final List<_OnboardingSlide> _slides = const [
    _OnboardingSlide(
      eyebrow: 'Privacy',
      title: 'Anonymous, not careless.',
      highlight: 'Anonymous',
      body: 'Speak freely without losing your edge.',
    ),
    _OnboardingSlide(
      eyebrow: 'Signal',
      title: 'Signal over noise.',
      highlight: 'Signal',
      body: 'Find honest takes, real questions, and useful answers.',
    ),
    _OnboardingSlide(
      eyebrow: 'Control',
      title: 'Own your space.',
      highlight: 'Own',
      body: 'Curate a profile that feels clean, calm, and professional.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen.prefKey, true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _goNext() {
    if (_pageIndex == _slides.length - 1) {
      _completeOnboarding();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _goPrevious() {
    if (_pageIndex == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'ANONPRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _completeOnboarding,
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            color: AppConstants.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _slides.length,
                      onPageChanged: (index) {
                        setState(() => _pageIndex = index);
                      },
                      itemBuilder: (context, index) {
                        final slide = _slides[index];
                        return AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, child) {
                            final page = _pageController.hasClients
                                ? (_pageController.page ?? _pageIndex.toDouble())
                                : _pageIndex.toDouble();
                            final delta = index - page;
                            return _buildSlide(
                              slide,
                              index,
                              offset: delta,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _pageIndex == index ? 26 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _pageIndex == index
                              ? AppConstants.primaryBlue
                              : AppConstants.lightGray,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: _pageIndex == 0 ? null : _goPrevious,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.textSecondary,
                          side: const BorderSide(color: AppConstants.lightGray),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _goNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 14,
                          ),
                        ),
                        child: Text(
                          _pageIndex == _slides.length - 1
                              ? 'Get started'
                              : 'Next',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdrop() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF050509),
              Color(0xFF0B0F1A),
              Color(0xFF000000),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.primaryBlue.withOpacity(0.15),
                ),
              ),
            ),
            Positioned(
              bottom: -140,
              left: -80,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.green.withOpacity(0.14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(
    _OnboardingSlide slide,
    int index, {
    double offset = 0,
  }) {
    final titleStyle = const TextStyle(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    final highlightStyle = titleStyle.copyWith(
      color: AppConstants.primaryBlue,
    );
    final translateX = offset * 20;
    final scale =
        (1 - (offset.abs() * 0.04)).clamp(0.94, 1.0).toDouble();

    return Transform.translate(
      offset: Offset(translateX, 0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppConstants.darkGray.withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppConstants.lightGray),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.mediumGray,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      slide.eyebrow.toUpperCase(),
                      style: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '0${index + 1} / 03',
                    style: const TextStyle(
                      color: AppConstants.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: _buildSlideArt(index, offset),
              ),
              const SizedBox(height: 16),
              _buildSlideTitle(slide, titleStyle, highlightStyle),
              const SizedBox(height: 14),
              Text(
                slide.body,
                style: const TextStyle(
                  color: AppConstants.textSecondary,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const Spacer(),
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.primaryBlue.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlideArt(int index, double offset) {
    final svg = _slideArtSvgs[index % _slideArtSvgs.length];
    final color = AppConstants.primaryBlue.withOpacity(0.9);
    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        final t = _floatController.value * math.pi * 2;
        final floatY = math.sin(t + index) * 6;
        final floatX = math.cos(t + index) * 4;
        final parallax = -offset * 6;
        final rotation = math.sin(t + index) * 0.04;
        return Transform.translate(
          offset: Offset(floatX + parallax, floatY),
          child: Transform.rotate(
            angle: rotation,
            child: child,
          ),
        );
      },
      child: SvgPicture.string(
        svg,
        width: 88,
        height: 88,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }

  Widget _buildSlideTitle(
    _OnboardingSlide slide,
    TextStyle titleStyle,
    TextStyle highlightStyle,
  ) {
    final highlight = slide.highlight;
    if (highlight == null || highlight.isEmpty) {
      return Text(slide.title, style: titleStyle);
    }
    final parts = slide.title.split(highlight);
    if (parts.length < 2) {
      return Text(slide.title, style: titleStyle);
    }
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: parts.first, style: titleStyle),
          TextSpan(text: highlight, style: highlightStyle),
          TextSpan(text: parts.sublist(1).join(highlight), style: titleStyle),
        ],
      ),
    );
  }
}

class _OnboardingSlide {
  final String eyebrow;
  final String title;
  final String? highlight;
  final String body;

  const _OnboardingSlide({
    required this.eyebrow,
    required this.title,
    this.highlight,
    required this.body,
  });
}
