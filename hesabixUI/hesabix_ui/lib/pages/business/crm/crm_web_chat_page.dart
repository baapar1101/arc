import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/pages/business/business_shell_side_nav_scope.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/crm_chat_service.dart';
import 'package:hesabix_ui/services/crm_chat_ws_client.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/pages/business/crm/crm_operator_voice.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
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
  static const double _kSurfaceRadius = 12;
  static const double _kPillRadius = 999;
  static const double _kCompactMobileWidth = 390;
  static const double _kDesktopSidebarWidthFactor = 0.33;
  static const double _kDesktopSidebarMinWidth = 280;
  static const double _kDesktopSidebarMaxWidth = 360;

  EdgeInsets _conversationCardPadding(bool compactMobile) => compactMobile
      ? const EdgeInsets.fromLTRB(10, 8, 6, 8)
      : const EdgeInsets.fromLTRB(12, 10, 8, 10);
  EdgeInsets _statusChipPadding(bool compactMobile) => compactMobile
      ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
      : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  EdgeInsets _composerPadding(bool compactMobile) => EdgeInsets.fromLTRB(
        12,
        compactMobile ? 6 : 8,
        12,
        compactMobile ? 10 : 12,
      );
  EdgeInsets _threadListPadding(bool compactMobile) =>
      EdgeInsets.all(compactMobile ? 10 : 12);
  EdgeInsets _threadHeaderPadding(bool compactMobile) => EdgeInsets.fromLTRB(
        12,
        compactMobile ? 10 : 12,
        12,
        compactMobile ? 10 : 12,
      );
  EdgeInsets _messageBubblePadding(bool compactMobile) => EdgeInsets.symmetric(
        horizontal: compactMobile ? 10 : 12,
        vertical: compactMobile ? 8 : 10,
      );
  TextStyle? _conversationTitleStyle(ThemeData theme, bool compactMobile) =>
      (compactMobile ? theme.textTheme.bodyMedium : theme.textTheme.titleSmall)
          ?.copyWith(fontWeight: FontWeight.w600, height: 1.2);
  TextStyle? _conversationMetaStyle(ThemeData theme, ColorScheme cs) =>
      theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25);
  TextStyle? _conversationTimeStyle(ThemeData theme, ColorScheme cs) =>
      theme.textTheme.labelSmall?.copyWith(
        color: cs.onSurfaceVariant.withValues(alpha: 0.92),
        fontWeight: FontWeight.w500,
      );
  TextStyle? _messageBodyStyle(ThemeData theme) =>
      theme.textTheme.bodyMedium?.copyWith(height: 1.35);
  TextStyle? _messageMetaStyle(ThemeData theme, ColorScheme cs) =>
      theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25);

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
  bool _allowWebChatVoice = false;
  bool _sendingFile = false;
  bool _composerDragOver = false;
  bool _recordingVoice = false;
  final Map<String, Uint8List> _imagePreviewCache = {};
  final OperatorVoiceController _voiceCtrl = createOperatorVoiceController();
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
  VoidCallback? _restoreDesktopRailAfterQuit;

  static int? _intFrom(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString());
  }

  static Map<String, dynamic>? _extraMetadataMap(dynamic v) {
    if (v is! Map) return null;
    return Map<String, dynamic>.from(v);
  }

  (IconData, String)? _visitorDeviceIconAndLabel(Map<String, dynamic>? meta, AppLocalizations t) {
    if (meta == null) return null;
    final dt = (meta['device_type'] ?? '').toString().toLowerCase().trim();
    if (dt.isEmpty) return null;
    if (dt == 'mobile') {
      return (Icons.smartphone, t.crmWebChatVisitorDeviceMobile);
    }
    if (dt == 'tablet') {
      return (Icons.tablet, t.crmWebChatVisitorDeviceTablet);
    }
    if (dt == 'desktop') {
      return (Icons.computer, t.crmWebChatVisitorDeviceDesktop);
    }
    return (Icons.devices, t.crmWebChatVisitorDeviceUnknown);
  }

  @override
  void initState() {
    super.initState();
    _msgScroll.addListener(_onMessageScroll);
    _svc = CrmChatService(apiClient: widget.apiClient);
    _storage = BusinessStorageService(widget.apiClient);
    _replyCtrl.addListener(_onReplyTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shellScope = BusinessShellSideNavScope.readMaybeOf(context);
      if (shellScope?.canControlDesktopRail ?? false) {
        shellScope!.setRailVisible(false);
        final scope = shellScope;
        _restoreDesktopRailAfterQuit = () => scope.setRailVisible(true);
      }
    });
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
    if (cid == null) return;
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

  void _replayAgentTypingOutboundIfAny() {
    final cid = _selectedConvId;
    if (cid == null || !_ws.isAuthenticated) return;
    final text = _replyCtrl.text;
    _typingDebounce?.cancel();
    if (text.trim().isEmpty) {
      _ws.sendTyping(cid, active: false);
      return;
    }
    _ws.sendTyping(cid, active: true);
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _ws.sendTyping(cid, active: false);
    });
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
    final authedOk = await _ws.connect(
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
    if (authedOk) {
      setState(() => _wsLive = true);
      _stopFallback();
      _startBackupPoll();
      if (_selectedConvId != null) {
        _ws.subscribeConversation(_selectedConvId!);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _replayAgentTypingOutboundIfAny();
      });
    } else {
      setState(() => _wsLive = false);
      _stopBackupPoll();
      _startFallback();
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
    final id = _intFrom(c['id']);
    if (id == null) return;
    final idx = _conversations.indexWhere(
      (e) {
        if (e is! Map) return false;
        return _intFrom(e['id']) == id;
      },
    );
    if (idx >= 0) {
      _conversations[idx] = c;
    }
  }

  String _firstCharForAvatar(String? s) {
    if (s == null || s.isEmpty) return '?';
    return s[0].toUpperCase();
  }

  /// نمایش خلاصه از URLهای بسیار بلند: ابتدا/انتها + … وسط (بدون اسکرول افقی).
  String _shortenUrlForDisplay(String url, {int maxChars = 80}) {
    final u = url.trim();
    if (u.length <= maxChars) return u;
    final inner = maxChars - 1;
    final head = (inner * 55 ~/ 100).clamp(24, inner - 16);
    final tail = inner - head;
    if (tail < 8) return '${u.substring(0, inner)}…';
    return '${u.substring(0, head)}…${u.substring(u.length - tail)}';
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
    _restoreDesktopRailAfterQuit?.call();
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
    unawaited(_voiceCtrl.dispose());
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
      bool allowVoice = false;
      try {
        final st = await _svc.getCrmSettings(businessId: widget.businessId);
        allowFiles = st['allow_web_chat_file_upload'] == true;
        allowVoice = st['allow_web_chat_voice'] == true;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _allowWebChatFileUpload = allowFiles;
        _allowWebChatVoice = allowVoice;
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
    }    );
    _loadMessages();
    _ws.subscribeConversation(id);
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

  Widget _buildConnectionChip(ThemeData theme, ColorScheme cs, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_kPillRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _wsLive ? Icons.wifi : Icons.wifi_off,
            size: 16,
            color: _wsLive ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            _socketStatusText(t),
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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

  Future<Uint8List?> _cachedImageThumb(String fileId) async {
    if (_imagePreviewCache.containsKey(fileId)) {
      return _imagePreviewCache[fileId];
    }
    try {
      final bytes = await _storage.downloadFile(
        businessId: widget.businessId,
        fileId: fileId,
      );
      final u = Uint8List.fromList(bytes);
      if (!mounted) return u;
      setState(() => _imagePreviewCache[fileId] = u);
      return u;
    } catch (_) {
      return null;
    }
  }

  Widget _buildMessageAttachment(
    ThemeData theme,
    ColorScheme cs,
    Map<dynamic, dynamic> file,
    AppLocalizations t,
  ) {
    final id = file['id']?.toString() ?? '';
    final name = file['original_name']?.toString() ?? t.crmWebChatFileLabel;
    final mime = (file['mime_type'] ?? '').toString().toLowerCase();
    if (mime.startsWith('image/') && id.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: GestureDetector(
            onTap: () => unawaited(_downloadChatFile(id, name)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
              child: FutureBuilder<Uint8List?>(
                future: _cachedImageThumb(id),
                builder: (ctx, snap) {
                  final b = snap.data;
                  if (b != null && b.isNotEmpty) {
                    return Image.memory(
                      b,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _attachmentFallback(theme, cs, t, id, name),
                    );
                  }
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: cs.surfaceContainerHighest,
                      child: Center(
                        child: snap.connectionState != ConnectionState.done
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
    if (mime.startsWith('audio/')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => unawaited(_downloadChatFile(id, name)),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
              border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.graphic_eq, color: cs.primary),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.download_rounded, size: 18, color: cs.primary),
              ],
            ),
          ),
        ),
      );
    }
    return _attachmentFallback(theme, cs, t, id, name);
  }

  Widget _attachmentFallback(ThemeData theme, ColorScheme cs, AppLocalizations t, String id, String name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => unawaited(_downloadChatFile(id, name)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, size: 18, color: cs.onPrimaryContainer),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.download, size: 16, color: cs.primary),
          ],
        ),
      ),
    );
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

  static bool _looksAudioFileName(String name) {
    final n = name.toLowerCase();
    for (final ext in <String>['.aac', '.webm', '.opus', '.ogg', '.oga', '.mp3', '.m4a', '.wav', '.flac']) {
      if (n.endsWith(ext)) return true;
    }
    return false;
  }

  Future<void> _sendAgentAttachmentBytes(Uint8List bytes, String filename) async {
    final id = _selectedConvId;
    if (id == null || !widget.authStore.canReplyCrmWebChat()) return;
    final t = AppLocalizations.of(context);
    final aud = _looksAudioFileName(filename);
    if (aud) {
      if (!_allowWebChatVoice) {
        SnackBarHelper.show(context, message: t.crmWebChatVoiceDisabledCrm, isError: true);
        return;
      }
    } else {
      if (!_allowWebChatFileUpload) {
        SnackBarHelper.show(context, message: t.crmWebChatFileUploadDisabledCrm, isError: true);
        return;
      }
    }
    setState(() => _sendingFile = true);
    try {
      final up = await _storage.uploadFile(
        businessId: widget.businessId,
        fileBytes: bytes,
        filename: filename.isNotEmpty ? filename : (aud ? 'voice.aac' : 'file'),
        moduleContext: 'crm_web_chat',
        contextId: id.toString(),
      );
      if (!mounted) return;
      final fid = up['file_id']?.toString();
      if (fid == null || fid.isEmpty) {
        throw StateError(t.crmWebChatFileIdMissing);
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
        if (_wsLive) _ws.sendTyping(id, active: false);
        unawaited(_markVisitorMessagesReadSilently());
      }
    } catch (e) {
      if (mounted) {
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

  Future<void> _onComposerDrop(DropDoneDetails detail) async {
    if (detail.files.isEmpty) return;
    final xf = detail.files.first;
    final name = xf.name;
    final bytes = await xf.readAsBytes();
    if (!mounted || bytes.isEmpty) return;
    await _sendAgentAttachmentBytes(Uint8List.fromList(bytes), name);
  }

  Future<void> _toggleOperatorVoice() async {
    if (kIsWeb) {
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).crmWebChatMicUnavailableWeb,
        isError: true,
      );
      return;
    }
    final id = _selectedConvId;
    if (id == null || !widget.authStore.canReplyCrmWebChat() || !_allowWebChatVoice) return;
    if (_sendingFile) return;
    final t = AppLocalizations.of(context);
    try {
      if (!_recordingVoice) {
        final ok = await _voiceCtrl.ensureReady();
        if (!ok) {
          SnackBarHelper.show(context, message: t.crmWebChatError('میکروفون'), isError: true);
          return;
        }
        await _voiceCtrl.startRecording();
        if (mounted) setState(() => _recordingVoice = true);
        return;
      }
      setState(() => _recordingVoice = false);
      final clip = await _voiceCtrl.stopAndRead();
      if (clip == null) return;
      final (blob, fname) = clip;
      await _sendAgentAttachmentBytes(blob, fname);
    } catch (e) {
      if (mounted) {
        setState(() => _recordingVoice = false);
        SnackBarHelper.show(
          context,
          message: t.crmWebChatError(ErrorExtractor.forContext(e, context)),
          isError: true,
        );
      }
    }
  }

  Widget _buildComposerField(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations t,
  ) {
    final canDrop =
        (_allowWebChatFileUpload || _allowWebChatVoice) && !_sendingFile && _selectedConvId != null;
    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _composerDragOver ? cs.primary : Colors.transparent, width: 2),
      ),
      child: TextField(
        controller: _replyCtrl,
        focusNode: _replyFocus,
        decoration: InputDecoration(
          hintText: t.crmWebChatReplyHint,
          helperText: canDrop ? t.crmWebChatComposerDropTarget : null,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        minLines: 1,
        maxLines: 6,
        textInputAction: TextInputAction.newline,
      ),
    );

    if (!canDrop) {
      return field;
    }

    return DropTarget(
      onDragEntered: (_) {
        if (!mounted) return;
        setState(() => _composerDragOver = true);
      },
      onDragExited: (_) {
        if (!mounted) return;
        setState(() => _composerDragOver = false);
      },
      onDragDone: (DropDoneDetails d) {
        if (!mounted) return;
        setState(() => _composerDragOver = false);
        unawaited(_onComposerDrop(d));
      },
      child: field,
    );
  }

  Future<void> _pickAndSendAgentFile() async {
    final id = _selectedConvId;
    if (id == null || !widget.authStore.canReplyCrmWebChat()) {
      return;
    }
    try {
      final pick = await FilePicker.platform.pickFiles(withData: true, type: FileType.any, allowMultiple: false);
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).crmWebChatFileReadFailed,
            isError: true,
          );
        }
        return;
      }
      final name = f.name.isNotEmpty ? f.name : 'file';
      Uint8List u8;
      if (bytes is Uint8List) {
        u8 = bytes;
      } else {
        u8 = Uint8List.fromList(bytes);
      }
      await _sendAgentAttachmentBytes(u8, name);
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
    final id = _intFrom(c['id']);
    if (id == null) return;
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
    final wide = screenW >= 720;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.crmWebChatPageTitle,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
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
    final screenW = MediaQuery.sizeOf(context).width;
    final compactMobile = screenW < _kCompactMobileWidth;
    if (!wide) {
      if (_selectedConvId != null && !_mobileShowList) {
        return _buildThreadPanel(context, theme, cs);
      }
      return _buildConversationsListColumn(
        theme: theme,
        t: t,
        cs: cs,
        width: screenW,
        compactMobile: compactMobile,
      );
    }
    final sidebarW = (screenW * _kDesktopSidebarWidthFactor).clamp(
      _kDesktopSidebarMinWidth,
      _kDesktopSidebarMaxWidth,
    );
    return Row(
      children: [
        _buildConversationsListColumn(
          theme: theme,
          t: t,
          cs: cs,
          width: sidebarW,
          compactMobile: false,
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
    required bool compactMobile,
  }) {
    final titleStyle = _conversationTitleStyle(theme, compactMobile);
    final cardPad = _conversationCardPadding(compactMobile);
    final chipPad = _statusChipPadding(compactMobile);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, compactMobile ? 8 : 10, 12, 2),
            child: Row(
              children: [
                _buildConnectionChip(theme, cs, t),
                const Spacer(),
                IconButton(
                  tooltip: t.crmWebChatRefreshTooltip,
                  visualDensity: compactMobile ? VisualDensity.compact : VisualDensity.standard,
                  onPressed: () => _loadAll(silent: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, compactMobile ? 6 : 8, 12, 6),
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
            padding: EdgeInsets.fromLTRB(12, compactMobile ? 6 : 8, 12, 4),
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
            padding: EdgeInsets.symmetric(horizontal: compactMobile ? 8 : 10),
            child: Wrap(
              spacing: 4,
              children: [
                ChoiceChip(
                  label: Text(t.crmWebChatFilterAll),
                  selected: _statusFilter == null,
                  labelStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  onSelected: (_) async {
                    setState(() => _statusFilter = null);
                    await _persistStatusFilter();
                    await _loadConversationsList(reset: true);
                  },
                ),
                ChoiceChip(
                  label: Text(t.crmWebChatStatusOpen),
                  selected: _statusFilter == 'open',
                  labelStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  onSelected: (_) async {
                    setState(() => _statusFilter = 'open');
                    await _persistStatusFilter();
                    await _loadConversationsList(reset: true);
                  },
                ),
                ChoiceChip(
                  label: Text(t.crmWebChatStatusPending),
                  selected: _statusFilter == 'pending',
                  labelStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  onSelected: (_) async {
                    setState(() => _statusFilter = 'pending');
                    await _persistStatusFilter();
                    await _loadConversationsList(reset: true);
                  },
                ),
                ChoiceChip(
                  label: Text(t.crmWebChatStatusResolved),
                  selected: _statusFilter == 'resolved',
                  labelStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
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
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
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
                        final id = _intFrom(c['id']);
                        if (id == null) {
                          return const SizedBox.shrink();
                        }
                        final title =
                            '${c['visitor_first_name'] ?? ''} ${c['visitor_last_name'] ?? ''}'.trim();
                        final sub = c['visitor_email']?.toString() ?? '';
                        final ph = c['visitor_phone']?.toString() ?? '';
                        final sel = _selectedConvId == id;
                        final lma = c['last_message_at']?.toString() ?? '';
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          elevation: sel ? 1.2 : 0,
                          color: sel ? cs.primaryContainer.withValues(alpha: 0.28) : cs.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_kSurfaceRadius),
                            side: BorderSide(
                              color: sel
                                  ? cs.primary.withValues(alpha: 0.4)
                                  : cs.outlineVariant.withValues(alpha: 0.55),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(_kSurfaceRadius),
                            onTap: () => _selectConversation(id),
                            child: Padding(
                              padding: cardPad,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title.isEmpty ? t.crmWebChatConversationNumber(id) : title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: titleStyle?.copyWith(
                                            letterSpacing: 0.1,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          [sub, ph].where((x) => x.trim().isNotEmpty).join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ) ??
                                              _conversationMetaStyle(theme, cs),
                                        ),
                                        if (lma.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            lma,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ) ??
                                                _conversationTimeStyle(theme, cs),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: chipPad,
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(_kPillRadius),
                                        ),
                                        child: Text(
                                          _statusLabel(t, c['status']?.toString()),
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.1,
                                          ),
                                        ),
                                      ),
                                      if (widget.authStore.canEditCrmWebChatConversations())
                                        PopupMenuButton<String>(
                                          icon: Icon(
                                            Icons.more_vert,
                                            size: compactMobile ? 17 : 18,
                                            color: cs.onSurfaceVariant,
                                          ),
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
                                ],
                              ),
                            ),
                          ),
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
    final compactMobile = MediaQuery.sizeOf(context).width < _kCompactMobileWidth;
    final c = _conversations.firstWhere(
      (e) {
        if (e is! Map) return false;
        return _intFrom(e['id']) == _selectedConvId;
      },
      orElse: () => <String, dynamic>{},
    );
    if (c is! Map || c['id'] == null) {
      return Center(child: Text(t.crmWebChatConversationNotFoundRefresh));
    }
    final conv = Map<String, dynamic>.from(c);
    final pageUrl = conv['page_url']?.toString();
    final assignName = _nameForUserId((conv['assigned_to_user_id'] as num?)?.toInt());
    final visitorName = '${conv['visitor_first_name'] ?? ''} ${conv['visitor_last_name'] ?? ''}'.trim();
    final email = (conv['visitor_email']?.toString() ?? '').trim();
    final phone = (conv['visitor_phone']?.toString() ?? '').trim();
    final extraMeta = _extraMetadataMap(conv['extra_metadata']);
    final visitorIp = (extraMeta?['visitor_ip'] ?? '').toString().trim();
    final deviceUi = _visitorDeviceIconAndLabel(extraMeta, t);
    final metaParts = <String>[
      if (email.isNotEmpty) email,
      if (phone.isNotEmpty) phone,
      if (visitorIp.isNotEmpty) t.crmWebChatVisitorIpLine(visitorIp),
      t.crmWebChatWidgetLine(_widgetName((conv['widget_id'] as num?)?.toInt())),
    ];

    return Column(
      children: [
        if (_loadingMsgs) LinearProgressIndicator(minHeight: 2, color: cs.primary),
        Material(
          color: cs.surfaceContainerLow,
          child: Padding(
            padding: _threadHeaderPadding(compactMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: compactMobile ? 19 : 22,
                      child: Text(
                        _firstCharForAvatar(conv['visitor_first_name']?.toString()),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (deviceUi != null) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: deviceUi.$2,
                        child: Icon(
                          deviceUi.$1,
                          size: 22,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visitorName.isEmpty ? '—' : visitorName,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (pageUrl != null && pageUrl.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              t.crmWebChatVisitorCurrentPageLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Tooltip(
                              message: pageUrl,
                              child: InkWell(
                                onTap: () async {
                                  final u = Uri.tryParse(pageUrl);
                                  if (u != null && await canLaunchUrl(u)) {
                                    await launchUrl(u, mode: LaunchMode.externalApplication);
                                  }
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    _shortenUrlForDisplay(pageUrl),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.primary,
                                      decoration: TextDecoration.underline,
                                      decorationColor: cs.primary.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (metaParts.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              metaParts.join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (assignName != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              t.crmWebChatAssigneeLine(assignName),
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
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
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _msgScroll,
            padding: _threadListPadding(compactMobile),
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
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: _messageBubblePadding(compactMobile),
                  constraints: BoxConstraints(maxWidth: compactMobile ? 420 : 520),
                  decoration: BoxDecoration(
                    color: isDeleted
                        ? cs.surfaceContainerHighest
                        : (agent
                            ? cs.surfaceContainerLow
                            : cs.secondaryContainer.withValues(alpha: 0.45)),
                    border: Border.all(
                      color: agent
                          ? cs.outlineVariant.withValues(alpha: 0.45)
                          : cs.secondary.withValues(alpha: 0.22),
                    ),
                    borderRadius: BorderRadius.circular(_kSurfaceRadius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (file is Map && file['id'] != null && !isDeleted)
                        _buildMessageAttachment(theme, cs, file as Map<dynamic, dynamic>, t),
                      if (isDeleted)
                        Text(
                          t.crmWebChatMessageDeleted,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else if (body.isNotEmpty)
                        Text(body, style: _messageBodyStyle(theme)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$who  ·  ${_formatMsgTime(m['created_at'])}'
                              '${m['edited_at'] != null ? '  ${t.crmWebChatMessageEditedBadge}' : ''}',
                              style: _messageMetaStyle(theme, cs),
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
              padding: _composerPadding(compactMobile),
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
                    if (_allowWebChatVoice)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: kIsWeb
                            ? Tooltip(
                                message: t.crmWebChatMicUnavailableWeb,
                                child: IconButton.filledTonal(
                                  onPressed: null,
                                  icon: Icon(Icons.mic_off_outlined, color: cs.onSurfaceVariant.withValues(alpha: 0.55)),
                                ),
                              )
                            : IconButton.filledTonal(
                                tooltip:
                                    _recordingVoice ? t.crmWebChatMicStopSend : t.crmWebChatMicRecording,
                                style: _recordingVoice
                                    ? IconButton.styleFrom(backgroundColor: cs.errorContainer)
                                    : null,
                                onPressed: (_selectedConvId == null || _sendingFile)
                                    ? null
                                    : _toggleOperatorVoice,
                                icon: Icon(
                                  _recordingVoice ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
                                  color: _recordingVoice ? cs.onErrorContainer : null,
                                ),
                              ),
                      ),
                    if (_allowWebChatVoice) const SizedBox(width: 4),
                    Expanded(child: _buildComposerField(theme, cs, t)),
                    SizedBox(width: compactMobile ? 6 : 8),
                    compactMobile
                        ? IconButton.filled(
                            tooltip: t.crmWebChatSend,
                            onPressed: (_sendingFile || _recordingVoice) ? null : _sendReply,
                            icon: const Icon(Icons.send_rounded),
                          )
                        : FilledButton(
                            onPressed: (_sendingFile || _recordingVoice) ? null : _sendReply,
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
