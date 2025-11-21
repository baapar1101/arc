import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/services/ai_service.dart';

/// دیالوگی برای دسترسی سریع به چت هوش مصنوعی از هر صفحه
class AIChatDialog extends StatefulWidget {
  final int? businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const AIChatDialog({
    super.key,
    this.businessId,
    required this.authStore,
    this.calendarController,
  });

  static Future<void> show(
    BuildContext context, {
    required AuthStore authStore,
    int? businessId,
    CalendarController? calendarController,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AIChatDialog(
        businessId: businessId,
        authStore: authStore,
        calendarController: calendarController,
      ),
    );
  }

  @override
  State<AIChatDialog> createState() => _AIChatDialogState();
}

class _AIChatDialogState extends State<AIChatDialog> {
  late final AIService _aiService;
  List<AIChatSession> _sessions = [];
  AIChatSession? _currentSession;
  List<AIChatMessage> _messages = [];
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sessionsLoading = true;
  bool _sending = false;
  bool _historyCollapsed = true;

  bool get _isJalali => widget.calendarController?.isJalali ?? true;

  @override
  void initState() {
    super.initState();
    ApiClient.bindAuthStore(widget.authStore);
    _aiService = AIService(ApiClient());
    _loadSessions();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _sessionsLoading = true);
    try {
      final list = await _aiService.listChatSessions(
        businessId: widget.businessId,
      );
      setState(() {
        list.sort((a, b) {
          final aDate = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        _sessions = list;
        _sessionsLoading = false;
      });
      if (list.isNotEmpty && _currentSession == null) {
        _selectSession(list.first);
      }
    } catch (e) {
      setState(() => _sessionsLoading = false);
      _showError('خطا در بارگذاری گفت‌وگوها: $e');
    }
  }

  Future<void> _selectSession(AIChatSession session) async {
    setState(() {
      _currentSession = session;
      _messages = [];
    });
    try {
      final msgs = await _aiService.getSessionMessages(sessionId: session.id!);
      setState(() => _messages = msgs);
      _scrollToBottom();
    } catch (e) {
      _showError('خطا در دریافت پیام‌ها: $e');
    }
  }

  Future<void> _startNewConversation() async {
    try {
      final newSession = await _aiService.createChatSession(
        businessId: widget.businessId,
      );
      await _loadSessions();
      _selectSession(newSession);
      _showSnackbar('گفت‌وگوی جدید ایجاد شد');
    } catch (e) {
      _showError('خطا در آغاز گفت‌وگو: $e');
    }
  }

  Future<void> _deleteSession(AIChatSession session) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف گفت‌وگو'),
            content: const Text('آیا از حذف این گفت‌وگو مطمئن هستید؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    try {
      await _aiService.deleteChatSession(session.id!);
      if (!mounted) return;
      _showSnackbar('گفت‌وگو حذف شد');
      await _loadSessions();
      if (_sessions.isNotEmpty) {
        _selectSession(_sessions.first);
      } else {
        setState(() {
          _currentSession = null;
          _messages = [];
        });
      }
    } catch (e) {
      _showError('حذف گفت‌وگو با خطا مواجه شد: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_sending || _currentSession == null || _messageCtrl.text.trim().isEmpty) return;

    final content = _messageCtrl.text.trim();
    _messageCtrl.clear();

    final userMessage = AIChatMessage(
      sessionId: _currentSession!.id!,
      role: MessageRole.user,
      content: content,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _sending = true;
    });
    _scrollToBottom();

    // ایجاد پیام assistant با محتوای خالی برای streaming
    final assistantMessageIndex = _messages.length;
    final assistantMessage = AIChatMessage(
      sessionId: _currentSession!.id!,
      role: MessageRole.assistant,
      content: '', // به تدریج پر می‌شود
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(assistantMessage);
    });
    _scrollToBottom();

    try {
      String accumulatedContent = '';
      
      await for (final chunk in _aiService.sendMessageStream(
        sessionId: _currentSession!.id!,
        content: content,
        onComplete: (usage, messageId) {
          // به‌روزرسانی usage stats و message ID
          setState(() {
            _messages[assistantMessageIndex] = AIChatMessage(
              sessionId: _currentSession!.id!,
              role: MessageRole.assistant,
              content: accumulatedContent,
              tokensUsed: usage?['total_tokens'] as int? ?? 0,
              createdAt: _messages[assistantMessageIndex].createdAt,
            );
            _sending = false;
          });
          _scrollToBottom();
        },
        onError: (error) {
          setState(() {
            _sending = false;
            _messages.removeAt(assistantMessageIndex);
          });
          _showError('ارسال پیام ناموفق بود: $error');
        },
      )) {
        accumulatedContent += chunk;
        
        // به‌روزرسانی UI به صورت real-time
        setState(() {
          _messages[assistantMessageIndex] = AIChatMessage(
            sessionId: _currentSession!.id!,
            role: MessageRole.assistant,
            content: accumulatedContent,
            createdAt: _messages[assistantMessageIndex].createdAt,
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _sending = false;
        if (_messages.length > assistantMessageIndex) {
          _messages.removeAt(assistantMessageIndex);
        }
      });
      _showError('ارسال پیام ناموفق بود: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context).size;
    final double dialogWidth = media.width > 1200 ? 1200 : media.width * 0.98;
    final double dialogHeight = media.height > 900 ? 900 : media.height * 0.95;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: dialogHeight),
        child: Column(
          children: [
            Container(
              color: theme.colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy_outlined),
                  const SizedBox(width: 8),
                  Text(
                    'دستیار هوش مصنوعی',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _startNewConversation,
                    icon: const Icon(Icons.add_comment),
                    label: const Text('گفت‌وگوی جدید'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'بستن',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: _historyCollapsed ? 0 : 260,
                    child: _historyCollapsed
                        ? const SizedBox.shrink()
                        : Container(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(color: theme.dividerColor),
                              ),
                            ),
                            child: _buildHistoryPanel(theme),
                          ),
                  ),
                  Container(
                    width: 40,
                    alignment: Alignment.topCenter,
                    child: IconButton(
                      tooltip: _historyCollapsed ? 'نمایش گفت‌وگوها' : 'مخفی‌سازی گفت‌وگوها',
                      onPressed: () => setState(() => _historyCollapsed = !_historyCollapsed),
                      icon: Icon(
                        _historyCollapsed ? Icons.chevron_right : Icons.chevron_left,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _currentSession == null
                        ? const Center(child: Text('ابتدا یک گفت‌وگو را انتخاب کنید'))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: theme.dividerColor),
                                  ),
                                ),
                                child: Text(
                                  _currentSession!.title,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              Expanded(
                                child: _messages.isEmpty
                                    ? const Center(
                                        child: Text('پیامی وجود ندارد. گفت‌وگو را آغاز کنید.'),
                                      )
                                    : ListView.builder(
                                        controller: _scrollController,
                                        padding: const EdgeInsets.all(16),
                                        itemCount: _messages.length,
                                        itemBuilder: (context, index) {
                                          final msg = _messages[index];
                                          final bool isUser =
                                              msg.role == MessageRole.user;
                                          return Align(
                                            alignment: isUser
                                                ? AlignmentDirectional.centerEnd
                                                : AlignmentDirectional.centerStart,
                                            child: Container(
                                              margin: const EdgeInsets.symmetric(
                                                vertical: 6,
                                              ),
                                              padding: const EdgeInsets.all(12),
                                              constraints: BoxConstraints(
                                                maxWidth: dialogWidth * 0.55,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isUser
                                                    ? theme.colorScheme.primary
                                                        .withOpacity(0.1)
                                                    : theme.colorScheme.surfaceVariant,
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    isUser ? 'شما' : 'AI',
                                                    style: theme.textTheme.labelSmall
                                                        ?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(msg.content),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                  border: Border(
                                    top: BorderSide(color: theme.dividerColor),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _messageCtrl,
                                        minLines: 1,
                                        maxLines: 5,
                                        textInputAction: TextInputAction.send,
                                        decoration: const InputDecoration(
                                          hintText: 'پیام خود را بنویسید...',
                                          border: OutlineInputBorder(),
                                        ),
                                        onSubmitted: (_) {
                                          if (!_sending && _messageCtrl.text.trim().isNotEmpty) {
                                            _sendMessage();
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed: _sending ? null : _sendMessage,
                                      icon: _sending
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.send),
                                      label: const Text('ارسال'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryPanel(ThemeData theme) {
    if (_sessionsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sessions.isEmpty) {
      return const Center(child: Text('گفت‌وگویی وجود ندارد'));
    }
    return ListView.builder(
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final selected = _currentSession?.id == session.id;
        final stamp = session.updatedAt ?? session.createdAt ?? DateTime.now();
        final dateText = HesabixDateUtils.formatForDisplay(stamp, _isJalali);
        return ListTile(
          selected: selected,
          title: Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(dateText),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'حذف گفت‌وگو',
            onPressed: () => _deleteSession(session),
          ),
          onTap: () => _selectSession(session),
        );
      },
    );
  }
}

