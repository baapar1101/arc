import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/support_unread_badge.dart';
import 'package:hesabix_ui/widgets/support/ticket_status_chip.dart';

/// Compact row for user ticket list (mobile + desktop).
class UserTicketListItem extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback? onTap;
  final CalendarController? calendarController;
  final bool isSelected;

  const UserTicketListItem({
    super.key,
    required this.ticket,
    this.onTap,
    this.calendarController,
    this.isSelected = false,
  });

  String _relativeTime(DateTime dt, AppLocalizations l10n) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final diff = DateTime.now().difference(local);
    if (diff.inDays > 0) return '${diff.inDays} روز پیش';
    if (diff.inHours > 0) return l10n.hoursAgo('${diff.inHours}');
    if (diff.inMinutes > 0) return l10n.minutesAgo('${diff.inMinutes}');
    return l10n.justNow;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Material(
      color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45) : theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ticket.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: ticket.isUnreadForUser || isSelected ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        SupportUnreadBadge(show: ticket.isUnreadForUser),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#${ticket.id} • ${_relativeTime(ticket.updatedAt, l10n)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (ticket.status != null) TicketStatusChip(status: ticket.status!, isSmall: true),
                        if (!ticket.isClosedFinal) SlaIndicator(slaStatus: ticket.slaStatus, compact: true),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
