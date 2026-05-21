import 'package:flutter/material.dart';

class PluginMarketplaceSkeleton extends StatelessWidget {
  final int cardCount;

  const PluginMarketplaceSkeleton({super.key, this.cardCount = 3});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(cardCount, (i) {
          return Padding(
            padding: EdgeInsets.only(bottom: i < cardCount - 1 ? 12 : 0),
            child: _ShimmerBox(
              height: 168,
              color: cs.surfaceContainerHighest,
            ),
          );
        }),
      ),
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
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
          opacity: 0.45 + _controller.value * 0.35,
          child: child,
        );
      },
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
