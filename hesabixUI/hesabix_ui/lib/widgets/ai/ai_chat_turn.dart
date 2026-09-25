// منطق نوبت چت جدا از God Widget (UX-01).
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/services/voice/voice_phase.dart';

/// اگر ارسال الان مجاز نیست، کلید دلیل را برمی‌گرداند.
///
/// `sending` / `emptyContent` / `approvalNeedsSession`
/// تماس صوتی دیگر ارسال متن را قفل نمی‌کند (تایپ وسط تماس مجاز است).
String? sendBlockReason({
  required bool voiceActive,
  required bool sending,
  required String content,
  required bool approveWrites,
  required bool requireExistingSession,
  required int? sessionId,
}) {
  if (sending) return 'sending';
  if (content.trim().isEmpty && !approveWrites) return 'emptyContent';
  if ((approveWrites || requireExistingSession) && sessionId == null) {
    return 'approvalNeedsSession';
  }
  return null;
}

/// نتیجهٔ آماده‌سازی یک نوبت ارسال — بدون setState.
class AIChatSendPlan {
  final String content;
  final String? blockKey;

  const AIChatSendPlan({required this.content, this.blockKey});

  bool get canSend => blockKey == null;
}

AIChatSendPlan planChatSend({
  required bool voiceActive,
  required bool sending,
  required String rawContent,
  required bool approveWrites,
  required bool requireExistingSession,
  required int? sessionId,
}) {
  final content = rawContent.trim();
  return AIChatSendPlan(
    content: content,
    blockKey: sendBlockReason(
      voiceActive: voiceActive,
      sending: sending,
      content: content,
      approveWrites: approveWrites,
      requireExistingSession: requireExistingSession,
      sessionId: sessionId,
    ),
  );
}

/// نگاشت رویداد سرور صوت به فاز UI — بدون setState.
VoicePhase? voicePhaseFromServerEvent(
  String? type, {
  String? statusPhase,
}) {
  switch (type) {
    case 'ready':
    case 'reconnected':
    case 'started':
    case 'speech_start':
      return VoicePhase.listening;
    case 'speech_end':
    case 'stt_started':
    case 'transcript_final':
      return VoicePhase.processing;
    case 'assistant_text_delta':
      return VoicePhase.speaking;
    case 'assistant_done':
      return VoicePhase.listening;
    case 'approval_required':
      return VoicePhase.processing;
    case 'error':
      return VoicePhase.error;
    case 'voice_status':
      if (statusPhase == 'speaking') return VoicePhase.speaking;
      if (statusPhase == 'listening') return VoicePhase.listening;
      return VoicePhase.processing;
    default:
      return null;
  }
}

AIChatMessage withUpdatedTokens(AIChatMessage message, int? totalTokens) {
  return AIChatMessage(
    id: message.id,
    sessionId: message.sessionId,
    role: message.role,
    content: message.content,
    functionCalls: message.functionCalls,
    functionResults: message.functionResults,
    tokensUsed: totalTokens ?? message.tokensUsed,
    createdAt: message.createdAt,
  );
}

List<AIChatMessage> patchLastAssistantUsage(
  List<AIChatMessage> messages,
  Map<String, dynamic>? usage,
) {
  if (usage == null || messages.isEmpty) return messages;
  final last = messages.last;
  if (last.role != MessageRole.assistant) return messages;
  final total = usage['total_tokens'] as int?;
  final updated = List<AIChatMessage>.from(messages);
  updated[updated.length - 1] = withUpdatedTokens(last, total);
  return updated;
}
