import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as date_utils;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/support_semantic_colors.dart';
import 'package:hesabix_ui/widgets/support/support_unread_badge.dart';
import 'package:hesabix_ui/widgets/support/ticket_status_chip.dart';

/// Compact row for user ticket list (mobile + desktop).
class UserTicketListItem extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback? onTap;
  final CalendarController? calendarController;
  final bool isSelected;
  final bool compact;

  const UserTicketListItem({
    super.key,
    required this.ticket,
    this.onTap,
    this.calendarController,
    this.isSelected = false,
    this.compact = false,
  });

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

  Color? _priorityColor(SupportPriority? priority) {
    if (priority?.color == null) return null;
    try {
      return Color(int.parse(priority!.color!.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = SupportSemanticColors.of(context);
    final isUnread = ticket.isUnreadForUser;
    final priorityColor = _priorityColor(ticket.priority);

    return Material(
      color: isSelected ? colors.selectedRowBg : theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 16,
            vertical: compact ? 9 : 12,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.45)),
              right: isSelected
                  ? BorderSide(color: theme.colorScheme.primary, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: compact ? _buildCompactRow(theme, l10n, colors, priorityColor, isUnread) : _buildFullRow(theme, l10n, colors, priorityColor, isUnread),
        ),
      ),
    );
  }

  Widget _buildCompactRow(
    ThemeData theme,
    AppLocalizations l10n,
    SupportSemanticColors colors,
    Color? priorityColor,
    bool isUnread,
  ) {
    return Row(
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isUnread || isSelected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  SupportUnreadBadge(show: isUnread),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  if (ticket.status != null)
                    TicketStatusChip(status: ticket.status!, isSmall: true),
                  const Spacer(),
                  Text(
                    _relativeTime(ticket.updatedAt, l10n),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFullRow(
    ThemeData theme,
    AppLocalizations l10n,
    SupportSemanticColors colors,
    Color? priorityColor,
    bool isUnread,
  ) {
    return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TicketAvatar(
                isUnread: isUnread,
                isClosed: ticket.isClosedFinal,
                theme: theme,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${ticket.id}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ticket.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: isUnread || isSelected ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        SupportUnreadBadge(show: isUnread),
                      ],
                    ),
                    if (ticket.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        ticket.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (ticket.status != null)
                          TicketStatusChip(status: ticket.status!, isSmall: true),
                        if (ticket.category != null)
                          _MetaChip(
                            icon: Icons.folder_outlined,
                            label: ticket.category!.name,
                            color: theme.colorScheme.secondary,
                          ),
                        if (ticket.priority != null && priorityColor != null)
                          _MetaChip(
                            icon: Icons.flag_rounded,
                            label: ticket.priority!.name,
                            color: priorityColor,
                          ),
                        if (!ticket.isClosedFinal)
                          SlaIndicator(slaStatus: ticket.slaStatus, compact: true),
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
                    _relativeTime(ticket.updatedAt, l10n),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ],
    );
  }
}

class _TicketAvatar extends StatelessWidget {
  final bool isUnread;
  final bool isClosed;
  final ThemeData theme;

  const _TicketAvatar({
    required this.isUnread,
    required this.isClosed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final Color bg;
    final Color fg;
    final IconData icon;

    if (isClosed) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.check_circle_outline_rounded;
    } else if (isUnread) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
      icon = Icons.mark_chat_unread_rounded;
    } else {
      bg = scheme.secondaryContainer.withValues(alpha: 0.65);
      fg = scheme.onSecondaryContainer;
      icon = Icons.chat_bubble_outline_rounded;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
