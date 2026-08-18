import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/services/voice/voice_phase.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_turn.dart';

void main() {
  test('sendBlockReason blocks voice, empty, and approval without session', () {
    expect(
      sendBlockReason(
        voiceActive: true,
        sending: false,
        content: 'سلام',
        approveWrites: false,
        requireExistingSession: false,
        sessionId: 1,
      ),
      'voiceActive',
    );
    expect(
      sendBlockReason(
        voiceActive: false,
        sending: false,
        content: '  ',
        approveWrites: false,
        requireExistingSession: false,
        sessionId: 1,
      ),
      'emptyContent',
    );
    expect(
      sendBlockReason(
        voiceActive: false,
        sending: false,
        content: 'تأیید',
        approveWrites: true,
        requireExistingSession: true,
        sessionId: null,
      ),
      'approvalNeedsSession',
    );
    expect(
      sendBlockReason(
        voiceActive: false,
        sending: false,
        content: 'گزارش فروش',
        approveWrites: false,
        requireExistingSession: false,
        sessionId: null,
      ),
      isNull,
    );
  });

  test('planChatSend trims content and surfaces block key', () {
    final blocked = planChatSend(
      voiceActive: false,
      sending: false,
      rawContent: '   ',
      approveWrites: false,
      requireExistingSession: false,
      sessionId: 1,
    );
    expect(blocked.canSend, isFalse);
    expect(blocked.blockKey, 'emptyContent');

    final ready = planChatSend(
      voiceActive: false,
      sending: false,
      rawContent: '  فروش  ',
      approveWrites: false,
      requireExistingSession: false,
      sessionId: 1,
    );
    expect(ready.canSend, isTrue);
    expect(ready.content, 'فروش');
  });

  test('planChatSend allows empty content when approving writes', () {
    final plan = planChatSend(
      voiceActive: false,
      sending: false,
      rawContent: '   ',
      approveWrites: true,
      requireExistingSession: true,
      sessionId: 9,
    );
    expect(plan.canSend, isTrue);
    expect(plan.content, isEmpty);
  });

  test('voicePhaseFromServerEvent maps known types', () {
    expect(voicePhaseFromServerEvent('ready'), VoicePhase.listening);
    expect(voicePhaseFromServerEvent('stt_started'), VoicePhase.processing);
    expect(voicePhaseFromServerEvent('assistant_text_delta'), VoicePhase.speaking);
    expect(voicePhaseFromServerEvent('error'), VoicePhase.error);
    expect(
      voicePhaseFromServerEvent('voice_status', statusPhase: 'speaking'),
      VoicePhase.speaking,
    );
    expect(voicePhaseFromServerEvent('unknown'), isNull);
  });

  test('patchLastAssistantUsage updates last assistant tokens', () {
    final messages = [
      AIChatMessage(
        sessionId: 1,
        role: MessageRole.user,
        content: 'سلام',
      ),
      AIChatMessage(
        sessionId: 1,
        role: MessageRole.assistant,
        content: 'پاسخ',
        tokensUsed: 0,
      ),
    ];
    final patched = patchLastAssistantUsage(messages, {'total_tokens': 42});
    expect(patched.last.tokensUsed, 42);
    expect(messages.last.tokensUsed, 0);
  });
}
