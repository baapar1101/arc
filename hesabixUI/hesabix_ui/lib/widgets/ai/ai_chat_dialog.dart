import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/business_route_paths.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/voice/voice_chat_controller.dart';
import 'package:hesabix_ui/services/voice/voice_phase.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_design.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_home_view.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_sidebar.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_suggestions.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_memory_sheet.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_knowledge_sheet.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_connectors_sheet.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_thread_view.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_stream_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_l10n.dart';
import 'package:share_plus/share_plus.dart';

/// دسترسی سریع به چت هوش مصنوعی — رابط تمام‌صفحه شبیه صفحه نخست ChatGPT.
class AIChatDialog extends StatefulWidget {
  final int? businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  /// وقتی true باشد داخل [AIChatPage] و go_router نمایش داده می‌شود (بدون دکمه بستن fullscreen).
  final bool embeddedInShell;

  const AIChatDialog({
    super.key,
    this.businessId,
    required this.authStore,
    this.calendarController,
    this.embeddedInShell = false,
  });

  static Future<void> show(
    BuildContext context, {
    required AuthStore authStore,
    int? businessId,
    CalendarController? calendarController,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        fullscreenDialog: true,
        opaque: true,
        transitionDuration: AIChatDesign.fadeTransition,
        reverseTransitionDuration: AIChatDesign.fadeTransition,
        pageBuilder: (context, animation, secondaryAnimation) => AIChatDialog(
          businessId: businessId,
          authStore: authStore,
          calendarController: calendarController,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<AIChatDialog> createState() => _AIChatDialogState();
}

class _AIChatDialogState extends State<AIChatDialog> {
  late final AIService _aiService;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<AIChatSession> _sessions = [];
  AIChatSession? _currentSession;
  List<AIChatMessage> _messages = [];
  final AIChatStreamController _stream = AIChatStreamController();
  bool _pendingWriteApproval = false;
  final TextEditingController _messageCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _sessionsLoading = true;
  bool _messagesLoading = false;
  bool _sending = false;
  Map<String, dynamic>? _availabilityInfo;
  DateTime? _availabilityCheckedAt;
  bool _showCreditWarning = false;
  bool _voiceCollectData = false;
  VoiceChatController? _voice;
  bool _voiceStarting = false;
  VoicePhase _voicePhase = VoicePhase.idle;
  Map<String, dynamic>? _voiceStatusEvent;
  int? _lastVoiceInteractionId;
  CancelToken? _streamCancelToken;
  bool _autoScrollEnabled = true;
  List<AIChatSuggestion> _suggestions = kDefaultAIChatSuggestions;
  List<Map<String, dynamic>> _proactiveAlerts = [];
  final Map<int, int> _messageFeedbackRatings = {};
  String _sessionSearch = '';
  Timer? _sessionSearchDebounce;
  List<Map<String, dynamic>> _attachments = [];

  bool get _isJalali => widget.calendarController?.isJalali ?? true;
  bool get _isGenerating => _sending && _stream.isActive;
  bool get _isHomeMode =>
      !_messagesLoading && _messages.isEmpty && !_stream.isActive && !_sending;

  bool get _canUseAi => _availabilityInfo?['can_use'] as bool? ?? true;

  String? get _aiBlockReason {
    if (_canUseAi) return null;
    final reason = _availabilityInfo?['reason'] as String?;
    switch (reason) {
      case 'NO_ACTIVE_SUBSCRIPTION':
        return 'برای استفاده از هوش مصنوعی، ابتدا یک پلن فعال کنید.';
      case 'QUOTA_EXCEEDED':
        return 'سهمیه توکن شما تمام شده است.';
      case 'INSUFFICIENT_FUNDS':
        return 'موجودی کیف پول برای این درخواست کافی نیست.';
      default:
        return 'در حال حاضر امکان استفاده از دستیار وجود ندارد.';
    }
  }

  @override
  void initState() {
    super.initState();
    ApiClient.bindAuthStore(widget.authStore);
    _aiService = AIService(ApiClient());
    _stream.addListener(_onStreamStateChanged);
    _scrollController.addListener(_onScrollChanged);
    _loadSessions();
    _loadSuggestions();
    if (widget.businessId != null) {
      unawaited(_loadProactiveAlerts());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isHomeMode) _focusNode.requestFocus();
    });
  }

  void _onStreamStateChanged() {
    if (mounted) setState(() {});
  }

  String _resolveToolLabel(String tool, String? toolKey) {
    final l10n = AppLocalizations.of(context);
    return aiToolLabel(l10n, tool, toolKey: toolKey);
  }

  @override
  void dispose() {
    _stream.removeListener(_onStreamStateChanged);
    _stream.dispose();
    _streamCancelToken?.cancel('disposed');
    _sessionSearchDebounce?.cancel();
    _scrollController.removeListener(_onScrollChanged);
    _messageCtrl.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _voice?.dispose();
    super.dispose();
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return (pos.maxScrollExtent - pos.pixels) < 140;
  }

  void _onScrollChanged() {
    final near = _isNearBottom();
    if (near == _autoScrollEnabled) return;
    setState(() => _autoScrollEnabled = near);
  }

  String _formatMessageTime(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (AIChatDesign.isCompactWidth(context)) return time;
    return HesabixDateUtils.formatDateTime(local, _isJalali);
  }

  Future<void> _showMessageActions(AIChatMessage msg) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('کپی'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _copyToClipboard(msg.content);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('اشتراک‌گذاری'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await Share.share(msg.content);
                  },
                ),
                if (msg.role == MessageRole.user)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('ویرایش و ارسال مجدد'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _editMessage(msg, regenerateAfter: true);
                    },
                  ),
                if (msg.role == MessageRole.assistant) ...[
                  ListTile(
                    leading: const Icon(Icons.edit_note_outlined),
                    title: const Text('ویرایش متن پاسخ'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _editMessage(msg, regenerateAfter: false);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('ویرایش و تولید مجدد'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _editMessage(msg, regenerateAfter: true);
                    },
                  ),
                ],
                if (msg.id != null)
                  ListTile(
                    leading: const Icon(Icons.call_split_rounded),
                    title: const Text('شاخه از اینجا'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _forkFromMessage(msg.id!);
                    },
                  ),
                if (msg.role == MessageRole.assistant && msg.id != null) ...[
                  ListTile(
                    leading: const Icon(Icons.thumb_up_outlined),
                    title: const Text('پاسخ مفید بود'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _submitFeedback(msg, 1);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.thumb_down_outlined),
                    title: const Text('پاسخ مفید نبود'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _submitFeedback(msg, -1);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('تولید مجدد پاسخ'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _regenerateLastResponse();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackbar('کپی شد');
  }

  void _stopGenerating({bool showNotice = true}) {
    final token = _streamCancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('user_cancel');
    }
    _streamCancelToken = null;
    final snap = _stream.snapshotForCancel();
    setState(() {
      if (snap != null && _currentSession?.id != null) {
        _messages = List<AIChatMessage>.from(_messages)
          ..add(
            AIChatMessage(
              sessionId: _currentSession!.id!,
              role: MessageRole.assistant,
              content: snap.partialContent,
              functionResults: _stream.functionResultsWithTrace(null),
              createdAt: snap.createdAt,
            ),
          );
      }
      _sending = false;
      _stream.clear();
    });
    if (showNotice) {
      _showSnackbar('تولید پاسخ متوقف شد');
    }
  }

  Future<void> _stopVoiceSession() async {
    if (_voice == null) return;
    setState(() {
      _voiceStarting = true;
      _voicePhase = VoicePhase.idle;
      _voiceStatusEvent = null;
    });
    try {
      await _voice!.dispose();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _voice = null;
      _voiceStarting = false;
      _voicePhase = VoicePhase.idle;
      _voiceStatusEvent = null;
    });
  }

  Future<void> _promptVoiceFeedback(int interactionId) async {
    if (_lastVoiceInteractionId == interactionId) return;
    _lastVoiceInteractionId = interactionId;

    int rating = 4;
    final ctrl = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('کیفیت صدای AI'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'به کیفیت صدای پاسخ AI امتیاز دهید تا در آینده بهتر شود.',
                  ),
                  const SizedBox(height: 12),
                  StatefulBuilder(
                    builder: (context, setLocal) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final star = i + 1;
                        final selected = star <= rating;
                        return IconButton(
                          tooltip: '$star',
                          onPressed: () => setLocal(() => rating = star),
                          icon: Icon(
                            selected ? Icons.star : Icons.star_border,
                            color: selected ? Colors.amber : null,
                          ),
                        );
                      }),
                    ),
                  ),
                  TextField(
                    controller: ctrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'نظر (اختیاری)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('بعداً'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('ثبت'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok) {
      ctrl.dispose();
      return;
    }

    try {
      await _aiService.submitVoiceFeedback(
        interactionId: interactionId,
        rating: rating,
        feedbackText: ctrl.text,
      );
      if (!mounted) return;
      _showSnackbar('بازخورد ثبت شد');
    } catch (e) {
      if (!mounted) return;
      _showError(
        'خطا در ثبت بازخورد: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _loadSuggestions() async {
    if (widget.businessId == null) return;
    try {
      final raw = await _aiService.getChatSuggestions(
        businessId: widget.businessId,
      );
      if (!mounted || raw.isEmpty) return;
      setState(() {
        _suggestions = raw.map(AIChatSuggestion.fromApi).toList();
      });
    } catch (e) {
      debugPrint('[AIChatDialog] suggestions load failed: $e');
    }
  }

  Future<void> _loadProactiveAlerts() async {
    if (widget.businessId == null) return;
    try {
      final alerts = await _aiService.getProactiveAlerts(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() => _proactiveAlerts = alerts);
    } catch (e) {
      debugPrint('[AIChatDialog] proactive alerts load failed: $e');
    }
  }

  void _onSessionSearchChanged(String query) {
    _sessionSearch = query;
    _sessionSearchDebounce?.cancel();
    _sessionSearchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) unawaited(_loadSessions());
    });
  }

  Future<void> _loadSessions() async {
    setState(() => _sessionsLoading = true);
    try {
      final list = await _aiService.listChatSessions(
        businessId: widget.businessId,
        search: _sessionSearch.isNotEmpty ? _sessionSearch : null,
      );
      if (!mounted) return;
      setState(() {
        list.sort((a, b) {
          final aDate =
              a.updatedAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDate =
              b.updatedAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        _sessions = list;
        _sessionsLoading = false;
      });
      await _checkAvailability();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sessionsLoading = false);
      _showError(
        'خطا در بارگذاری گفت‌وگوها: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<bool> _ensureSession() async {
    if (_currentSession != null) return true;
    try {
      final session = await _aiService.createChatSession(
        businessId: widget.businessId,
      );
      if (!mounted) return false;
      setState(() {
        _currentSession = session;
        _messages = [];
      });
      unawaited(_loadSessions());
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showError(
        'خطا در آغاز گفت‌وگو: ${ErrorExtractor.forContext(e, context)}',
      );
      return false;
    }
  }

  Future<void> _selectSession(AIChatSession session) async {
    if (_currentSession?.id == session.id) return;
    if (_isGenerating) {
      _stopGenerating(showNotice: false);
    }
    if (_voice != null) {
      await _stopVoiceSession();
    }
    setState(() {
      _currentSession = session;
      _messages = [];
      _messagesLoading = true;
    });
    try {
      final msgs = await _aiService.getSessionMessages(sessionId: session.id!);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _messagesLoading = false;
      });
      _scrollToBottom(force: true);
      await _checkAvailability();
      unawaited(_loadAttachments());
      if (_messages.isEmpty) {
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _messagesLoading = false);
      _showError(
        'خطا در دریافت پیام‌ها: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _loadAttachments() async {
    final sid = _currentSession?.id;
    if (sid == null) return;
    try {
      final list = await _aiService.listSessionAttachments(sid);
      if (!mounted) return;
      setState(() => _attachments = list);
    } catch (e) {
      debugPrint('[AIChatDialog] attachments load failed: $e');
    }
  }

  Future<void> _pickAndUploadAttachment() async {
    if (!await _ensureSession()) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'txt',
        'md',
        'csv',
        'json',
        'pdf',
        'log',
        'xml',
        'html',
        'htm',
      ],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showError('فایل خالی است یا قابل خواندن نیست');
      return;
    }
    try {
      await _aiService.uploadSessionAttachment(
        sessionId: _currentSession!.id!,
        filename: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      _showSnackbar('پیوست اضافه شد');
      await _loadAttachments();
    } catch (e) {
      if (!mounted) return;
      _showError(
        'آپلود پیوست ناموفق: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _openMemorySheet() async {
    await showAIChatMemorySheet(
      context: context,
      aiService: _aiService,
      businessId: widget.businessId,
    );
  }

  Future<void> _openMessageSearch() async {
    final sid = _currentSession?.id;
    if (sid == null) return;
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> hits = [];
    bool searching = false;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> runSearch(String q) async {
              if (q.trim().length < 2) {
                setSheetState(() => hits = []);
                return;
              }
              setSheetState(() => searching = true);
              try {
                final r = await _aiService.searchSessionMessages(
                  sessionId: sid,
                  query: q.trim(),
                );
                setSheetState(() => hits = r);
              } catch (e) {
                SnackBarHelper.show(
                  context,
                  message: ErrorExtractor.forContext(e, context),
                  isError: true,
                );
              } finally {
                setSheetState(() => searching = false);
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'جستجو در گفت‌وگو',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'عبارت جستجو…',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: runSearch,
                  ),
                  const SizedBox(height: 12),
                  if (searching)
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (hits.isEmpty)
                    Text(
                      'نتیجه‌ای نیست',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: hits.length,
                        itemBuilder: (context, i) {
                          final h = hits[i];
                          final role = h['role'] as String? ?? '';
                          final content = h['content'] as String? ?? '';
                          return ListTile(
                            title: Text(
                              content.length > 120
                                  ? '${content.substring(0, 120)}…'
                                  : content,
                            ),
                            subtitle: Text(role == 'user' ? 'شما' : 'دستیار'),
                            onTap: () => Navigator.pop(ctx),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
    searchCtrl.dispose();
  }

  bool get _availabilityFresh {
    if (_availabilityCheckedAt == null) return false;
    return DateTime.now().difference(_availabilityCheckedAt!) <
        const Duration(minutes: 2);
  }

  Future<void> _checkAvailability({int estimatedTokens = 1000}) async {
    try {
      final availability = await _aiService.checkAvailability(
        businessId: widget.businessId,
        estimatedTokens: estimatedTokens,
      );
      if (!mounted) return;
      setState(() {
        _availabilityInfo = availability;
        _availabilityCheckedAt = DateTime.now();
        final details = availability['details'] as Map<String, dynamic>?;
        final subscription = details?['subscription'] as Map<String, dynamic>?;
        final usagePercentage = subscription?['usage_percentage'] as num?;
        _showCreditWarning = usagePercentage != null && usagePercentage >= 80;
      });
    } catch (e) {
      debugPrint('[AIChatDialog] Error checking availability: $e');
    }
  }

  /// چک اعتبار فقط وقتی کش منقضی شده یا قبلاً ناموفق بوده.
  Future<bool> _ensureCanSend(String content) async {
    if (_availabilityFresh &&
        (_availabilityInfo?['can_use'] as bool? ?? false)) {
      return true;
    }
    try {
      final availability = await _aiService.checkAvailability(
        businessId: widget.businessId,
        estimatedTokens: content.length * 2,
      );
      if (!mounted) return false;
      _availabilityInfo = availability;
      _availabilityCheckedAt = DateTime.now();
      if (!(availability['can_use'] as bool? ?? false)) {
        _showDetailedError(availability);
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[AIChatDialog] Error checking availability before send: $e');
      return true;
    }
  }

  void _scheduleSessionsRefreshForTitle() {
    unawaited(_loadSessions());
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) unawaited(_loadSessions());
    });
  }

  Future<void> _goToHome() async {
    if (_isGenerating) _stopGenerating(showNotice: false);
    if (_voice != null) await _stopVoiceSession();
    if (!mounted) return;
    setState(() {
      _currentSession = null;
      _messages = [];
      _messagesLoading = false;
      _stream.clear();
      _attachments = [];
    });
    _messageCtrl.clear();
    _focusNode.requestFocus();
  }

  Future<void> _startNewConversation() => _goToHome();

  Future<void> _deleteSession(AIChatSession session) async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف گفت‌وگو'),
            content: const Text('آیا از حذف این گفت‌وگو مطمئن هستید؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('لغو'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    try {
      await _aiService.deleteChatSession(session.id!);
      if (!mounted) return;
      _showSnackbar('گفت‌وگو حذف شد');
      final wasCurrent = _currentSession?.id == session.id;
      await _loadSessions();
      if (!mounted) return;
      if (wasCurrent) {
        await _goToHome();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(
        'حذف گفت‌وگو با خطا مواجه شد: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _onSuggestionSelected(AIChatSuggestion suggestion) async {
    _messageCtrl.text = suggestion.prompt;
    await _sendMessage();
  }

  Future<void> _editMessage(
    AIChatMessage msg, {
    required bool regenerateAfter,
  }) async {
    if (_sending || _currentSession?.id == null || msg.id == null) return;
    final ctrl = TextEditingController(text: msg.content);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویرایش پیام'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'متن جدید…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('ارسال'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newText == null || newText.isEmpty) return;

    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

    if (!regenerateAfter) {
      try {
        await _aiService.editChatMessage(
          sessionId: _currentSession!.id!,
          messageId: msg.id!,
          content: newText,
          regenerateAfter: false,
        );
        if (!mounted) return;
        setState(() {
          _messages[idx] = AIChatMessage(
            id: msg.id,
            sessionId: msg.sessionId,
            role: msg.role,
            content: newText,
            createdAt: msg.createdAt,
            functionCalls: msg.functionCalls,
            functionResults: msg.functionResults,
          );
        });
        _showSnackbar('پیام به‌روزرسانی شد');
      } catch (e) {
        if (!mounted) return;
        _showError('ویرایش ناموفق: ${ErrorExtractor.forContext(e, context)}');
      }
      return;
    }

    setState(() {
      if (msg.role == MessageRole.user) {
        _messages = List<AIChatMessage>.from(_messages.sublist(0, idx + 1));
        _messages[idx] = AIChatMessage(
          id: msg.id,
          sessionId: msg.sessionId,
          role: MessageRole.user,
          content: newText,
          createdAt: msg.createdAt,
        );
      } else {
        _messages = List<AIChatMessage>.from(_messages.sublist(0, idx));
      }
      _pendingWriteApproval = false;
      _stream.begin(phase: 'connecting');
      _sending = true;
    });

    await _runAssistantStream(
      (token) => _aiService.editUserMessageStream(
        sessionId: _currentSession!.id!,
        messageId: msg.id!,
        content: newText,
        regenerateAfter: true,
        cancelToken: token,
        onComplete: (_, __) {},
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _sending = false;
            _stream.clear();
          });
          _showError(
            'ویرایش ناموفق: ${ErrorExtractor.forContext(error, context)}',
          );
        },
      ),
      errorLabel: 'ویرایش',
    );
  }

  Future<void> _forkFromMessage(int upToMessageId) async {
    if (_currentSession?.id == null) return;
    try {
      final data = await _aiService.forkChatSession(
        sessionId: _currentSession!.id!,
        upToMessageId: upToMessageId,
      );
      final sessionJson = data['session'] as Map<String, dynamic>?;
      final newId = sessionJson?['id'] as int?;
      if (newId == null) return;
      await _loadSessions();
      if (!mounted) return;
      final matches = _sessions.where((s) => s.id == newId);
      if (matches.isNotEmpty) {
        await _selectSession(matches.first);
        _showSnackbar('شاخهٔ گفت‌وگو باز شد');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('شاخه‌سازی ناموفق: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _exportConversation() async {
    if (_currentSession?.id == null) return;
    try {
      final data = await _aiService.exportChatSession(_currentSession!.id!);
      final md = data['markdown'] as String? ?? '';
      if (md.isEmpty) {
        _showSnackbar('گفت‌وگو خالی است');
        return;
      }
      await Share.share(md, subject: data['title'] as String?);
    } catch (e) {
      if (!mounted) return;
      _showError('خروجی ناموفق: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  void _openKnowledgeSheet() {
    showAIChatKnowledgeSheet(
      context: context,
      aiService: _aiService,
      businessId: widget.businessId,
    );
  }

  void _openConnectorsSheet() {
    showAIChatConnectorsSheet(
      context: context,
      aiService: _aiService,
      businessId: widget.businessId,
    );
  }

  Future<void> _submitFeedback(AIChatMessage msg, int rating) async {
    if (_currentSession?.id == null || msg.id == null) return;
    try {
      await _aiService.submitMessageFeedback(
        sessionId: _currentSession!.id!,
        messageId: msg.id!,
        rating: rating,
      );
      if (!mounted) return;
      setState(() => _messageFeedbackRatings[msg.id!] = rating);
      _showSnackbar(rating > 0 ? 'ممنون از بازخورد مثبت' : 'بازخورد ثبت شد');
    } catch (e) {
      if (!mounted) return;
      _showError(
        'ثبت بازخورد ناموفق: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _runAssistantStream(
    Stream<AIStreamChunk> Function(CancelToken cancelToken) streamFactory, {
    String errorLabel = 'پاسخ',
  }) async {
    _streamCancelToken?.cancel('replaced');
    final cancelToken = CancelToken();
    _streamCancelToken = cancelToken;
    try {
      var accumulatedContent = '';
      Object? finalFunctionCalls;
      Object? finalFunctionResults;
      int? assistantMessageId;

      await for (final chunk in streamFactory(cancelToken)) {
        if (chunk.error != null) return;
        _stream.applyChunk(chunk, resolveToolLabel: _resolveToolLabel);
        if (chunk.contentDelta != null && chunk.contentDelta!.isNotEmpty) {
          accumulatedContent += chunk.contentDelta!;
        }
        if (chunk.done) {
          finalFunctionCalls = chunk.functionCalls;
          finalFunctionResults = chunk.functionResults;
          assistantMessageId = chunk.messageId;
          _stream.mergeAgentTraceFromDone(chunk.agentTrace);
          break;
        }
        if (_stream.updateAccumulatedContent(accumulatedContent, chunk)) {
          _scrollToBottom();
        }
      }

      if (!mounted) return;
      setState(() {
        if (accumulatedContent.isNotEmpty ||
            _stream.toolActivities.isNotEmpty ||
            _stream.traceSteps.isNotEmpty) {
          _messages = List<AIChatMessage>.from(_messages)
            ..add(
              AIChatMessage(
                id: assistantMessageId,
                sessionId: _currentSession!.id!,
                role: MessageRole.assistant,
                content: accumulatedContent,
                functionCalls: finalFunctionCalls,
                functionResults: _stream.functionResultsWithTrace(
                  finalFunctionResults,
                ),
                createdAt: _stream.timestamp,
              ),
            );
        }
        _pendingWriteApproval = _stream.toolActivities.any(
          (t) => t.approvalRequired,
        );
        _stream.clear();
        _sending = false;
      });
      _scrollToBottom(force: true);
      _scheduleSessionsRefreshForTitle();
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _stream.clear();
      });
      _showError(
        '$errorLabel ناموفق: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (_streamCancelToken == cancelToken) {
        _streamCancelToken = null;
      }
    }
  }

  Future<void> _regenerateLastResponse() async {
    if (_sending || _currentSession?.id == null) return;
    if (_messages.isEmpty) return;
    final last = _messages.last;
    if (last.role != MessageRole.assistant) {
      _showSnackbar('آخرین پیام باید از دستیار باشد');
      return;
    }

    setState(() {
      _messages = List<AIChatMessage>.from(_messages)..removeLast();
      _pendingWriteApproval = false;
      _stream.begin(phase: 'connecting');
      _sending = true;
    });

    await _runAssistantStream(
      (token) => _aiService.regenerateLastResponseStream(
        sessionId: _currentSession!.id!,
        cancelToken: token,
        onComplete: (_, __) {},
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _sending = false;
            _stream.clear();
          });
          _showError(
            'تولید مجدد ناموفق: ${ErrorExtractor.forContext(error, context)}',
          );
        },
      ),
      errorLabel: 'تولید مجدد',
    );
  }

  Future<void> _confirmWriteApproval() async {
    if (_sending || !_pendingWriteApproval) return;
    await _sendMessage(
      contentOverride:
          'کاربر عملیات پیشنهادی را تأیید کرد. لطفاً همان عملیات را اجرا کن.',
      approveWrites: true,
      skipUserBubble: true,
    );
  }

  Future<void> _sendMessage({
    String? contentOverride,
    bool approveWrites = false,
    bool skipUserBubble = false,
  }) async {
    if (_voice != null) {
      _showSnackbar(AppLocalizations.of(context).aiVoiceTextBlockedWhileActive);
      return;
    }
    if (_sending) return;
    final content = (contentOverride ?? _messageCtrl.text).trim();
    if (content.isEmpty) return;

    if (!skipUserBubble) {
      _messageCtrl.clear();
    }

    setState(() => _sending = true);
    _scrollToBottom(force: true);

    if (!await _ensureSession()) {
      if (!mounted) return;
      setState(() => _sending = false);
      return;
    }

    if (!await _ensureCanSend(content)) {
      if (!mounted) return;
      setState(() => _sending = false);
      return;
    }

    if (!skipUserBubble) {
      final userMessage = AIChatMessage(
        sessionId: _currentSession!.id!,
        role: MessageRole.user,
        content: content,
        createdAt: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _messages = List<AIChatMessage>.from(_messages)..add(userMessage);
      });
    }

    if (!mounted) return;
    setState(() {
      _stream.begin(phase: 'connecting');
      _sending = true;
    });

    Map<String, dynamic>? finalUsage;
    await _runAssistantStream(
      (cancelToken) => _aiService.sendMessageStream(
        sessionId: _currentSession!.id!,
        content: content,
        approveWrites: approveWrites,
        onComplete: (usage, messageId) {
          finalUsage = usage;
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _sending = false;
            _stream.clear();
          });
          _showError(
            'ارسال پیام ناموفق بود: ${ErrorExtractor.forContext(error, context)}',
          );
        },
        cancelToken: cancelToken,
      ),
      errorLabel: 'ارسال پیام',
    );
    if (!mounted) return;
    if (finalUsage != null && _messages.isNotEmpty) {
      final last = _messages.last;
      if (last.role == MessageRole.assistant) {
        setState(() {
          final idx = _messages.length - 1;
          _messages[idx] = AIChatMessage(
            id: last.id,
            sessionId: last.sessionId,
            role: last.role,
            content: last.content,
            functionCalls: last.functionCalls,
            functionResults: last.functionResults,
            tokensUsed: finalUsage?['total_tokens'] as int? ?? last.tokensUsed,
            createdAt: last.createdAt,
          );
        });
      }
    }
  }

  void _setVoicePhase(VoicePhase phase, {Map<String, dynamic>? statusEvent}) {
    if (!mounted) return;
    setState(() {
      _voicePhase = phase;
      if (statusEvent != null) {
        _voiceStatusEvent = statusEvent;
      }
    });
  }

  void _handleVoiceServerEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'ready':
      case 'reconnected':
        _setVoicePhase(VoicePhase.listening);
        return;
      case 'started':
        _setVoicePhase(VoicePhase.listening);
        final tts = event['tts'] as Map<String, dynamic>?;
        if (tts?['dummy_warning'] == true) {
          _showSnackbar(
            AppLocalizations.of(context).aiVoiceDummyTtsWarning,
          );
        }
        return;
      case 'speech_start':
        _setVoicePhase(VoicePhase.listening);
        return;
      case 'speech_end':
      case 'stt_started':
        _setVoicePhase(VoicePhase.processing, statusEvent: event);
        return;
      case 'voice_status':
        final phase = event['phase'] as String?;
        if (phase == 'speaking') {
          _setVoicePhase(VoicePhase.speaking, statusEvent: event);
        } else if (phase == 'listening') {
          _setVoicePhase(VoicePhase.listening, statusEvent: event);
        } else {
          _setVoicePhase(VoicePhase.processing, statusEvent: event);
        }
        return;
      case 'transcript_final':
        _setVoicePhase(VoicePhase.processing, statusEvent: event);
        break;
      case 'assistant_text_delta':
        _setVoicePhase(VoicePhase.speaking, statusEvent: event);
        break;
      case 'assistant_done':
        _setVoicePhase(VoicePhase.listening, statusEvent: event);
        break;
      case 'error':
        _setVoicePhase(VoicePhase.error, statusEvent: event);
        break;
      default:
        break;
    }
  }

  Future<void> _toggleVoice() async {
    if (!await _ensureSession()) return;
    if (_voiceStarting || _voice != null) return;

    setState(() {
      _voiceStarting = true;
      _voicePhase = VoicePhase.connecting;
      _voiceStatusEvent = null;
    });
    final ready = Completer<void>();
    bool gotReady = false;
    final controller = VoiceChatController(
      sessionId: _currentSession!.id!,
      collectDataOptIn: _voiceCollectData,
      onEvent: (event) {
        final type = event['type'] as String?;
        _handleVoiceServerEvent(event);
        if (type == 'ready' || type == 'started') {
          if (!gotReady) {
            gotReady = true;
            if (!ready.isCompleted) ready.complete();
          }
          return;
        }
        if (type == 'transcript_final') {
          final text = (event['text'] as String?)?.trim() ?? '';
          if (text.isEmpty) return;
          final userMsg = AIChatMessage(
            sessionId: _currentSession!.id!,
            role: MessageRole.user,
            content: text,
            createdAt: DateTime.now(),
          );
          setState(() {
            _messages = List<AIChatMessage>.from(_messages)..add(userMsg);
          });
          _scrollToBottom();
          return;
        }
        if (type == 'assistant_text_delta') {
          final delta = event['text'] as String? ?? '';
          if (delta.isEmpty) return;
          setState(() {
            _stream.content = (_stream.content ?? '') + delta;
            _stream.timestamp ??= DateTime.now();
          });
          _scrollToBottom();
          return;
        }
        if (type == 'assistant_done') {
          final text = (event['text'] as String?) ?? '';
          final usage = event['usage'] as Map<String, dynamic>?;
          final interactionId = event['interaction_id'] as int?;
          final inputTokens = usage?['input_tokens'] as int? ?? 0;
          final outputTokens = usage?['output_tokens'] as int? ?? 0;
          final totalTokens = usage?['total_tokens'] as int? ??
              (inputTokens + outputTokens);
          setState(() {
            if (text.trim().isNotEmpty) {
              _messages = List<AIChatMessage>.from(_messages)
                ..add(
                  AIChatMessage(
                    sessionId: _currentSession!.id!,
                    role: MessageRole.assistant,
                    content: text,
                    tokensUsed: totalTokens,
                    createdAt: _stream.timestamp ?? DateTime.now(),
                  ),
                );
            }
            _stream.clear();
          });
          _scrollToBottom();
          if (interactionId != null) {
            _promptVoiceFeedback(interactionId);
          }
          return;
        }
        if (type == 'error') {
          final errorCode = event['error'] as String?;
          final errorMessage = event['message'] as String? ?? 'خطای نامشخص';
          if (!gotReady && !ready.isCompleted) {
            ready.completeError(errorMessage);
          }
          if (errorCode == 'SESSION_TIMEOUT' ||
              errorCode == 'INACTIVITY_TIMEOUT') {
            _showError(
              'جلسه صوتی به دلیل timeout بسته شد. لطفاً دوباره تلاش کنید.',
            );
            _stopVoiceSession();
          } else if (errorCode == 'VOICE_DEPS_MISSING' ||
              errorCode == 'WEBM_NOT_SUPPORTED') {
            _showError(errorMessage);
            _stopVoiceSession();
          } else if (errorCode == 'STT_FAILED') {
            _showError('خطا در تشخیص گفتار: $errorMessage');
            _setVoicePhase(VoicePhase.listening);
          } else if (errorCode == 'EMPTY_TRANSCRIPT') {
            _setVoicePhase(VoicePhase.listening);
            _showError('متن قابل تشخیص نیست. لطفاً دوباره تلاش کنید.');
          } else if (errorCode == 'NO_ACTIVE_SUBSCRIPTION' ||
              errorCode == 'QUOTA_EXCEEDED' ||
              errorCode == 'INSUFFICIENT_FUNDS' ||
              errorCode == 'AVAILABILITY_CHECK_FAILED') {
            _showError(errorMessage);
            _stopVoiceSession();
          } else if (errorCode == 'FORBIDDEN') {
            _showError('شما به این کسب‌وکار دسترسی ندارید.');
            _stopVoiceSession();
          } else {
            _showError('خطا: $errorMessage');
          }
        }
      },
      onError: (msg) {
        if (!mounted) return;
        _showError(msg);
      },
    );

    try {
      await controller.start();
      if (!mounted) return;
      setState(() {
        _voice = controller;
        _voiceStarting = false;
      });
      try {
        await ready.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (_) {}
      if (!mounted) return;
      await _voice!.startRecording();
      if (!mounted) return;
      setState(() => _voicePhase = VoicePhase.listening);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceStarting = false;
        _voicePhase = VoicePhase.idle;
      });
      _showError(
        'خطا در شروع مکالمه صوتی: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!force && !_autoScrollEnabled) return;
      if (_scrollController.hasClients) {
        final target = _scrollController.position.maxScrollExtent;
        final current = _scrollController.position.pixels;
        final delta = (target - current).abs();
        if (delta > 1200) {
          _scrollController.jumpTo(target);
        } else {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _navigateToSubscription() {
    final bid = widget.businessId;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    if (bid == null) return;
    try {
      final prefix = BusinessRoutePaths.prefixFromRouterState(router.state);
      router.go('$prefix/ai/subscription');
    } catch (_) {
      router.go('/business/$bid/tab0/ai/subscription');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    SnackBarHelper.showError(context, message: message);
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    SnackBarHelper.show(context, message: message);
  }

  void _showDetailedError(Map<String, dynamic> errorData) {
    final reason = errorData['reason'] as String?;
    final details = errorData['details'] as Map<String, dynamic>?;

    String title;
    String message;
    List<Widget> actions = [];

    switch (reason) {
      case 'NO_ACTIVE_SUBSCRIPTION':
        title = 'نیاز به اشتراک';
        message = 'برای استفاده از هوش مصنوعی، ابتدا یک پلن را انتخاب کنید.';
        final suggestions =
            (details?['suggestions'] as List?)?.cast<String>() ?? [];
        if (suggestions.isNotEmpty) message += '\n\n${suggestions.join('\n')}';
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToSubscription();
            },
            child: const Text('مشاهده پلن‌ها'),
          ),
        ];
        break;
      case 'QUOTA_EXCEEDED':
        final subscription = details?['subscription'] as Map<String, dynamic>?;
        final tokensUsed = subscription?['tokens_used'] as int? ?? 0;
        final tokensLimit = subscription?['tokens_limit'] as int? ?? 0;
        title = 'سهمیه تمام شده';
        message =
            'شما ${tokensUsed.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} از ${tokensLimit.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} توکن خود را استفاده کرده‌اید.';
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToSubscription();
            },
            child: const Text('ارتقا پلن'),
          ),
        ];
        break;
      case 'INSUFFICIENT_FUNDS':
        final wallet = details?['wallet'] as Map<String, dynamic>?;
        final balance = wallet?['balance'] as num? ?? 0;
        final estimatedCost = wallet?['estimated_cost'] as num? ?? 0;
        title = 'موجودی کیف پول ناکافی';
        message =
            'موجودی: ${balance.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} ریال\n'
            'هزینه تخمینی: ${estimatedCost.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} ریال';
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ];
        break;
      default:
        title = 'خطا';
        message = details?['message'] as String? ?? 'خطای نامشخص';
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ];
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: actions,
      ),
    );
  }

  Future<void> _openVoiceSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('تنظیمات', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('بهبود کیفیت صدا'),
                  subtitle: const Text(
                    'با ارسال داده‌های ناشناس به بهبود تجربه صوتی کمک کنید.',
                  ),
                  value: _voiceCollectData,
                  onChanged: (v) => setState(() => _voiceCollectData = v),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openHistory() {
    if (AIChatDesign.showPersistentSidebar(context)) return;
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final persistentSidebar = AIChatDesign.showPersistentSidebar(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.colorScheme.surface,
      endDrawer: persistentSidebar
          ? null
          : AIChatHistoryDrawer(
              sessions: _sessions,
              currentSession: _currentSession,
              loading: _sessionsLoading,
              isJalali: _isJalali,
              onNewChat: _startNewConversation,
              onSelectSession: _selectSession,
              onDeleteSession: _deleteSession,
              onSearch: _onSessionSearchChanged,
            ),
      body: Container(
        decoration: AIChatDesign.pageBackground(theme, isDark: isDark),
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (persistentSidebar)
                AIChatSidebar(
                  sessions: _sessions,
                  currentSession: _currentSession,
                  loading: _sessionsLoading,
                  isJalali: _isJalali,
                  onNewChat: _startNewConversation,
                  onSelectSession: _selectSession,
                  onDeleteSession: _deleteSession,
                  onSearch: _onSessionSearchChanged,
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAppBar(theme),
                    if (_showCreditWarning) _buildCreditWarning(theme),
                    if (_pendingWriteApproval && !_sending)
                      _buildWriteApprovalBanner(theme),
                    if (_attachments.isNotEmpty && !_isHomeMode)
                      _buildAttachmentsBar(theme),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: AIChatDesign.layoutTransition,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _isHomeMode
                            ? AIChatHomeView(
                                key: const ValueKey('home'),
                                messageController: _messageCtrl,
                                focusNode: _focusNode,
                                sending: _sending,
                                disabled: _sessionsLoading,
                                voiceStarting: _voiceStarting,
                                voiceActive: _voice != null,
                                voicePhase: _voicePhase,
                                voiceStatusEvent: _voiceStatusEvent,
                                canUseAi: _canUseAi,
                                blockReason: _aiBlockReason,
                                onSend: () => _sendMessage(),
                                onMic: _toggleVoice,
                                onStopVoice: _stopVoiceSession,
                                onSuggestionSelected: _onSuggestionSelected,
                                suggestions: _suggestions,
                                proactiveAlerts: _proactiveAlerts,
                                onAlertAction: (prompt) {
                                  _messageCtrl.text = prompt;
                                  unawaited(_sendMessage());
                                },
                                onUpgradePlan: widget.businessId != null
                                    ? _navigateToSubscription
                                    : null,
                              )
                            : AIChatThreadView(
                                key: ValueKey('thread-${_currentSession?.id}'),
                                messages: _messages,
                                streamingContent: _stream.content,
                                streamingToolActivities: _stream.toolActivities,
                                streamingTraceSteps: _stream.traceSteps,
                                streamingStatusPhase: _stream.statusPhase,
                                streamingStatusStep: _stream.statusStep,
                                streamingIteration: _stream.iteration,
                                streamingMaxIterations: _stream.maxIterations,
                                streamingElapsedSeconds:
                                    _stream.elapsedSeconds > 0
                                    ? _stream.elapsedSeconds
                                    : null,
                                streamingTimestamp: _stream.timestamp,
                                messageFeedbackRatings: _messageFeedbackRatings,
                                onCopyMessage: _copyToClipboard,
                                onFeedback: _submitFeedback,
                                onRegenerateLast: _regenerateLastResponse,
                                lastAssistantMessageId:
                                    _messages.isNotEmpty &&
                                        _messages.last.role ==
                                            MessageRole.assistant
                                    ? _messages.last.id
                                    : null,
                                contextUsageRatio: _stream.contextUsageRatio,
                                contextUsagePercent: _stream.contextUsagePercent,
                                contextHistorySummarized:
                                    _stream.contextHistorySummarized,
                                messagesLoading: _messagesLoading,
                                sending: _sending,
                                disabled: !_canUseAi,
                                voiceStarting: _voiceStarting,
                                voiceActive: _voice != null,
                                voicePhase: _voicePhase,
                                voiceStatusEvent: _voiceStatusEvent,
                                showScrollToBottom: !_autoScrollEnabled,
                                isGenerating: _isGenerating,
                                scrollController: _scrollController,
                                messageController: _messageCtrl,
                                focusNode: _focusNode,
                                formatTime: _formatMessageTime,
                                onSend: () => _sendMessage(),
                                onMic: _toggleVoice,
                                onStopVoice: _stopVoiceSession,
                                onStopGenerating: _stopGenerating,
                                onScrollToBottom: () =>
                                    _scrollToBottom(force: true),
                                onMessageLongPress: _showMessageActions,
                                onAttach: _pickAndUploadAttachment,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme) {
    final scheme = theme.colorScheme;
    final compact = AIChatDesign.isCompactWidth(context);
    final showHistoryBtn = !AIChatDesign.showPersistentSidebar(context);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 6),
        child: Row(
          children: [
            if (showHistoryBtn)
              IconButton(
                tooltip: 'گفت‌وگوها',
                onPressed: _openHistory,
                icon: const Icon(Icons.menu_rounded),
              ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    scheme.primary,
                    scheme.tertiary.withValues(alpha: 0.92),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isHomeMode
                        ? 'دستیار هوشمند حسابیکس'
                        : (_currentSession?.title ?? 'گفت‌وگو'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _isGenerating
                        ? 'در حال تحلیل و آماده‌سازی پاسخ'
                        : 'تحلیل مالی، گزارش و راهنمایی عملیاتی',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_isGenerating) ...[
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _stopGenerating,
                icon: Icon(Icons.stop_circle_outlined, color: scheme.error),
                label: const Text('توقف'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: scheme.error,
                ),
              ),
            ],
            if (!compact)
              TextButton.icon(
                onPressed: _startNewConversation,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('جدید'),
              )
            else
              IconButton(
                tooltip: 'گفت‌وگوی جدید',
                onPressed: _startNewConversation,
                icon: const Icon(Icons.add_comment_outlined),
              ),
            _AiMoreMenu(
              isHomeMode: _isHomeMode,
              hasSession: _currentSession != null,
              hasBusiness: widget.businessId != null,
              onSearch: _openMessageSearch,
              onMemory: _openMemorySheet,
              onExport: _exportConversation,
              onConnectors: _openConnectorsSheet,
              onKnowledge: _openKnowledgeSheet,
              onVoiceSettings: _openVoiceSettings,
            ),
            if (widget.embeddedInShell)
              IconButton(
                tooltip: 'بازگشت',
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded),
              )
            else
              IconButton(
                tooltip: 'بستن',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsBar(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final att in _attachments)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: InputChip(
                  label: Text(
                    att['filename'] as String? ?? 'فایل',
                    style: theme.textTheme.labelSmall,
                  ),
                  avatar: const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 18,
                  ),
                  onDeleted: () async {
                    final id = att['id'] as int?;
                    final sid = _currentSession?.id;
                    if (id == null || sid == null) return;
                    try {
                      await _aiService.deleteSessionAttachment(
                        sessionId: sid,
                        attachmentId: id,
                      );
                      await _loadAttachments();
                    } catch (e) {
                      if (!mounted) return;
                      _showError(ErrorExtractor.forContext(e, context));
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWriteApprovalBanner(ThemeData theme) {
    final scheme = theme.colorScheme;
    // جمع‌آوری عملیات‌های در انتظار تأیید از آخرین پیام
    final pendingOps = <Map<String, dynamic>>[];
    if (_messages.isNotEmpty) {
      final lastMsg = _messages.last;
      final fnResults = lastMsg.functionResults;
      if (fnResults is Map) {
        for (final entry in fnResults.entries) {
          final val = entry.value;
          if (val is Map && val['error'] == 'APPROVAL_REQUIRED') {
            pendingOps.add(Map<String, dynamic>.from(val));
          }
        }
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    color: scheme.tertiary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'عملیات زیر نیاز به تأیید شما دارد:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // نمایش پارامترهای هر عملیات
          if (pendingOps.isNotEmpty)
            ...pendingOps.map((op) => _WriteOpPreview(
                  op: op,
                  theme: theme,
                  scheme: scheme,
                ))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'برای امنیت، فقط همان عملیاتی اجرا می‌شود که دستیار پیشنهاد کرده.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer.withValues(alpha: 0.78),
                ),
              ),
            ),
          // دکمه‌های تأیید/رد
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _sending
                      ? null
                      : () {
                          setState(() => _pendingWriteApproval = false);
                        },
                  child: Text(
                    'لغو',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sending ? null : _confirmWriteApproval,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('تأیید و اجرا'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.tertiary,
                    foregroundColor: scheme.onTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditWarning(ThemeData theme) {
    if (!_showCreditWarning || _availabilityInfo == null) {
      return const SizedBox.shrink();
    }

    final details = _availabilityInfo!['details'] as Map<String, dynamic>?;
    final subscription = details?['subscription'] as Map<String, dynamic>?;
    final tokensRemaining = subscription?['tokens_remaining'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange.shade800,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'اعتبار رو به اتمام — ${tokensRemaining.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} توکن باقی‌مانده',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade900,
              ),
            ),
          ),
          TextButton(
            onPressed: widget.businessId != null
                ? _navigateToSubscription
                : null,
            child: const Text('ارتقا'),
          ),
        ],
      ),
    );
  }
}

class _AiMoreMenu extends StatelessWidget {
  final bool isHomeMode;
  final bool hasSession;
  final bool hasBusiness;
  final VoidCallback onSearch;
  final VoidCallback onMemory;
  final VoidCallback onExport;
  final VoidCallback onConnectors;
  final VoidCallback onKnowledge;
  final VoidCallback onVoiceSettings;

  const _AiMoreMenu({
    required this.isHomeMode,
    required this.hasSession,
    required this.hasBusiness,
    required this.onSearch,
    required this.onMemory,
    required this.onExport,
    required this.onConnectors,
    required this.onKnowledge,
    required this.onVoiceSettings,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_AiMenuAction>(
      tooltip: 'ابزارهای دستیار',
      icon: const Icon(Icons.more_horiz_rounded),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case _AiMenuAction.search:
            onSearch();
            break;
          case _AiMenuAction.memory:
            onMemory();
            break;
          case _AiMenuAction.export:
            onExport();
            break;
          case _AiMenuAction.connectors:
            onConnectors();
            break;
          case _AiMenuAction.knowledge:
            onKnowledge();
            break;
          case _AiMenuAction.voice:
            onVoiceSettings();
            break;
        }
      },
      itemBuilder: (context) => [
        if (!isHomeMode && hasSession) ...[
          const PopupMenuItem(
            value: _AiMenuAction.search,
            child: _AiMenuItem(icon: Icons.search_rounded, label: 'جستجو در پیام‌ها'),
          ),
          const PopupMenuItem(
            value: _AiMenuAction.memory,
            child: _AiMenuItem(icon: Icons.psychology_outlined, label: 'حافظه دستیار'),
          ),
          const PopupMenuItem(
            value: _AiMenuAction.export,
            child: _AiMenuItem(icon: Icons.ios_share_outlined, label: 'خروجی گفت‌وگو'),
          ),
        ],
        if (hasBusiness) ...[
          const PopupMenuItem(
            value: _AiMenuAction.connectors,
            child: _AiMenuItem(icon: Icons.link_rounded, label: 'کانکتورها'),
          ),
          const PopupMenuItem(
            value: _AiMenuAction.knowledge,
            child: _AiMenuItem(icon: Icons.menu_book_outlined, label: 'دانشنامه'),
          ),
        ],
        const PopupMenuItem(
          value: _AiMenuAction.voice,
          child: _AiMenuItem(icon: Icons.tune_rounded, label: 'تنظیمات صدا'),
        ),
      ],
    );
  }
}

enum _AiMenuAction { search, memory, export, connectors, knowledge, voice }

class _AiMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AiMenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 19, color: scheme.primary),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

/// نمایش diff/preview پارامترهای یک عملیات نوشتنی در حال انتظار تأیید
class _WriteOpPreview extends StatefulWidget {
  final Map<String, dynamic> op;
  final ThemeData theme;
  final ColorScheme scheme;

  const _WriteOpPreview({
    required this.op,
    required this.theme,
    required this.scheme,
  });

  @override
  State<_WriteOpPreview> createState() => _WriteOpPreviewState();
}

class _WriteOpPreviewState extends State<_WriteOpPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.op['label'] as String? ?? widget.op['function'] as String? ?? 'عملیات';
    final args = widget.op['arguments'] as Map? ?? {};
    final scheme = widget.scheme;
    final theme = widget.theme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    size: 16,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && args.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Table(
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(),
                },
                children: args.entries
                    .where((e) => e.value != null && e.value.toString().isNotEmpty)
                    .map(
                      (e) => TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 2, 10, 2),
                            child: Text(
                              e.key,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              e.value.toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
