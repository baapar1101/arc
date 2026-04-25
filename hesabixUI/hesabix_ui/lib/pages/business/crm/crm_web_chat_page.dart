import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/crm_chat_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';

/// صندوق ورودی چت وب (ویجت جاسازی‌شده در سایت مشتری).
class CrmWebChatPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CrmWebChatPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CrmWebChatPage> createState() => _CrmWebChatPageState();
}

class _CrmWebChatPageState extends State<CrmWebChatPage> {
  final CrmChatService _svc = CrmChatService(apiClient: ApiClient());
  List<dynamic> _conversations = [];
  List<dynamic> _widgets = [];
  int? _selectedConvId;
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _loadingMsgs = false;
  final TextEditingController _replyCtrl = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
    });
    try {
      final convs = await _svc.listConversations(businessId: widget.businessId);
      final w = await _svc.listWidgets(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _conversations = convs;
        _widgets = w;
        _loading = false;
      });
      if (_selectedConvId != null) {
        await _loadMessages(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    final id = _selectedConvId;
    if (id == null) return;
    if (!silent) {
      setState(() => _loadingMsgs = true);
    }
    try {
      final msgs = await _svc.listMessages(businessId: widget.businessId, conversationId: id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loadingMsgs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMsgs = false);
      if (!silent) {
        SnackBarHelper.show(context, message: 'خطا در پیام‌ها: $e', isError: true);
      }
    }
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_selectedConvId != null) {
        _loadMessages(silent: true);
      }
      _loadAll();
    });
  }

  void _selectConversation(int id) {
    setState(() {
      _selectedConvId = id;
      _messages = [];
    });
    _loadMessages();
    _startPoll();
  }

  Future<void> _sendReply() async {
    final id = _selectedConvId;
    final text = _replyCtrl.text.trim();
    if (id == null || text.isEmpty) return;
    if (!widget.authStore.canWriteSection('crm')) {
      SnackBarHelper.show(context, message: 'مجوز نوشتن CRM ندارید', isError: true);
      return;
    }
    try {
      await _svc.postAgentMessage(businessId: widget.businessId, conversationId: id, body: text);
      _replyCtrl.clear();
      await _loadMessages();
      await _loadAll();
      if (mounted) SnackBarHelper.show(context, message: 'ارسال شد');
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }

  Future<void> _createWidgetDialog() async {
    if (!widget.authStore.canWriteSection('crm')) {
      SnackBarHelper.show(context, message: 'مجوز نوشتن CRM ندارید', isError: true);
      return;
    }
    final nameCtrl = TextEditingController();
    final originsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویجت چت جدید'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام')),
            TextField(
              controller: originsCtrl,
              decoration: const InputDecoration(
                labelText: 'دامنه‌های مجاز (اختیاری)',
                hintText: 'example.com، با ویرگول جدا کنید',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ایجاد')),
        ],
      ),
    );
    try {
      if (ok != true || !mounted) return;
      final raw = originsCtrl.text.trim();
      List<String>? origins;
      if (raw.isNotEmpty) {
        origins = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      await _svc.createWidget(
        businessId: widget.businessId,
        name: nameCtrl.text.trim().isEmpty ? 'ویجت' : nameCtrl.text.trim(),
        allowedOrigins: origins,
      );
      await _loadAll();
      if (mounted) SnackBarHelper.show(context, message: 'ویجت ایجاد شد');
    } catch (e) {
      if (mounted) SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    } finally {
      nameCtrl.dispose();
      originsCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return const AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('چت وب'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/crm/dashboard'),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
          if (widget.authStore.canWriteSection('crm'))
            IconButton(icon: const Icon(Icons.add), onPressed: _createWidgetDialog),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                SizedBox(
                  width: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_widgets.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'کلید عمومی فعال: ${_widgets.map((w) => w['public_key']).join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _conversations.length,
                          itemBuilder: (ctx, i) {
                            final c = _conversations[i] as Map<String, dynamic>;
                            final id = c['id'] as int;
                            final title =
                                '${c['visitor_first_name'] ?? ''} ${c['visitor_last_name'] ?? ''}'.trim();
                            final sub = c['visitor_email']?.toString() ?? '';
                            final sel = _selectedConvId == id;
                            return ListTile(
                              selected: sel,
                              title: Text(title.isEmpty ? 'مکالمه $id' : title),
                              subtitle: Text(sub),
                              trailing: Text(c['status']?.toString() ?? ''),
                              onTap: () => _selectConversation(id),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selectedConvId == null
                      ? const Center(child: Text('یک مکالمه را انتخاب کنید'))
                      : Column(
                          children: [
                            if (_loadingMsgs) const LinearProgressIndicator(minHeight: 2),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _messages.length,
                                itemBuilder: (ctx, i) {
                                  final m = _messages[i] as Map<String, dynamic>;
                                  final role = m['sender_role']?.toString() ?? '';
                                  final body = m['body']?.toString() ?? '';
                                  final agent = role == 'agent';
                                  return Align(
                                    alignment: agent ? Alignment.centerLeft : Alignment.centerRight,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: agent
                                            ? Colors.blue.shade50
                                            : Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(body),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (widget.authStore.canWriteSection('crm'))
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _replyCtrl,
                                        decoration: const InputDecoration(
                                          hintText: 'پاسخ…',
                                          border: OutlineInputBorder(),
                                        ),
                                        minLines: 1,
                                        maxLines: 4,
                                        onSubmitted: (_) => _sendReply(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(onPressed: _sendReply, child: const Text('ارسال')),
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
}
