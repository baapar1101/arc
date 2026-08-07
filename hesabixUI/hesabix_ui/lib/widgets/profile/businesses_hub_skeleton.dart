import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';

class BusinessesHubSkeleton extends StatelessWidget {
  final bool listMode;

  const BusinessesHubSkeleton({super.key, this.listMode = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);
    if (listMode || isMobile) {
      return Column(
        children: List.generate(4, (i) {
          return Padding(
            padding: EdgeInsets.only(bottom: i < 3 ? 12 : 0),
            child: _ShimmerBox(height: 88, color: cs.surfaceContainerHighest),
          );
        }),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = ResponsiveHelper.breakpoint(context) == 'lg' ? 3 : 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: List.generate(cols * 2, (i) {
            final w = (constraints.maxWidth - (cols - 1) * 16) / cols;
            return SizedBox(
              width: w,
              child: _ShimmerBox(height: 168, color: cs.surfaceContainerHighest),
            );
          }),
        );
      },
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double height;
  final Color color;

  const _ShimmerBox({required this.height, required this.color});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.42 + _controller.value * 0.38,
          child: child,
        );
      },
      child: Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
