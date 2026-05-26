import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/business_route_paths.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/voice/voice_chat_controller.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_design.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_home_view.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_sidebar.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_suggestions.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_thread_view.dart';
import 'package:share_plus/share_plus.dart';

/// دسترسی سریع به چت هوش مصنوعی — رابط تمام‌صفحه شبیه صفحه نخست ChatGPT.
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
  String? _streamingContent;
  DateTime? _streamingTimestamp;
  final TextEditingController _messageCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _sessionsLoading = true;
  bool _messagesLoading = false;
  bool _sending = false;
  Map<String, dynamic>? _availabilityInfo;
  bool _showCreditWarning = false;
  bool _voiceCollectData = false;
  VoiceChatController? _voice;
  bool _voiceStarting = false;
  bool _voiceRecording = false;
  int? _lastVoiceInteractionId;
  CancelToken? _streamCancelToken;
  DateTime? _lastStreamUiUpdate;
  bool _autoScrollEnabled = true;

  bool get _isJalali => widget.calendarController?.isJalali ?? true;
  bool get _isGenerating => _sending && _streamingContent != null;
  bool get _isHomeMode =>
      !_messagesLoading &&
      _messages.isEmpty &&
      _streamingContent == null &&
      !_sending;

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
    _scrollController.addListener(_onScrollChanged);
    _loadSessions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isHomeMode) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _streamCancelToken?.cancel('disposed');
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
    setState(() {
      _sending = false;
      _streamingContent = null;
      _streamingTimestamp = null;
    });
    if (showNotice) {
      _showSnackbar('تولید پاسخ متوقف شد');
    }
  }

  Future<void> _stopVoiceSession() async {
    if (_voice == null) return;
    setState(() {
      _voiceStarting = true;
      _voiceRecording = false;
    });
    try {
      await _voice!.dispose();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _voice = null;
      _voiceStarting = false;
    });
  }

  Future<void> _promptVoiceFeedback(int interactionId) async {
    if (_lastVoiceInteractionId == interactionId) return;
    _lastVoiceInteractionId = interactionId;

    int rating = 4;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('کیفیت صدای AI'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('به کیفیت صدای پاسخ AI امتیاز دهید تا در آینده بهتر شود.'),
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
      _showError('خطا در ثبت بازخورد: ${ErrorExtractor.forContext(e, context)}');
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _sessionsLoading = true);
    try {
      final list = await _aiService.listChatSessions(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        list.sort((a, b) {
          final aDate = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        _sessions = list;
        _sessionsLoading = false;
      });
      await _checkAvailability();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sessionsLoading = false);
      _showError('خطا در بارگذاری گفت‌وگوها: ${ErrorExtractor.forContext(e, context)}');
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
      await _loadSessions();
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showError('خطا در آغاز گفت‌وگو: ${ErrorExtractor.forContext(e, context)}');
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
      if (_messages.isEmpty) {
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _messagesLoading = false);
      _showError('خطا در دریافت پیام‌ها: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _checkAvailability() async {
    try {
      final availability = await _aiService.checkAvailability(
        businessId: widget.businessId,
        estimatedTokens: 1000,
      );
      if (!mounted) return;
      setState(() {
        _availabilityInfo = availability;
        final details = availability['details'] as Map<String, dynamic>?;
        final subscription = details?['subscription'] as Map<String, dynamic>?;
        final usagePercentage = subscription?['usage_percentage'] as num?;
        _showCreditWarning = usagePercentage != null && usagePercentage >= 80;
      });
    } catch (e) {
      debugPrint('[AIChatDialog] Error checking availability: $e');
    }
  }

  Future<void> _goToHome() async {
    if (_isGenerating) _stopGenerating(showNotice: false);
    if (_voice != null) await _stopVoiceSession();
    if (!mounted) return;
    setState(() {
      _currentSession = null;
      _messages = [];
      _messagesLoading = false;
      _streamingContent = null;
      _streamingTimestamp = null;
    });
    _messageCtrl.clear();
    _focusNode.requestFocus();
  }

  Future<void> _startNewConversation() => _goToHome();

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
      final wasCurrent = _currentSession?.id == session.id;
      await _loadSessions();
      if (!mounted) return;
      if (wasCurrent) {
        await _goToHome();
      }
    } catch (e) {
      if (!mounted) return;
      _showError('حذف گفت‌وگو با خطا مواجه شد: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _onSuggestionSelected(AIChatSuggestion suggestion) async {
    _messageCtrl.text = suggestion.prompt;
    await _sendMessage();
  }

  Future<void> _sendMessage() async {
    if (_sending || _messageCtrl.text.trim().isEmpty) return;
    if (!await _ensureSession()) return;

    final content = _messageCtrl.text.trim();

    try {
      final availability = await _aiService.checkAvailability(
        businessId: widget.businessId,
        estimatedTokens: content.length * 2,
      );
      if (!(availability['can_use'] as bool? ?? false)) {
        _showDetailedError(availability);
        return;
      }
    } catch (e) {
      debugPrint('[AIChatDialog] Error checking availability before send: $e');
    }

    _messageCtrl.clear();

    final userMessage = AIChatMessage(
      sessionId: _currentSession!.id!,
      role: MessageRole.user,
      content: content,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages = List<AIChatMessage>.from(_messages)..add(userMessage);
      _sending = true;
    });
    _scrollToBottom(force: true);

    try {
      _streamCancelToken?.cancel('replaced');
      final cancelToken = CancelToken();
      _streamCancelToken = cancelToken;
      String accumulatedContent = '';
      Map<String, dynamic>? finalUsage;
      setState(() {
        _streamingContent = '';
        _streamingTimestamp = DateTime.now();
      });

      await for (final chunk in _aiService.sendMessageStream(
        sessionId: _currentSession!.id!,
        content: content,
        onComplete: (usage, messageId) {
          finalUsage = usage;
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _sending = false;
            _streamingContent = null;
            _streamingTimestamp = null;
          });
          _showError('ارسال پیام ناموفق بود: ${ErrorExtractor.forContext(error, context)}');
        },
        cancelToken: cancelToken,
      )) {
        accumulatedContent += chunk;
        final now = DateTime.now();
        final shouldUpdate = _lastStreamUiUpdate == null ||
            now.difference(_lastStreamUiUpdate!) >= const Duration(milliseconds: 60);
        if (shouldUpdate) {
          _lastStreamUiUpdate = now;
          if (!mounted) return;
          setState(() => _streamingContent = accumulatedContent);
          _scrollToBottom();
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (!mounted) return;
      setState(() {
        if (accumulatedContent.isNotEmpty) {
          _messages = List<AIChatMessage>.from(_messages)
            ..add(
              AIChatMessage(
                sessionId: _currentSession!.id!,
                role: MessageRole.assistant,
                content: accumulatedContent,
                tokensUsed: finalUsage?['total_tokens'] as int? ?? 0,
                createdAt: _streamingTimestamp,
              ),
            );
        }
        _streamingContent = null;
        _streamingTimestamp = null;
        _sending = false;
      });
      _streamCancelToken = null;
      _scrollToBottom(force: true);
      unawaited(_loadSessions());
    } catch (e, stack) {
      if (e is DioException && CancelToken.isCancel(e)) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _streamingContent = null;
          _streamingTimestamp = null;
        });
        _streamCancelToken = null;
        return;
      }
      debugPrint('[AIChatDialog] Streaming error: $e');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _streamingContent = null;
        _streamingTimestamp = null;
      });
      _streamCancelToken = null;
      _showError('ارسال پیام ناموفق بود: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _toggleVoice() async {
    if (!await _ensureSession()) return;
    if (_voiceStarting) return;

    if (_voice != null) {
      try {
        if (_voiceRecording) {
          await _voice!.stopRecording();
          if (!mounted) return;
          setState(() => _voiceRecording = false);
        } else {
          await _voice!.startRecording();
          if (!mounted) return;
          setState(() => _voiceRecording = true);
        }
      } catch (e) {
        if (!mounted) return;
        _showError('خطا در کنترل ضبط: ${ErrorExtractor.forContext(e, context)}');
      }
      return;
    }

    setState(() => _voiceStarting = true);
    final ready = Completer<void>();
    bool gotReady = false;
    final controller = VoiceChatController(
      sessionId: _currentSession!.id!,
      collectDataOptIn: _voiceCollectData,
      onEvent: (event) {
        final type = event['type'] as String?;
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
            _streamingContent = (_streamingContent ?? '') + delta;
            _streamingTimestamp ??= DateTime.now();
          });
          _scrollToBottom();
          return;
        }
        if (type == 'assistant_done') {
          final text = (event['text'] as String?) ?? '';
          final usage = event['usage'] as Map<String, dynamic>?;
          final interactionId = event['interaction_id'] as int?;
          setState(() {
            if (text.trim().isNotEmpty) {
              _messages = List<AIChatMessage>.from(_messages)
                ..add(
                  AIChatMessage(
                    sessionId: _currentSession!.id!,
                    role: MessageRole.assistant,
                    content: text,
                    tokensUsed: usage?['total_tokens'] as int? ?? 0,
                    createdAt: _streamingTimestamp ?? DateTime.now(),
                  ),
                );
            }
            _streamingContent = null;
            _streamingTimestamp = null;
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
          if (errorCode == 'SESSION_TIMEOUT' || errorCode == 'INACTIVITY_TIMEOUT') {
            _showError('جلسه صوتی به دلیل timeout بسته شد. لطفاً دوباره تلاش کنید.');
            _stopVoiceSession();
          } else if (errorCode == 'STT_FAILED') {
            _showError('خطا در تشخیص گفتار: $errorMessage');
          } else if (errorCode == 'EMPTY_TRANSCRIPT') {
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
      setState(() => _voiceRecording = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceStarting = false);
      _showError('خطا در شروع مکالمه صوتی: ${ErrorExtractor.forContext(e, context)}');
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
        final suggestions = (details?['suggestions'] as List?)?.cast<String>() ?? [];
        if (suggestions.isNotEmpty) message += '\n\n${suggestions.join('\n')}';
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
        ];
        break;
      default:
        title = 'خطا';
        message = details?['message'] as String? ?? 'خطای نامشخص';
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
        ];
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
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
                  subtitle: const Text('با ارسال داده‌های ناشناس به بهبود تجربه صوتی کمک کنید.'),
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
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAppBar(theme),
                    if (_showCreditWarning) _buildCreditWarning(theme),
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
                                voiceRecording: _voiceRecording,
                                canUseAi: _canUseAi,
                                blockReason: _aiBlockReason,
                                onSend: _sendMessage,
                                onMic: _toggleVoice,
                                onStopVoice: _stopVoiceSession,
                                onSuggestionSelected: _onSuggestionSelected,
                                onUpgradePlan: widget.businessId != null
                                    ? _navigateToSubscription
                                    : null,
                              )
                            : AIChatThreadView(
                                key: ValueKey('thread-${_currentSession?.id}'),
                                messages: _messages,
                                streamingContent: _streamingContent,
                                streamingTimestamp: _streamingTimestamp,
                                messagesLoading: _messagesLoading,
                                sending: _sending,
                                disabled: !_canUseAi,
                                voiceStarting: _voiceStarting,
                                voiceActive: _voice != null,
                                voiceRecording: _voiceRecording,
                                showScrollToBottom: !_autoScrollEnabled,
                                isGenerating: _isGenerating,
                                scrollController: _scrollController,
                                messageController: _messageCtrl,
                                focusNode: _focusNode,
                                formatTime: _formatMessageTime,
                                onSend: _sendMessage,
                                onMic: _toggleVoice,
                                onStopVoice: _stopVoiceSession,
                                onStopGenerating: _stopGenerating,
                                onScrollToBottom: () => _scrollToBottom(force: true),
                                onMessageLongPress: _showMessageActions,
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
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
        child: Row(
          children: [
            if (showHistoryBtn)
              IconButton(
                tooltip: 'گفت‌وگوها',
                onPressed: _openHistory,
                icon: const Icon(Icons.menu_rounded),
              ),
            Expanded(
              child: Text(
                _isHomeMode
                    ? 'دستیار هوشمند'
                    : (_currentSession?.title ?? 'گفت‌وگو'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (_isGenerating)
              IconButton(
                tooltip: 'توقف',
                onPressed: _stopGenerating,
                icon: Icon(Icons.stop_circle_outlined, color: scheme.error),
              ),
            IconButton(
              tooltip: 'تنظیمات صدا',
              onPressed: _openVoiceSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
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
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'اعتبار رو به اتمام — ${tokensRemaining.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} توکن باقی‌مانده',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade900),
            ),
          ),
          TextButton(
            onPressed: widget.businessId != null ? _navigateToSubscription : null,
            child: const Text('ارتقا'),
          ),
        ],
      ),
    );
  }
}
