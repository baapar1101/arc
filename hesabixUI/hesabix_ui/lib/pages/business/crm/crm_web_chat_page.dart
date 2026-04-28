import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/crm_chat_service.dart';
import 'package:hesabix_ui/services/crm_chat_ws_client.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

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
  List<dynamic> _widgetsCache = [];
  int? _selectedConvId;
  List<dynamic> _messages = [];
  List<Map<String, dynamic>> _businessUsers = [];
  bool _loading = true;
  bool _loadingMsgs = false;
  bool _wsLive = false;
  bool _allowWebChatFileUpload = false;
  bool _sendingFile = false;
  /// `null` = همه؛ پیش‌فرض پس از بارگذاری ترجیح ذخیره‌شده یا «باز».
  String? _statusFilter = 'open';
  Timer? _fallbackPoll;
  Timer? _backupPoll;
  final FocusNode _replyFocus = FocusNode();
  bool _peerTyping = false;
  Timer? _typingDebounce;
  Timer? _typingStopTimer;

  String _convSearch = '';
  Timer? _searchDebounce;
  bool _convHasMore = false;
  bool _loadingMoreConvs = false;
  bool _msgHasMoreOlder = false;
  bool _loadingOlderMsgs = false;
  bool _mobileShowList = true;
  final TextEditingController _convSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _msgScroll.addListener(_onMessageScroll);
    _svc = CrmChatService(apiClient: widget.apiClient);
    _storage = BusinessStorageService(widget.apiClient);
    _replyCtrl.addListener(_onReplyTextChanged);
    unawaited(_bootstrap());
  }

  static const _kStatusFilterPrefPrefix = 'crm_web_chat_status_filter_v1_';

  Future<void> _bootstrap() async {
    await _restoreStatusFilter();
    if (!mounted) return;
    unawaited(_loadBusinessUsers());
    await _loadAll();
    if (!mounted) return;
    await _initRealtime();
  }

  Future<void> _restoreStatusFilter() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString('$_kStatusFilterPrefPrefix${widget.businessId}');
    if (!mounted) return;
    setState(() {
      if (v == null || v.isEmpty) {
        _statusFilter = 'open';
      } else if (v == 'all') {
        _statusFilter = null;
      } else if (const {'open', 'pending', 'resolved'}.contains(v)) {
        _statusFilter = v;
      } else {
        _statusFilter = 'open';
      }
    });
  }

  Future<void> _persistStatusFilter() async {
    final p = await SharedPreferences.getInstance();
    final key = '$_kStatusFilterPrefPrefix${widget.businessId}';
    if (_statusFilter == null) {
      await p.setString(key, 'all');
    } else {
      await p.setString(key, _statusFilter!);
    }
  }

  Future<void> _loadWidgetsCache() async {
    try {
      final w = await _svc.listWidgets(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _widgetsCache = w);
    } catch (_) {}
  }

  String _statusLabelForBulk(AppLocalizations t, String code) {
    switch (code) {
      case 'open':
        return t.crmWebChatStatusOpen;
      case 'pending':
        return t.crmWebChatStatusPending;
      case 'resolved':
        return t.crmWebChatStatusResolved;
      default:
        return code;
    }
  }

  Future<void> _onFilterHeaderLongPress(AppLocalizations t) async {
    if (!widget.authStore.canEditCrmWebChatConversations()) return;
    final body = _statusFilter == null
        ? t.crmWebChatBulkDeleteConfirmAll
        : t.crmWebChatBulkDeleteConfirmStatus(_statusLabelForBulk(t, _statusFilter!));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.crmWebChatBulkDeleteTitle),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final n = await _svc.deleteAllConversations(
        businessId: widget.businessId,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _selectedConvId = null;
        _messages = [];
      });
      await _loadConversationsList(silent: true, reset: true);
      SnackBarHelper.show(context, message: t.crmWebChatBulkDeleteDone(n));
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: t.crmWebChatError(ErrorExtractor.forContext(e, context)),
          isError: true,
        );
      }
    }
  }

  void _onReplyTextChanged() {
    final cid = _selectedConvId;
    if (cid == null || !_wsLive) return;
    final text = _replyCtrl.text;
    _typingDebounce?.cancel();
    if (text.trim().isEmpty) {
      _ws.sendTyping(cid, active: false);
      return;
    }
    _typingDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _ws.sendTyping(cid, active: true);
      _typingStopTimer?.cancel();
      _typingStopTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _ws.sendTyping(cid, active: false);
      });
    });
  }

  Future<void> _markVisitorMessagesReadSilently() async {
    final id = _selectedConvId;
    if (id == null) return;
    int? maxVid;
    for (final x in _messages) {
      if (x is! Map) continue;
      if (x['sender_role']?.toString() != 'visitor') continue;
      final mid = (x['id'] as num?)?.toInt();
      if (mid == null) continue;
      if (maxVid == null || mid > maxVid) maxVid = mid;
    }
    if (maxVid == null) return;
    try {
      await _svc.markConversationRead(
        businessId: widget.businessId,
        conversationId: id,
        upToMessageId: maxVid,
      );
    } catch (_) {}
  }

  Future<void> _initRealtime() async {
    final key = widget.authStore.apiKey;
    if (key == null || key.isEmpty) {
      if (mounted) {
        setState(() => _wsLive = false);
        _stopBackupPoll();
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
        _stopBackupPoll();
        _startFallback();
      },
    );
    if (!mounted) return;
    setState(() => _wsLive = true);
    _stopFallback();
    _startBackupPoll();
    if (_selectedConvId != null) {
      _ws.subscribeConversation(_selectedConvId!);
    }
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    if (msg['type']?.toString() != 'crm_chat.event') return;
    final event = msg['event']?.toString();
    if (event == 'typing') {
      final cid = (msg['conversation_id'] as num?)?.toInt();
      if (cid == null || cid != _selectedConvId) return;
      if (msg['from_role']?.toString() != 'visitor') return;
      if (!mounted) return;
      setState(() => _peerTyping = msg['active'] == true);
      return;
    }
    if (event == 'messages.read') {
      final cid = (msg['conversation_id'] as num?)?.toInt();
      if (cid == null || cid != _selectedConvId) return;
      final rawIds = msg['message_ids'];
      if (rawIds is! List) return;
      final idSet = rawIds
          .map((e) => e is int ? e : int.tryParse(e.toString()))
          .whereType<int>()
          .toSet();
      final readAt = msg['read_at'];
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((row) {
          if (row is! Map) return row;
          final mid = (row['id'] as num?)?.toInt();
          if (mid != null && idSet.contains(mid)) {
            final copy = Map<String, dynamic>.from(row);
            copy['read_at'] = readAt;
            return copy;
          }
          return row;
        }).toList();
      });
      return;
    }
    if (event == 'message.deleted') {
      final cid = (msg['conversation_id'] as num?)?.toInt();
      final mid = (msg['message_id'] as num?)?.toInt();
      if (cid == null || mid == null || cid != _selectedConvId) return;
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((row) {
          if (row is! Map) return row;
          if ((row['id'] as num?)?.toInt() == mid) {
            final copy = Map<String, dynamic>.from(row);
            copy['is_deleted'] = true;
            copy['body'] = '';
            copy['file'] = null;
            return copy;
          }
          return row;
        }).toList();
      });
      return;
    }
    if (event == 'message.updated') {
      final raw = msg['message'];
      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      final cid = (m['conversation_id'] as num?)?.toInt();
      if (cid == null) return;
      if (cid != _selectedConvId) {
        unawaited(_loadConversationsList(silent: true));
        return;
      }
      final mid = (m['id'] as num?)?.toInt();
      if (mid == null || !mounted) return;
      setState(() {
        _messages = _messages.map((row) {
          if (row is! Map) return row;
          if ((row['id'] as num?)?.toInt() == mid) {
            return Map<String, dynamic>.from(m);
          }
          return row;
        }).toList();
      });
      unawaited(_loadConversationsList(silent: true));
      return;
    }
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
      return;
    }
    if (event == 'conversations.bulk_deleted') {
      final bid = (msg['business_id'] as num?)?.toInt();
      if (bid == null || bid != widget.businessId) return;
      if (!mounted) return;
      setState(() {
        _selectedConvId = null;
        _messages = [];
      });
      unawaited(_loadConversationsList(silent: true, reset: true));
      return;
    }
    if (event == 'conversation.deleted') {
      final bid = (msg['business_id'] as num?)?.toInt();
      final cid = (msg['conversation_id'] as num?)?.toInt();
      if (bid == null || cid == null || bid != widget.businessId) return;
      if (!mounted) return;
      setState(() {
        _conversations = _conversations.where((e) {
          if (e is! Map) return true;
          return (e['id'] as num?)?.toInt() != cid;
        }).toList();
        if (_selectedConvId == cid) {
          _selectedConvId = null;
          _messages = [];
        }
      });
      return;
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
    _fallbackPoll = Timer.periodic(const Duration(seconds: 8), (_) {
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

  /// همگام‌سازی آرام حتی وقتی WebSocket وصل است (چند worker / از دست رفتن رویداد).
  void _startBackupPoll() {
    _backupPoll?.cancel();
    if (!_wsLive) return;
    _backupPoll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_wsLive) return;
      unawaited(_loadConversationsList(silent: true));
      if (_selectedConvId != null) {
        unawaited(_loadMessages(silent: true));
      }
    });
  }

  void _stopBackupPoll() {
    _backupPoll?.cancel();
    _backupPoll = null;
  }

  @override
  void dispose() {
    _replyCtrl.removeListener(_onReplyTextChanged);
    _typingDebounce?.cancel();
    _typingStopTimer?.cancel();
    _stopFallback();
    _stopBackupPoll();
    _ws.disconnect();
    _replyCtrl.dispose();
    _searchDebounce?.cancel();
    _msgScroll.removeListener(_onMessageScroll);
    _msgScroll.dispose();
    _convSearchCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _onMessageScroll() {
    if (!_msgScroll.hasClients) return;
    if (!_msgHasMoreOlder || _loadingOlderMsgs) return;
    if (_msgScroll.position.pixels > 100) return;
    unawaited(_loadOlderMessages());
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
      await _loadWidgetsCache();
      bool allowFiles = false;
      try {
        final st = await _svc.getCrmSettings(businessId: widget.businessId);
        allowFiles = st['allow_web_chat_file_upload'] == true;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _allowWebChatFileUpload = allowFiles;
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
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
        context,
        message: t.crmWebChatError(ErrorExtractor.forContext(e, context)),
        isError: true,
      );
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadConversationsList({bool silent = false, bool reset = true}) async {
    if (!reset) {
      if (!_convHasMore || _loadingMoreConvs) return;
    }
    if (!reset) {
      setState(() => _loadingMoreConvs = true);
    }
    try {
      final offset = reset ? 0 : _conversations.length;
      final (convs, hasMore) = await _svc.listConversations(
        businessId: widget.businessId,
        status: _statusFilter,
        limit: 40,
        offset: offset,
        search: _convSearch.trim().isEmpty ? null : _convSearch.trim(),
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _conversations = convs;
        } else {
          _conversations = [..._conversations, ...convs];
        }
        _convHasMore = hasMore;
        _loadingMoreConvs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoreConvs = false);
    }
  }

  void _onConvSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _convSearch = v);
      unawaited(_loadConversationsList(silent: true, reset: true));
    });
  }

  bool _onConversationsListScroll(ScrollNotification n) {
    if (n.metrics.pixels > n.metrics.maxScrollExtent - 180) {
      if (_convHasMore && !_loadingMoreConvs) {
        unawaited(_loadConversationsList(silent: true, reset: false));
      }
    }
    return false;
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
      final (msgs, hasOlder) = await _svc.listMessages(
        businessId: widget.businessId,
        conversationId: id,
        limit: 80,
      );
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loadingMsgs = false;
        _msgHasMoreOlder = hasOlder;
      });
      _scrollToEnd();
      unawaited(_markVisitorMessagesReadSilently());
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMsgs = false);
      if (!silent) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
        context,
        message: t.crmWebChatErrorLoadingMessages(ErrorExtractor.forContext(e, context)),
        isError: true,
      );
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    final id = _selectedConvId;
    if (id == null || !_msgHasMoreOlder || _loadingOlderMsgs) return;
    if (_messages.isEmpty) return;
    final first = _messages.first;
    if (first is! Map) return;
    final before = (first['id'] as num?)?.toInt();
    if (before == null) return;
    setState(() => _loadingOlderMsgs = true);
    try {
      final (older, hasOlder) = await _svc.listMessages(
        businessId: widget.businessId,
        conversationId: id,
        limit: 40,
        beforeMessageId: before,
      );
      if (!mounted) return;
      setState(() {
        _messages = [...older, ..._messages];
        _msgHasMoreOlder = hasOlder;
        _loadingOlderMsgs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlderMsgs = false);
    }
  }

  Future<void> _deleteMessage(int messageId) async {
    final cid = _selectedConvId;
    if (cid == null || !widget.authStore.canDeleteCrmWebChatMessages()) return;
    try {
      await _svc.deleteMessage(
        businessId: widget.businessId,
        conversationId: cid,
        messageId: messageId,
      );
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((row) {
          if (row is! Map) return row;
          if ((row['id'] as num?)?.toInt() == messageId) {
            final c = Map<String, dynamic>.from(row);
            c['is_deleted'] = true;
            c['body'] = '';
            c['file'] = null;
            return c;
          }
          return row;
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: AppLocalizations.of(context).crmWebChatError(ErrorExtractor.forContext(e, context)),
          isError: true,
        );
      }
    }
  }

  Future<void> _deleteConversation(int conversationId) async {
    if (!widget.authStore.canEditCrmWebChatConversations()) return;
    try {
      await _svc.deleteConversation(
        businessId: widget.businessId,
        conversationId: conversationId,
      );
      if (!mounted) return;
      setState(() {
        _conversations = _conversations.where((e) {
          if (e is! Map) return true;
          return (e['id'] as num?)?.toInt() != conversationId;
        }).toList();
        if (_selectedConvId == conversationId) {
          _selectedConvId = null;
          _messages = [];
        }
      });
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).crmWebChatConversationDeleted,
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: AppLocalizations.of(context).crmWebChatError(ErrorExtractor.forContext(e, context)),
          isError: true,
        );
      }
    }
  }

  Future<void> _editAgentMessage(Map<String, dynamic> msg) async {
    if (!widget.authStore.canReplyCrmWebChat()) return;
    final cid = _selectedConvId;
    final mid = (msg['id'] as num?)?.toInt();
    if (cid == null || mid == null) return;
    final controller = TextEditingController(text: msg['body']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(loc.crmWebChatEditMessageTitle),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: loc.crmWebChatEditMessageHint,
              border: const OutlineInputBorder(),
            ),
            maxLines: 6,
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.save)),
          ],
        );
      },
    );
    final text = controller.text.trim();
    controller.dispose();
    if (ok != true || !mounted) return;
    try {
      await _svc.patchAgentMessage(
        businessId: widget.businessId,
        conversationId: cid,
        messageId: mid,
        body: text,
      );
      await _loadMessages(silent: true);
      await _loadConversationsList(silent: true, reset: true);
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).crmWebChatEditMessageSaved,
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: AppLocalizations.of(context).crmWebChatError(ErrorExtractor.forContext(e, context)),
          isError: true,
        );
      }
    }
  }

  void _selectConversation(int id) {
    setState(() {
      _selectedConvId = id;
      _messages = [];
      _peerTyping = false;
      _mobileShowList = false;
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
    for (final w in _widgetsCache) {
      if (w is Map && (w['id'] as num?)?.toInt() == widgetId) {
        return w['name']?.toString() ?? '';
      }
    }
    return '#$widgetId';
  }

  String _socketStatusText(AppLocalizations t) {
    final key = widget.authStore.apiKey;
    if (key == null || key.isEmpty) return t.crmWebChatSocketNoKey;
    if (_wsLive) return t.crmWebChatSocketLive;
    if (_fallbackPoll != null) return t.crmWebChatSocketPolling;
    return t.crmWebChatSocketOffline;
  }

  bool _messageHasReadReceipt(Map<dynamic, dynamic> m) => m['read_at'] != null;

  String _statusLabel(AppLocalizations t, String? s) {
    switch (s) {
      case 'open':
        return t.crmWebChatStatusOpen;
      case 'pending':
        return t.crmWebChatStatusPending;
      case 'resolved':
        return t.crmWebChatStatusResolved;
      default:
        return s ?? t.crmWebChatUnassigned;
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
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.crmWebChatFileSaved);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
        context,
        message: t.crmWebChatErrorDownload(ErrorExtractor.forContext(e, context)),
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

  Future<void> _pickAndSendAgentFile() async {
    final id = _selectedConvId;
    if (id == null || !widget.authStore.canReplyCrmWebChat()) {
      return;
    }
    if (!_allowWebChatFileUpload) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.crmWebChatFileUploadDisabledCrm, isError: true);
      return;
    }
    try {
      final pick = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.any,
        allowMultiple: false,
      );
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.show(
            context,
            message: t.crmWebChatFileReadFailed,
            isError: true,
          );
        }
        return;
      }
      setState(() => _sendingFile = true);
      final up = await _storage.uploadFile(
        businessId: widget.businessId,
        fileBytes: bytes,
        filename: f.name.isNotEmpty ? f.name : 'file',
        moduleContext: 'crm_web_chat',
        contextId: id.toString(),
      );
      if (!mounted) return;
      final fid = up['file_id']?.toString();
      if (fid == null || fid.isEmpty) {
        throw StateError(AppLocalizations.of(context).crmWebChatFileIdMissing);
      }
      final cap = _replyCtrl.text.trim();
      await _svc.postAgentMessage(
        businessId: widget.businessId,
        conversationId: id,
        body: cap.isNotEmpty ? cap : null,
        fileStorageId: fid,
      );
      _replyCtrl.clear();
      await _loadMessages();
      await _loadConversationsList();
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.crmWebChatFileSent);
        if (_wsLive) _ws.sendTyping(id, active: false);
        unawaited(_markVisitorMessagesReadSilently());
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
          context,
          message: t.crmWebChatError(ErrorExtractor.forContext(e, context)),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  Future<void> _sendReply() async {
    final id = _selectedConvId;
    final text = _replyCtrl.text.trim();
    if (id == null || text.isEmpty) return;
    if (!widget.authStore.canReplyCrmWebChat()) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.crmWebChatNoCrmWritePermission, isError: true);
      return;
    }
    try {
      await _svc.postAgentMessage(businessId: widget.businessId, conversationId: id, body: text);
      _replyCtrl.clear();
      await _loadMessages();
      await _loadConversationsList();
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.crmWebChatMessageSent);
        final cid = _selectedConvId;
        if (cid != null && _wsLive) _ws.sendTyping(cid, active: false);
        unawaited(_markVisitorMessagesReadSilently());
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
        context,
        message: t.crmWebChatError(ErrorExtractor.forContext(e, context)),
        isError: true,
      );
      }
    }
  }

  Future<void> _patchConv(Map<String, dynamic> c, {String? status, int? assignedTo, int? leadId, int? personId}) async {
    if (!widget.authStore.canEditCrmWebChatConversations()) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.crmWebChatNoCrmWritePermission, isError: true);
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
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.crmWebChatSaved);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
        context,
        message: t.crmWebChatError(ErrorExtractor.forContext(e, context)),
        isError: true,
      );
      }
    }
  }

  Future<void> _showEditConvSheet(Map<String, dynamic> c) async {
    if (!widget.authStore.canEditCrmWebChatConversations()) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.crmWebChatNoCrmWritePermission, isError: true);
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
        final loc = AppLocalizations.of(ctx);
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
                  Text(loc.crmWebChatEditConversationTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: st, // ignore: deprecated_member_use
                    decoration: InputDecoration(labelText: loc.crmWebChatFieldStatus, border: const OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(value: 'open', child: Text(loc.crmWebChatStatusOpen)),
                      DropdownMenuItem(value: 'pending', child: Text(loc.crmWebChatStatusPending)),
                      DropdownMenuItem(value: 'resolved', child: Text(loc.crmWebChatStatusResolved)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setModal(() => st = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: assign, // ignore: deprecated_member_use
                    decoration: InputDecoration(labelText: loc.crmWebChatAssignTo, border: const OutlineInputBorder()),
                    items: [
                      DropdownMenuItem<int?>(value: null, child: Text(loc.crmWebChatUnassigned)),
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
                    decoration: InputDecoration(
                      labelText: loc.crmWebChatOptionalLeadId,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: personCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: loc.crmWebChatOptionalPersonId,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      int? parseId(String x) {
                        final s = x.trim();
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
                    child: Text(loc.save),
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

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canViewCrmWebChat()) {
      return AccessDeniedPage(message: AppLocalizations.of(context).crmWebChatAccessDenied);
    }

    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenW = MediaQuery.sizeOf(context).width;
    final wide = screenW >= 800;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.crmWebChatPageTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (!wide && _selectedConvId != null && !_mobileShowList) {
              setState(() => _mobileShowList = true);
            } else {
              context.go('/business/${widget.businessId}/crm/dashboard');
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(
                    _wsLive ? Icons.wifi : Icons.wifi_off,
                    size: 20,
                    color: _wsLive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  Text(
                    _socketStatusText(t),
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      height: 1.1,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.crmWebChatRefreshTooltip,
            onPressed: () => _loadAll(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildMainBody(theme, t, cs, wide: wide),
    );
  }

  Widget _buildMainBody(ThemeData theme, AppLocalizations t, ColorScheme cs, {required bool wide}) {
    if (!wide) {
      if (_selectedConvId != null && !_mobileShowList) {
        return _buildThreadPanel(context, theme, cs);
      }
      return _buildConversationsListColumn(
        theme: theme,
        t: t,
        cs: cs,
        width: MediaQuery.sizeOf(context).width,
      );
    }
    return Row(
      children: [
        _buildConversationsListColumn(
          theme: theme,
          t: t,
          cs: cs,
          width: 380,
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedConvId == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      t.crmWebChatSelectConversation,
                      style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              : _buildThreadPanel(context, theme, cs),
        ),
      ],
    );
  }

  Widget _buildConversationsListColumn({
    required ThemeData theme,
    required AppLocalizations t,
    required ColorScheme cs,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _convSearchCtrl,
              onChanged: _onConvSearchChanged,
              decoration: InputDecoration(
                hintText: t.crmWebChatSearchConversationsHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: widget.authStore.canEditCrmWebChatConversations()
                      ? () => unawaited(_onFilterHeaderLongPress(t))
                      : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.crmWebChatFilterStatusLabel,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      if (widget.authStore.canEditCrmWebChatConversations())
                        Icon(
                          Icons.touch_app_outlined,
                          size: 16,
                          color: cs.outline,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.crmWebChatFilterLongPressHint,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 4,
              children: [
                ChoiceChip(
                  label: Text(t.crmWebChatFilterAll),
                  selected: _statusFilter == null,
                  onSelected: (_) async {
                    setState(() => _statusFilter = null);
                    await _persistStatusFilter();
                    await _loadConversationsList(reset: true);
                  },
                ),
                ChoiceChip(
                  label: Text(t.crmWebChatStatusOpen),
                  selected: _statusFilter == 'open',
                  onSelected: (_) async {
                    setState(() => _statusFilter = 'open');
                    await _persistStatusFilter();
                    await _loadConversationsList(reset: true);
                  },
                ),
                ChoiceChip(
                  label: Text(t.crmWebChatStatusPending),
                  selected: _statusFilter == 'pending',
                  onSelected: (_) async {
                    setState(() => _statusFilter = 'pending');
                    await _persistStatusFilter();
                    await _loadConversationsList(reset: true);
                  },
                ),
                ChoiceChip(
                  label: Text(t.crmWebChatStatusResolved),
                  selected: _statusFilter == 'resolved',
                  onSelected: (_) async {
                    setState(() => _statusFilter = 'resolved');
                    await _persistStatusFilter();
                    await _loadConversationsList(reset: true);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onConversationsListScroll,
              child: _conversations.isEmpty
                  ? Center(
                      child: Text(t.crmWebChatNoConversations),
                    )
                  : ListView.builder(
                      itemCount: _conversations.length + (_convHasMore && _loadingMoreConvs ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i == _conversations.length) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final c = _conversations[i] as Map<String, dynamic>;
                        final id = c['id'] as int;
                        final title =
                            '${c['visitor_first_name'] ?? ''} ${c['visitor_last_name'] ?? ''}'.trim();
                        final sub = c['visitor_email']?.toString() ?? '';
                        final ph = c['visitor_phone']?.toString() ?? '';
                        final purl = c['page_url']?.toString().trim() ?? '';
                        final sel = _selectedConvId == id;
                        final lma = c['last_message_at']?.toString() ?? '';
                        return ListTile(
                          selected: sel,
                          title: Text(
                            title.isEmpty ? t.crmWebChatConversationNumber(id) : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              sub,
                              ph,
                              if (purl.isNotEmpty) purl,
                              if (lma.isNotEmpty) lma,
                            ].join(' · '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: SizedBox(
                            width: 112,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    _statusLabel(t, c['status']?.toString()),
                                    style: theme.textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.authStore.canEditCrmWebChatConversations())
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert, size: 20, color: cs.onSurfaceVariant),
                                    padding: EdgeInsets.zero,
                                    onSelected: (v) async {
                                      if (v != 'delete') return;
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(t.crmWebChatDeleteConversation),
                                          content: Text(t.crmWebChatDeleteConversationConfirm),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
                                          ],
                                        ),
                                      );
                                      if (ok == true && mounted) await _deleteConversation(id);
                                    },
                                    itemBuilder: (ctx) => [
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Text(t.crmWebChatDeleteConversation),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          onTap: () => _selectConversation(id),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadPanel(BuildContext context, ThemeData theme, ColorScheme cs) {
    final t = AppLocalizations.of(context);
    final c = _conversations.firstWhere(
      (e) => e is Map && (e)['id'] == _selectedConvId,
      orElse: () => <String, dynamic>{},
    );
    if (c is! Map || c['id'] == null) {
      return Center(child: Text(t.crmWebChatConversationNotFoundRefresh));
    }
    final conv = Map<String, dynamic>.from(c);
    final pageUrl = conv['page_url']?.toString();
    final assignName = _nameForUserId((conv['assigned_to_user_id'] as num?)?.toInt());

    return Column(
      children: [
        if (_loadingMsgs) LinearProgressIndicator(minHeight: 2, color: cs.primary),
        Material(
          color: cs.surfaceContainerHighest,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.crmWebChatVisitorStartPageLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              InkWell(
                                onTap: () async {
                                  final u = Uri.tryParse(pageUrl);
                                  if (u != null && await canLaunchUrl(u)) {
                                    await launchUrl(u, mode: LaunchMode.externalApplication);
                                  }
                                },
                                child: Text(
                                  pageUrl,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        '${conv['visitor_email'] ?? ''}  ·  ${conv['visitor_phone'] ?? ''}  ·  ${t.crmWebChatWidgetLine(_widgetName((conv['widget_id'] as num?)?.toInt()))}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (assignName != null) Text(t.crmWebChatAssigneeLine(assignName), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (widget.authStore.canEditCrmWebChatConversations())
                  FilledButton.tonal(
                    onPressed: () => _showEditConvSheet(conv),
                    child: Text(t.crmWebChatEditConversationButton),
                  ),
                TextButton(
                  onPressed: () => context.push('/business/${widget.businessId}/crm/leads'),
                  child: Text(t.crmWebChatLeads),
                ),
              ],
            ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _msgScroll,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length + (_loadingOlderMsgs ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (_loadingOlderMsgs && i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: Text(t.crmWebChatLoadOlder, style: theme.textTheme.labelSmall),
                  ),
                );
              }
              final mi = i - (_loadingOlderMsgs ? 1 : 0);
              if (mi < 0 || mi >= _messages.length) {
                return const SizedBox.shrink();
              }
              final m = _messages[mi] as Map<String, dynamic>;
              final role = m['sender_role']?.toString() ?? '';
              final body = m['body']?.toString() ?? '';
              final isDeleted = m['is_deleted'] == true;
              final agent = role == 'agent';
              final uid = (m['user_id'] as num?)?.toInt();
              final who = agent
                  ? (uid != null ? (_nameForUserId(uid) ?? t.crmWebChatRoleAgent) : t.crmWebChatRoleAgent)
                  : t.crmWebChatRoleVisitor;
              final file = m['file'];
              return Align(
                alignment: agent ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: isDeleted
                        ? cs.surfaceContainerHighest
                        : (agent ? cs.primaryContainer : cs.secondaryContainer),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (file is Map && file['id'] != null && !isDeleted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => _downloadChatFile(
                              file['id']!.toString(),
                              file['original_name']?.toString() ?? t.crmWebChatFileLabel,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_file, size: 18, color: cs.onPrimaryContainer),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    file['original_name']?.toString() ?? t.crmWebChatFileLabel,
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
                      if (isDeleted)
                        Text(
                          t.crmWebChatMessageDeleted,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else if (body.isNotEmpty)
                        Text(body, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$who  ·  ${_formatMsgTime(m['created_at'])}'
                              '${m['edited_at'] != null ? '  ${t.crmWebChatMessageEditedBadge}' : ''}',
                              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                          if (!isDeleted && !agent)
                            Tooltip(
                              message: _messageHasReadReceipt(m)
                                  ? t.crmWebChatTooltipMessageRead
                                  : t.crmWebChatTooltipMessageSent,
                              child: Icon(
                                Icons.done_all,
                                size: 15,
                                color: _messageHasReadReceipt(m)
                                    ? cs.primary
                                    : cs.onSurfaceVariant.withValues(alpha: 0.75),
                              ),
                            ),
                          if (widget.authStore.canReplyCrmWebChat() && agent && !isDeleted)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: t.crmWebChatEditMessageTitle,
                              onPressed: () => unawaited(_editAgentMessage(m)),
                            ),
                          if (widget.authStore.canDeleteCrmWebChatMessages() && !isDeleted)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                final id = (m['id'] as num?)?.toInt();
                                if (id == null) return;
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(t.crmWebChatDeleteMessage),
                                    content: Text(t.crmWebChatDeleteMessageConfirm),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
                                    ],
                                  ),
                                );
                                if (ok == true && mounted) await _deleteMessage(id);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_peerTyping)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t.crmWebChatPeerTyping,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        if (widget.authStore.canReplyCrmWebChat())
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
                    if (_allowWebChatFileUpload)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: IconButton.filledTonal(
                          tooltip: t.crmWebChatAttachFileTooltip,
                          onPressed: (_selectedConvId == null || _sendingFile) ? null : _pickAndSendAgentFile,
                          icon: _sendingFile
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.attach_file_outlined),
                        ),
                      ),
                    if (_allowWebChatFileUpload) const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _replyCtrl,
                        focusNode: _replyFocus,
                        decoration: InputDecoration(
                          hintText: t.crmWebChatReplyHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sendingFile ? null : _sendReply,
                      child: Text(t.crmWebChatSend),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
