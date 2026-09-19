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
<<<<<<< HEAD
=======
  State<TicketDetailsDialog> createState() => _TicketDetailsDialogState();
}

class _TicketDetailsDialogState extends State<TicketDetailsDialog> {
  late SupportTicket _ticket;
  List<SupportMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ResponseTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _messages = _ticket.messages ?? [];
    _loadMessages();
    if (widget.isOperator) {
      _loadTemplates();
    }
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await ResponseTemplatesService.getTemplates();
      if (mounted) {
        setState(() {
          _templates = templates;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _showTemplatesDialog() async {
    if (!mounted) return;
    
    final selectedTemplate = await showDialog<ResponseTemplate>(
      context: context,
      builder: (context) => _TemplatesDialog(templates: _templates),
    );

    if (selectedTemplate != null) {
      // Replace variables in template
      final variables = {
        'user_name': _ticket.user?.displayName ?? 'کاربر',
        'ticket_id': _ticket.id.toString(),
        'ticket_title': _ticket.title,
      };
      
      final formattedContent = selectedTemplate.format(variables);
      _messageController.text = formattedContent;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showOverlayMessage(String message, Color backgroundColor, Duration duration) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  backgroundColor == Colors.green ? Icons.check_circle : Icons.error,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // Remove overlay after duration
    Future.delayed(duration, () {
      overlayEntry.remove();
    });
  }

  Future<void> _loadMessages() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final supportService = SupportService(ApiClient());
      final queryInfo = {
        'take': 1000, // Get all messages
        'skip': 0,
        'sort_by': 'created_at',
        'sort_desc': false,
      };
      
      // Use appropriate endpoint based on whether user is operator or not
      final response = widget.isOperator
          ? await supportService.searchOperatorTicketMessages(_ticket.id, queryInfo)
          : await supportService.searchTicketMessages(_ticket.id, queryInfo);
      final messages = response.items;
      
      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        // Show error message using Overlay to appear above dialog
        _showOverlayMessage(
          l10n.ticketLoadingError,
          Colors.red,
          const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final supportService = SupportService(ApiClient());
      final request = CreateMessageRequest(content: content);
      
      SupportMessage message;
      if (widget.isOperator) {
        message = await supportService.sendOperatorMessage(_ticket.id, request);
        // Refresh ticket to get updated last_updated time
        final updatedTicket = await supportService.getOperatorTicket(_ticket.id);
        setState(() {
          _ticket = updatedTicket;
        });
      } else {
        message = await supportService.sendMessage(_ticket.id, request);
        // Refresh ticket to get updated last_updated time
        final updatedTicket = await supportService.getTicket(_ticket.id);
        setState(() {
          _ticket = updatedTicket;
        });
      }

      setState(() {
        _messages.add(message);
        _messageController.clear();
        _isSending = false;
      });

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        // Show success message using Overlay to appear above dialog
        _showOverlayMessage(
          l10n.messageSentSuccessfully,
          Colors.green,
          const Duration(seconds: 2),
        );
      }

      // Notify parent about ticket update
      widget.onTicketUpdated?.call();
    } catch (e) {
      setState(() {
        _isSending = false;
      });

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        // Show error message using Overlay to appear above dialog
        _showOverlayMessage(
          l10n.errorSendingMessage,
          Colors.red,
          const Duration(seconds: 3),
        );
      }
    }
  }


  Widget _buildInfoChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTicketDate(DateTime dateTime) {
    final localDateTime = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    final isJalali = widget.calendarController?.isJalali ?? true;
    return date_utils.MarkStreetDateUtils.formatDateTime(localDateTime, isJalali);
  }

  Widget _buildConversationInfo(AppLocalizations l10n, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                color: theme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.conversation,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
              const Spacer(),
              Text(
                l10n.messageCount(_messages.length.toString()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          if (widget.isOperator && (_ticket.user != null || _ticket.assignedOperator != null)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_ticket.user != null)
                  _buildInfoChip(
                    l10n.createdBy,
                    _ticket.user!.displayName,
                    Icons.person,
                  ),
                if (_ticket.assignedOperator != null)
                  _buildInfoChip(
                    l10n.assignedTo,
                    _ticket.assignedOperator!.displayName,
                    Icons.person_outline,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
>>>>>>> github/Huma
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
