import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/support/message_bubble.dart';
import 'package:hesabix_ui/widgets/support/ticket_status_chip.dart';
import 'package:hesabix_ui/widgets/support/priority_indicator.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';

class TicketDetailPage extends StatefulWidget {
  final SupportTicket ticket;

  const TicketDetailPage({
    super.key,
    required this.ticket,
  });

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  final _messageController = TextEditingController();
  final SupportService _supportService = SupportService(ApiClient());
  
  SupportTicket? _ticket;
  List<SupportMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _loadTicketDetails();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadTicketDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ticket = await _supportService.getTicket(_ticket!.id);
      final messagesResponse = await _supportService.searchTicketMessages(
        _ticket!.id,
        {
          'search': '',
          'search_fields': ['content'],
          'filters': [],
          'sort_by': 'created_at',
          'sort_desc': false,
          'skip': 0,
          'take': 100,
        },
      );
      
      setState(() {
        _ticket = ticket;
        _messages = messagesResponse.items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final request = CreateMessageRequest(content: content);
      final message = await _supportService.sendMessage(_ticket!.id, request);
      
      setState(() {
        _messages.add(message);
        _messageController.clear();
        _isSending = false;
      });
    } catch (e) {
      setState(() {
        _isSending = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ارسال پیام: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('تیکت #${_ticket?.id ?? ''}'),
        actions: [
          IconButton(
            onPressed: _loadTicketDetails,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'خطا در بارگذاری تیکت',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTicketDetails,
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    if (_ticket == null) {
      return const Center(
        child: Text('تیکت یافت نشد'),
      );
    }

    return Column(
      children: [
        // Ticket header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.2),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _ticket!.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TicketStatusChip(status: _ticket!.status!),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _ticket!.description,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_ticket!.category != null) ...[
                    _buildInfoChip(
                      context,
                      Icons.category,
                      _ticket!.category!.name,
                      theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_ticket!.priority != null) ...[
                    PriorityIndicator(
                      priority: _ticket!.priority!,
                      isSmall: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  Text(
                    _formatDate(_ticket!.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Messages
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: Colors.grey.withOpacity(0.6),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'هیچ پیامی یافت نشد',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return MessageBubble(
                      message: message,
                      isCurrentUser: message.isFromUser,
                    );
                  },
                ),
        ),
        
        // Message input
        if (!_ticket!.isClosed && !_ticket!.isResolved)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'پیام خود را بنویسید...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: 3,
                    minLines: 1,
                    enabled: !_isSending,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} روز پیش';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ساعت پیش';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} دقیقه پیش';
    } else {
      return 'همین الان';
    }
  }
}
