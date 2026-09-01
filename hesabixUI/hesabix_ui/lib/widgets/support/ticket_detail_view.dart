import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/models/response_template.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/services/response_templates_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as date_utils;
import 'package:hesabix_ui/widgets/support/message_bubble.dart';
import 'package:hesabix_ui/widgets/support/ai_ticket_assistant.dart';
import 'package:hesabix_ui/widgets/support/ticket_action_bar.dart';
import 'package:hesabix_ui/widgets/support/ticket_attachment_picker.dart';
import 'package:hesabix_ui/widgets/support/ticket_event_timeline.dart';
import 'package:hesabix_ui/services/support_realtime_service.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/ticket_composer.dart';
import 'package:hesabix_ui/widgets/support/ticket_pinned_request.dart';
import 'package:hesabix_ui/widgets/support/ticket_meta_sidebar.dart';
import 'package:hesabix_ui/widgets/support/ticket_status_chip.dart';
import 'package:hesabix_ui/utils/support_ticket_clipboard.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

enum TicketDetailDisplayMode { dialog, page, embedded }

class TicketDetailView extends StatefulWidget {
  final SupportTicket ticket;
  final bool isOperator;
  final VoidCallback? onTicketUpdated;
  final CalendarController? calendarController;
  final TicketDetailDisplayMode displayMode;
  final VoidCallback? onRequestCsat;

  const TicketDetailView({
    super.key,
    required this.ticket,
    this.isOperator = false,
    this.onTicketUpdated,
    this.calendarController,
    this.displayMode = TicketDetailDisplayMode.dialog,
    this.onRequestCsat,
  });

  @override
  State<TicketDetailView> createState() => _TicketDetailViewState();
}

class _TicketDetailViewState extends State<TicketDetailView> {
  late SupportTicket _ticket;
  List<SupportMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ResponseTemplate> _templates = [];
  TicketComposeMode _composeMode = TicketComposeMode.publicReply;
  bool _isActionBusy = false;
  List<SupportStatus> _statuses = [];
  List<SupportPriority> _priorities = [];
  List<SupportOperatorInfo> _operators = [];
  List<SupportAttachment> _pendingAttachments = [];
  bool _isUploadingAttachment = false;
  List<SupportTicketEvent> _events = [];
  SupportRealtimeService? _realtime;
  List<Map<String, dynamic>> _userTicketHistory = [];

  bool get _canUserReply => !widget.isOperator && !_ticket.isClosedFinal;
  bool get _canComposeMessage => widget.isOperator || _canUserReply;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _messages = _ticket.messages ?? [];
    _loadMessages();
    _loadEvents();
    if (widget.isOperator) {
      _loadTemplates();
      _loadOperatorMetadata();
      _loadUserTicketHistory();
    }
    _connectRealtime();
    _markTicketRead();
  }

  Future<void> _markTicketRead() async {
    try {
      final svc = SupportService(ApiClient());
      if (widget.isOperator) {
        await svc.markOperatorTicketRead(_ticket.id);
      } else {
        await svc.markUserTicketRead(_ticket.id);
      }
    } catch (_) {}
  }

  Future<void> _loadUserTicketHistory() async {
    try {
      final items = await SupportService(ApiClient()).getOperatorUserTicketHistory(
        _ticket.userId,
        take: 5,
      );
      if (mounted) setState(() => _userTicketHistory = items);
    } catch (_) {}
  }

  void _connectRealtime() {
    final apiKey = ApiClient.getAuthStore()?.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _realtime = createSupportRealtimeService();
    _realtime!.connect(
      apiKey: apiKey,
      onEvent: (event) {
        if ('${event['type']}' != 'support') return;
        if (event['ticket_id'] != _ticket.id) return;
        if (!mounted) return;
        if (event['event'] == 'message.created') {
          _loadMessages(silent: true);
        } else {
          _reloadTicket();
        }
      },
    );
    _realtime!.subscribeTicket(_ticket.id);
  }

  Future<void> _reloadTicket() async {
    try {
      final supportService = SupportService(ApiClient());
      final ticket = widget.isOperator
          ? await supportService.getOperatorTicket(_ticket.id)
          : await supportService.getTicket(_ticket.id);
      if (!mounted) return;
      setState(() => _ticket = ticket);
      widget.onTicketUpdated?.call();
    } catch (_) {}
  }

  Future<void> _loadOperatorMetadata() async {
    try {
      final supportService = SupportService(ApiClient());
      final results = await Future.wait([
        supportService.getStatuses(),
        supportService.getPriorities(),
        supportService.getSupportOperators(),
      ]);
      if (!mounted) return;
      setState(() {
        _statuses = results[0] as List<SupportStatus>;
        _priorities = results[1] as List<SupportPriority>;
        _operators = results[2] as List<SupportOperatorInfo>;
      });
    } catch (_) {}
  }

  Future<void> _loadEvents() async {
    try {
      final events = await SupportService(ApiClient()).getTicketEvents(
        _ticket.id,
        isOperator: widget.isOperator,
      );
      if (mounted) setState(() => _events = events);
    } catch (_) {}
  }

  Future<void> _pickAttachment() async {
    final file = await TicketAttachmentPicker.pickFile();
    if (file == null || file.bytes == null) return;
    setState(() => _isUploadingAttachment = true);
    try {
      final attachment = await SupportService(ApiClient()).uploadAttachment(
        _ticket.id,
        file.bytes!,
        file.name,
        isOperator: widget.isOperator,
      );
      if (mounted) {
        setState(() => _pendingAttachments = [..._pendingAttachments, attachment]);
      }
    } catch (e) {
      if (mounted) {
        _showOverlayMessage('خطا در آپلود فایل', SemanticColorResolver.negative(context), const Duration(seconds: 3));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  Future<void> _closeTicket() async {
    setState(() => _isActionBusy = true);
    try {
      final updated = await SupportService(ApiClient()).closeTicket(_ticket.id);
      if (!mounted) return;
      setState(() => _ticket = updated);
      _showOverlayMessage('تیکت بسته شد', SemanticColorResolver.positive(context), const Duration(seconds: 2), isSuccess: true);
      widget.onTicketUpdated?.call();
      if (!widget.isOperator && updated.csatSubmittedAt == null) {
        widget.onRequestCsat?.call();
      }
    } catch (e) {
      if (mounted) {
        _showOverlayMessage('خطا در بستن تیکت', SemanticColorResolver.negative(context), const Duration(seconds: 3));
      }
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _reopenTicket() async {
    setState(() => _isActionBusy = true);
    try {
      final updated = await SupportService(ApiClient()).reopenTicket(_ticket.id);
      if (!mounted) return;
      setState(() => _ticket = updated);
      _showOverlayMessage('تیکت بازگشایی شد', SemanticColorResolver.positive(context), const Duration(seconds: 2), isSuccess: true);
      widget.onTicketUpdated?.call();
    } catch (e) {
      if (mounted) {
        _showOverlayMessage('خطا در بازگشایی تیکت', SemanticColorResolver.negative(context), const Duration(seconds: 3));
      }
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _handleStatusChange(int statusId) async {
    if (statusId == _ticket.statusId) return;
    setState(() => _isActionBusy = true);
    try {
      final updated = await SupportService(ApiClient()).updateTicketStatus(
        _ticket.id,
        UpdateStatusRequest(statusId: statusId),
      );
      if (!mounted) return;
      setState(() => _ticket = updated);
      widget.onTicketUpdated?.call();
    } catch (e) {
      if (mounted) {
        _showOverlayMessage('خطا در تغییر وضعیت', SemanticColorResolver.negative(context), const Duration(seconds: 3));
      }
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _handlePriorityChange(int priorityId) async {
    if (priorityId == _ticket.priorityId) return;
    setState(() => _isActionBusy = true);
    try {
      final updated = await SupportService(ApiClient()).updateTicketPriority(
        _ticket.id,
        UpdatePriorityRequest(priorityId: priorityId),
      );
      if (!mounted) return;
      setState(() => _ticket = updated);
      widget.onTicketUpdated?.call();
    } catch (e) {
      if (mounted) {
        _showOverlayMessage('خطا در تغییر اولویت', SemanticColorResolver.negative(context), const Duration(seconds: 3));
      }
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _handleAssignChange(int? operatorId) async {
    if (operatorId == null || operatorId == _ticket.assignedOperatorId) return;
    setState(() => _isActionBusy = true);
    try {
      final updated = await SupportService(ApiClient()).assignTicket(
        _ticket.id,
        AssignTicketRequest(operatorId: operatorId),
      );
      if (!mounted) return;
      setState(() => _ticket = updated);
      widget.onTicketUpdated?.call();
    } catch (e) {
      if (mounted) {
        _showOverlayMessage('خطا در تخصیص تیکت', SemanticColorResolver.negative(context), const Duration(seconds: 3));
      }
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
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
    _realtime?.unsubscribeTicket(_ticket.id);
    _realtime?.disconnect();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showOverlayMessage(String message, Color backgroundColor, Duration duration, {bool isSuccess = false}) {
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
                  isSuccess ? Icons.check_circle : Icons.error,
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

  Future<void> _loadMessages({bool silent = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (!silent) {
        // Keep existing messages visible during silent refresh.
      }
    });

    try {
      final supportService = SupportService(ApiClient());
      final messages = await supportService.getAllTicketMessages(
        _ticket.id,
        isOperator: widget.isOperator,
      );
      
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      // Scroll to bottom only on first load or when near bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        final nearBottom = pos.maxScrollExtent - pos.pixels < 120;
        if (!silent || nearBottom || _messages.length <= 3) {
          _scrollController.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      
      if (mounted && !silent) {
        final l10n = AppLocalizations.of(context);
        _showOverlayMessage(
          l10n.ticketLoadingError,
          SemanticColorResolver.negative(context),
          const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty && _pendingAttachments.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final supportService = SupportService(ApiClient());
      final request = CreateMessageRequest(
        content: content,
        isInternal: widget.isOperator && _composeMode == TicketComposeMode.internalNote,
        attachmentIds: _pendingAttachments.map((a) => a.id).toList(),
      );
      
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
        _composeMode = TicketComposeMode.publicReply;
        _pendingAttachments = [];
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
          SemanticColorResolver.positive(context),
          const Duration(seconds: 2),
          isSuccess: true,
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
          SemanticColorResolver.negative(context),
          const Duration(seconds: 3),
        );
      }
    }
  }


  Widget _buildCompactOperatorHeader(ThemeData theme, AppLocalizations l10n) {
    final showBack = widget.displayMode == TicketDetailDisplayMode.page;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6))),
        ),
        child: Row(
          children: [
            if (showBack)
              IconButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/user/profile/operator');
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                tooltip: 'بازگشت به صندوق',
                visualDensity: VisualDensity.compact,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _ticket.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        l10n.ticketNumber(_ticket.id.toString()),
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      SlaIndicator(slaStatus: _ticket.slaStatus, compact: true),
                    ],
                  ),
                ],
              ),
            ),
            if (_ticket.status != null) TicketStatusChip(status: _ticket.status!, isSmall: true),
            _buildCopyTicketButton(l10n, compact: true),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbeddedMetaPanel(ThemeData theme) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        initiallyExpanded: false,
        leading: Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
        title: Text('اطلاعات تیکت', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        children: [
          TicketMetaSidebar(
            ticket: _ticket,
            events: _events,
            userTicketHistory: _userTicketHistory,
            calendarController: widget.calendarController,
            isOperator: widget.isOperator,
          ),
        ],
      ),
    );
  }

  Widget _buildComposer({bool compact = false}) {
    return TicketComposer(
      messageController: _messageController,
      isOperator: widget.isOperator,
      canCompose: _canComposeMessage,
      isSending: _isSending,
      isUploadingAttachment: _isUploadingAttachment,
      mode: _composeMode,
      pendingAttachments: _pendingAttachments,
      templates: _templates,
      compact: compact,
      onModeChanged: (m) => setState(() => _composeMode = m),
      onSend: _sendMessage,
      onPickAttachment: _pickAttachment,
      onRemoveAttachment: (id) => setState(
        () => _pendingAttachments = _pendingAttachments.where((a) => a.id != id).toList(),
      ),
      onShowTemplates: widget.isOperator && _templates.isNotEmpty ? _showTemplatesDialog : null,
      onShowAiAssistant: widget.isOperator ? _showAiAssistantSheet : null,
      onApplyTemplate: (template) {
        final variables = {
          'user_name': _ticket.user?.displayName ?? 'کاربر',
          'ticket_id': _ticket.id.toString(),
          'ticket_title': _ticket.title,
        };
        _messageController.text = template.format(variables);
      },
    );
  }

  Future<void> _showAiAssistantSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: AITicketAssistant(
                ticketId: _ticket.id,
                ticketContext: _ticket.description,
                onReplySuggested: (suggestedReply) {
                  _messageController.text = suggestedReply;
                  Navigator.pop(ctx);
                },
                onAutoReply: (replyText) {
                  _loadMessages(silent: true);
                  widget.onTicketUpdated?.call();
                  Navigator.pop(ctx);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  int _listItemCount({
    required bool showSidePanel,
    required bool compactUser,
    required bool showMetaInThread,
  }) {
    var count = 1 + _messages.length;
    if (!showSidePanel && !compactUser) count += 1;
    if (showMetaInThread) count += 1;
    if (_messages.isEmpty) count += 1;
    return count;
  }

  Widget _buildListItem(
    BuildContext context,
    int index,
    bool showSidePanel,
    AppLocalizations l10n,
    ThemeData theme, {
    bool compactUser = false,
    bool showMetaInThread = false,
  }) {
    var cursor = 0;

    if (showMetaInThread) {
      if (index == cursor) return _buildEmbeddedMetaPanel(theme);
      cursor++;
    }

    if (!showSidePanel && !compactUser) {
      if (index == cursor) return _buildConversationInfo(l10n, theme);
      cursor++;
    }

    if (index == cursor) {
      return TicketPinnedRequest(
        ticket: _ticket,
        isOperator: widget.isOperator,
        initiallyExpanded: !widget.isOperator,
      );
    }
    cursor++;

    if (_messages.isEmpty) {
      if (index == cursor) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  l10n.noMessagesFound,
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      }
      cursor++;
    }

    final messageStart = cursor;
    if (index >= messageStart && index < messageStart + _messages.length) {
      final message = _messages[index - messageStart];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: MessageBubble(
          message: message,
          calendarController: widget.calendarController,
          isOperator: widget.isOperator,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildInfoChip(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _formatTicketDate(DateTime dateTime) {
    final localDateTime = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    final isJalali = widget.calendarController?.isJalali ?? true;
    return date_utils.HesabixDateUtils.formatDateTime(localDateTime, isJalali);
  }

  String _formatClipboardDateTime(DateTime dateTime) {
    final localDateTime = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    final isJalali = widget.calendarController?.isJalali ?? true;
    return date_utils.HesabixDateUtils.formatDateTime(localDateTime, isJalali);
  }

  Future<void> _copyFullTicketText(BuildContext context) async {
    final text = formatSupportTicketForClipboard(
      ticket: _ticket,
      messages: _messages,
      includeInternalNotes: widget.isOperator,
      formatDateTime: _formatClipboardDateTime,
    );
    await copySupportTextToClipboard(context, text);
  }

  Widget _buildCopyTicketButton(AppLocalizations l10n, {bool compact = false}) {
    return IconButton(
      icon: Icon(compact ? Icons.copy_outlined : Icons.copy_all_outlined, size: compact ? 18 : 22),
      tooltip: l10n.supportTicketCopyAll,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      onPressed: () => _copyFullTicketText(context),
    );
  }

  Widget _buildCompactUserHeader(ThemeData theme, AppLocalizations l10n, bool showBack) {
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6))),
        ),
        child: Row(
          children: [
            if (showBack)
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'بازگشت',
              ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ticket.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    l10n.ticketNumber(_ticket.id.toString()),
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (_ticket.status != null) TicketStatusChip(status: _ticket.status!, isSmall: true),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'close') _closeTicket();
                if (value == 'reopen') _reopenTicket();
              },
              itemBuilder: (context) => [
                if (!_ticket.isClosedFinal)
                  const PopupMenuItem(value: 'close', child: Text('بستن تیکت')),
                if (_ticket.isClosedFinal)
                  const PopupMenuItem(value: 'reopen', child: Text('بازگشایی تیکت')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationInfo(AppLocalizations l10n, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.isOperator) _buildCopyTicketButton(l10n, compact: true),
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
            if (_userTicketHistory.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('تیکت‌های قبلی کاربر', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              ..._userTicketHistory.where((t) => t['id'] != _ticket.id).map(
                (t) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('#${t['id']} — ${t['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${t['status'] ?? ''}'),
                  onTap: () {
                    final id = t['id'];
                    if (id is int) context.push('/user/profile/operator/tickets/$id');
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final isEmbedded = widget.displayMode == TicketDetailDisplayMode.embedded;
    final isDialog = widget.displayMode == TicketDetailDisplayMode.dialog;
    final isPage = widget.displayMode == TicketDetailDisplayMode.page;
    final compactUser = !widget.isOperator && (isEmbedded || isPage);
    final compactOperator = widget.isOperator && (isEmbedded || isPage);
    final useCompactChrome = compactUser || compactOperator;

    final body = Container(
        width: isDialog ? MediaQuery.of(context).size.width * 0.9 : null,
        height: isDialog ? MediaQuery.of(context).size.height * 0.9 : null,
        decoration: BoxDecoration(
          borderRadius: isDialog ? BorderRadius.circular(20) : null,
          color: theme.colorScheme.surface,
        ),
        child: Column(
          children: [
            if (compactUser)
              _buildCompactUserHeader(theme, l10n, isPage)
            else if (compactOperator)
              _buildCompactOperatorHeader(theme, l10n)
            else
              Container(
              padding: EdgeInsets.all(isEmbedded ? 14 : 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: isDialog
                    ? const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))
                    : null,
                border: isEmbedded ? Border(bottom: BorderSide(color: theme.dividerColor)) : null,
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
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        SlaIndicator(slaStatus: _ticket.slaStatus),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 14, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              _formatTicketDate(_ticket.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!widget.isOperator && !_ticket.isClosedFinal)
                    TextButton.icon(
                      onPressed: _isActionBusy ? null : _closeTicket,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('بستن تیکت'),
                    ),
                  if (!widget.isOperator && _ticket.isClosedFinal)
                    TextButton.icon(
                      onPressed: _isActionBusy ? null : _reopenTicket,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('بازگشایی'),
                    ),
                  if (widget.isOperator) _buildCopyTicketButton(l10n),
                  if (widget.displayMode != TicketDetailDisplayMode.embedded)
                    IconButton(
                      onPressed: () {
                        if (widget.displayMode == TicketDetailDisplayMode.page) {
                          context.pop();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: Icon(
                        widget.displayMode == TicketDetailDisplayMode.page
                            ? Icons.arrow_back
                            : Icons.close,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),

            if (!widget.isOperator && _ticket.needsCsat)
              Material(
                color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.star_outline, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'تیکت بسته شد. لطفاً رضایت خود را ثبت کنید.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: widget.onRequestCsat,
                        child: const Text('ثبت رضایت'),
                      ),
                    ],
                  ),
                ),
              ),

            if (widget.isOperator && _statuses.isNotEmpty)
              TicketActionBar(
                ticket: _ticket,
                statuses: _statuses,
                priorities: _priorities,
                operators: _operators,
                isBusy: _isActionBusy,
                compact: useCompactChrome,
                onStatusChanged: (v) {
                  if (v != null) _handleStatusChange(v);
                },
                onPriorityChanged: (v) {
                  if (v != null) _handlePriorityChange(v);
                },
                onAssignChanged: _handleAssignChange,
              ),

            if (_events.isNotEmpty && !widget.isOperator && !compactUser)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TicketEventTimeline(
                  events: _events,
                  calendarController: widget.calendarController,
                ),
              ),

            if (!_canComposeMessage)
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: useCompactChrome ? 6 : 10),
                color: SemanticColorResolver.warning(context).withValues(alpha: 0.12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: SemanticColorResolver.warning(context), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'این تیکت بسته شده است. برای ادامه گفتگو آن را بازگشایی کنید.',
                        style: TextStyle(color: SemanticColorResolver.warning(context), fontSize: useCompactChrome ? 12 : 13),
                      ),
                    ),
                    if (!widget.isOperator)
                      TextButton(onPressed: _reopenTicket, child: const Text('بازگشایی')),
                  ],
                ),
              ),

            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: useCompactChrome ? 6 : 16),
                child: LayoutBuilder(
                builder: (context, constraints) {
                  // Side meta panel for operator when detail pane is wide enough
                  // (including embedded split view on large screens).
                  final showSidePanel = widget.isOperator && constraints.maxWidth > 720;
                  final showMetaInThread = compactOperator && !showSidePanel;

                  Widget buildThread() {
                    if (_isLoading && _messages.isEmpty) {
                      return const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        if (_isLoading && _messages.isNotEmpty)
                          const LinearProgressIndicator(minHeight: 2),
                        Expanded(
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _scrollController,
                              primary: false,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              itemCount: _listItemCount(
                                showSidePanel: showSidePanel,
                                compactUser: compactUser,
                                showMetaInThread: showMetaInThread,
                              ),
                              itemBuilder: (context, index) => _buildListItem(
                                context,
                                index,
                                showSidePanel,
                                l10n,
                                theme,
                                compactUser: compactUser,
                                showMetaInThread: showMetaInThread,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  if (!showSidePanel) {
                    return buildThread();
                  }

                  final sidePanelWidth = math.min(
                    300.0,
                    math.max(240.0, constraints.maxWidth * 0.26),
                  );

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: sidePanelWidth,
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(10),
                            child: TicketMetaSidebar(
                              ticket: _ticket,
                              events: _events,
                              userTicketHistory: _userTicketHistory,
                              calendarController: widget.calendarController,
                              isOperator: widget.isOperator,
                            ),
                          ),
                        ),
                      ),
                      VerticalDivider(width: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
                      Expanded(child: buildThread()),
                    ],
                  );
                },
              ),
              ),
            ),

            if (_canComposeMessage) _buildComposer(compact: useCompactChrome),
          ],
        ),
      );

    if (widget.displayMode == TicketDetailDisplayMode.embedded ||
        widget.displayMode == TicketDetailDisplayMode.page) {
      return SizedBox.expand(child: body);
    }
    return body;
  }
}

/// Dialog for selecting response templates
class _TemplatesDialog extends StatelessWidget {
  final List<ResponseTemplate> templates;

  const _TemplatesDialog({required this.templates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'قالب‌های پاسخ',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: templates.isEmpty
                  ? Center(
                      child: Text(
                        'هیچ قالبی یافت نشد',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: templates.length,
                      itemBuilder: (context, index) {
                        final template = templates[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              template.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              template.content.length > 100
                                  ? '${template.content.substring(0, 100)}...'
                                  : template.content,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.of(context).pop(template);
                            },
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
