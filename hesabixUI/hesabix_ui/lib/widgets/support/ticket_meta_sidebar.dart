import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as date_utils;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/ticket_event_timeline.dart';
import 'package:hesabix_ui/widgets/support/ticket_status_chip.dart';
import 'package:hesabix_ui/widgets/support/priority_indicator.dart';

/// Operator sidebar: customer info, SLA, properties, history.
class TicketMetaSidebar extends StatelessWidget {
  final SupportTicket ticket;
  final List<SupportTicketEvent> events;
  final List<Map<String, dynamic>> userTicketHistory;
  final CalendarController? calendarController;
  final bool isOperator;

  const TicketMetaSidebar({
    super.key,
    required this.ticket,
    this.events = const [],
    this.userTicketHistory = const [],
    this.calendarController,
    this.isOperator = true,
  });

  String _fmt(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final isJalali = calendarController?.isJalali ?? true;
    return date_utils.HesabixDateUtils.formatDateTime(local, isJalali);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (isOperator && ticket.user != null) ...[
          _SectionTitle(icon: Icons.person_outline, title: 'مشتری'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer, size: 20),
            ),
            title: Text(ticket.user!.displayName, style: theme.textTheme.titleSmall),
            subtitle: ticket.user!.email != null ? Text(ticket.user!.email!) : null,
          ),
          const SizedBox(height: 8),
        ],
        _SectionTitle(icon: Icons.tune, title: 'مشخصات'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (ticket.status != null) TicketStatusChip(status: ticket.status!, isSmall: true),
            if (ticket.priority != null) PriorityIndicator(priority: ticket.priority!, isSmall: true),
            SlaIndicator(slaStatus: ticket.slaStatus),
          ],
        ),
        const SizedBox(height: 12),
        _MetaRow(label: l10n.ticketCreatedAt, value: _fmt(ticket.createdAt)),
        _MetaRow(label: l10n.ticketUpdatedAt, value: _fmt(ticket.updatedAt)),
        if (ticket.assignedOperator != null)
          _MetaRow(label: l10n.assignedTo, value: ticket.assignedOperator!.displayName),
        if (isOperator && userTicketHistory.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle(icon: Icons.history, title: 'تیکت‌های قبلی'),
          ...userTicketHistory.where((t) => t['id'] != ticket.id).map(
                (t) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('#${t['id']} — ${t['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${t['status'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_left, size: 18),
                  onTap: () {
                    final id = t['id'];
                    if (id is int) context.push('/user/profile/operator?ticket=$id');
                  },
                ),
              ),
        ],
        if (events.isNotEmpty) ...[
          const SizedBox(height: 8),
          TicketEventTimeline(
            events: events,
            calendarController: calendarController,
            initiallyExpanded: true,
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
