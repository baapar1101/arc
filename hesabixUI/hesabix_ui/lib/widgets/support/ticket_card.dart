import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'ticket_status_chip.dart';
import 'priority_indicator.dart';

class TicketCard extends StatelessWidget {
  final SupportTicket ticket;
  final CalendarController? calendarController;
  final VoidCallback? onTap;
  final bool showUserInfo;

  const TicketCard({
    super.key,
    required this.ticket,
    this.calendarController,
    this.onTap,
    this.showUserInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title and status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TicketStatusChip(status: ticket.status!),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Description
                Text(
                  ticket.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                
                const SizedBox(height: 16),
                // Tags and metadata row
                Row(
                  children: [
                    if (ticket.category != null) ...[
                      _buildInfoChip(
                        context,
                        Icons.category_outlined,
                        ticket.category!.name,
                        theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (ticket.priority != null) ...[
                      PriorityIndicator(
                        priority: ticket.priority!,
                        isSmall: true,
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    _buildTimeChip(context, ticket.createdAt),
                  ],
                ),
                
                if (showUserInfo && ticket.user != null) ...[
                  const SizedBox(height: 12),
                  _buildUserInfo(context, ticket),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeChip(BuildContext context, DateTime dateTime) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
          ),
          const SizedBox(width: 4),
          Text(
            _formatDate(dateTime, l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfo(BuildContext context, SupportTicket ticket) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            child: Icon(
              Icons.person,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.createdBy,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ticket.user!.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (ticket.assignedOperator != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.support_agent,
                    size: 12,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ticket.assignedOperator!.displayName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dateTime, AppLocalizations l10n) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    // If the difference is negative (future time), show just now
    if (difference.isNegative) {
      return l10n.justNow;
    }

    if (difference.inDays > 0) {
      return l10n.daysAgo(difference.inDays.toString());
    } else if (difference.inHours > 0) {
      return l10n.hoursAgo(difference.inHours.toString());
    } else if (difference.inMinutes > 0) {
      return l10n.minutesAgo(difference.inMinutes.toString());
    } else if (difference.inSeconds > 10) {
      return l10n.justNow;
    } else {
      return l10n.justNow;
    }
  }
}
