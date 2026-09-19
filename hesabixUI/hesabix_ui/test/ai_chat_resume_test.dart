import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_resume.dart';

void main() {
  group('resumeHintFromFunctionResults', () {
    test('empty when no run checkpoint', () {
      final hint = resumeHintFromFunctionResults({'ok': true});
      expect(hint.canContinue, isFalse);
      expect(hint.runId, isNull);
    });

    test('reads run_id and stop message from _agent_run / _agent_budget', () {
      final hint = resumeHintFromFunctionResults({
        kAgentRunStorageKey: {
          'run_id': 'run-abc',
          'can_continue': true,
          'status': 'interrupted',
        },
        kAgentBudgetStorageKey: {
          'stop_message_fa': 'بودجهٔ تکرار تمام شد',
        },
      });
      expect(hint.canContinue, isTrue);
      expect(hint.runId, 'run-abc');
      expect(hint.stopMessageFa, 'بودجهٔ تکرار تمام شد');
    });

    test('uses fallback stop message when budget has none', () {
      final hint = resumeHintFromFunctionResults(
        {
          kAgentRunStorageKey: {
            'run_id': 'run-2',
            'status': 'budget_exhausted',
          },
        },
        fallbackStopMessage: 'از بنر استریم',
      );
      expect(hint.runId, 'run-2');
      expect(hint.stopMessageFa, 'از بنر استریم');
    });
  });

  group('resumeHintFromMessages', () {
    test('only inspects the latest assistant message', () {
      final messages = [
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.assistant,
          content: 'قطع شد',
          functionResults: {
            kAgentRunStorageKey: {
              'run_id': 'old-run',
              'can_continue': true,
            },
          },
        ),
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.user,
          content: 'ادامه بده',
        ),
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.assistant,
          content: 'تمام',
          functionResults: {'ok': true},
        ),
      ];
      final hint = resumeHintFromMessages(messages);
      expect(hint.canContinue, isFalse);
      expect(hint.runId, isNull);
    });
  });

  group('session reopen catch-up', () {
    test('awaits assistant when last message is the user', () {
      final messages = [
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.user,
          content: 'موجودی صندوق؟',
        ),
      ];
      expect(sessionAwaitsAssistantReply(messages), isTrue);
    });

    test('does not await when assistant already persisted', () {
      final messages = [
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.user,
          content: 'سوال',
        ),
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.assistant,
          content: 'پاسخ',
        ),
      ];
      expect(sessionAwaitsAssistantReply(messages), isFalse);
    });

    test('cold UI replays SSE from the start even if server last_event_id is high', () {
      expect(
        sseReplayCursor(uiHasAssistantPartial: false, serverLastEventId: 42),
        0,
      );
    });

    test('live reconnect keeps server cursor when partial is already on screen', () {
      expect(
        sseReplayCursor(uiHasAssistantPartial: true, serverLastEventId: 42),
        42,
      );
    });
  });
}
