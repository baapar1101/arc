import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/support/ticket_detail_view.dart';

export 'ticket_detail_view.dart' show TicketDetailView, TicketDetailDisplayMode;

/// Shell wrappers for [TicketDetailView] (dialog / page / embedded).
class TicketDetailsDialog extends StatelessWidget {
  final SupportTicket ticket;
  final bool isOperator;
  final VoidCallback? onTicketUpdated;
  final CalendarController? calendarController;
  final TicketDetailDisplayMode displayMode;
  final VoidCallback? onRequestCsat;

  const TicketDetailsDialog({
    super.key,
    required this.ticket,
    this.isOperator = false,
    this.onTicketUpdated,
    this.calendarController,
    this.displayMode = TicketDetailDisplayMode.dialog,
    this.onRequestCsat,
  });

  @override
  Widget build(BuildContext context) {
    final view = TicketDetailView(
      key: key,
      ticket: ticket,
      isOperator: isOperator,
      onTicketUpdated: onTicketUpdated,
      calendarController: calendarController,
      displayMode: displayMode,
      onRequestCsat: onRequestCsat,
    );

    switch (displayMode) {
      case TicketDetailDisplayMode.page:
      case TicketDetailDisplayMode.embedded:
        return view;
      case TicketDetailDisplayMode.dialog:
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: view,
        );
    }
  }
}
