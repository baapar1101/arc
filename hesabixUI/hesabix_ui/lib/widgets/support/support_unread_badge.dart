import 'package:flutter/material.dart';

/// Unread indicator dot for ticket list rows.
class SupportUnreadBadge extends StatelessWidget {
  final bool show;
  final double size;

  const SupportUnreadBadge({super.key, required this.show, this.size = 8});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}
