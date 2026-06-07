import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

/// Modern animated splash screen for the FirstPro accounting app.
///
/// Displays with smooth animations while the app initializes:
/// 1. Gradient background with floating geometric shapes
/// 2. Logo with scale + fade-in animation
/// 3. App name with slide-up animation
/// 4. Subtle progress indicator at the bottom
///
/// This is a passive widget — it does not control navigation.
/// The parent (main.dart) decides when to transition away.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _bgShapesController;
  late AnimationController _progressController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textSlide;
  late Animation<double> _textOpacity;
  late Animation<double> _progressValue;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startAnimations();
  }

  void _initAnimations() {
    // ── Logo: scale + fade (0 → 600ms) ──
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );

    // ── Text: slide up + fade (400 → 900ms) ──
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _textSlide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    // ── Background shapes: continuous slow rotation ──
    _bgShapesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // ── Progress bar (fills over 2500ms) ──
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );
  }

  Future<void> _startAnimations() async {
    // Phase 1: Logo appears (0-600ms)
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 400));

    // Phase 2: Text slides in (400-900ms)
    if (!mounted) return;
    _textController.forward();
    await Future.delayed(const Duration(milliseconds: 100));

    // Phase 3: Progress bar fills (500-3000ms)
    if (!mounted) return;
    _progressController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _bgShapesController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primaryDark,
                AppColors.primary,
                AppColors.primaryLight,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // ── Floating geometric shapes ──
              ..._buildFloatingShapes(size),

              // ── Main content ──
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo with animation
                    AnimatedBuilder(
                      animation: _logoController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _logoOpacity.value,
                          child: Transform.scale(
                            scale: _logoScale.value,
                            child: child,
                          ),
                        );
                      },
                      child: _buildLogo(),
                    ),

                    const SizedBox(height: 32),

                    // App name with animation
                    AnimatedBuilder(
                      animation: _textController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _textOpacity.value,
                          child: Transform.translate(
                            offset: Offset(0, _textSlide.value),
                            child: child,
                          ),
                        );
                      },
                      child: _buildAppName(),
                    ),
                  ],
                ),
              ),

              // ── Bottom progress indicator ──
              Positioned(
                left: 48,
                right: 48,
                bottom: size.height * 0.12,
                child: AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progressValue.value,
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'جاري التحميل...',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.6),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.3),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Icon(
            Icons.calculate_outlined,
            size: 56,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildAppName() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          AppConstants.appFullName,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.6),
              width: 1,
            ),
            color: AppColors.secondary.withValues(alpha: 0.1),
          ),
          child: Text(
            AppConstants.appSlogan,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary.withValues(alpha: 0.9),
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFloatingShapes(Size size) {
    return [
      // Top-right circle
      Positioned(
        top: size.height * 0.08,
        right: -30,
        child: AnimatedBuilder(
          animation: _bgShapesController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _bgShapesController.value * 0.5,
              child: child,
            );
          },
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ),
      ),

      // Bottom-left circle
      Positioned(
        bottom: size.height * 0.15,
        left: -40,
        child: AnimatedBuilder(
          animation: _bgShapesController,
          builder: (context, child) {
            return Transform.rotate(
              angle: -_bgShapesController.value * 0.3,
              child: child,
            );
          },
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
        ),
      ),

      // Top-left diamond
      Positioned(
        top: size.height * 0.2,
        left: 30,
        child: AnimatedBuilder(
          animation: _bgShapesController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _bgShapesController.value * 1.0,
              child: child,
            );
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
      ),

      // Mid-right small dot
      Positioned(
        top: size.height * 0.45,
        right: 40,
        child: AnimatedBuilder(
          animation: _bgShapesController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(
                0,
                10 * (_bgShapesController.value * 2 - 1).abs(),
              ),
              child: child,
            );
          },
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.secondary.withValues(alpha: 0.2),
            ),
          ),
        ),
      ),

      // Bottom-right diamond
      Positioned(
        bottom: size.height * 0.25,
        right: 60,
        child: AnimatedBuilder(
          animation: _bgShapesController,
          builder: (context, child) {
            return Transform.rotate(
              angle: -_bgShapesController.value * 0.7,
              child: child,
            );
          },
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
      ),

      // Subtle radial glow behind logo
      Positioned.fill(
        child: Center(
          child: AnimatedBuilder(
            animation: _logoController,
            builder: (context, _) {
              return Container(
                width: 200 * _logoScale.value,
                height: 200 * _logoScale.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.secondary.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.3, 1.0],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ];
  }
}
