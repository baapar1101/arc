import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/core/auth_store.dart';

class AIChatPage extends StatefulWidget {
  final int? businessId;
  final AuthStore authStore;

  const AIChatPage({
    super.key,
    this.businessId,
    required this.authStore,
  });

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  late final AIService _aiService;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<AIChatSession> _sessions = [];
  AIChatSession? _currentSession;
  List<AIChatMessage> _messages = [];
  bool _loading = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final sessions = await _aiService.listChatSessions(
        businessId: widget.businessId,
      );
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
      if (sessions.isNotEmpty && _currentSession == null) {
        _selectSession(sessions.first);
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری جلسات: $e')),
        );
      }
    }
  }

  Future<void> _selectSession(AIChatSession session) async {
    setState(() {
      _currentSession = session;
      _messages = [];
    });
    try {
      final messages = await _aiService.getSessionMessages(
        sessionId: session.id!,
      );
      setState(() => _messages = messages);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری پیام‌ها: $e')),
        );
      }
    }
  }

  Future<void> _createNewSession() async {
    final titleController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('جلسه چت جدید'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'عنوان جلسه',
            hintText: 'مثلاً: سوالات حسابداری',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, titleController.text),
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final session = await _aiService.createChatSession(
          title: result,
          businessId: widget.businessId,
        );
        _loadSessions();
        _selectSession(session);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطا: $e')),
          );
        }
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _currentSession == null) return;

    final content = _messageController.text.trim();
    _messageController.clear();

    // اضافه کردن پیام کاربر به UI
    final userMessage = AIChatMessage(
      sessionId: _currentSession!.id!,
      role: MessageRole.user,
      content: content,
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

      final messageData = response['message'] as Map<String, dynamic>;
      final assistantMessage = AIChatMessage(
        sessionId: _currentSession!.id!,
        role: MessageRole.assistant,
        content: messageData['content'] as String? ?? '',
        tokensUsed: response['usage']?['total_tokens'] as int? ?? 0,
      );

      setState(() {
        _messages.add(assistantMessage);
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _sending = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ارسال پیام: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('چت با AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewSession,
            tooltip: 'جلسه جدید',
          ),
        ],
      ),
      body: Row(
        children: [
          // Sidebar: لیست جلسات
          Container(
            width: 300,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _createNewSession,
                    icon: const Icon(Icons.add),
                    label: const Text('جلسه جدید'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _sessions.isEmpty
                          ? const Center(child: Text('جلسه‌ای وجود ندارد'))
                          : ListView.builder(
                              itemCount: _sessions.length,
                              itemBuilder: (context, index) {
                                final session = _sessions[index];
                                final isSelected =
                                    _currentSession?.id == session.id;
                                return ListTile(
                                  selected: isSelected,
                                  title: Text(session.title),
                                  subtitle: session.updatedAt != null
                                      ? Text(
                                          '${session.updatedAt!.day}/${session.updatedAt!.month}/${session.updatedAt!.year}',
                                        )
                                      : null,
                                  onTap: () => _selectSession(session),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      if (await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('حذف جلسه'),
                                              content: const Text(
                                                  'آیا از حذف این جلسه اطمینان دارید؟'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context, false),
                                                  child: const Text('لغو'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context, true),
                                                  child: const Text('حذف'),
                                                ),
                                              ],
                                            ),
                                          ) ??
                                          false) {
                                        try {
                                          await _aiService
                                              .deleteChatSession(session.id!);
                                          _loadSessions();
                                          if (_currentSession?.id == session.id) {
                                            setState(() {
                                              _currentSession = null;
                                              _messages = [];
                                            });
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(content: Text('خطا: $e')),
                                            );
                                          }
                                        }
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          // Main: چت
          Expanded(
            child: _currentSession == null
                ? const Center(child: Text('یک جلسه را انتخاب کنید'))
                : Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: theme.dividerColor),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 12),
                            Text(
                              _currentSession!.title,
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      // Messages
                      Expanded(
                        child: _messages.isEmpty
                            ? const Center(
                                child: Text('پیامی وجود ندارد. شروع به چت کنید!'))
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: _messages.length +
                                    (_sending ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _messages.length && _sending) {
                                    return const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  final message = _messages[index];
                                  final isUser = message.role == MessageRole.user;
                                  return Align(
                                    alignment: isUser
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                                0.7,
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isUser
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            message.content,
                                            style: theme.textTheme.bodyLarge?.copyWith(
                                              color: isUser
                                                  ? theme.colorScheme.onPrimary
                                                  : null,
                                            ),
                                          ),
                                          if (message.tokensUsed > 0)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 8),
                                              child: Text(
                                                '${message.tokensUsed} توکن',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: isUser
                                                      ? theme.colorScheme.onPrimary
                                                          .withOpacity(0.7)
                                                      : null,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      // Input
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: theme.dividerColor),
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
                                ),
                                maxLines: null,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filled(
                              onPressed: _sending ? null : _sendMessage,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

