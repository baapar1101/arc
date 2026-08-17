import 'package:hesabix_ui/services/voice/voice_chat_controller.dart';
import 'package:hesabix_ui/services/voice/voice_phase.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_turn.dart';

enum AIChatVoiceErrorFollowUp { none, listen, stopSession }

enum AIChatVoiceErrorMessageKind {
  timeout,
  serverRaw,
  sttFailed,
  emptyTranscript,
  forbidden,
  generic,
}

class AIChatVoiceAssistantCommit {
  final String text;
  final int tokensUsed;
  final int? interactionId;

  const AIChatVoiceAssistantCommit({
    required this.text,
    required this.tokensUsed,
    this.interactionId,
  });
}

/// نتیجهٔ تفسیر یک رویداد WS صوت — بدون BuildContext.
class AIChatVoiceEventEffect {
  final VoicePhase? phase;
  final Map<String, dynamic>? statusEventForPhase;
  final bool showDummyTtsWarning;
  final bool completeReady;
  final Object? completeReadyError;
  final String? userTranscript;
  final String? assistantDelta;
  final AIChatVoiceAssistantCommit? assistantCommit;
  final bool clearStream;
  final AIChatVoiceErrorFollowUp errorFollowUp;
  final AIChatVoiceErrorMessageKind? errorKind;
  final String? errorServerMessage;

  const AIChatVoiceEventEffect({
    this.phase,
    this.statusEventForPhase,
    this.showDummyTtsWarning = false,
    this.completeReady = false,
    this.completeReadyError,
    this.userTranscript,
    this.assistantDelta,
    this.assistantCommit,
    this.clearStream = false,
    this.errorFollowUp = AIChatVoiceErrorFollowUp.none,
    this.errorKind,
    this.errorServerMessage,
  });
}

int voiceUsageTotalTokens(Map<String, dynamic>? usage) {
  final input = usage?['input_tokens'] as int? ?? 0;
  final output = usage?['output_tokens'] as int? ?? 0;
  return usage?['total_tokens'] as int? ?? (input + output);
}

AIChatVoiceErrorMessageKind voiceErrorMessageKind(String? errorCode) {
  switch (errorCode) {
    case 'SESSION_TIMEOUT':
    case 'INACTIVITY_TIMEOUT':
      return AIChatVoiceErrorMessageKind.timeout;
    case 'VOICE_DEPS_MISSING':
    case 'WEBM_NOT_SUPPORTED':
    case 'NO_ACTIVE_SUBSCRIPTION':
    case 'QUOTA_EXCEEDED':
    case 'INSUFFICIENT_FUNDS':
    case 'AVAILABILITY_CHECK_FAILED':
      return AIChatVoiceErrorMessageKind.serverRaw;
    case 'STT_FAILED':
      return AIChatVoiceErrorMessageKind.sttFailed;
    case 'EMPTY_TRANSCRIPT':
      return AIChatVoiceErrorMessageKind.emptyTranscript;
    case 'FORBIDDEN':
      return AIChatVoiceErrorMessageKind.forbidden;
    default:
      return AIChatVoiceErrorMessageKind.generic;
  }
}

AIChatVoiceErrorFollowUp voiceErrorFollowUp(String? errorCode) {
  switch (errorCode) {
    case 'SESSION_TIMEOUT':
    case 'INACTIVITY_TIMEOUT':
    case 'VOICE_DEPS_MISSING':
    case 'WEBM_NOT_SUPPORTED':
    case 'NO_ACTIVE_SUBSCRIPTION':
    case 'QUOTA_EXCEEDED':
    case 'INSUFFICIENT_FUNDS':
    case 'AVAILABILITY_CHECK_FAILED':
    case 'FORBIDDEN':
      return AIChatVoiceErrorFollowUp.stopSession;
    case 'STT_FAILED':
    case 'EMPTY_TRANSCRIPT':
      return AIChatVoiceErrorFollowUp.listen;
    default:
      return AIChatVoiceErrorFollowUp.none;
  }
}

/// تفسیر رویداد سرور صوت همان‌طور که dialog قبلاً inline انجام می‌داد.
AIChatVoiceEventEffect interpretVoiceServerEvent(
  Map<String, dynamic> event, {
  required bool gotReady,
}) {
  final type = event['type'] as String?;
  String? statusPhase;
  if (type == 'voice_status') {
    statusPhase = event['phase'] as String?;
  }
  final mapped = voicePhaseFromServerEvent(type, statusPhase: statusPhase);
  final statusEventForPhase = mapped != null ? event : null;

  var showDummyTts = false;
  if (type == 'started') {
    final tts = event['tts'];
    if (tts is Map && tts['dummy_warning'] == true) {
      showDummyTts = true;
    }
  }

  if (type == 'ready' || type == 'started') {
    return AIChatVoiceEventEffect(
      phase: mapped,
      statusEventForPhase: statusEventForPhase,
      showDummyTtsWarning: showDummyTts,
      completeReady: true,
    );
  }

  if (type == 'transcript_final') {
    final text = (event['text'] as String?)?.trim() ?? '';
    return AIChatVoiceEventEffect(
      phase: mapped,
      statusEventForPhase: statusEventForPhase,
      userTranscript: text.isEmpty ? null : text,
    );
  }

  if (type == 'assistant_text_delta') {
    final delta = event['text'] as String? ?? '';
    return AIChatVoiceEventEffect(
      phase: mapped,
      statusEventForPhase: statusEventForPhase,
      assistantDelta: delta.isEmpty ? null : delta,
    );
  }

  if (type == 'assistant_done') {
    final text = (event['text'] as String?) ?? '';
    final usageRaw = event['usage'];
    final usage = usageRaw is Map
        ? Map<String, dynamic>.from(usageRaw)
        : null;
    return AIChatVoiceEventEffect(
      phase: mapped,
      statusEventForPhase: statusEventForPhase,
      assistantCommit: AIChatVoiceAssistantCommit(
        text: text,
        tokensUsed: voiceUsageTotalTokens(usage),
        interactionId: event['interaction_id'] as int?,
      ),
      clearStream: true,
    );
  }

  if (type == 'error') {
    final errorCode = event['error'] as String?;
    final raw = (event['message'] as String?)?.trim();
    final serverMessage = (raw == null || raw.isEmpty) ? null : raw;
    final followUp = voiceErrorFollowUp(errorCode);
    return AIChatVoiceEventEffect(
      phase: mapped,
      statusEventForPhase: statusEventForPhase,
      completeReadyError: gotReady ? null : (serverMessage ?? ''),
      errorFollowUp: followUp,
      errorKind: voiceErrorMessageKind(errorCode),
      errorServerMessage: serverMessage,
    );
  }

  return AIChatVoiceEventEffect(
    phase: mapped,
    statusEventForPhase: statusEventForPhase,
  );
}

/// State جلسهٔ صوت جدا از God Widget (UX-01).
///
/// ساخت [VoiceChatController] و UI در dialog می‌ماند.
class AIChatVoiceSessionController {
  VoiceChatController? engine;
  bool starting = false;
  VoicePhase phase = VoicePhase.idle;
  Map<String, dynamic>? statusEvent;
  bool collectData = false;
  int? lastFeedbackInteractionId;

  bool get isActive => engine != null;

  bool get isBusy => starting || isActive;

  void beginConnecting() {
    starting = true;
    phase = VoicePhase.connecting;
    statusEvent = null;
  }

  void attachEngine(VoiceChatController controller) {
    engine = controller;
    starting = false;
  }

  void markListening() {
    phase = VoicePhase.listening;
  }

  void failStart() {
    starting = false;
    phase = VoicePhase.idle;
  }

  void beginStopping() {
    starting = true;
    phase = VoicePhase.idle;
    statusEvent = null;
  }

  void finishStopped() {
    engine = null;
    starting = false;
    phase = VoicePhase.idle;
    statusEvent = null;
  }

  void applyPhase(VoicePhase next, {Map<String, dynamic>? event}) {
    phase = next;
    if (event != null) {
      statusEvent = event;
    }
  }

  /// اگر قبلاً برای همین interaction بازخورد خواسته شده false است.
  bool shouldPromptFeedback(int interactionId) {
    if (lastFeedbackInteractionId == interactionId) return false;
    lastFeedbackInteractionId = interactionId;
    return true;
  }
}
