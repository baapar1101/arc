import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/support/ticket_status_chip.dart';
import 'package:hesabix_ui/widgets/support/priority_indicator.dart';

class TicketActionBar extends StatelessWidget {
  final SupportTicket ticket;
  final List<SupportStatus> statuses;
  final List<SupportPriority> priorities;
  final List<SupportOperatorInfo> operators;
  final bool isBusy;
  final ValueChanged<int?>? onStatusChanged;
  final ValueChanged<int?>? onPriorityChanged;
  final ValueChanged<int?>? onAssignChanged;

  const TicketActionBar({
    super.key,
    required this.ticket,
    required this.statuses,
    required this.priorities,
    required this.operators,
    this.isBusy = false,
    this.onStatusChanged,
    this.onPriorityChanged,
    this.onAssignChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (ticket.status != null) TicketStatusChip(status: ticket.status!),
          if (ticket.priority != null) PriorityIndicator(priority: ticket.priority!),
          _buildDropdown<int>(
            context,
            label: 'وضعیت',
            value: ticket.statusId,
            items: statuses
                .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                .toList(),
            onChanged: isBusy ? null : onStatusChanged,
          ),
          _buildDropdown<int>(
            context,
            label: 'اولویت',
            value: ticket.priorityId,
            items: priorities
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                .toList(),
            onChanged: isBusy ? null : onPriorityChanged,
          ),
          _buildDropdown<int?>(
            context,
            label: 'اپراتور',
            value: ticket.assignedOperatorId,
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('بدون تخصیص')),
              ...operators.map(
                (op) => DropdownMenuItem<int?>(
                  value: op.id,
                  child: Text(op.displayName),
                ),
              ),
            ],
            onChanged: isBusy ? null : onAssignChanged,
          ),
          if (isBusy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>(
    BuildContext context, {
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return SizedBox(
      width: 160,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
