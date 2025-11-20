import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/support/message_bubble.dart';
import 'package:hesabix_ui/widgets/support/ai_ticket_assistant.dart';

class TicketDetailsDialog extends StatefulWidget {
  final SupportTicket ticket;
  final bool isOperator;
  final VoidCallback? onTicketUpdated;

  const TicketDetailsDialog({
    super.key,
    required this.ticket,
    this.isOperator = false,
    this.onTicketUpdated,
  });

  @override
  State<TicketDetailsDialog> createState() => _TicketDetailsDialogState();
}

class _TicketDetailsDialogState extends State<TicketDetailsDialog> {
  late SupportTicket _ticket;
  List<SupportMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _messages = _ticket.messages ?? [];
    _loadMessages();
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
      final response = await supportService.searchTicketMessages(_ticket.id, queryInfo);
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.support_agent,
                    color: theme.primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ticketNumber(_ticket.id.toString()),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                        Text(
                          _ticket.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Messages Section (Main Focus) + AI Panel
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(
                builder: (context, constraints) {
                  final showSidePanel = widget.isOperator && constraints.maxWidth > 900;
                  final conversationColumn = Column(
                    children: [
                      if (!showSidePanel) _buildConversationInfo(l10n, theme),

                      // Messages List
                      Expanded(
                        child: _isLoading
                            ? const Center(
                                child: CircularProgressIndicator(),
                              )
                            : _messages.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline,
                                          size: 48,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          l10n.noMessagesFound,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Scrollbar(
                                    controller: _scrollController,
                                    thumbVisibility: true,
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.all(16),
                                      itemCount: _messages.length,
                                      itemBuilder: (context, index) {
                                        final message = _messages[index];
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: MessageBubble(
                                            message: message,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                      ),

                      if (!showSidePanel && widget.isOperator)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: AITicketAssistant(
                            ticketId: _ticket.id,
                            ticketContext: _ticket.description,
                            onReplySuggested: (suggestedReply) {
                              _messageController.text = suggestedReply;
                            },
                            onAutoReply: (replyText) {
                              _loadMessages();
                              widget.onTicketUpdated?.call();
                            },
                          ),
                        ),

                      // Message Input
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          border: Border(
                            top: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                decoration: InputDecoration(
                                  hintText: widget.isOperator
                                      ? l10n.writeYourResponse
                                      : l10n.writeYourMessage,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(25),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(25),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(25),
                                    borderSide: BorderSide(color: theme.primaryColor),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                keyboardType: TextInputType.multiline,
                                minLines: 1,
                                maxLines: 5,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              decoration: BoxDecoration(
                                color: theme.primaryColor,
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: IconButton(
                                onPressed: _isSending ? null : _sendMessage,
                                icon: _isSending
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.send,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );

                  if (!showSidePanel) {
                    return conversationColumn;
                  }

                  final sidePanelWidth = math.min(
                    360.0,
                    math.max(280.0, constraints.maxWidth * 0.28),
                  );

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: sidePanelWidth,
                        child: Scrollbar(
                          thumbVisibility: true,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
                          child: Column(
                            children: [
                              _buildConversationInfo(l10n, theme),
                              const SizedBox(height: 12),
                              AITicketAssistant(
                                ticketId: _ticket.id,
                                ticketContext: _ticket.description,
                                onReplySuggested: (suggestedReply) {
                                  _messageController.text = suggestedReply;
                                },
                                onAutoReply: (replyText) {
                                  _loadMessages();
                                  widget.onTicketUpdated?.call();
                                },
                              ),
                            ],
                          ),
                        ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: conversationColumn),
                    ],
                  );
                },
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
