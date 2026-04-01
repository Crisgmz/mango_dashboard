import 'package:flutter/material.dart';
import '../../../core/responsive/dpi_scale.dart';

class MangoSplashScreen extends StatefulWidget {
  const MangoSplashScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<MangoSplashScreen> createState() => _MangoSplashScreenState();
}

class _MangoSplashScreenState extends State<MangoSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeOut)),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)),
    );

    _controller.forward();
    
    // Auto complete after duration
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Hero(
              tag: 'app_logo',
              child: Image.asset(
                'assets/logo/logo.png',
                width: dpi.scale(160),
                height: dpi.scale(160),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
