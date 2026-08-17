import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/services/voice/voice_phase.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_voice_session.dart';

void main() {
  group('interpretVoiceServerEvent', () {
    test('ready completes handshake and maps to listening', () {
      final effect = interpretVoiceServerEvent(
        const {'type': 'ready'},
        gotReady: false,
      );
      expect(effect.completeReady, isTrue);
      expect(effect.phase, VoicePhase.listening);
      expect(effect.showDummyTtsWarning, isFalse);
    });

    test('started with dummy tts warns', () {
      final effect = interpretVoiceServerEvent(
        const {
          'type': 'started',
          'tts': {'dummy_warning': true},
        },
        gotReady: false,
      );
      expect(effect.completeReady, isTrue);
      expect(effect.showDummyTtsWarning, isTrue);
      expect(effect.phase, VoicePhase.listening);
    });

    test('transcript_final ignores empty and keeps text', () {
      expect(
        interpretVoiceServerEvent(
          const {'type': 'transcript_final', 'text': '  '},
          gotReady: true,
        ).userTranscript,
        isNull,
      );
      expect(
        interpretVoiceServerEvent(
          const {'type': 'transcript_final', 'text': '  فروش  '},
          gotReady: true,
        ).userTranscript,
        'فروش',
      );
    });

    test('assistant_text_delta accumulates only non-empty', () {
      expect(
        interpretVoiceServerEvent(
          const {'type': 'assistant_text_delta', 'text': ''},
          gotReady: true,
        ).assistantDelta,
        isNull,
      );
      final effect = interpretVoiceServerEvent(
        const {'type': 'assistant_text_delta', 'text': 'سلام'},
        gotReady: true,
      );
      expect(effect.assistantDelta, 'سلام');
      expect(effect.phase, VoicePhase.speaking);
    });

    test('assistant_done commits tokens and interaction id', () {
      final effect = interpretVoiceServerEvent(
        {
          'type': 'assistant_done',
          'text': 'پاسخ',
          'interaction_id': 9,
          'usage': {'input_tokens': 3, 'output_tokens': 5},
        },
        gotReady: true,
      );
      expect(effect.clearStream, isTrue);
      expect(effect.assistantCommit?.text, 'پاسخ');
      expect(effect.assistantCommit?.tokensUsed, 8);
      expect(effect.assistantCommit?.interactionId, 9);
      expect(effect.phase, VoicePhase.listening);
    });

    test('timeout error stops session and fails handshake', () {
      final effect = interpretVoiceServerEvent(
        const {
          'type': 'error',
          'error': 'SESSION_TIMEOUT',
          'message': 'timed out',
        },
        gotReady: false,
      );
      expect(effect.phase, VoicePhase.error);
      expect(effect.errorFollowUp, AIChatVoiceErrorFollowUp.stopSession);
      expect(effect.errorKind, AIChatVoiceErrorMessageKind.timeout);
      expect(effect.completeReadyError, 'timed out');
    });

    test('empty transcript listens again', () {
      final effect = interpretVoiceServerEvent(
        const {'type': 'error', 'error': 'EMPTY_TRANSCRIPT'},
        gotReady: true,
      );
      expect(effect.errorFollowUp, AIChatVoiceErrorFollowUp.listen);
      expect(effect.errorKind, AIChatVoiceErrorMessageKind.emptyTranscript);
      expect(effect.completeReadyError, isNull);
    });

    test('unknown error does not stop session', () {
      final effect = interpretVoiceServerEvent(
        const {
          'type': 'error',
          'error': 'WEIRD',
          'message': 'boom',
        },
        gotReady: true,
      );
      expect(effect.errorFollowUp, AIChatVoiceErrorFollowUp.none);
      expect(effect.errorKind, AIChatVoiceErrorMessageKind.generic);
      expect(effect.errorServerMessage, 'boom');
    });
  });

  group('AIChatVoiceSessionController', () {
    test('connecting then attach then stop', () {
      final c = AIChatVoiceSessionController();
      c.beginConnecting();
      expect(c.starting, isTrue);
      expect(c.phase, VoicePhase.connecting);
      expect(c.isActive, isFalse);
      expect(c.isBusy, isTrue);

      c.failStart();
      expect(c.starting, isFalse);
      expect(c.phase, VoicePhase.idle);
    });

    test('shouldPromptFeedback is once per interaction', () {
      final c = AIChatVoiceSessionController();
      expect(c.shouldPromptFeedback(4), isTrue);
      expect(c.shouldPromptFeedback(4), isFalse);
      expect(c.shouldPromptFeedback(5), isTrue);
    });
  });
}
