import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/support_models.dart';

class TicketActionBar extends StatelessWidget {
  final SupportTicket ticket;
  final List<SupportStatus> statuses;
  final List<SupportPriority> priorities;
  final List<SupportOperatorInfo> operators;
  final bool isBusy;
  final bool compact;
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
    this.compact = false,
    this.onStatusChanged,
    this.onPriorityChanged,
    this.onAssignChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldWidth = compact ? 128.0 : 168.0;
    final fields = [
      _field(context, width: fieldWidth, label: 'وضعیت', child: DropdownButton<int>(
        value: ticket.statusId,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: statuses.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: isBusy ? null : onStatusChanged,
      )),
      _field(context, width: fieldWidth, label: 'اولویت', child: DropdownButton<int>(
        value: ticket.priorityId,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: priorities.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: isBusy ? null : onPriorityChanged,
      )),
      _field(context, width: fieldWidth, label: 'اپراتور', child: DropdownButton<int?>(
        value: ticket.assignedOperatorId,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('بدون تخصیص', overflow: TextOverflow.ellipsis)),
          ...operators.map((op) => DropdownMenuItem<int?>(value: op.id, child: Text(op.displayName, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: isBusy ? null : onAssignChanged,
      )),
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: compact
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...fields.map((f) => Padding(padding: const EdgeInsets.only(left: 6), child: f)),
                  if (isBusy)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            )
          : Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...fields,
                if (isBusy)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
    );
  }

  Widget _field(BuildContext context, {required double width, required String label, required Widget child}) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: theme.colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: child,
      ),
    );
  }
}
