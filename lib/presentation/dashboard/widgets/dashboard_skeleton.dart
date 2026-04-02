import 'package:flutter/material.dart';

import '../../theme/theme_data_factory.dart';

class DashboardSkeleton extends StatefulWidget {
  const DashboardSkeleton({super.key});

  @override
  State<DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final opacity = 0.3 + (_animation.value * 0.4);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SkeletonBox(width: 160, height: 28, opacity: opacity),
            const SizedBox(height: 6),
            _SkeletonBox(width: 120, height: 16, opacity: opacity),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth > 600 ? 4 : 2;
                final aspectRatio = constraints.maxWidth > 600 ? 1.6 : 1.05;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: aspectRatio,
                  children: List.generate(
                    4,
                    (_) => _SkeletonCard(opacity: opacity),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            _SkeletonBox(width: double.infinity, height: 260, opacity: opacity, radius: 16),
            const SizedBox(height: 20),
            _SkeletonBox(width: double.infinity, height: 320, opacity: opacity, radius: 16),
          ],
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.opacity,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double opacity;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: MangoThemeFactory.altSurface(context),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MangoThemeFactory.cardColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MangoThemeFactory.borderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MangoThemeFactory.altSurface(context),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const Spacer(),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: MangoThemeFactory.altSurface(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 100,
              height: 20,
              decoration: BoxDecoration(
                color: MangoThemeFactory.altSurface(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
