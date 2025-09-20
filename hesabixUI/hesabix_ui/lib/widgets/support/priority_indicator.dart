import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/support_models.dart';

class PriorityIndicator extends StatelessWidget {
  final SupportPriority priority;
  final bool isSmall;
  final bool showText;

  const PriorityIndicator({
    super.key,
    required this.priority,
    this.isSmall = false,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getPriorityColor(theme);
    
    if (!showText) {
      return Container(
        width: isSmall ? 12 : 16,
        height: isSmall ? 12 : 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 12,
        vertical: isSmall ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(isSmall ? 12 : 16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isSmall ? 6 : 8,
            height: isSmall ? 6 : 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            priority.name,
            style: TextStyle(
              color: color,
              fontSize: isSmall ? 11 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getPriorityColor(ThemeData theme) {
    if (priority.color != null) {
      try {
        return Color(int.parse(priority.color!.replaceFirst('#', '0xFF')));
      } catch (e) {
        // Fallback to default colors
      }
    }

    // Default colors based on priority name
    switch (priority.name.toLowerCase()) {
      case 'کم':
        return Colors.green;
      case 'متوسط':
        return Colors.orange;
      case 'بالا':
        return Colors.red;
      case 'فوری':
        return Colors.red.shade800;
      default:
        return theme.colorScheme.primary;
    }
  }
}
