import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as date_utils;
import 'package:hesabix_ui/models/support_models.dart';

class TicketEventTimeline extends StatelessWidget {
  final List<SupportTicketEvent> events;
  final CalendarController? calendarController;
  final bool initiallyExpanded;

  const TicketEventTimeline({
    super.key,
    required this.events,
    this.calendarController,
    this.initiallyExpanded = false,
  });

  String _labelFor(SupportTicketEvent event) {
    switch (event.eventType) {
      case 'status_changed':
        return 'تغییر وضعیت';
      case 'priority_changed':
        return 'تغییر اولویت';
      case 'assigned':
        return 'تخصیص اپراتور';
      case 'closed':
        return 'بسته شد';
      case 'reopened':
        return 'بازگشایی شد';
      default:
        return event.eventType;
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'assigned':
        return Icons.person_add_alt_1;
      case 'closed':
        return Icons.lock;
      case 'reopened':
        return Icons.lock_open;
      case 'priority_changed':
        return Icons.flag;
      default:
        return Icons.history;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isJalali = calendarController?.isJalali ?? true;

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: Icon(Icons.timeline, color: theme.colorScheme.primary),
      title: Text('تاریخچه رویدادها (${events.length})'),
      children: events
          .map(
            (event) => ListTile(
              dense: true,
              leading: Icon(_iconFor(event.eventType), size: 18),
              title: Text(_labelFor(event)),
              subtitle: Text(
                date_utils.HesabixDateUtils.formatDateTime(
                  event.createdAt.isUtc ? event.createdAt.toLocal() : event.createdAt,
                  isJalali,
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
          )
          .toList(),
    );
  }
}
