import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_stream_controller.dart';

void main() {
  String label(String tool, String? key) => key ?? tool;

  group('AIChatStreamController', () {
    test('begin then clear resets stream state', () {
      final c = AIChatStreamController();
      c.begin(phase: 'connecting');
      expect(c.statusPhase, 'connecting');
      expect(c.content, '');
      expect(c.isActive, isTrue);

      c.clear();
      expect(c.content, isNull);
      expect(c.statusPhase, isNull);
      expect(c.isActive, isFalse);
      expect(c.toolActivities, isEmpty);
    });

    test('content delta sets writing and accumulates via updateAccumulatedContent', () {
      final c = AIChatStreamController();
      c.begin();
      const chunk = AIStreamChunk(contentDelta: 'سلام');
      c.applyChunk(chunk, resolveToolLabel: label);
      expect(c.statusPhase, 'writing');
      c.updateAccumulatedContent('سلام', chunk);
      expect(c.content, 'سلام');
    });

    test('tool start then end with approval records pending ops', () {
      final c = AIChatStreamController();
      c.begin();
      c.applyChunk(
        const AIStreamChunk(
          toolEvent: AIStreamToolEvent(
            type: 'tool_start',
            tool: 'create_invoice',
            toolKey: 'createInvoice',
          ),
        ),
        resolveToolLabel: label,
      );
      expect(c.statusPhase, 'running_tool');
      expect(c.toolActivities.single.running, isTrue);

      c.applyChunk(
        const AIStreamChunk(
          toolEvent: AIStreamToolEvent(
            type: 'tool_end',
            tool: 'create_invoice',
            toolKey: 'createInvoice',
            success: false,
            approvalRequired: true,
            approvalDetail: {
              'function': 'create_invoice',
              'arguments': {'customer': 'علی'},
            },
          ),
        ),
        resolveToolLabel: label,
      );
      expect(c.toolActivities.single.running, isFalse);
      expect(c.toolActivities.single.approvalRequired, isTrue);
      expect(c.pendingWriteApproval, isTrue);
      expect(c.pendingApprovalOps, hasLength(1));
      expect(c.pendingApprovalOps.first['function'], 'create_invoice');
    });

    test('heartbeat while connecting switches phase to thinking', () {
      final c = AIChatStreamController();
      c.begin(phase: 'connecting');
      c.applyChunk(
        const AIStreamChunk(heartbeatElapsedMs: 1500),
        resolveToolLabel: label,
      );
      expect(c.statusPhase, 'thinking');
      expect(c.elapsedSeconds, 2);
    });

    test('applyDoneMetadata stores budget, runId and awaiting approval', () {
      final c = AIChatStreamController();
      c.begin();
      c.applyDoneMetadata(
        const AIStreamChunk(
          runId: 'run-1',
          awaitingApproval: true,
          agentBudget: AIStreamAgentBudget(
            stopReason: 'budget_exhausted',
            stopMessageFa: 'بودجه تمام شد',
          ),
        ),
      );
      expect(c.runId, 'run-1');
      expect(c.pendingWriteApproval, isTrue);
      expect(c.statusPhase, 'awaiting_approval');
      expect(c.agentBudget?.stopMessageFa, 'بودجه تمام شد');
    });

    test('snapshotForCancel captures partial content and tools', () {
      final c = AIChatStreamController();
      c.begin();
      const delta = AIStreamChunk(contentDelta: 'نیمه');
      c.applyChunk(delta, resolveToolLabel: label);
      c.updateAccumulatedContent('نیمه', delta);
      final snap = c.snapshotForCancel();
      expect(snap, isNotNull);
      expect(snap!.partialContent, 'نیمه');
    });

    test('mergeAgentTraceFromDone replaces matching step ids', () {
      final c = AIChatStreamController();
      c.begin();
      c.applyChunk(
        const AIStreamChunk(
          traceStep: AIAgentTraceStep(
            stepId: 'llm_1',
            kind: 'context',
            state: 'active',
          ),
        ),
        resolveToolLabel: label,
      );
      c.mergeAgentTraceFromDone(const [
        AIAgentTraceStep(stepId: 'llm_1', kind: 'context', state: 'done'),
        AIAgentTraceStep(stepId: 'answer_1', kind: 'answer', state: 'done'),
      ]);
      expect(c.traceSteps, hasLength(2));
      expect(c.traceSteps.first.state, 'done');
      expect(c.traceSteps.last.stepId, 'answer_1');
    });
  });
}
