import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/services/ai_service.dart';

/// دیالوگی برای دسترسی سریع به چت هوش مصنوعی از هر صفحه
class AIChatDialog extends StatefulWidget {
  final int? businessId;
  final AuthStore authStore;

  const AIChatDialog({
    super.key,
    this.businessId,
    required this.authStore,
  });

  static Future<void> show(
    BuildContext context, {
    required AuthStore authStore,
    int? businessId,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AIChatDialog(
        businessId: businessId,
        authStore: authStore,
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
        _sessions = list;
        _sessionsLoading = false;
      });
      if (list.isNotEmpty && _currentSession == null) {
        _selectSession(list.first);
      }
    } catch (e) {
      setState(() => _sessionsLoading = false);
      _showError('خطا در بارگذاری جلسات: $e');
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

  Future<void> _createSession() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('جلسه جدید'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'عنوان',
            hintText: 'مثلاً: سوالات مالیاتی',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );

    if (title == null || title.isEmpty) return;

    try {
      final newSession = await _aiService.createChatSession(
        title: title,
        businessId: widget.businessId,
      );
      await _loadSessions();
      _selectSession(newSession);
    } catch (e) {
      _showError('خطا در ایجاد جلسه: $e');
    }
  }

  Future<void> _deleteSession(AIChatSession session) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف جلسه'),
            content: const Text('آیا از حذف این جلسه مطمئن هستید؟'),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('جلسه حذف شد')));
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
      _showError('حذف جلسه با خطا مواجه شد: $e');
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

    try {
      final response = await _aiService.sendMessage(
        sessionId: _currentSession!.id!,
        content: content,
      );
      final msg = response['message'] as Map<String, dynamic>;
      final usage = response['usage'] as Map<String, dynamic>? ?? {};

      final assistantMessage = AIChatMessage(
        sessionId: _currentSession!.id!,
        role: MessageRole.fromString(msg['role'] as String? ?? 'assistant'),
        content: msg['content'] as String? ?? '',
        tokensUsed: usage['total_tokens'] as int? ?? 0,
        createdAt: msg['created_at'] != null
            ? DateTime.parse(msg['created_at'] as String)
            : DateTime.now(),
      );

      setState(() {
        _messages.add(assistantMessage);
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _sending = false);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context).size;
    final double dialogWidth = media.width > 1000 ? 1000 : media.width * 0.95;
    final double dialogHeight = media.height > 720 ? 720 : media.height * 0.9;

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
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _createSession,
                    icon: const Icon(Icons.add),
                    label: const Text('جلسه جدید'),
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
                  SizedBox(
                    width: 280,
                    child: Column(
                      children: [
                        Expanded(
                          child: _sessionsLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _sessions.isEmpty
                                  ? const Center(child: Text('جلسه‌ای وجود ندارد'))
                                  : ListView.builder(
                                      itemCount: _sessions.length,
                                      itemBuilder: (context, index) {
                                        final session = _sessions[index];
                                        final bool selected =
                                            _currentSession?.id == session.id;
                                        return ListTile(
                                          selected: selected,
                                          title: Text(
                                            session.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: session.updatedAt != null
                                              ? Text(
                                                  '${session.updatedAt!.year}/${session.updatedAt!.month}/${session.updatedAt!.day}',
                                                )
                                              : null,
                                          trailing: IconButton(
                                            icon: const Icon(Icons.delete_outline),
                                            tooltip: 'حذف',
                                            onPressed: () => _deleteSession(session),
                                          ),
                                          onTap: () => _selectSession(session),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _currentSession == null
                        ? const Center(child: Text('ابتدا یک جلسه را انتخاب کنید'))
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
                                        child: Text(
                                          'پیامی وجود ندارد. گفتگو را آغاز کنید.',
                                        ),
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
                                  color: theme.colorScheme.surfaceVariant
                                      .withOpacity(0.3),
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
                                        decoration: const InputDecoration(
                                          hintText: 'پیام خود را بنویسید...',
                                          border: OutlineInputBorder(),
                                        ),
                                        onSubmitted: (_) => _sendMessage(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed: _sending ? null : _sendMessage,
                                      icon: _sending
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(strokeWidth: 2),
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
}

