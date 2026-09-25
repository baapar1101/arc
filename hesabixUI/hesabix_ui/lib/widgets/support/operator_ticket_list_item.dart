import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as date_utils;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/support_semantic_colors.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// Dense inbox row for operator ticket lists (Zendesk/Gmail-style, ~52–64px).
class OperatorTicketListItem extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isSelected;
  final VoidCallback? onTap;
  final CalendarController? calendarController;
  final bool? isChecked;
  final ValueChanged<bool?>? onToggleSelect;

  const OperatorTicketListItem({
    super.key,
    required this.row,
    this.isSelected = false,
    this.onTap,
    this.calendarController,
    this.isChecked,
    this.onToggleSelect,
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

  Color _statusColor(SupportStatus status, BuildContext context, ThemeData theme) {
    if (status.color != null) {
      try {
        return Color(int.parse(status.color!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    final semantics = SemanticColorResolver.of(context);
    switch (status.name.toLowerCase()) {
      case 'باز':
      case 'open':
        return semantics.info;
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

  Color _priorityColor(SupportPriority priority, BuildContext context, ThemeData theme) {
    if (priority.color != null) {
      try {
        return Color(int.parse(priority.color!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    final semantics = SemanticColorResolver.of(context);
    switch (priority.name.toLowerCase()) {
      case 'کم':
      case 'low':
        return semantics.positive;
      case 'متوسط':
      case 'medium':
        return semantics.warning;
      case 'بالا':
      case 'high':
      case 'فوری':
      case 'urgent':
        return semantics.negative;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = SupportSemanticColors.of(context);
    final ticket = _ticket;
    final id = row['id'];
    final title = '${row['title'] ?? ''}';
    final isUnread = row['is_unread_for_operator'] == true;
    final userMap = row['user'];
    final userName = userMap is Map
        ? SupportUser.fromJson(Map<String, dynamic>.from(userMap)).displayName
        : '';
    final slaStatus = slaStatusFromRow(row);
    final slaSide = slaRowBorderSide(context, slaStatus);
    final activityAt = ticket?.lastActivityAt ?? DateTime.now();
    final showCheckbox = onToggleSelect != null && isChecked != null;
    final sub = ticket?.supportSubscription ??
        (row['support_subscription'] is Map
            ? TicketSupportSubscription.fromJson(
                Map<String, dynamic>.from(row['support_subscription'] as Map),
              )
            : null);
    final planTooltip = () {
      if (sub == null) {
        return row['is_priority_subscriber'] == true ? 'مشترک اولویت‌دار' : null;
      }
      final parts = <String>[sub.planName, sub.statusLabel];
      if (sub.endsAt != null) {
        final isJalali = calendarController?.isJalali ?? true;
        parts.add(
          'تا ${date_utils.HesabixDateUtils.formatForDisplay(sub.endsAt!, isJalali)}',
        );
      }
      return parts.join(' · ');
    }();

    return Material(
      color: isSelected ? colors.selectedRowBg : null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52, maxHeight: 64),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.45)),
              left: slaSide ?? BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              if (showCheckbox) ...[
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: onToggleSelect,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        if (isUnread)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        else
                          const SizedBox(width: 9),
                        Text(
                          '#$id',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (sub != null || row['is_priority_subscriber'] == true) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: planTooltip ?? 'مشترک اولویت‌دار',
                            child: Icon(
                              Icons.workspace_premium_rounded,
                              size: 14,
                              color: sub?.isGrace == true
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.tertiary,
                            ),
                          ),
                        ],
                        if (sub != null && sub.planName.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 88),
                            child: Text(
                              sub.planName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.tertiary,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isUnread || isSelected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _relativeTime(activityAt, l10n),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (ticket?.status != null) ...[
                          _CompactStatus(status: ticket!.status!, color: _statusColor(ticket.status!, context, theme)),
                          const SizedBox(width: 6),
                        ],
                        if (ticket?.priority != null)
                          Tooltip(
                            message: ticket!.priority!.name,
                            child: Icon(
                              Icons.flag,
                              size: 13,
                              color: _priorityColor(ticket.priority!, context, theme),
                            ),
                          ),
                        if (ticket?.priority != null) const SizedBox(width: 4),
                        _CompactSlaIcon(slaStatus: slaStatus),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactStatus extends StatelessWidget {
  final SupportStatus status;
  final Color color;

  const _CompactStatus({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          status.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CompactSlaIcon extends StatelessWidget {
  final String slaStatus;

  const _CompactSlaIcon({required this.slaStatus});

  @override
  Widget build(BuildContext context) {
    if (slaStatus == 'ok') return const SizedBox.shrink();

    final colors = SupportSemanticColors.of(context);
    final (color, label, icon) = switch (slaStatus) {
      'breached' => (colors.slaBreached, 'نقض SLA', Icons.error_outline),
      'warning' => (colors.slaWarning, 'نزدیک SLA', Icons.schedule),
      _ => (colors.slaOk, 'در SLA', Icons.check_circle_outline),
    };

    return Tooltip(
      message: label,
      child: Icon(icon, size: 14, color: color),
    );
  }
}
