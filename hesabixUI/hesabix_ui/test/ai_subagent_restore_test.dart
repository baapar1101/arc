import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_subagent_restore.dart';

void main() {
  test('merges persisted subagent into last assistant trace', () {
    final messages = [
      AIChatMessage(
        sessionId: 1,
        role: MessageRole.user,
        content: 'گزارش بده',
      ),
      AIChatMessage(
        sessionId: 1,
        role: MessageRole.assistant,
        content: 'در حال بررسی',
        functionResults: {
          kAgentTraceStorageKey: [
            {
              'step_id': 'plan_1',
              'kind': 'plan',
              'state': 'done',
            },
          ],
        },
      ),
    ];
    final merged = mergeSubagentSummariesIntoMessages(messages, [
      const AIChatSubagentSummary(
        subagentId: 'sub1',
        goal: 'فروش ماه',
        status: 'completed',
      ),
    ]);
    final steps = extractAgentTraceFromResults(merged.last.functionResults);
    expect(steps.any((s) => s.kind == 'subagent' && s.subagentId == 'sub1'), isTrue);
    expect(steps.any((s) => s.kind == 'plan'), isTrue);
  });

  test('functionResultsAwaitApproval reads storage key', () {
    expect(
      functionResultsAwaitApproval({kAwaitingApprovalStorageKey: true}),
      isTrue,
    );
    expect(functionResultsAwaitApproval({'ok': true}), isFalse);
  });
}
