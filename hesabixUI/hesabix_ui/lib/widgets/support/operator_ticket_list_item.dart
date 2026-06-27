import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as date_utils;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/support_unread_badge.dart';
import 'package:hesabix_ui/widgets/support/support_semantic_colors.dart';
import 'package:hesabix_ui/widgets/support/ticket_status_chip.dart';

/// Compact inbox row for operator ticket lists (Zendesk-style).
class OperatorTicketListItem extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isSelected;
  final VoidCallback? onTap;
  final CalendarController? calendarController;

  const OperatorTicketListItem({
    super.key,
    required this.row,
    this.isSelected = false,
    this.onTap,
    this.calendarController,
  });

  SupportTicket? get _ticket {
    try {
      return SupportTicket.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  String _relativeTime(DateTime dt, AppLocalizations l10n) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final diff = DateTime.now().difference(local);
    if (diff.isNegative) return l10n.justNow;
    if (diff.inDays > 0) {
      final isJalali = calendarController?.isJalali ?? true;
      return date_utils.HesabixDateUtils.formatForDisplay(local, isJalali);
    }
    if (diff.inHours > 0) return l10n.hoursAgo('${diff.inHours}');
    if (diff.inMinutes > 0) return l10n.minutesAgo('${diff.inMinutes}');
    return l10n.justNow;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = SupportSemanticColors.of(context);
    final ticket = _ticket;
    final id = row['id'];
    final title = '${row['title'] ?? ''}';
    final userMap = row['user'];
    final userName = userMap is Map
        ? SupportUser.fromJson(Map<String, dynamic>.from(userMap)).displayName
        : '';
    final slaStatus = slaStatusFromRow(row);
    final slaSide = slaRowBorderSide(slaStatus);
    final updatedAt = ticket?.updatedAt ?? DateTime.now();

    return Material(
      color: isSelected ? colors.selectedRowBg : null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
              left: slaSide ?? BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#$id',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        SupportUnreadBadge(show: row['is_unread_for_operator'] == true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (ticket?.status != null)
                          TicketStatusChip(status: ticket!.status!, isSmall: true),
                        if (ticket?.priority != null)
                          _PriorityDot(priority: ticket!.priority!),
                        SlaIndicator(slaStatus: slaStatus, compact: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _relativeTime(updatedAt, l10n),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (ticket?.assignedOperator != null) ...[
                    const SizedBox(height: 6),
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: theme.colorScheme.secondary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  final SupportPriority priority;

  const _PriorityDot({required this.priority});

  Color _color() {
    if (priority.color != null) {
      try {
        return Color(int.parse(priority.color!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Tooltip(
      message: priority.name,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag, size: 12, color: c),
          const SizedBox(width: 3),
          Text(
            priority.name,
            style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
