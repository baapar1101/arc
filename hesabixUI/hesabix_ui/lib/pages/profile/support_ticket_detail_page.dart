import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/support/ticket_csat_dialog.dart';
import 'package:hesabix_ui/widgets/support/ticket_details_dialog.dart';

/// صفحه جزئیات تیکت (deep link و navigation مستقیم)
class SupportTicketDetailPage extends StatefulWidget {
  final int ticketId;
  final CalendarController? calendarController;
  final bool isOperator;

  const SupportTicketDetailPage({
    super.key,
    required this.ticketId,
    this.calendarController,
    this.isOperator = false,
  });

  @override
  State<SupportTicketDetailPage> createState() => _SupportTicketDetailPageState();
}

class _SupportTicketDetailPageState extends State<SupportTicketDetailPage> {
  final SupportService _supportService = SupportService(ApiClient());
  SupportTicket? _ticket;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  Future<void> _loadTicket() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ticket = widget.isOperator
          ? await _supportService.getOperatorTicket(widget.ticketId)
          : await _supportService.getTicket(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('تیکت #${widget.ticketId}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(
              widget.isOperator ? '/user/profile/operator' : '/user/profile/support',
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(
                  widget.isOperator ? '/user/profile/operator' : '/user/profile/support',
                ),
                child: Text(widget.isOperator ? 'بازگشت به صندوق ورودی' : 'بازگشت به پشتیبانی'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: TicketDetailsDialog(
        key: ValueKey(_ticket!.id),
        ticket: _ticket!,
        isOperator: widget.isOperator,
        calendarController: widget.calendarController,
        displayMode: TicketDetailDisplayMode.page,
        onTicketUpdated: () async {
          try {
            final ticket = widget.isOperator
                ? await _supportService.getOperatorTicket(widget.ticketId)
                : await _supportService.getTicket(widget.ticketId);
            if (mounted) setState(() => _ticket = ticket);
          } catch (_) {}
        },
        onRequestCsat: widget.isOperator ? null : () => _maybeShowCsat(),
      ),
    );
  }

  Future<void> _maybeShowCsat() async {
    final ok = await TicketCsatDialog.show(context, widget.ticketId);
    if (ok == true && mounted) _loadTicket();
  }
}
