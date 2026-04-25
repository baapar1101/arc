import 'dart:async';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hesabix_ui/config/app_config.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/crm_chat_service.dart';
import 'package:hesabix_ui/services/crm_chat_ws_client.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';

/// صندوق ورودی چت وب (ویجت جاسازی‌شده در سایت مشتری).
class CrmWebChatPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final ApiClient apiClient;

  CrmWebChatPage({
    super.key,
    required this.businessId,
    required this.authStore,
    ApiClient? apiClient,
  }) : apiClient = apiClient ?? ApiClient();

  @override
  State<CrmWebChatPage> createState() => _CrmWebChatPageState();
}

class _CrmWebChatPageState extends State<CrmWebChatPage> {
  late final CrmChatService _svc;
  late final BusinessStorageService _storage;
  final CrmChatWsClient _ws = createCrmChatWsClient();
  final TextEditingController _replyCtrl = TextEditingController();
  final ScrollController _msgScroll = ScrollController();

  List<dynamic> _conversations = [];
  List<dynamic> _widgets = [];
  int? _selectedConvId;
  List<dynamic> _messages = [];
  List<Map<String, dynamic>> _businessUsers = [];
  bool _loading = true;
  bool _loadingMsgs = false;
  bool _wsLive = false;
  String? _statusFilter;
  Timer? _fallbackPoll;
  final FocusNode _replyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _svc = CrmChatService(apiClient: widget.apiClient);
    _storage = BusinessStorageService(widget.apiClient);
    _loadAll();
    _loadBusinessUsers();
    _initRealtime();
  }

  Future<void> _initRealtime() async {
    final key = widget.authStore.apiKey;
    if (key == null || key.isEmpty) {
      if (mounted) {
        setState(() => _wsLive = false);
        _startFallback();
      }
      return;
    }
    await _ws.connect(
      apiKey: key,
      businessId: widget.businessId,
      onMessage: _onWsMessage,
      onDisconnected: () {
        if (!mounted) return;
        setState(() => _wsLive = false);
        _startFallback();
      },
    );
    if (!mounted) return;
    setState(() => _wsLive = true);
    _stopFallback();
    if (_selectedConvId != null) {
      _ws.subscribeConversation(_selectedConvId!);
    }
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    if (msg['type']?.toString() != 'crm_chat.event') return;
    final event = msg['event']?.toString();
    if (event == 'message.created') {
      final cid = (msg['conversation_id'] as num?)?.toInt() ??
          ((msg['message'] is Map ? (msg['message'] as Map)['conversation_id'] : null) as num?)?.toInt();
      if (cid == null) {
        unawaited(_loadConversationsList(silent: true));
        return;
      }
      if (cid == _selectedConvId) {
        unawaited(_loadMessages(silent: true));
      } else {
        unawaited(_loadConversationsList(silent: true));
      }
      return;
    }
    if (event == 'conversation.started' || event == 'conversation.updated') {
      unawaited(_loadConversationsList(silent: true));
      if (event == 'conversation.updated' && msg['conversation'] is Map) {
        final raw = msg['conversation'] as Map;
        final c = Map<String, dynamic>.from(raw);
        if ((c['id'] as num?)?.toInt() == _selectedConvId) {
          if (!mounted) return;
          setState(() {
            _mergeConversationInList(c);
          });
        }
      }
    }
  }

  void _mergeConversationInList(Map<String, dynamic> c) {
    final id = c['id'] as int?;
    if (id == null) return;
    final idx = _conversations.indexWhere((e) => e is Map && (e)['id'] == id);
    if (idx >= 0) {
      _conversations[idx] = c;
    }
  }

  String _firstCharForAvatar(String? s) {
    if (s == null || s.isEmpty) return '?';
    return s[0].toUpperCase();
  }

  void _startFallback() {
    _fallbackPoll?.cancel();
    if (_wsLive) return;
    _fallbackPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      unawaited(_loadConversationsList(silent: true));
      if (_selectedConvId != null) {
        unawaited(_loadMessages(silent: true));
      }
    });
  }

  void _stopFallback() {
    _fallbackPoll?.cancel();
    _fallbackPoll = null;
  }

  @override
  void dispose() {
    _stopFallback();
    _ws.disconnect();
    _replyCtrl.dispose();
    _msgScroll.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadBusinessUsers() async {
    try {
      final res = await BusinessUserService(widget.apiClient).getBusinessUsers(widget.businessId);
      if (!mounted) return;
      setState(() {
        _businessUsers = res.users
            .map((u) => <String, dynamic>{'id': u.userId, 'name': u.userName, 'email': u.userEmail})
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      await _loadConversationsList(silent: true);
      final w = await _svc.listWidgets(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _widgets = w;
        if (!silent) _loading = false;
      });
      if (_selectedConvId != null) {
        await _loadMessages(silent: true);
        _scrollToEnd();
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _loading = false);
      if (!silent && mounted) {
        SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadConversationsList({bool silent = false}) async {
    final convs = await _svc.listConversations(
      businessId: widget.businessId,
      status: _statusFilter,
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _conversations = convs;
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_msgScroll.hasClients) return;
      _msgScroll.jumpTo(_msgScroll.position.maxScrollExtent);
    });
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
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMsgs = false);
      if (!silent) {
        SnackBarHelper.show(
        context,
        message: 'خطا در پیام‌ها: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
      }
    }
  }

  void _selectConversation(int id) {
    setState(() {
      _selectedConvId = id;
      _messages = [];
    });
    _loadMessages();
    if (_wsLive) {
      _ws.subscribeConversation(id);
    }
  }

  String? _nameForUserId(int? userId) {
    if (userId == null) return null;
    for (final u in _businessUsers) {
      if ((u['id'] as num?)?.toInt() == userId) {
        return u['name']?.toString();
      }
    }
    return null;
  }

  String _widgetName(int? widgetId) {
    if (widgetId == null) return '';
    for (final w in _widgets) {
      if (w is Map && (w['id'] as num?)?.toInt() == widgetId) {
        return w['name']?.toString() ?? '';
      }
    }
    return '#$widgetId';
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'open':
        return 'باز';
      case 'pending':
        return 'در انتظار';
      case 'resolved':
        return 'حل‌شده';
      default:
        return s ?? '—';
    }
  }

  Future<void> _downloadChatFile(String fileId, String originalName) async {
    try {
      final bytes = await _storage.downloadFile(
        businessId: widget.businessId,
        fileId: fileId,
      );
      final name = originalName.isNotEmpty ? originalName : 'file';
      final ext = name.contains('.') ? name.split('.').last : 'bin';
      await FileSaver.instance.saveFile(
        name: name,
        bytes: Uint8List.fromList(bytes),
        ext: ext,
      );
      if (mounted) SnackBarHelper.show(context, message: 'فایل ذخیره شد');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
        context,
        message: 'خطا در دانلود: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
      }
    }
  }

  String _formatMsgTime(dynamic raw) {
    if (raw == null) return '';
    try {
      DateTime? dt;
      if (raw is String) {
        dt = DateTime.tryParse(raw);
      } else if (raw is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(raw);
      }
      if (dt == null) return raw.toString();
      final local = dt.toLocal();
      final j = Jalali.fromDateTime(local);
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')} $h:$m';
    } catch (_) {
      return raw.toString();
    }
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
      await _loadConversationsList();
      if (mounted) SnackBarHelper.show(context, message: 'ارسال شد');
    } catch (e) {
      if (mounted) SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    }
  }

  Future<void> _copyText(String text, String successMsg) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) SnackBarHelper.show(context, message: successMsg);
  }

  Future<void> _patchConv(Map<String, dynamic> c, {String? status, int? assignedTo, int? leadId, int? personId}) async {
    if (!widget.authStore.canWriteSection('crm')) {
      SnackBarHelper.show(context, message: 'مجوز نوشتن CRM ندارید', isError: true);
      return;
    }
    final id = c['id'] as int;
    try {
      await _svc.patchConversation(
        businessId: widget.businessId,
        conversationId: id,
        status: status,
        assignedToUserId: assignedTo,
        leadId: leadId,
        personId: personId,
      );
      await _loadConversationsList();
      await _loadAll(silent: true);
      if (mounted) SnackBarHelper.show(context, message: 'ذخیره شد');
    } catch (e) {
      if (mounted) SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    }
  }

  Future<void> _showEditConvSheet(Map<String, dynamic> c) async {
    if (!widget.authStore.canWriteSection('crm')) {
      SnackBarHelper.show(context, message: 'مجوز نوشتن CRM ندارید', isError: true);
      return;
    }
    var st0 = c['status']?.toString() ?? 'open';
    if (!const {'open', 'pending', 'resolved'}.contains(st0)) st0 = 'open';
    String st = st0;
    int? assign = (c['assigned_to_user_id'] as num?)?.toInt();
    final leadCtrl = TextEditingController(text: c['lead_id'] != null ? '${c['lead_id']}' : '');
    final personCtrl = TextEditingController(text: c['person_id'] != null ? '${c['person_id']}' : '');

    final ok = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ویرایش مکالمه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: st, // ignore: deprecated_member_use
                    decoration: const InputDecoration(labelText: 'وضعیت', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('باز')),
                      DropdownMenuItem(value: 'pending', child: Text('در انتظار')),
                      DropdownMenuItem(value: 'resolved', child: Text('حل‌شده')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setModal(() => st = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: assign, // ignore: deprecated_member_use
                    decoration: const InputDecoration(labelText: 'تخصیص به', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('—')),
                      ..._businessUsers.map(
                        (u) => DropdownMenuItem<int?>(
                          value: (u['id'] as num?)?.toInt(),
                          child: Text(u['name']?.toString() ?? ''),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setModal(() => assign = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: leadCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'شناسه لید (اختیاری)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: personCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'شناسه شخص (اختیاری)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      int? parseId(String t) {
                        final s = t.trim();
                        if (s.isEmpty) return null;
                        return int.tryParse(s);
                      }

                      final lid = parseId(leadCtrl.text);
                      final pid = parseId(personCtrl.text);
                      Navigator.pop(ctx, {
                        'status': st,
                        'assign': assign,
                        'lead': lid,
                        'person': pid,
                      });
                    },
                    child: const Text('ذخیره'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (ok is Map) {
      final d = Map<String, dynamic>.from(ok);
      await _patchConv(
        c,
        status: d['status'] as String?,
        assignedTo: d['assign'] as int?,
        leadId: d['lead'] as int?,
        personId: d['person'] as int?,
      );
    }
    leadCtrl.dispose();
    personCtrl.dispose();
  }

  static String _embedSnippet(String apiBase, String publicKey) {
    final base = apiBase.replaceAll(RegExp(r'/+$'), '');
    return '''// پایه API: $base
// مرحله ۱: POST /api/v1/public/crm-chat/conversations/start
// بدنه: {"public_key": "$publicKey", "first_name", "last_name", "email", "phone", "page_url"}
// سپس با visitor_token و conversation_id به POST /api/v1/public/crm-chat/messages پیام بفرستید.
// جزئیات: مستندات CRM_WEB_CHAT در مخزن Hesabix''';
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
      if (mounted) SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    } finally {
      nameCtrl.dispose();
      originsCtrl.dispose();
    }
  }

  Future<void> _editWidgetDialog(Map<String, dynamic> w) async {
    if (!widget.authStore.canWriteSection('crm')) {
      SnackBarHelper.show(context, message: 'مجوز نوشتن CRM ندارید', isError: true);
      return;
    }
    final id = w['id'] as int;
    final nameCtrl = TextEditingController(text: w['name']?.toString() ?? '');
    final originsCtrl = TextEditingController(
      text: (w['allowed_origins'] is List) ? (w['allowed_origins'] as List).map((e) => e.toString()).join('، ') : '',
    );
    bool isActive = w['is_active'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) {
          return AlertDialog(
            title: const Text('ویرایش ویجت'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام')),
                  TextField(
                    controller: originsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'دامنه‌های مجاز (اختیاری)',
                      hintText: 'با ویرگول',
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('فعال'),
                    value: isActive,
                    onChanged: (v) => setSt(() => isActive = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
            ],
          );
        },
      ),
    );
    try {
      if (ok != true || !mounted) return;
      final raw = originsCtrl.text.trim();
      List<String>? origins;
      if (raw.isNotEmpty) {
        origins = raw.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } else {
        origins = const [];
      }
      await _svc.updateWidget(
        businessId: widget.businessId,
        widgetId: id,
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        allowedOrigins: origins,
        isActive: isActive,
      );
      await _loadAll();
      if (mounted) SnackBarHelper.show(context, message: 'ویجت به‌روز شد');
    } catch (e) {
      if (mounted) SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
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

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final apiBase = AppConfig.apiBaseUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('چت وب'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/crm/dashboard'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Icon(
                _wsLive ? Icons.wifi : Icons.wifi_off,
                size: 22,
                color: _wsLive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'بارگذاری مجدد',
            onPressed: () => _loadAll(),
          ),
          if (widget.authStore.canWriteSection('crm'))
            IconButton(icon: const Icon(Icons.add), onPressed: _createWidgetDialog),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Text(
                          'فیلتر وضعیت',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Wrap(
                          spacing: 4,
                          children: [
                            ChoiceChip(
                              label: const Text('همه'),
                              selected: _statusFilter == null,
                              onSelected: (_) async {
                                setState(() => _statusFilter = null);
                                await _loadConversationsList();
                              },
                            ),
                            ChoiceChip(
                              label: const Text('باز'),
                              selected: _statusFilter == 'open',
                              onSelected: (_) async {
                                setState(() => _statusFilter = 'open');
                                await _loadConversationsList();
                              },
                            ),
                            ChoiceChip(
                              label: const Text('در انتظار'),
                              selected: _statusFilter == 'pending',
                              onSelected: (_) async {
                                setState(() => _statusFilter = 'pending');
                                await _loadConversationsList();
                              },
                            ),
                            ChoiceChip(
                              label: const Text('حل‌شده'),
                              selected: _statusFilter == 'resolved',
                              onSelected: (_) async {
                                setState(() => _statusFilter = 'resolved');
                                await _loadConversationsList();
                              },
                            ),
                          ],
                        ),
                      ),
                      if (_widgets.isNotEmpty) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text('ویجت‌ها', style: theme.textTheme.titleSmall),
                        ),
                        SizedBox(
                          height: 160,
                          child: ListView.builder(
                            itemCount: _widgets.length,
                            itemBuilder: (ctx, i) {
                              final w = _widgets[i] as Map<String, dynamic>;
                              final pk = w['public_key']?.toString() ?? '';
                              final name = w['name']?.toString() ?? 'ویجت';
                              final active = w['is_active'] == true;
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: ListTile(
                                  dense: true,
                                  title: Text(name),
                                  subtitle: Text(
                                    active ? 'فعال' : 'غیرفعال',
                                    style: TextStyle(color: active ? cs.primary : cs.error),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (k) {
                                      if (k == 'copy_pk') {
                                        unawaited(_copyText(pk, 'کلید عمومی کپی شد'));
                                      } else if (k == 'copy_embed') {
                                        unawaited(
                                          _copyText(
                                            _embedSnippet(apiBase, pk),
                                            'راهنمای اتصال کپی شد',
                                          ),
                                        );
                                      } else if (k == 'edit' && widget.authStore.canWriteSection('crm')) {
                                        _editWidgetDialog(w);
                                      }
                                    },
                                    itemBuilder: (c) => [
                                      const PopupMenuItem(value: 'copy_pk', child: Text('کپی کلید عمومی')),
                                      const PopupMenuItem(value: 'copy_embed', child: Text('کپی راهنمای API')),
                                      if (widget.authStore.canWriteSection('crm'))
                                        const PopupMenuItem(value: 'edit', child: Text('ویرایش…')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('هنوز ویجی نساخته‌اید — از + استفاده کنید.'),
                        ),
                      const Divider(height: 1),
                      Expanded(
                        child: _conversations.isEmpty
                            ? const Center(
                                child: Text('مکالمه‌ای نیست — یا فیلتر را تغییر دهید'),
                              )
                            : ListView.builder(
                                itemCount: _conversations.length,
                                itemBuilder: (ctx, i) {
                                  final c = _conversations[i] as Map<String, dynamic>;
                                  final id = c['id'] as int;
                                  final title =
                                      '${c['visitor_first_name'] ?? ''} ${c['visitor_last_name'] ?? ''}'.trim();
                                  final sub = c['visitor_email']?.toString() ?? '';
                                  final ph = c['visitor_phone']?.toString() ?? '';
                                  final sel = _selectedConvId == id;
                                  final lma = c['last_message_at']?.toString() ?? '';
                                  return ListTile(
                                    selected: sel,
                                    title: Text(title.isEmpty ? 'مکالمه $id' : title,
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      [sub, ph, if (lma.isNotEmpty) lma].join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Text(_statusLabel(c['status']?.toString()), style: theme.textTheme.bodySmall),
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
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'یک مکالمه را انتخاب کنید',
                              style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        )
                      : _buildThreadPanel(theme, cs),
                ),
              ],
            ),
    );
  }

  Widget _buildThreadPanel(ThemeData theme, ColorScheme cs) {
    final c = _conversations.firstWhere(
      (e) => e is Map && (e)['id'] == _selectedConvId,
      orElse: () => <String, dynamic>{},
    );
    if (c is! Map || c['id'] == null) {
      return const Center(child: Text('مکالمه یافت نشد — به‌روزرسانی را بزنید'));
    }
    final conv = Map<String, dynamic>.from(c);
    final pageUrl = conv['page_url']?.toString();
    final assignName = _nameForUserId((conv['assigned_to_user_id'] as num?)?.toInt());

    return Column(
      children: [
        if (_loadingMsgs) LinearProgressIndicator(minHeight: 2, color: cs.primary),
        Material(
          color: cs.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  child: Text(
                    _firstCharForAvatar(conv['visitor_first_name']?.toString()),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${conv['visitor_first_name'] ?? ''} ${conv['visitor_last_name'] ?? ''}'.trim(),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (pageUrl != null && pageUrl.isNotEmpty)
                        InkWell(
                          onTap: () async {
                            final u = Uri.tryParse(pageUrl);
                            if (u != null && await canLaunchUrl(u)) {
                              await launchUrl(u, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Text(
                            pageUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                          ),
                        ),
                      Text(
                        '${conv['visitor_email'] ?? ''}  ·  ${conv['visitor_phone'] ?? ''}  ·  ویجت: ${_widgetName((conv['widget_id'] as num?)?.toInt())}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (assignName != null) Text('مسئول: $assignName', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (widget.authStore.canWriteSection('crm'))
                  FilledButton.tonal(
                    onPressed: () => _showEditConvSheet(conv),
                    child: const Text('ویرایش مکالمه'),
                  ),
                TextButton(
                  onPressed: () => context.push('/business/${widget.businessId}/crm/leads'),
                  child: const Text('لیدها'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _msgScroll,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (ctx, i) {
              final m = _messages[i] as Map<String, dynamic>;
              final role = m['sender_role']?.toString() ?? '';
              final body = m['body']?.toString() ?? '';
              final agent = role == 'agent';
              final uid = (m['user_id'] as num?)?.toInt();
              final who = agent
                  ? (uid != null ? (_nameForUserId(uid) ?? 'پشتیبان') : 'پشتیبان')
                  : 'بازدیدکننده';
              final file = m['file'];
              return Align(
                alignment: agent ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: agent ? cs.primaryContainer : cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (file is Map && file['id'] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => _downloadChatFile(
                              file['id']!.toString(),
                              file['original_name']?.toString() ?? 'file',
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_file, size: 18, color: cs.onPrimaryContainer),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    file['original_name']?.toString() ?? 'فایل',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.download, size: 16, color: cs.primary),
                              ],
                            ),
                          ),
                        ),
                      if (body.isNotEmpty) Text(body, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        '$who  ·  ${_formatMsgTime(m['created_at'])}',
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.authStore.canWriteSection('crm'))
          Material(
            color: cs.surface,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.enter, control: true): _sendReply,
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyCtrl,
                        focusNode: _replyFocus,
                        decoration: const InputDecoration(
                          hintText: 'پاسخ… (Ctrl+Enter ارسال)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _sendReply, child: const Text('ارسال')),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
