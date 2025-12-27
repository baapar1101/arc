import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/voice/voice_chat_controller.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:share_plus/share_plus.dart';

/// دیالوگی برای دسترسی سریع به چت هوش مصنوعی از هر صفحه
class AIChatDialog extends StatefulWidget {
  final int? businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;
  final bool fullscreen;

  const AIChatDialog({
    super.key,
    this.businessId,
    required this.authStore,
    this.calendarController,
    this.fullscreen = false,
  });

  static Future<void> show(
    BuildContext context, {
    required AuthStore authStore,
    int? businessId,
    CalendarController? calendarController,
  }) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final bool isMobile = shortestSide < 600;
    if (isMobile) {
      return Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => AIChatDialog(
            fullscreen: true,
            businessId: businessId,
            authStore: authStore,
            calendarController: calendarController,
          ),
        ),
      );
    }
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
  String? _streamingContent;
  DateTime? _streamingTimestamp;
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sessionsLoading = true;
  bool _messagesLoading = false;
  bool _sending = false;
  bool _historyCollapsed = true;
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
  bool get _isCompact => MediaQuery.sizeOf(context).width < 720;
  bool get _isGenerating => _sending && _streamingContent != null;

  @override
  void initState() {
    super.initState();
    ApiClient.bindAuthStore(widget.authStore);
    _aiService = AIService(ApiClient());
    _scrollController.addListener(_onScrollChanged);
    _loadSessions();
  }

  @override
  void dispose() {
    _streamCancelToken?.cancel('disposed');
    _scrollController.removeListener(_onScrollChanged);
    _messageCtrl.dispose();
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
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (_isCompact) return time;
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
                  leading: const Icon(Icons.copy),
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
      _showError('خطا در ثبت بازخورد: $e');
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
      setState(() {
        _messages = msgs;
        _messagesLoading = false;
      });
      _scrollToBottom(force: true);
      // بررسی اعتبار بعد از انتخاب session
      _checkAvailability();
    } catch (e) {
      setState(() => _messagesLoading = false);
      _showError('خطا در دریافت پیام‌ها: $e');
    }
  }
  
  Future<void> _checkAvailability() async {
    try {
      final availability = await _aiService.checkAvailability(
        businessId: widget.businessId,
        estimatedTokens: 1000,
      );
      
      setState(() {
        _availabilityInfo = availability;
        
        // بررسی هشدار کم بودن اعتبار
        final details = availability['details'] as Map<String, dynamic>?;
        final subscription = details?['subscription'] as Map<String, dynamic>?;
        final usagePercentage = subscription?['usage_percentage'] as num?;
        
        _showCreditWarning = usagePercentage != null && usagePercentage >= 80;
      });
    } catch (e) {
      // در صورت خطا در چک اعتبار، اجازه ادامه بده
      debugPrint('[AIChatDialog] Error checking availability: $e');
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
    
    // چک اعتبار قبل از ارسال
    try {
      final availability = await _aiService.checkAvailability(
        businessId: widget.businessId,
        estimatedTokens: content.length * 2, // تخمین تقریبی
      );
      
      if (!(availability['can_use'] as bool? ?? false)) {
        _showDetailedError(availability);
        return;
      }
    } catch (e) {
      // در صورت خطا در چک، اجازه ادامه بده
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
          _showError('ارسال پیام ناموفق بود: $error');
        },
        cancelToken: cancelToken,
      )) {
        accumulatedContent += chunk;
        
        // به‌روزرسانی UI با throttle برای جلوگیری از لگ روی موبایل
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
      setState(() {
        _sending = false;
        _streamingContent = null;
        _streamingTimestamp = null;
      });
      _streamCancelToken = null;
      _showError('ارسال پیام ناموفق بود: $e');
    }
  }

  Future<void> _toggleVoice() async {
    if (_currentSession == null) return;
    if (_voiceStarting) return;

    // اگر voice فعال است، فقط ضبط را toggle کن
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
        _showError('خطا در کنترل ضبط: $e');
      }
      return;
    }

    // Start voice
    setState(() => _voiceStarting = true);
    final ready = Completer<void>();
    bool gotReady = false;
    final controller = VoiceChatController(
      sessionId: _currentSession!.id!,
      collectDataOptIn: _voiceCollectData,
      onEvent: (event) {
        final type = event['type'] as String?;
        if (type == 'ready') {
          if (!gotReady) {
            gotReady = true;
            if (!ready.isCompleted) ready.complete();
          }
          setState(() {
            // Connection ready
          });
          return;
        }
        if (type == 'started') {
          if (!gotReady) {
            gotReady = true;
            if (!ready.isCompleted) ready.complete();
          }
          setState(() {
            // Session started
          });
          return;
        }
        if (type == 'stt_started') {
          setState(() {
            // STT processing started
          });
          return;
        }
        if (type == 'speech_start') {
          setState(() {
            // User started speaking
          });
          return;
        }
        if (type == 'speech_end') {
          setState(() {
            // User finished speaking
          });
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
          // اگر سرور قبل از آماده شدن خطا بدهد، ready را fail کن تا flow سریع‌تر متوقف شود
          if (!gotReady && !ready.isCompleted) {
            ready.completeError(errorMessage);
          }
          
          // Handle specific error codes
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
          return;
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
      // منتظر آماده‌شدن سمت سرور قبل از شروع ارسال فریم‌ها (جلوگیری از خطای "ابتدا پیام start...")
      try {
        await ready.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // اگر event نرسید، کمی صبر کن و ادامه بده (بعضی سرورها ready را ارسال نمی‌کنند)
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (_) {
        // اگر ready با خطا کامل شد، بگذار ادامه‌ی try/catch بیرونی هندل کند
      }
      if (!mounted) return;
      await _voice!.startRecording();
      if (!mounted) return;
      setState(() => _voiceRecording = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceStarting = false);
      _showError('خطا در شروع مکالمه صوتی: $e');
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!force && !_autoScrollEnabled) return;
      if (_scrollController.hasClients) {
        final target = _scrollController.position.maxScrollExtent;
        final current = _scrollController.position.pixels;
        final delta = (target - current).abs();
        // برای جلوگیری از پرش روی فاصله‌های خیلی زیاد
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
        if (suggestions.isNotEmpty) {
          message += '\n\n${suggestions.join('\n')}';
        }
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Navigate to subscription page
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
        message = 'شما ${tokensUsed.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} از ${tokensLimit.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} توکن خود را استفاده کرده‌اید.';
        final suggestions = (details?['suggestions'] as List?)?.cast<String>() ?? [];
        if (suggestions.isNotEmpty) {
          message += '\n\n${suggestions.join('\n')}';
        }
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Navigate to subscription page
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
        message = 'موجودی: ${balance.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} ریال\n'
                  'هزینه تخمینی: ${estimatedCost.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} ریال';
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Navigate to wallet page
            },
            child: const Text('شارژ کیف پول'),
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
    
    showDialog(
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
  
  Widget _buildCreditWarning() {
    if (!_showCreditWarning || _availabilityInfo == null) {
      return const SizedBox.shrink();
    }
    
    final details = _availabilityInfo!['details'] as Map<String, dynamic>?;
    final subscription = details?['subscription'] as Map<String, dynamic>?;
    final tokensRemaining = subscription?['tokens_remaining'] as int? ?? 0;
    final suggestions = (details?['suggestions'] as List?)?.cast<String>() ?? const <String>[];
    
    return Container(
      color: Colors.orange.withOpacity(0.1),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '⚠️ اعتبار شما رو به اتمام است',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${tokensRemaining.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} توکن باقی مانده',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12,
                  ),
                ),
                if (suggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      suggestions.first,
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // TODO: Navigate to subscription page
            },
            child: const Text('ارتقا پلن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context).size;
    final double dialogWidth = media.width > 1200 ? 1200 : media.width * 0.98;
    final double dialogHeight = media.height > 900 ? 900 : media.height * 0.95;
    final double contentWidth = widget.fullscreen ? media.width : dialogWidth;

    final Widget content = Column(
          children: [
        if (!widget.fullscreen)
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
                if (_isGenerating)
                  TextButton.icon(
                    onPressed: _stopGenerating,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('توقف'),
                  ),
                IconButton(
                  tooltip: 'تنظیمات',
                  onPressed: _openVoiceSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
                const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _startNewConversation,
                    icon: const Icon(Icons.add_comment),
                  label: _isCompact ? const Text('جدید') : const Text('گفت‌وگوی جدید'),
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
              if (!widget.fullscreen && !_isCompact) ...[
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
              ],
              Expanded(child: _buildChatPanel(theme, contentWidth)),
            ],
          ),
        ),
      ],
    );

    if (widget.fullscreen) {
      return Scaffold(
        endDrawer: Drawer(
          child: SafeArea(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('گفت‌وگوها'),
                  trailing: IconButton(
                    tooltip: 'گفت‌وگوی جدید',
                    onPressed: () async {
                      Navigator.of(context).pop(); // close drawer
                      await _startNewConversation();
                    },
                    icon: const Icon(Icons.add),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _buildHistoryPanel(theme, closeOnSelect: true)),
              ],
            ),
          ),
        ),
        appBar: AppBar(
          title: Text(_currentSession?.title ?? 'دستیار هوش مصنوعی'),
          actions: [
            if (_isGenerating)
              IconButton(
                tooltip: 'توقف تولید پاسخ',
                onPressed: _stopGenerating,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            IconButton(
              tooltip: 'تنظیمات',
              onPressed: _openVoiceSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              tooltip: 'گفت‌وگوی جدید',
              onPressed: _startNewConversation,
              icon: const Icon(Icons.add_comment),
            ),
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'گفت‌وگوها',
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                icon: const Icon(Icons.history),
              ),
            ),
          ],
        ),
        body: content,
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: dialogHeight),
        child: content,
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

  Widget _buildChatPanel(ThemeData theme, double contentWidth) {
    final double bubbleFraction = _isCompact ? 0.92 : (contentWidth < 1000 ? 0.75 : 0.55);
    final double bubbleMaxWidth = contentWidth * bubbleFraction;

    return _currentSession == null
        ? Center(
            child: _sessionsLoading
                ? const CircularProgressIndicator()
                : const Text('ابتدا یک گفت‌وگو را انتخاب کنید'),
          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
              if (!widget.fullscreen)
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
                              _buildCreditWarning(),
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                      child: _messagesLoading
                          ? const Center(child: CircularProgressIndicator())
                          : (_messages.isEmpty
                              ? const Center(child: Text('پیامی وجود ندارد. گفت‌وگو را آغاز کنید.'))
                                          : ListView.builder(
                                              controller: _scrollController,
                                              padding: const EdgeInsets.all(16),
                                              itemCount: _messages.length,
                                              itemBuilder: (context, index) {
                                                final msg = _messages[index];
                                                final bool isUser = msg.role == MessageRole.user;
                                    final timeText = _formatMessageTime(msg.createdAt);
                                                return Align(
                                                  alignment: isUser
                                                      ? AlignmentDirectional.centerEnd
                                                      : AlignmentDirectional.centerStart,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onLongPress: () => _showMessageActions(msg),
                                                  child: Container(
                                          margin: const EdgeInsets.symmetric(vertical: 6),
                                                    padding: const EdgeInsets.all(12),
                                          constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                                                    decoration: BoxDecoration(
                                                      color: isUser
                                                          ? theme.colorScheme.primary.withOpacity(0.1)
                                                          : theme.colorScheme.surfaceVariant,
                                                      borderRadius: BorderRadius.circular(16),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                      children: [
                                                        Text(
                                                          isUser ? 'شما' : 'AI',
                                                          style: theme.textTheme.labelSmall?.copyWith(
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                  ),
                                                  const Spacer(),
                                                  if (timeText.isNotEmpty)
                                                    Text(
                                                      timeText,
                                                      textDirection: TextDirection.ltr,
                                                      style: theme.textTheme.labelSmall?.copyWith(
                                                        color: theme.colorScheme.onSurfaceVariant,
                                                      ),
                                                    ),
                                                ],
                                                        ),
                                                        const SizedBox(height: 4),
                                              SelectableText(msg.content),
                                                      ],
                                          ),
                                                    ),
                                                  ),
                                                );
                                              },
                                )),
                                    ),
                                    if (_streamingContent != null)
                      _buildStreamingPreview(theme, bubbleMaxWidth),
                                  ],
                                ),
                              ),
              _buildComposerBar(theme),
            ],
          );
  }

  Widget _buildComposerBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
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
                isDense: true,
                                        ),
                                        onSubmitted: (_) {
                                          if (!_sending && _messageCtrl.text.trim().isNotEmpty) {
                                            _sendMessage();
                                          }
                                        },
                                      ),
                                    ),
          const SizedBox(width: 8),
                                    IconButton(
            tooltip: _voice == null ? 'مکالمه صوتی' : (_voiceRecording ? 'توقف ضبط' : 'شروع ضبط'),
                                      onPressed: _voiceStarting ? null : _toggleVoice,
                                      icon: _voiceStarting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Icon(
                    _voice == null ? Icons.mic : (_voiceRecording ? Icons.mic_off : Icons.mic_none),
                                            ),
                                    ),
          if (_voice != null)
                                      IconButton(
                                        tooltip: 'پایان مکالمه صوتی',
                                        onPressed: _voiceStarting ? null : _stopVoiceSession,
                                        icon: const Icon(Icons.call_end),
                                      ),
          if (_isGenerating)
            IconButton(
              tooltip: 'توقف تولید پاسخ',
              onPressed: _stopGenerating,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
                                    FilledButton.icon(
                                      onPressed: _sending ? null : _sendMessage,
                                      icon: _sending
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.send),
            label: _isCompact ? const Text('ارسال') : const Text('ارسال'),
                                    ),
                                  ],
      ),
    );
  }

  Widget _buildStreamingPreview(ThemeData theme, double bubbleMaxWidth) {
    final content = _streamingContent ?? '';
    final timeText = _formatMessageTime(_streamingTimestamp);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: bubbleMaxWidth,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'AI (در حال نوشتن...)',
                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (timeText.isNotEmpty)
                  Text(
                    timeText,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(content),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryPanel(ThemeData theme, {bool closeOnSelect = false}) {
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
          onTap: () {
            if (closeOnSelect) {
              Navigator.of(context).pop(); // close drawer
            }
            _selectSession(session);
          },
        );
      },
    );
  }
}

