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
}
