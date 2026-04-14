import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/support_models.dart';

class TicketStatusChip extends StatelessWidget {
  final SupportStatus status;
  final bool isSmall;

  const TicketStatusChip({
    super.key,
    required this.status,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getStatusColor(theme);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 12,
        vertical: isSmall ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(isSmall ? 12 : 16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSmall) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            status.name,
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

  Color _getStatusColor(ThemeData theme) {
    if (status.color != null) {
      try {
        return Color(int.parse(status.color!.replaceFirst('#', '0xFF')));
      } catch (e) {
        // Fallback to default colors
      }
    }

    // Default colors based on status name
    switch (status.name.toLowerCase()) {
      case 'باز':
        return Colors.blue;
      case 'در حال پیگیری':
        return Colors.purple;
      case 'در انتظار کاربر':
        return Colors.cyan;
      case 'بسته':
        return Colors.grey;
      case 'حل شده':
        return Colors.green;
      default:
        return theme.colorScheme.primary;
    }
  }
}
