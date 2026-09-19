import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

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
    final color = _getStatusColor(context, theme);

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

  Color _getStatusColor(BuildContext context, ThemeData theme) {
    if (status.color != null) {
      try {
        return Color(int.parse(status.color!.replaceFirst('#', '0xFF')));
      } catch (e) {
        // Fallback to default colors
      }
    }

    final semantics = SemanticColorResolver.of(context);
    switch (status.name.toLowerCase()) {
      case 'باز':
<<<<<<< HEAD
      case 'open':
        return semantics.info;
=======
        return Colors.grey;
>>>>>>> github/Huma
      case 'در حال پیگیری':
      case 'in progress':
        return theme.colorScheme.tertiary;
      case 'در انتظار کاربر':
      case 'waiting':
        return semantics.warning;
      case 'بسته':
      case 'closed':
        return theme.colorScheme.outline;
      case 'حل شده':
      case 'resolved':
        return semantics.positive;
      default:
        return theme.colorScheme.primary;
    }
  }
}
