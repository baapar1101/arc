import 'package:hesabix_ui/theme/glass.dart';
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
import 'package:hesabix_ui/models/ai_voice_models.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/voice/voice_chat_controller.dart';
import 'package:hesabix_ui/services/voice/voice_dictation.dart';
import 'package:hesabix_ui/services/voice/voice_pcm_wav.dart';
import 'package:hesabix_ui/services/voice/voice_phase.dart';
import 'package:hesabix_ui/services/voice/voice_tts_player.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/hscript_code_extract.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_design.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_home_view.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_sidebar.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_suggestions.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_memory_sheet.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_knowledge_sheet.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_connectors_sheet.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_skills_sheet.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_thread_view.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_onboarding_banner.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_stream_controller.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_stream_turn.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_resume.dart';
import 'package:hesabix_ui/widgets/ai/ai_write_approval_helpers.dart';
import 'package:hesabix_ui/widgets/ai/ai_subagent_restore.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_turn.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_session_controller.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_voice_session.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_message_sheet.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_enter_to_send.dart';
import 'package:hesabix_ui/widgets/ai/ai_execution_mode.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_execution_mode_store.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_last_session_store.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_location.dart';
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

  /// پیام اولیه (مثلاً از استودیو HScript).
  final String? initialPrompt;

  /// اگر true باشد پس از آماده‌شدن جلسه، [initialPrompt] ارسال می‌شود.
  final bool autoSendInitialPrompt;

  /// مدل از پیش‌انتخاب‌شده (مثلاً از دیالوگ «از AI بساز»).
  final String? initialModelCode;

  /// بازگردانی جلسه بعد از رفرش وب (`/ai/chat/:sessionId`).
  final int? initialSessionId;

  /// وقتی از استودیو HScript باز شود، امکان اعمال مستقیم اسکریپت از پیام‌ها.
  final void Function(String code)? onApplyHScriptCode;

  const AIChatDialog({
    super.key,
    this.businessId,
    required this.authStore,
    this.calendarController,
    this.embeddedInShell = false,
    this.initialPrompt,
    this.autoSendInitialPrompt = true,
    this.initialModelCode,
    this.initialSessionId,
    this.onApplyHScriptCode,
  });

  static Future<void> show(
    BuildContext context, {
    required AuthStore authStore,
    int? businessId,
    CalendarController? calendarController,
    String? initialPrompt,
    bool autoSendInitialPrompt = true,
    String? initialModelCode,
    void Function(String code)? onApplyHScriptCode,
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
          initialPrompt: initialPrompt,
          autoSendInitialPrompt: autoSendInitialPrompt,
          initialModelCode: initialModelCode,
          onApplyHScriptCode: onApplyHScriptCode,
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
  final AIChatSessionController _thread = AIChatSessionController();
  List<AIChatSession> get _sessions => _thread.sessions;
  AIChatSession? get _currentSession => _thread.current;
  List<AIChatMessage> get _messages => _thread.messages;
  set _messages(List<AIChatMessage> value) => _thread.messages = value;
  bool get _sessionsLoading => _thread.sessionsLoading;
  bool get _messagesLoading => _thread.messagesLoading;
  final AIChatStreamController _stream = AIChatStreamController();
  bool _pendingWriteApproval = false;
  int? _pendingApprovalSessionId;
  final TextEditingController _messageCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  Map<String, dynamic>? _availabilityInfo;
  DateTime? _availabilityCheckedAt;
  bool _showCreditWarning = false;
  final AIChatVoiceSessionController _voiceSession =
      AIChatVoiceSessionController();
  VoiceChatController? get _voice => _voiceSession.engine;
  bool get _voiceStarting => _voiceSession.starting;
  VoicePhase get _voicePhase => _voiceSession.phase;
  Map<String, dynamic>? get _voiceStatusEvent => _voiceSession.statusEvent;
  bool get _voiceCollectData => _voiceSession.collectData;
  set _voiceCollectData(bool value) => _voiceSession.collectData = value;
  CancelToken? _streamCancelToken;
  bool _autoScrollEnabled = true;
  List<AIChatSuggestion> _suggestions = kDefaultAIChatSuggestions;
  List<Map<String, dynamic>> _proactiveAlerts = [];
  final Map<int, int> _messageFeedbackRatings = {};
  String _sessionSearch = '';
  Timer? _sessionSearchDebounce;
  List<Map<String, dynamic>> _attachments = [];
  final List<GlobalKey> _messageKeys = [];
  String? _streamErrorMessage;
  bool _streamErrorRecoverable = false;
  VoidCallback? _pendingStreamRetry;
  bool _didRestoreSession = false;
  final AISseCursor _sseCursor = AISseCursor();
  String? _continueRunId;
  String? _continueStopMessage;
  List<AIModelCatalogItem> _availableModels = [];
  String? _selectedModelCode;
  String? _lastResolvedModelLabel;
  bool _modelsLoading = false;
  bool _focusChatMode = false;
  String _executionMode = AIExecutionMode.defaultMode;
  bool _initialPromptHandled = false;
  AIVoiceCatalog? _voiceCatalog;
  String? _selectedSttCode;
  String? _selectedTtsCode;
  bool _businessAllowCloudAudio = false;
  bool _policyAllowCloudAudio = false;
  bool _savingVoiceSettings = false;
  bool _dictating = false;
  bool _dictateBusy = false;
  VoiceDictationController? _dictation;
  final VoiceTtsPlayer _ttsPlayer = VoiceTtsPlayer();
  String? _speakingMessageKey;
  Timer? _dictateLimitTimer;

  bool get _isJalali => widget.calendarController?.isJalali ?? true;
  bool get _isGenerating => _sending && _stream.isActive;

  bool get _showWriteApprovalBanner {
    if (_currentSession?.id == null) return false;
    if (_pendingApprovalSessionId != null &&
        _pendingApprovalSessionId != _currentSession!.id) {
      return false;
    }
    return collectPendingApprovalOps(
      messages: _messages,
      sessionId: _currentSession?.id,
      streamPending: _sending || _stream.pendingWriteApproval,
      pendingApprovalSessionId: _pendingApprovalSessionId,
      streamOps: _stream.pendingApprovalOps,
    ).isNotEmpty;
  }

  bool get _canConfirmWriteApproval =>
      _showWriteApprovalBanner &&
      !_sending &&
      _currentSession?.id != null &&
      (messagesHavePendingWriteApproval(_messages) ||
          _stream.pendingApprovalOps.isNotEmpty);
  bool get _isHomeMode => _thread.isHomeMode(
        streamActive: _stream.isActive,
        sending: _sending,
      );

  bool get _canUseAi => _availabilityInfo?['can_use'] as bool? ?? true;

  void _syncContinueRunFromMessages() {
    final hint = resumeHintFromMessages(
      _messages,
      fallbackStopMessage: _stream.agentBudget?.stopMessageFa,
    );
    _continueRunId = hint.runId;
    _continueStopMessage = hint.stopMessageFa;
  }

  void _syncMessageKeys() {
    while (_messageKeys.length < _messages.length) {
      _messageKeys.add(GlobalKey());
    }
    while (_messageKeys.length > _messages.length) {
      _messageKeys.removeLast();
    }
  }

  void _clearWriteApprovalState() {
    _pendingWriteApproval = false;
    _pendingApprovalSessionId = null;
    _stream.pendingWriteApproval = false;
    _stream.pendingApprovalOps = [];
  }

  void _syncPendingWriteApprovalFromMessages() {
    final ops = extractPendingApprovalOpsFromMessages(_messages);
    _pendingWriteApproval = ops.isNotEmpty;
    _pendingApprovalSessionId = ops.isNotEmpty ? _currentSession?.id : null;
  }

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
    _loadSuggestions();
    unawaited(_loadExecutionModePreference());
    unawaited(_bootstrapSessions());
    if (widget.businessId != null) {
      _modelsLoading = true;
      unawaited(_loadProactiveAlerts());
      unawaited(_loadAvailableModels());
      unawaited(_loadVoiceCatalog());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isHomeMode) _focusNode.requestFocus();
      unawaited(_maybeBootstrapInitialPrompt());
    });
  }

  Future<void> _maybeBootstrapInitialPrompt() async {
    if (_initialPromptHandled) return;
    final prompt = widget.initialPrompt?.trim();
    if (prompt == null || prompt.isEmpty) return;
    // صبر تا بارگذاری جلسات تمام شود
    for (var i = 0; i < 40 && mounted && _sessionsLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // صبر تا مدل‌ها لود شوند تا auto-send با model خالی/اشتباه نرود
    if (widget.businessId != null) {
      for (var i = 0; i < 60 && mounted && _modelsLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (!mounted || _initialPromptHandled) return;
    _initialPromptHandled = true;
    if (widget.autoSendInitialPrompt) {
      await _sendMessage(contentOverride: prompt);
    } else {
      setState(() => _messageCtrl.text = prompt);
      _focusNode.requestFocus();
    }
  }

  Future<void> _loadExecutionModePreference() async {
    final stored = await AIChatExecutionModeStore.load(widget.businessId);
    if (!mounted) return;
    setState(() => _executionMode = stored);
  }

  Future<void> _onExecutionModeChanged(String mode) async {
    final next = AIExecutionMode.normalize(mode);
    if (next == _executionMode) return;
    if (_showWriteApprovalBanner) {
      _showSnackbar(
        'ابتدا عملیات در انتظار تأیید را تأیید یا لغو کنید، سپس حالت را تغییر دهید.',
      );
      return;
    }
    if (AIExecutionMode.requiresAutonomousConfirmation(_executionMode, next)) {
      final confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('فعال‌سازی حالت خودکار'),
          content: const Text(
            'در این حالت دستیار می‌تواند تغییرات معمولی را بدون پرسیدن از شما '
            'در سیستم اعمال کند. عملیات پرریسک (حذف، workflow و …) همچنان '
            'نیاز به تأیید دارند.\n\nادامه می‌دهید؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('فعال‌سازی'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _executionMode = next);
    await AIChatExecutionModeStore.save(widget.businessId, next);
    final sessionId = _currentSession?.id;
    if (sessionId != null) {
      try {
        final updated = await _aiService.updateChatSession(
          sessionId: sessionId,
          executionMode: next,
        );
        if (!mounted) return;
        setState(() => _thread.patchSession(updated));
      } catch (e) {
        debugPrint('[AIChatDialog] update execution mode failed: $e');
      }
    }
  }

  Future<void> _loadAvailableModels() async {
    if (widget.businessId == null) return;
    setState(() => _modelsLoading = true);
    try {
      final result = await _aiService.listAvailableAIModelsResult(
        businessId: widget.businessId,
      );
      final models = result.models;
      final preferred = result.preferredModelCode;
      if (!mounted) return;

      bool hasCode(String? code) =>
          code != null && models.any((m) => m.code == code);

      String? selected = _selectedModelCode;
      if (!hasCode(selected)) selected = null;
      if (!hasCode(selected) && hasCode(widget.initialModelCode)) {
        selected = widget.initialModelCode;
      }
      if (!hasCode(selected) && hasCode(preferred)) {
        selected = preferred;
      }
      if (!hasCode(selected)) {
        for (final m in models) {
          if (m.isDefault) {
            selected = m.code;
            break;
          }
        }
      }
      selected ??= models.where((m) => m.isAuto).map((m) => m.code).firstOrNull;
      selected ??= models.isNotEmpty ? models.first.code : null;
      setState(() {
        _availableModels = models;
        _selectedModelCode = selected;
        _modelsLoading = false;
      });
      if (selected != null) {
        await _checkAvailability(model: selected);
      }
    } catch (e) {
      debugPrint('[AIChatDialog] load models failed: $e');
      if (mounted) setState(() => _modelsLoading = false);
    }
  }

  Future<void> _loadVoiceCatalog() async {
    final bid = widget.businessId;
    if (bid == null) return;
    try {
      final catalog = await _aiService.getVoiceCatalog(businessId: bid);
      Map<String, dynamic>? settings;
      try {
        settings = await _aiService.getBusinessVoiceSettings(bid);
      } catch (_) {}
      if (!mounted) return;
      String? pick(List<AIVoiceModelItem> items, String? preferred, String? fallback) {
        bool has(String? code) =>
            code != null && items.any((m) => m.code == code);
        if (has(preferred)) return preferred;
        if (has(fallback)) return fallback;
        for (final item in items) {
          if (item.isDefault) return item.code;
        }
        return items.isNotEmpty ? items.first.code : null;
      }

      setState(() {
        _voiceCatalog = catalog;
        _policyAllowCloudAudio = catalog.policyAllowCloudAudio;
        _businessAllowCloudAudio =
            settings?['allow_cloud_audio'] == true || catalog.allowCloudAudio;
        _selectedSttCode = pick(
          catalog.stt,
          settings?['preferred_stt_code'] as String?,
          catalog.defaultSttCode,
        );
        _selectedTtsCode = pick(
          catalog.tts,
          settings?['preferred_tts_code'] as String?,
          catalog.defaultTtsCode,
        );
      });
    } catch (e) {
      debugPrint('[AIChatDialog] voice catalog failed: $e');
    }
  }

  Future<void> _onSttChanged(String code) async {
    if (code == _selectedSttCode) return;
    setState(() => _selectedSttCode = code);
    await _persistVoicePreference(stt: code);
  }

  Future<void> _onTtsChanged(String code) async {
    if (code == _selectedTtsCode) return;
    setState(() => _selectedTtsCode = code);
    await _persistVoicePreference(tts: code);
  }

  Future<void> _persistVoicePreference({String? stt, String? tts}) async {
    final bid = widget.businessId;
    if (bid == null) return;
    try {
      await _aiService.saveBusinessVoiceSettings(bid, {
        if (stt != null) 'preferred_stt_code': stt,
        if (tts != null) 'preferred_tts_code': tts,
      });
    } catch (e) {
      debugPrint('[AIChatDialog] persist voice preference failed: $e');
    }
  }

  Future<void> _setBusinessCloudAudio(bool value) async {
    final bid = widget.businessId;
    if (bid == null || _savingVoiceSettings) return;
    if (value && !_policyAllowCloudAudio) {
      _showError(AppLocalizations.of(context).aiVoiceCloudDisabled);
      return;
    }
    setState(() => _savingVoiceSettings = true);
    try {
      final saved = await _aiService.saveBusinessVoiceSettings(bid, {
        'allow_cloud_audio': value,
      });
      if (!mounted) return;
      setState(() {
        _businessAllowCloudAudio = saved['allow_cloud_audio'] == true;
        _policyAllowCloudAudio = saved['policy_allow_cloud_audio'] == true;
      });
      await _loadVoiceCatalog();
    } catch (e) {
      if (!mounted) return;
      _showError(ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _savingVoiceSettings = false);
    }
  }

  void _insertComposerText(String text) {
    final value = _messageCtrl.value;
    final current = value.text;
    final sel = value.selection;
    if (sel.isValid && sel.start >= 0 && sel.end <= current.length) {
      final prefix = current.substring(0, sel.start);
      final suffix = current.substring(sel.end);
      final glue = prefix.isNotEmpty &&
              !prefix.endsWith(' ') &&
              !prefix.endsWith('\n')
          ? ' '
          : '';
      final next = '$prefix$glue$text$suffix';
      final offset = prefix.length + glue.length + text.length;
      _messageCtrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: offset),
      );
    } else {
      final glue =
          current.isNotEmpty && !current.endsWith(' ') ? ' ' : '';
      final next = '$current$glue$text';
      _messageCtrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  Future<void> _stopDictationCapture() async {
    _dictateLimitTimer?.cancel();
    _dictateLimitTimer = null;
    final controller = _dictation;
    _dictation = null;
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {}
  }

  Future<void> _toggleDictate() async {
    if (widget.businessId == null || _voice != null || _voiceStarting) return;
    final l10n = AppLocalizations.of(context);
    if (_dictateBusy) return;
    if (_dictating) {
      setState(() {
        _dictating = false;
        _dictateBusy = true;
      });
      _dictateLimitTimer?.cancel();
      List<int> pcm = const [];
      try {
        pcm = await _dictation?.stop() ?? const [];
      } catch (_) {}
      await _stopDictationCapture();
      if (!mounted) return;
      if (pcm.isEmpty) {
        setState(() => _dictateBusy = false);
        _showSnackbar(l10n.aiVoiceDictationEmpty);
        return;
      }
      try {
        final wav = pcm16ToWav(Uint8List.fromList(pcm));
        final text = await _aiService.transcribeVoice(
          wavBytes: wav,
          businessId: widget.businessId,
          sttCode: _selectedSttCode,
        );
        if (!mounted) return;
        if (text.isEmpty) {
          _showSnackbar(l10n.aiVoiceDictationEmpty);
        } else {
          _insertComposerText(text);
          _focusNode.requestFocus();
        }
      } catch (e) {
        if (!mounted) return;
        _showError(l10n.aiVoiceDictationFailed(ErrorExtractor.forContext(e, context)));
      } finally {
        if (mounted) setState(() => _dictateBusy = false);
      }
      return;
    }

    await _ttsPlayer.stop();
    if (mounted) setState(() => _speakingMessageKey = null);
    final capture = VoiceDictationController();
    try {
      await capture.start(onPcm: (_) {});
      if (!mounted) {
        await capture.dispose();
        return;
      }
      _dictation = capture;
      setState(() => _dictating = true);
      _dictateLimitTimer?.cancel();
      _dictateLimitTimer = Timer(const Duration(seconds: 28), () {
        if (_dictating && mounted) unawaited(_toggleDictate());
      });
    } catch (e) {
      try {
        await capture.dispose();
      } catch (_) {}
      if (!mounted) return;
      _showError(ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _speakMessage(AIChatMessage message) async {
    final text = message.content.trim();
    if (text.isEmpty || widget.businessId == null) return;
    final l10n = AppLocalizations.of(context);
    final key = aiChatSpeakKey(message);
    if (_speakingMessageKey == key) {
      await _ttsPlayer.stop();
      if (mounted) setState(() => _speakingMessageKey = null);
      return;
    }
    if (_voice != null) return;
    if (_dictating) await _toggleDictate();
    if (!mounted) return;
    final tts = _voiceCatalog?.tts.where((m) => m.code == _selectedTtsCode);
    if (tts != null && tts.isNotEmpty && tts.first.dummy) {
      _showSnackbar(l10n.aiVoiceDummyTtsWarning);
    }
    setState(() => _speakingMessageKey = key);
    try {
      final wav = await _aiService.synthesizeVoice(
        text: text,
        businessId: widget.businessId,
        ttsCode: _selectedTtsCode,
      );
      if (!mounted) return;
      if (_speakingMessageKey != key) return;
      await _ttsPlayer.playWav(wav);
      if (!mounted) return;
      setState(() => _speakingMessageKey = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _speakingMessageKey = null);
      _showError(l10n.aiVoiceReadAloudFailed(ErrorExtractor.forContext(e, context)));
    }
  }

  Future<void> _onModelChanged(String? code) async {
    if (code == null || code == _selectedModelCode) return;
    setState(() {
      _selectedModelCode = code;
      if (code != 'auto') _lastResolvedModelLabel = null;
    });
    if (widget.businessId != null) {
      try {
        await _aiService.setPreferredModel(
          modelCode: code,
          businessId: widget.businessId,
        );
      } catch (e) {
        debugPrint('[AIChatDialog] set preferred model failed: $e');
      }
    }
    _availabilityCheckedAt = null;
    await _checkAvailability(model: code);
  }

  String? _selectedModelPricingHint() {
    final details = _availabilityInfo?['details'] as Map<String, dynamic>?;
    final pricing = details?['model_pricing'] as Map<String, dynamic>?;
    return pricing?['pricing_hint'] as String?;
  }

  String? _composerModelHint() {
    final pricing = _selectedModelPricingHint();
    final resolved = _lastResolvedModelLabel;
    if (resolved != null && resolved.isNotEmpty) {
      final tail = 'آخرین پاسخ با $resolved';
      return pricing != null && pricing.isNotEmpty ? '$pricing · $tail' : tail;
    }
    return pricing;
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
    _thread.dispose();
    _streamCancelToken?.cancel('disposed');
    _sessionSearchDebounce?.cancel();
    _scrollController.removeListener(_onScrollChanged);
    _messageCtrl.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _voice?.dispose();
    _dictateLimitTimer?.cancel();
    unawaited(_dictation?.dispose());
    unawaited(_ttsPlayer.dispose());
    super.dispose();
  }

  double _distanceFromBottom() {
    if (!_scrollController.hasClients) return 0;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels;
  }

  void _onScrollChanged() {
    // هیسترزیس: آستانه‌های جدا برای فعال/غیرفعال شدن تا حین استریم نوسان نکند.
    final distance = _distanceFromBottom();
    final shouldEnable = distance < 80;
    final shouldDisable = distance > 200;
    if (_autoScrollEnabled && shouldDisable) {
      setState(() => _autoScrollEnabled = false);
    } else if (!_autoScrollEnabled && shouldEnable) {
      setState(() => _autoScrollEnabled = true);
    }
  }

  String _formatMessageTime(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (AIChatDesign.isCompactWidth(context)) return time;
    return HesabixDateUtils.formatDateTime(local, _isJalali);
  }

  Future<void> _showMessageActions(AIChatMessage msg) {
    return showAIChatMessageActionSheet(
      context: context,
      message: msg,
      canApplyHScript: widget.onApplyHScriptCode != null,
      onCopy: () => _copyToClipboard(msg.content),
      onShare: () {
        Share.share(msg.content);
      },
      onApplyHScript: widget.onApplyHScriptCode == null
          ? null
          : () {
              final code = HScriptCodeExtract.extract(msg.content);
              if (code == null || code.isEmpty) return;
              widget.onApplyHScriptCode!(code);
              Navigator.of(context).pop();
            },
      onEditUserResend: () => _editMessage(msg, regenerateAfter: true),
      onEditAssistantText: () => _editMessage(msg, regenerateAfter: false),
      onEditAssistantRegenerate: () =>
          _editMessage(msg, regenerateAfter: true),
      onFork: msg.id == null ? null : () => _forkFromMessage(msg.id!),
      onFeedbackUp: () => _submitFeedback(msg, 1),
      onFeedbackDown: () => _submitFeedback(msg, -1),
      onRegenerate: _regenerateLastResponse,
      onSpeak: msg.role == MessageRole.assistant &&
              msg.content.trim().isNotEmpty
          ? () => unawaited(_speakMessage(msg))
          : null,
      onPinToMemory: widget.businessId == null || msg.content.trim().isEmpty
          ? null
          : () => unawaited(_pinMessageToMemory(msg)),
    );
  }

  Future<void> _pinMessageToMemory(AIChatMessage msg) async {
    try {
      await _aiService.pinAIMemoryEntry(
        content: msg.content.trim(),
        businessId: widget.businessId,
      );
      if (!mounted) return;
      _showSnackbar(AppLocalizations.of(context).aiMemoryPinned);
    } catch (e) {
      if (!mounted) return;
      _showError(
        AppLocalizations.of(context).aiMemoryError(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackbar(AppLocalizations.of(context).aiChatCopied);
  }

  void _stopGenerating({
    bool showNotice = true,
    bool cancelServerRun = true,
  }) {
    final token = _streamCancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('user_cancel');
    }
    _streamCancelToken = null;
    final runId = _stream.runId ?? _sseCursor.runId;
    final sessionId = _currentSession?.id;
    if (cancelServerRun &&
        runId != null &&
        runId.isNotEmpty &&
        sessionId != null) {
      unawaited(
        _aiService.cancelAgentRun(sessionId: sessionId, runId: runId),
      );
    }
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
      _showSnackbar(AppLocalizations.of(context).aiChatGenerationStopped);
    }
  }

  Future<void> _stopVoiceSession() async {
    if (_voice == null) return;
    setState(_voiceSession.beginStopping);
    try {
      await _voice!.dispose();
    } catch (_) {}
    if (!mounted) return;
    setState(_voiceSession.finishStopped);
  }

  Future<void> _promptVoiceFeedback(int interactionId) async {
    if (!_voiceSession.shouldPromptFeedback(interactionId)) return;

    int rating = 4;
    final ctrl = TextEditingController();
    final l10n = AppLocalizations.of(context);
    final ok =
        await showGlassDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(l10n.aiVoiceFeedbackTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.aiVoiceFeedbackBody),
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
                    decoration: InputDecoration(
                      labelText: l10n.aiVoiceFeedbackCommentLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.aiVoiceFeedbackLater),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.aiVoiceFeedbackSubmit),
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
      _showSnackbar(AppLocalizations.of(context).aiChatFeedbackSaved);
    } catch (e) {
      if (!mounted) return;
      _showError(
        AppLocalizations.of(context).aiChatFeedbackFailed(
          ErrorExtractor.forContext(e, context),
        ),
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
    setState(_thread.markSessionsLoading);
    try {
      final list = await _aiService.listChatSessions(
        businessId: widget.businessId,
        search: _sessionSearch.isNotEmpty ? _sessionSearch : null,
      );
      if (!mounted) return;
      setState(() => _thread.replaceSessions(list));
      await _checkAvailability();
    } catch (e) {
      if (!mounted) return;
      setState(_thread.failSessionsLoad);
      _showError(
        AppLocalizations.of(context).aiChatSessionsLoadFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  Future<void> _bootstrapSessions() async {
    await _loadSessions();
    if (!mounted) return;
    await _restoreSessionIfNeeded();
  }

  void _rememberOpenSession(int? sessionId) {
    _reflectSessionLocation(sessionId);
    if (sessionId == null) {
      unawaited(AIChatLastSessionStore.clear(widget.businessId));
      return;
    }
    unawaited(AIChatLastSessionStore.save(widget.businessId, sessionId));
  }

  void _reflectSessionLocation(int? sessionId) {
    if (!widget.embeddedInShell) return;
    replaceAiChatSessionPath(sessionId: sessionId);
  }

  Future<void> _restoreSessionIfNeeded() async {
    if (_didRestoreSession) return;
    _didRestoreSession = true;
    if (_currentSession != null) return;
    final prompt = widget.initialPrompt?.trim();
    if (prompt != null && prompt.isNotEmpty) return;

    var id = widget.initialSessionId;
    id ??= await AIChatLastSessionStore.load(widget.businessId);
    if (id == null || !mounted) return;

    var session = _thread.sessionById(id);
    session ??= await _aiService.getChatSession(sessionId: id);
    if (session == null || !mounted) return;
    await _selectSession(session, resumeActiveRun: true);
  }

  Future<void> _resumeActiveRunIfNeeded() async {
    final sessionId = _currentSession?.id;
    if (sessionId == null || _sending) return;

    Future<void> reloadMessages() async {
      final msgs = await _aiService.getSessionMessages(sessionId: sessionId);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _syncMessageKeys();
        _syncContinueRunFromMessages();
        _syncPendingWriteApprovalFromMessages();
      });
    }

    bool awaitsAssistant() => sessionAwaitsAssistantReply(_messages);

    var active = await _aiService.getActiveAgentRun(sessionId: sessionId);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    if (active != null && active.isGenerating) {
      final runId = active.runId;
      _sseCursor.runId = runId;
      _sseCursor.lastEventId = sseReplayCursor(
        uiHasAssistantPartial: !awaitsAssistant(),
        serverLastEventId: active.lastEventId,
      );
      _showSnackbar(l10n.aiResumingPreviousRun);
      setState(() {
        _stream.begin(phase: 'connecting');
        _sending = true;
      });
      await _runAssistantStream(
        (cancelToken) => _aiService.subscribeAgentRunStream(
          sessionId: sessionId,
          runId: runId,
          sseCursor: _sseCursor,
          cancelToken: cancelToken,
        ),
        errorLabel: l10n.aiContinueAnalysis,
      );
      if (mounted && !_sending) {
        await reloadMessages();
      }
      return;
    }

    if (awaitsAssistant()) {
      await reloadMessages();
    }
    if (!mounted || _sending) return;

    if (awaitsAssistant()) {
      unawaited(_pollPersistedAssistant(sessionId));
    }

    if (active != null && active.canContinue) {
      setState(() {
        _continueRunId = active.runId;
        _continueStopMessage = active.stopMessageFa?.trim().isNotEmpty == true
            ? active.stopMessageFa
            : l10n.aiContinueAfterRefreshHint;
      });
    }
  }

  Future<void> _pollPersistedAssistant(int sessionId) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      if (!mounted || _sending) return;
      if (!sessionAwaitsAssistantReply(_messages)) return;
      final active = await _aiService.getActiveAgentRun(sessionId: sessionId);
      if (!mounted || _sending) return;
      if (active != null && active.isGenerating) {
        await _resumeActiveRunIfNeeded();
        return;
      }
      final msgs = await _aiService.getSessionMessages(sessionId: sessionId);
      if (!mounted || _sending) return;
      setState(() {
        _messages = msgs;
        _syncMessageKeys();
        _syncContinueRunFromMessages();
        _syncPendingWriteApprovalFromMessages();
      });
    }
  }

  Future<bool> _ensureSession() async {
    if (_currentSession != null) return true;
    try {
      final session = await _aiService.createChatSession(
        businessId: widget.businessId,
        executionMode: _executionMode,
      );
      if (!mounted) return false;
      setState(() {
        _thread.adoptCreatedSession(session);
        _clearWriteApprovalState();
      });
      _rememberOpenSession(session.id);
      unawaited(_loadSessions());
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showError(
        AppLocalizations.of(context).aiChatStartConversationFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
      return false;
    }
  }

  Future<void> _selectSession(
    AIChatSession session, {
    bool resumeActiveRun = true,
  }) async {
    if (_currentSession?.id == session.id) return;
    if (_isGenerating) {
      _stopGenerating(showNotice: false, cancelServerRun: false);
    }
    if (_voice != null) {
      await _stopVoiceSession();
    }
    _sseCursor.lastEventId = null;
    _sseCursor.runId = null;
    setState(() {
      _thread.beginSelectSession(session);
      _executionMode = AIExecutionMode.normalize(session.executionMode);
      _clearWriteApprovalState();
    });
    try {
      final msgs = await _aiService.getSessionMessages(sessionId: session.id!);
      if (!mounted) return;
      setState(() {
        _thread.finishSelectSession(msgs);
        _syncMessageKeys();
        _syncPendingWriteApprovalFromMessages();
        _syncContinueRunFromMessages();
      });
      _rememberOpenSession(session.id);
      _scrollToBottom(force: true);
      await _restorePersistedSubagents(session.id!);
      await _checkAvailability();
      unawaited(_loadAttachments());
      if (_messages.isEmpty) {
        _focusNode.requestFocus();
      }
      if (resumeActiveRun) {
        await _resumeActiveRunIfNeeded();
      }
    } catch (e) {
      if (!mounted) return;
      setState(_thread.failSelectSession);
      _showError(
        AppLocalizations.of(context).aiChatMessagesLoadFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  Future<void> _restorePersistedSubagents(int sessionId) async {
    try {
      final items = await _aiService.listSessionSubagents(sessionId);
      if (!mounted || items.isEmpty) return;
      final merged = mergeSubagentSummariesIntoMessages(_messages, items);
      if (identical(merged, _messages)) return;
      setState(() {
        _messages = merged;
        _syncMessageKeys();
      });
    } catch (e) {
      debugPrint('[AIChatDialog] subagent restore failed: $e');
    }
  }

  void _dropAwaitingApprovalAssistantForResume() {
    if (_messages.isEmpty) return;
    final last = _messages.last;
    if (last.role != MessageRole.assistant) return;
    final pending = extractPendingApprovalOpsFromResults(last.functionResults);
    if (!functionResultsAwaitApproval(last.functionResults) && pending.isEmpty) {
      return;
    }
    _messages = List<AIChatMessage>.from(_messages)..removeLast();
    _syncMessageKeys();
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
      _showError(AppLocalizations.of(context).aiChatEmptyFile);
      return;
    }
    if (!await _ensureSession()) return;
    try {
      await _aiService.uploadSessionAttachment(
        sessionId: _currentSession!.id!,
        filename: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      _showSnackbar(AppLocalizations.of(context).aiChatAttachmentAdded);
      await _loadAttachments();
    } catch (e) {
      if (!mounted) return;
      _showError(
        AppLocalizations.of(context).aiChatAttachmentUploadFailed(
          ErrorExtractor.forContext(e, context),
        ),
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
    await showGlassModalBottomSheet<void>(
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

  Future<void> _checkAvailability({
    int estimatedTokens = 1000,
    String? model,
  }) async {
    try {
      final availability = await _aiService.checkAvailability(
        businessId: widget.businessId,
        estimatedTokens: estimatedTokens,
        model: model ?? _selectedModelCode,
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
        model: _selectedModelCode,
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
      if (!mounted) return false;
      _showError(
        AppLocalizations.of(context).aiStreamAvailabilityCheckFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
      return false;
    }
  }

  void _scheduleSessionsRefreshForTitle() {
    unawaited(_syncAfterAssistantResponse());
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) unawaited(_syncAfterAssistantResponse());
    });
  }

  Future<void> _syncAfterAssistantResponse() async {
    final sessionId = _currentSession?.id;
    if (sessionId == null) return;
    try {
      final msgs = await _aiService.getSessionMessages(sessionId: sessionId);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _syncMessageKeys();
        _syncContinueRunFromMessages();
        _syncPendingWriteApprovalFromMessages();
      });
      await _loadSessions();
      if (!mounted) return;
      final updated = _thread.sessionById(sessionId);
      if (updated != null) {
        setState(() => _thread.adoptCreatedSession(updated));
      }
    } catch (e) {
      debugPrint('[AIChatDialog] sync after response failed: $e');
    }
  }

  Future<void> _goToHome() async {
    if (_isGenerating) _stopGenerating(showNotice: false, cancelServerRun: false);
    if (_voice != null) await _stopVoiceSession();
    if (!mounted) return;
    setState(() {
      _thread.goHome();
      _stream.clear();
      _attachments = [];
      _clearWriteApprovalState();
      _continueRunId = null;
      _continueStopMessage = null;
    });
    _reflectSessionLocation(null);
    unawaited(AIChatLastSessionStore.clear(widget.businessId));
    _messageCtrl.clear();
    _focusNode.requestFocus();
  }

  Future<void> _startNewConversation() => _goToHome();

  Future<void> _deleteSession(AIChatSession session) async {
    final confirm =
        await showGlassDialog<bool>(
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
      _showSnackbar(AppLocalizations.of(context).aiChatConversationDeleted);
      final wasCurrent = _currentSession?.id == session.id;
      await _loadSessions();
      if (!mounted) return;
      if (wasCurrent) {
        await _goToHome();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(
        AppLocalizations.of(context).aiChatDeleteConversationFailed(
          ErrorExtractor.forContext(e, context),
        ),
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
    final newText = await showGlassDialog<String>(
      context: context,
      builder: (ctx) => _AIChatEditMessageDialog(initialText: msg.content),
    );
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
        _showSnackbar(AppLocalizations.of(context).aiChatMessageUpdated);
      } catch (e) {
        if (!mounted) return;
        _showError(
          AppLocalizations.of(context).aiChatEditFailed(
            ErrorExtractor.forContext(e, context),
          ),
        );
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
      _clearWriteApprovalState();
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
      ),
      errorLabel: AppLocalizations.of(context).aiChatErrorLabelEdit,
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
        _showSnackbar(AppLocalizations.of(context).aiChatForkOpened);
      }
    } catch (e) {
      if (!mounted) return;
      _showError(
        AppLocalizations.of(context).aiChatForkFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  Future<void> _exportConversation() async {
    if (_currentSession?.id == null) return;
    try {
      final data = await _aiService.exportChatSession(_currentSession!.id!);
      final md = data['markdown'] as String? ?? '';
      if (md.isEmpty) {
        _showSnackbar(AppLocalizations.of(context).aiChatExportEmpty);
        return;
      }
      await Share.share(md, subject: data['title'] as String?);
    } catch (e) {
      if (!mounted) return;
      _showError(
        AppLocalizations.of(context).aiChatExportFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
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

  void _openSkillsSheet() {
    showAIChatSkillsSheet(
      context: context,
      aiService: _aiService,
      businessId: widget.businessId,
      onOpenPanelPage:
          widget.embeddedInShell ? null : _navigateToPanelPage,
    );
  }

  void _navigateToPanelPage(String relativePath) {
    final bid = widget.businessId;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    if (bid == null) return;
    try {
      final prefix = BusinessRoutePaths.prefixFromRouterState(router.state);
      router.go('$prefix/$relativePath');
    } catch (_) {
      router.go('/business/$bid/tab0/$relativePath');
    }
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
      _showSnackbar(
        rating > 0
            ? AppLocalizations.of(context).aiChatFeedbackThanks
            : AppLocalizations.of(context).aiChatFeedbackSaved,
      );
    } catch (e) {
      if (!mounted) return;
      _showError(
        AppLocalizations.of(context).aiChatFeedbackFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  String _friendlyStreamError(AIChatStreamTurnOutcome outcome) {
    final l10n = AppLocalizations.of(context);
    switch (outcome.errorCode) {
      case 'STREAM_STALL':
        return l10n.aiStreamStallError;
      case 'EMPTY_STREAM':
        return l10n.aiStreamEmptyError;
      case 'RUN_IDLE':
        return l10n.aiContinueAfterRefreshHint;
      default:
        return outcome.errorMessage ?? l10n.aiErrorRecoveryTitle;
    }
  }

  String _labelForResolvedModel(String? code) {
    final resolvedCode = code?.trim();
    if (resolvedCode == null || resolvedCode.isEmpty) return '';
    final match = _availableModels.where((m) => m.code == resolvedCode);
    return match.isNotEmpty ? match.first.displayName : resolvedCode;
  }

  void _applyStreamOutcome(AIChatStreamTurnOutcome outcome) {
    if (outcome.errorCode == 'RUN_CANCELLED') {
      setState(() {
        _sending = false;
        _stream.clear();
      });
      return;
    }
    if (outcome.status == AIChatStreamTurnStatus.chunkError) {
      setState(() {
        if (outcome.hasPartialAssistant && _currentSession?.id != null) {
          _messages = List<AIChatMessage>.from(_messages)
            ..add(
              AIChatMessage(
                sessionId: _currentSession!.id!,
                role: MessageRole.assistant,
                content: outcome.partialContent!,
                functionResults: outcome.partialFunctionResults,
                createdAt: outcome.partialCreatedAt,
              ),
            );
        }
        _streamErrorMessage = _friendlyStreamError(outcome);
        _streamErrorRecoverable = outcome.errorRecoverable;
        if (outcome.applyContinue) {
          _continueRunId = outcome.continueRunId;
          _continueStopMessage = outcome.continueStopMessage;
        }
        _sending = false;
        _stream.clear();
        _syncMessageKeys();
      });
      return;
    }

    final modelLabel = _labelForResolvedModel(outcome.resolvedModelCode);
    setState(() {
      if (modelLabel.isNotEmpty) {
        _lastResolvedModelLabel = modelLabel;
      }
      if (outcome.hasVisibleOutput) {
        _messages = List<AIChatMessage>.from(_messages)
          ..add(
            AIChatMessage(
              id: outcome.assistantMessageId,
              sessionId: _currentSession!.id!,
              role: MessageRole.assistant,
              content: outcome.sanitizedResolvedContent,
              functionCalls: outcome.functionCalls,
              functionResults: outcome.functionResults,
              createdAt: outcome.createdAt,
            ),
          );
        _streamErrorMessage = null;
        _streamErrorRecoverable = false;
        _continueRunId = outcome.continueRunId;
        _continueStopMessage = outcome.continueStopMessage;
      } else {
        _streamErrorMessage =
            AppLocalizations.of(context).aiChatEmptyAssistantReply;
        _streamErrorRecoverable = true;
      }
      _syncPendingWriteApprovalFromMessages();
      if (!_pendingWriteApproval &&
          (_stream.pendingWriteApproval ||
              _stream.pendingApprovalOps.isNotEmpty)) {
        _pendingWriteApproval = true;
        _pendingApprovalSessionId = _currentSession?.id;
      }
      _stream.clear();
      _sending = false;
      _syncMessageKeys();
    });
    _scrollToBottom(force: true);
    _scheduleSessionsRefreshForTitle();
  }

  Future<void> _runAssistantStream(
    Stream<AIStreamChunk> Function(CancelToken cancelToken) streamFactory, {
    String? errorLabel,
    int reconnectAttempt = 0,
  }) async {
    _pendingStreamRetry = () {
      unawaited(_runAssistantStream(streamFactory, errorLabel: errorLabel));
    };
    _streamCancelToken?.cancel('replaced');
    final cancelToken = CancelToken();
    _streamCancelToken = cancelToken;
    try {
      final outcome = await _stream.consume(
        streamFactory(cancelToken),
        resolveToolLabel: _resolveToolLabel,
        sseCursorRunId: _sseCursor.runId,
        onContentTick: _scrollToBottom,
      );
      if (!mounted) return;
      if (reconnectAttempt < 2 &&
          outcome.shouldReconnect &&
          await _reconnectAssistantStream(
            outcome,
            errorLabel: errorLabel,
            reconnectAttempt: reconnectAttempt,
          )) {
        return;
      }
      _applyStreamOutcome(outcome);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        if (mounted && _streamCancelToken == cancelToken) {
          setState(() => _sending = false);
        }
        return;
      }
      if (!mounted) return;
      final synthetic = AIChatStreamTurnOutcome(
        status: AIChatStreamTurnStatus.chunkError,
        errorMessage: ErrorExtractor.forContext(e, context),
        errorRecoverable: true,
        errorCode: 'NETWORK',
        suggestedAction: 'reconnect',
        applyContinue: true,
        continueRunId: _stream.runId ?? _sseCursor.runId,
      );
      if (reconnectAttempt < 2 &&
          await _reconnectAssistantStream(
            synthetic,
            errorLabel: errorLabel,
            reconnectAttempt: reconnectAttempt,
          )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _continueRunId = _stream.runId ?? _sseCursor.runId;
        _continueStopMessage = _stream.agentBudget?.stopMessageFa;
        _stream.clear();
      });
      _showError(
        AppLocalizations.of(context).aiChatActionFailed(
          errorLabel ?? AppLocalizations.of(context).aiChatErrorLabelReply,
          ErrorExtractor.forContext(e, context),
        ),
      );
    } finally {
      if (_streamCancelToken == cancelToken) {
        _streamCancelToken = null;
      }
    }
  }

  Future<bool> _reconnectAssistantStream(
    AIChatStreamTurnOutcome outcome, {
    String? errorLabel,
    required int reconnectAttempt,
  }) async {
    final sessionId = _currentSession?.id;
    final runId = outcome.continueRunId ?? _stream.runId ?? _sseCursor.runId;
    if (sessionId == null || runId == null || runId.isEmpty) return false;
    if (!mounted) return false;
    _sseCursor.runId = runId;
    setState(() {
      _sending = true;
      _stream.statusPhase = 'connecting';
    });
    final useContinue = outcome.shouldContinueRun;
    await _runAssistantStream(
      (cancelToken) => useContinue
          ? _aiService.continueAgentRunStream(
              sessionId: sessionId,
              runId: runId,
              executionMode: _executionMode,
              model: _selectedModelCode,
              sseCursor: _sseCursor,
              cancelToken: cancelToken,
            )
          : _aiService.subscribeAgentRunStream(
              sessionId: sessionId,
              runId: runId,
              sseCursor: _sseCursor,
              cancelToken: cancelToken,
            ),
      errorLabel: errorLabel,
      reconnectAttempt: reconnectAttempt + 1,
    );
    return true;
  }

  Future<void> _continueIncompleteRun() async {
    final runId = _continueRunId;
    final sessionId = _currentSession?.id;
    if (runId == null || sessionId == null || _sending) return;
    setState(() {
      _continueRunId = null;
      _continueStopMessage = null;
      _streamErrorMessage = null;
      _stream.begin(phase: 'connecting');
      _sending = true;
    });
    await _runAssistantStream(
      (cancelToken) => _aiService.continueAgentRunStream(
        sessionId: sessionId,
        runId: runId,
        executionMode: _executionMode,
        model: _selectedModelCode,
        sseCursor: _sseCursor,
        cancelToken: cancelToken,
      ),
      errorLabel: AppLocalizations.of(context).aiContinueAnalysis,
    );
  }

  Future<void> _regenerateLastResponse() async {
    if (_sending || _currentSession?.id == null) return;
    if (_messages.isEmpty) return;
    final last = _messages.last;
    if (last.role != MessageRole.assistant) {
      _showSnackbar(AppLocalizations.of(context).aiChatRegenerateNeedsAssistant);
      return;
    }

    setState(() {
      _thread.removeLastMessage();
      _clearWriteApprovalState();
      _stream.begin(phase: 'connecting');
      _sending = true;
    });

    await _runAssistantStream(
      (token) => _aiService.regenerateLastResponseStream(
        sessionId: _currentSession!.id!,
        cancelToken: token,
        onComplete: (_, __) {},
      ),
      errorLabel: AppLocalizations.of(context).aiChatErrorLabelRegenerate,
    );
  }

  List<Map<String, dynamic>> _collectPendingApprovalOps() {
    return collectPendingApprovalOps(
      messages: _messages,
      sessionId: _currentSession?.id,
      streamPending: _sending || _stream.pendingWriteApproval,
      pendingApprovalSessionId: _pendingApprovalSessionId,
      streamOps: _stream.pendingApprovalOps,
    );
  }

  void _patchLastAssistantTodos(AISessionTodoSnapshot snapshot) {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.role != MessageRole.assistant) continue;
      final fr = msg.functionResults is Map
          ? Map<String, dynamic>.from(msg.functionResults as Map)
          : <String, dynamic>{};
      fr[kAgentTodosStorageKey] = snapshot.toJson();
      _messages[i] = AIChatMessage(
        id: msg.id,
        sessionId: msg.sessionId,
        role: msg.role,
        content: msg.content,
        functionCalls: msg.functionCalls,
        functionResults: fr,
        tokensUsed: msg.tokensUsed,
        createdAt: msg.createdAt,
      );
      break;
    }
  }

  Future<void> _onSessionTodoStatus(
    AISessionTodoItem item,
    String status,
  ) async {
    final sessionId = _currentSession?.id;
    if (sessionId == null || item.id.isEmpty) return;
    try {
      final snapshot = await _aiService.updateSessionTodo(
        sessionId: sessionId,
        todoId: item.id,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _stream.todoSnapshot = snapshot;
        _patchLastAssistantTodos(snapshot);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackbar(ErrorExtractor.userMessage(e));
    }
  }

  Future<void> _cancelSubagent(String subagentId) async {
    final sessionId = _currentSession?.id;
    if (sessionId == null || subagentId.trim().isEmpty) return;
    try {
      await _aiService.cancelSubagent(
        sessionId: sessionId,
        subagentId: subagentId.trim(),
      );
      if (!mounted) return;
      _stream.markSubagentCancelled(subagentId.trim());
    } catch (e) {
      if (!mounted) return;
      _showSnackbar(ErrorExtractor.userMessage(e));
    }
  }

  Future<void> _confirmWriteApproval() async {
    if (_sending) return;
    if (!_canConfirmWriteApproval) {
      _showSnackbar(AppLocalizations.of(context).aiChatWriteApprovalNotFound);
      _clearWriteApprovalState();
      return;
    }
    await _sendMessage(
      contentOverride: '',
      approveWrites: true,
      skipUserBubble: true,
      requireExistingSession: true,
      silent: true,
    );
  }

  Future<void> _sendMessage({
    String? contentOverride,
    bool approveWrites = false,
    bool skipUserBubble = false,
    bool requireExistingSession = false,
    bool silent = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final plan = planChatSend(
      voiceActive: _voice != null,
      sending: _sending,
      rawContent: contentOverride ?? _messageCtrl.text,
      approveWrites: approveWrites,
      requireExistingSession: requireExistingSession,
      sessionId: _currentSession?.id,
    );
    if (plan.blockKey == 'sending' || plan.blockKey == 'emptyContent') return;
    if (plan.blockKey == 'approvalNeedsSession') {
      _showSnackbar(l10n.aiChatApprovalNeedsOpenSession);
      return;
    }

    final content = plan.content;
    if (_voice != null) {
      _voice!.bargeIn();
    }
    if (_dictating) {
      unawaited(_toggleDictate());
    }
    await _ttsPlayer.stop();
    if (_speakingMessageKey != null) {
      _speakingMessageKey = null;
    }

    if (!skipUserBubble) {
      _messageCtrl.clear();
    }

    setState(() => _sending = true);
    _scrollToBottom(force: true);

    if (requireExistingSession || approveWrites) {
      if (_currentSession?.id == null) {
        if (!mounted) return;
        setState(() => _sending = false);
        _showSnackbar(l10n.aiChatApprovalNeedsOpenSession);
        return;
      }
    } else if (!await _ensureSession()) {
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
      if (!mounted) return;
      setState(() {
        _thread.appendOptimisticUser(content);
        _syncMessageKeys();
      });
    }

    if (!mounted) return;
    setState(() {
      if (silent || approveWrites) {
        _dropAwaitingApprovalAssistantForResume();
      }
      _stream.begin(phase: 'connecting');
      _sending = true;
    });

    Map<String, dynamic>? finalUsage;
    await _runAssistantStream(
      (cancelToken) => _aiService.sendMessageStream(
        sessionId: _currentSession!.id!,
        content: content,
        approveWrites: approveWrites,
        silent: silent || approveWrites,
        executionMode: _executionMode,
        model: _selectedModelCode,
        sseCursor: _sseCursor,
        onComplete: (usage, messageId) {
          finalUsage = usage;
        },
        cancelToken: cancelToken,
      ),
      errorLabel: l10n.aiChatErrorLabelSend,
    );
    if (!mounted) return;
    if (finalUsage != null) {
      setState(() => _thread.applyUsageToLastAssistant(finalUsage));
    }
  }

  void _setVoicePhase(VoicePhase phase, {Map<String, dynamic>? statusEvent}) {
    if (!mounted) return;
    setState(() => _voiceSession.applyPhase(phase, event: statusEvent));
  }

  String _voiceErrorText(AIChatVoiceEventEffect effect) {
    final l10n = AppLocalizations.of(context);
    final server = effect.errorServerMessage ?? l10n.aiChatUnknownError;
    switch (effect.errorKind) {
      case AIChatVoiceErrorMessageKind.timeout:
        return l10n.aiChatVoiceTimeout;
      case AIChatVoiceErrorMessageKind.serverRaw:
        return server;
      case AIChatVoiceErrorMessageKind.sttFailed:
        return l10n.aiChatVoiceSttFailed(server);
      case AIChatVoiceErrorMessageKind.emptyTranscript:
        return l10n.aiChatVoiceEmptyTranscript;
      case AIChatVoiceErrorMessageKind.forbidden:
        return l10n.aiChatVoiceForbidden;
      case AIChatVoiceErrorMessageKind.generic:
        return l10n.aiChatVoiceError(server);
      case null:
        return server;
    }
  }

  void _applyVoiceEventEffect(AIChatVoiceEventEffect effect) {
    if (!mounted) return;
    if (effect.phase != null) {
      _setVoicePhase(effect.phase!, statusEvent: effect.statusEventForPhase);
    }
    if (effect.showDummyTtsWarning) {
      _showSnackbar(AppLocalizations.of(context).aiVoiceDummyTtsWarning);
    }
    if (effect.approvalDetail != null) {
      _stream.ingestVoiceApproval(effect.approvalDetail!);
      _pendingWriteApproval = true;
      _pendingApprovalSessionId = _currentSession?.id;
    }
    if (effect.traceStep != null) {
      _stream.ingestVoiceTraceStep(effect.traceStep!);
    }
    final sessionId = _currentSession?.id;
    if (effect.userTranscript != null && sessionId != null) {
      setState(() {
        _messages = List<AIChatMessage>.from(_messages)
          ..add(
            AIChatMessage(
              sessionId: sessionId,
              role: MessageRole.user,
              content: effect.userTranscript!,
              createdAt: DateTime.now(),
            ),
          );
        _syncMessageKeys();
      });
      _scrollToBottom();
    }
    if (effect.assistantDelta != null) {
      setState(() {
        _stream.content = (_stream.content ?? '') + effect.assistantDelta!;
        _stream.timestamp ??= DateTime.now();
      });
      _scrollToBottom();
    }
    if (effect.assistantCommit != null || effect.clearStream) {
      final commit = effect.assistantCommit;
      final approvalOps =
          List<Map<String, dynamic>>.from(_stream.pendingApprovalOps);
      setState(() {
        if (commit != null &&
            sessionId != null &&
            (commit.text.trim().isNotEmpty || approvalOps.isNotEmpty)) {
          final results = <String, dynamic>{};
          for (var i = 0; i < approvalOps.length; i++) {
            results['voice_approval_$i'] = {
              ...approvalOps[i],
              'error': 'APPROVAL_REQUIRED',
            };
          }
          _messages = List<AIChatMessage>.from(_messages)
            ..add(
              AIChatMessage(
                sessionId: sessionId,
                role: MessageRole.assistant,
                content: commit.text.trim().isEmpty
                    ? 'در انتظار تأیید شما'
                    : commit.text,
                tokensUsed: commit.tokensUsed,
                functionResults: results.isEmpty ? null : results,
                createdAt: _stream.timestamp ?? DateTime.now(),
              ),
            );
          _syncMessageKeys();
          if (approvalOps.isNotEmpty) {
            _pendingWriteApproval = true;
            _pendingApprovalSessionId = sessionId;
          }
        }
        if (effect.clearStream) {
          _stream.clear(keepWriteApproval: approvalOps.isNotEmpty);
        }
      });
      _scrollToBottom();
      final interactionId = commit?.interactionId;
      if (interactionId != null) {
        unawaited(_promptVoiceFeedback(interactionId));
      }
    }
    if (effect.errorKind != null) {
      _showError(_voiceErrorText(effect));
      switch (effect.errorFollowUp) {
        case AIChatVoiceErrorFollowUp.stopSession:
          unawaited(_stopVoiceSession());
          break;
        case AIChatVoiceErrorFollowUp.listen:
          _setVoicePhase(VoicePhase.listening);
          break;
        case AIChatVoiceErrorFollowUp.none:
          break;
      }
    }
  }

  Future<void> _toggleVoice() async {
    if (!await _ensureSession()) return;
    if (_voiceStarting || _voice != null) return;
    if (_dictating) await _toggleDictate();
    await _ttsPlayer.stop();
    if (mounted) setState(() => _speakingMessageKey = null);

    setState(_voiceSession.beginConnecting);
    final ready = Completer<void>();
    var gotReady = false;
    final controller = VoiceChatController(
      sessionId: _currentSession!.id!,
      collectDataOptIn: _voiceCollectData,
      modelCode: _selectedModelCode,
      executionMode: _executionMode,
      sttCode: _selectedSttCode,
      ttsCode: _selectedTtsCode,
      onEvent: (event) {
        final effect = interpretVoiceServerEvent(event, gotReady: gotReady);
        _applyVoiceEventEffect(effect);
        if (effect.completeReady && !gotReady) {
          gotReady = true;
          if (!ready.isCompleted) ready.complete();
        }
        if (effect.completeReadyError != null &&
            !gotReady &&
            !ready.isCompleted) {
          ready.completeError(effect.completeReadyError!);
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
      setState(() => _voiceSession.attachEngine(controller));
      try {
        await ready.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (_) {}
      if (!mounted) return;
      await _voice!.startRecording();
      if (!mounted) return;
      setState(_voiceSession.markListening);
    } catch (e) {
      if (!mounted) return;
      setState(_voiceSession.failStart);
      _showError(
        AppLocalizations.of(context).aiChatVoiceStartFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!force && !_autoScrollEnabled) return;
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      final delta = (target - _scrollController.position.pixels).abs();
      // حین استریم با دلتای کوچک به‌صورت نرم می‌چسبد؛ پرش‌های بزرگ
      // (بارگذاری اولیه/تعویض گفت‌وگو) بدون انیمیشن انجام می‌شود.
      if (force || delta < 8 || delta > 600) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
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
        final extra = errorData['extra'] as Map<String, dynamic>? ??
            errorData['extra_data'] as Map<String, dynamic>?;
        final tokensUsed = subscription?['tokens_used'] as int? ??
            extra?['tokens_used'] as int? ??
            0;
        final tokensLimit = subscription?['tokens_limit'] as int? ??
            extra?['tokens_limit'] as int? ??
            0;
        title = 'سهمیه تمام شده';
        message = details?['message'] as String? ??
            errorData['message'] as String? ??
            'سهمیه توکن شما تمام شده است.';
        if (tokensLimit > 0) {
          message =
              '$message\n\nشما ${formatWithThousands(tokensUsed)} از ${formatWithThousands(tokensLimit)} توکن خود را استفاده کرده‌اید.';
        }
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

    showGlassDialog<void>(
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
    await showGlassModalBottomSheet<void>(
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
                Text(
                  AppLocalizations.of(context).aiVoiceSettingsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    AppLocalizations.of(context).aiVoiceImproveQualityTitle,
                  ),
                  subtitle: Text(
                    AppLocalizations.of(context).aiVoiceImproveQualitySubtitle,
                  ),
                  value: _voiceCollectData,
                  onChanged: (v) => setState(() => _voiceCollectData = v),
                ),
                if (widget.businessId != null) ...[
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      AppLocalizations.of(context).aiVoiceBusinessAllowCloud,
                    ),
                    subtitle: Text(
                      _policyAllowCloudAudio
                          ? AppLocalizations.of(context)
                              .aiVoiceBusinessAllowCloudHint
                          : AppLocalizations.of(context).aiVoiceCloudDisabled,
                    ),
                    value: _businessAllowCloudAudio,
                    onChanged: _savingVoiceSettings
                        ? null
                        : (v) {
                            Navigator.of(context).pop();
                            unawaited(_setBusinessCloudAudio(v));
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

  void _openHistory() {
    if (AIChatDesign.showPersistentSidebar(context) && !_focusChatMode) return;
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final persistentSidebar =
        AIChatDesign.showPersistentSidebar(context) && !_focusChatMode;

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
              businessId: widget.businessId,
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
                  businessId: widget.businessId,
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
                    if (_isHomeMode)
                      AIChatOnboardingBanner(businessId: widget.businessId),
                    if (_attachments.isNotEmpty && !_isHomeMode)
                      _buildAttachmentsBar(theme),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: AIChatDesign.layoutTransition,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, _) {
                          return currentChild ?? const SizedBox.shrink();
                        },
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
                                onDictate: widget.businessId != null
                                    ? _toggleDictate
                                    : null,
                                dictating: _dictating,
                                dictateBusy: _dictateBusy,
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
                                availableModels: _availableModels,
                                selectedModelCode: _selectedModelCode,
                                modelsLoading: _modelsLoading,
                                onModelChanged:
                                    _sending ? null : _onModelChanged,
                                modelPricingHint: _composerModelHint(),
                                creditWarningMessage: _creditWarningText(),
                                onCreditUpgrade: widget.businessId != null
                                    ? _navigateToSubscription
                                    : null,
                                executionMode: _executionMode,
                                onExecutionModeChanged:
                                    _sending ? null : _onExecutionModeChanged,
                                sttModels: _voiceCatalog?.stt ?? const [],
                                ttsModels: _voiceCatalog?.tts ?? const [],
                                selectedSttCode: _selectedSttCode,
                                selectedTtsCode: _selectedTtsCode,
                                onSttChanged:
                                    _sending ? null : _onSttChanged,
                                onTtsChanged:
                                    _sending ? null : _onTtsChanged,
                                onAttach: _pickAndUploadAttachment,
                                attachmentsBar: _attachments.isNotEmpty
                                    ? _buildAttachmentsBar(
                                        theme,
                                        padded: false,
                                      )
                                    : null,
                              )
                            : AIChatThreadView(
                                key: ValueKey(
                                  'thread-${_currentSession?.id}',
                                ),
                                businessId: widget.businessId,
                                suppressApprovalToolChips:
                                    _showWriteApprovalBanner,
                                messages: _messages,
                                messageKeys: _messageKeys,
                                streamingContent: _stream.content,
                                streamingToolActivities:
                                    _stream.toolActivities,
                                streamingTraceSteps: _stream.traceSteps,
                                streamingTodoSnapshot: _stream.todoSnapshot,
                                streamingStatusPhase: _stream.statusPhase,
                                streamingStatusStep: _stream.statusStep,
                                streamingIteration: _stream.iteration,
                                streamingMaxIterations:
                                    _stream.maxIterations,
                                streamingElapsedSeconds:
                                    _stream.elapsedSeconds > 0
                                    ? _stream.elapsedSeconds
                                    : null,
                                streamingAgentBudget: _stream.agentBudget,
                                streamingTimestamp: _stream.timestamp,
                                messageFeedbackRatings:
                                    _messageFeedbackRatings,
                                onCopyMessage: _copyToClipboard,
                                onFeedback: _submitFeedback,
                                onRegenerateLast: _regenerateLastResponse,
                                lastAssistantMessageId:
                                    _messages.isNotEmpty &&
                                        _messages.last.role ==
                                            MessageRole.assistant
                                    ? _messages.last.id
                                    : null,
                                contextUsageRatio:
                                    _stream.contextUsageRatio,
                                contextUsagePercent:
                                    _stream.contextUsagePercent,
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
                                onDictate: widget.businessId != null
                                    ? _toggleDictate
                                    : null,
                                dictating: _dictating,
                                dictateBusy: _dictateBusy,
                                onStopVoice: _stopVoiceSession,
                                onStopGenerating: _stopGenerating,
                                onScrollToBottom: () =>
                                    _scrollToBottom(force: true),
                                onMessageLongPress: _showMessageActions,
                                onAttach: _pickAndUploadAttachment,
                                availableModels: _availableModels,
                                selectedModelCode: _selectedModelCode,
                                modelsLoading: _modelsLoading,
                                onModelChanged:
                                    _sending ? null : _onModelChanged,
                                modelPricingHint: _composerModelHint(),
                                streamErrorMessage: _streamErrorMessage,
                                streamErrorRecoverable: _streamErrorRecoverable,
                                onRetryStreamError:
                                    _streamErrorRecoverable &&
                                            _pendingStreamRetry != null
                                        ? () {
                                            setState(() {
                                              _streamErrorMessage = null;
                                              _streamErrorRecoverable = false;
                                            });
                                            _pendingStreamRetry!();
                                          }
                                        : null,
                                onDismissStreamError: () => setState(() {
                                  _streamErrorMessage = null;
                                  _streamErrorRecoverable = false;
                                }),
                                continueRunId: _continueRunId,
                                continueRunHint: _continueStopMessage,
                                onContinueRun: _continueRunId != null
                                    ? () => unawaited(_continueIncompleteRun())
                                    : null,
                                onDismissContinueRun: () => setState(() {
                                  _continueRunId = null;
                                  _continueStopMessage = null;
                                }),
                                showWriteApproval: _showWriteApprovalBanner,
                                writeApprovalOps: _collectPendingApprovalOps(),
                                writeApprovalLoading: _sending,
                                canConfirmWriteApproval:
                                    _canConfirmWriteApproval || _sending,
                                writeApprovalBlockedReason:
                                    (_canConfirmWriteApproval || _sending)
                                    ? null
                                    : 'برای تأیید، همان گفت‌وگویی را از تاریخچه باز کنید که دستیار در آن درخواست تأیید کرده است.',
                                onConfirmWriteApproval: _confirmWriteApproval,
                                onDismissWriteApproval: () =>
                                    setState(_clearWriteApprovalState),
                                onTodoStatus: _onSessionTodoStatus,
                                onCancelSubagent: _cancelSubagent,
                                creditWarningMessage: _creditWarningText(),
                                onCreditUpgrade: widget.businessId != null
                                    ? _navigateToSubscription
                                    : null,
                                executionMode: _executionMode,
                                onExecutionModeChanged:
                                    _sending ? null : _onExecutionModeChanged,
                                onSpeakMessage: widget.businessId != null
                                    ? _speakMessage
                                    : null,
                                speakingMessageKey: _speakingMessageKey,
                                sttModels: _voiceCatalog?.stt ?? const [],
                                ttsModels: _voiceCatalog?.tts ?? const [],
                                selectedSttCode: _selectedSttCode,
                                selectedTtsCode: _selectedTtsCode,
                                onSttChanged:
                                    _sending ? null : _onSttChanged,
                                onTtsChanged:
                                    _sending ? null : _onTtsChanged,
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
    final embedded = widget.embeddedInShell;
    final l10n = AppLocalizations.of(context);
    final showHistoryBtn =
        !AIChatDesign.showPersistentSidebar(context) || _focusChatMode;
    final showSubtitle = _isGenerating;
    final title = _isHomeMode
        ? l10n.aiChatAssistantTitle
        : (_currentSession?.title ?? l10n.aiChatConversationFallbackTitle);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          embedded ? 8 : 10,
          embedded ? 6 : 10,
          12,
          embedded ? 4 : 6,
        ),
        child: Row(
          children: [
            if (showHistoryBtn)
              IconButton(
                tooltip: l10n.aiChatHistoryTooltip,
                onPressed: _openHistory,
                icon: const Icon(Icons.menu_rounded),
                visualDensity: VisualDensity.compact,
              ),
            if (!embedded) ...[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: scheme.primary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: embedded ? TextAlign.center : TextAlign.start,
                style: (embedded
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (showSubtitle)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Semantics(
                  liveRegion: true,
                  label: l10n.aiChatResponding,
                  child: Text(
                    l10n.aiChatResponding,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            if (_isGenerating) ...[
              const SizedBox(width: 4),
              compact
                  ? IconButton(
                      tooltip: l10n.aiChatStop,
                      onPressed: _stopGenerating,
                      icon: Icon(
                        Icons.stop_circle_outlined,
                        color: scheme.error,
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: _stopGenerating,
                      icon: Icon(
                        Icons.stop_circle_outlined,
                        color: scheme.error,
                      ),
                      label: Text(l10n.aiChatStop),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: scheme.error,
                      ),
                    ),
            ],
            if (!compact)
              IconButton(
                tooltip: l10n.aiChatNewConversation,
                onPressed: _startNewConversation,
                icon: const Icon(Icons.edit_outlined, size: 20),
              )
            else
              IconButton(
                tooltip: l10n.aiChatNewConversation,
                onPressed: _startNewConversation,
                icon: const Icon(Icons.edit_outlined),
              ),
            _AiMoreMenu(
              isHomeMode: _isHomeMode,
              hasSession: _currentSession != null,
              hasBusiness: widget.businessId != null,
              focusMode: _focusChatMode,
              showFocusToggle: AIChatDesign.showPersistentSidebar(context),
              onSearch: _openMessageSearch,
              onMemory: _openMemorySheet,
              onExport: _exportConversation,
              onConnectors: _openConnectorsSheet,
              onKnowledge: _openKnowledgeSheet,
              onSkills: _openSkillsSheet,
              onVoiceSettings: _openVoiceSettings,
              onToggleFocus: () =>
                  setState(() => _focusChatMode = !_focusChatMode),
            ),
            if (!embedded)
              IconButton(
                tooltip: l10n.aiChatClose,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsBar(ThemeData theme, {bool padded = true}) {
    final scheme = theme.colorScheme;
    return Container(
      margin: padded
          ? const EdgeInsets.fromLTRB(16, 0, 16, 6)
          : EdgeInsets.zero,
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

  String? _creditWarningText() {
    if (!_showCreditWarning || _availabilityInfo == null) {
      return null;
    }

    final details = _availabilityInfo!['details'] as Map<String, dynamic>?;
    final subscription = details?['subscription'] as Map<String, dynamic>?;
    final isUnlimited = subscription?['is_unlimited'] as bool? ?? false;
    if (isUnlimited) {
      return null;
    }
    final tokensRemaining = subscription?['tokens_remaining'] as int? ?? 0;
    return 'اعتبار رو به اتمام — ${tokensRemaining.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} توکن باقی‌مانده';
  }
}

class _AiMoreMenu extends StatelessWidget {
  final bool isHomeMode;
  final bool hasSession;
  final bool hasBusiness;
  final bool focusMode;
  final bool showFocusToggle;
  final VoidCallback onSearch;
  final VoidCallback onMemory;
  final VoidCallback onExport;
  final VoidCallback onConnectors;
  final VoidCallback onKnowledge;
  final VoidCallback onSkills;
  final VoidCallback onVoiceSettings;
  final VoidCallback? onToggleFocus;

  const _AiMoreMenu({
    required this.isHomeMode,
    required this.hasSession,
    required this.hasBusiness,
    this.focusMode = false,
    this.showFocusToggle = false,
    required this.onSearch,
    required this.onMemory,
    required this.onExport,
    required this.onConnectors,
    required this.onKnowledge,
    required this.onSkills,
    required this.onVoiceSettings,
    this.onToggleFocus,
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
          case _AiMenuAction.skills:
            onSkills();
            break;
          case _AiMenuAction.voice:
            onVoiceSettings();
            break;
          case _AiMenuAction.focus:
            onToggleFocus?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (showFocusToggle && onToggleFocus != null)
          PopupMenuItem(
            value: _AiMenuAction.focus,
            child: _AiMenuItem(
              icon: focusMode
                  ? Icons.view_sidebar_rounded
                  : Icons.crop_landscape_rounded,
              label: focusMode ? 'نمای کامل' : 'حالت تمرکز',
            ),
          ),
        if (!isHomeMode && hasSession) ...[
          const PopupMenuItem(
            value: _AiMenuAction.search,
            child: _AiMenuItem(
              icon: Icons.search_rounded,
              label: 'جستجو در پیام‌ها',
            ),
          ),
          const PopupMenuItem(
            value: _AiMenuAction.memory,
            child: _AiMenuItem(
              icon: Icons.psychology_outlined,
              label: 'حافظه دستیار',
            ),
          ),
          const PopupMenuItem(
            value: _AiMenuAction.export,
            child: _AiMenuItem(
              icon: Icons.ios_share_outlined,
              label: 'خروجی گفت‌وگو',
            ),
          ),
        ],
        if (hasBusiness) ...[
          const PopupMenuItem(
            value: _AiMenuAction.connectors,
            child: _AiMenuItem(icon: Icons.link_rounded, label: 'کانکتورها'),
          ),
          const PopupMenuItem(
            value: _AiMenuAction.knowledge,
            child: _AiMenuItem(
              icon: Icons.menu_book_outlined,
              label: 'دانشنامه',
            ),
          ),
          const PopupMenuItem(
            value: _AiMenuAction.skills,
            child: _AiMenuItem(
              icon: Icons.extension_outlined,
              label: 'مهارت‌های AI',
            ),
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

enum _AiMenuAction {
  search,
  memory,
  export,
  connectors,
  knowledge,
  skills,
  voice,
  focus,
}

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

class _AIChatEditMessageDialog extends StatefulWidget {
  final String initialText;

  const _AIChatEditMessageDialog({required this.initialText});

  @override
  State<_AIChatEditMessageDialog> createState() =>
      _AIChatEditMessageDialogState();
}

class _AIChatEditMessageDialogState extends State<_AIChatEditMessageDialog> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final compact = AIChatDesign.isCompactWidth(context);
    return AlertDialog(
      title: const Text('ویرایش پیام'),
      content: AIChatEnterToSend(
        focusNode: _focus,
        onSend: _submit,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          maxLines: 6,
          autofocus: true,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: compact
                ? 'متن جدید…'
                : 'متن جدید… (Enter ارسال، Shift+Enter خط جدید)',
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('ارسال'),
        ),
      ],
    );
  }
}
