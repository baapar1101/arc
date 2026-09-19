import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_stream_controller.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_stream_turn.dart';

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

  group('AIChatStreamController.consume', () {
    test('accumulates deltas then commits done content', () async {
      final c = AIChatStreamController();
      c.begin();
      final outcome = await c.consume(
        Stream.fromIterable(const [
          AIStreamChunk(contentDelta: 'سلام '),
          AIStreamChunk(contentDelta: 'دنیا', done: true, messageId: 42),
        ]),
        resolveToolLabel: label,
      );
      expect(outcome.status, AIChatStreamTurnStatus.success);
      expect(outcome.resolvedContent, 'سلام دنیا');
      expect(outcome.assistantMessageId, 42);
      expect(outcome.hasVisibleOutput, isTrue);
      expect(c.content, isNotNull);
    });

    test('finalContent replaces accumulated deltas', () async {
      final c = AIChatStreamController();
      c.begin();
      final outcome = await c.consume(
        Stream.fromIterable(const [
          AIStreamChunk(contentDelta: 'پیش‌نویس'),
          AIStreamChunk(done: true, finalContent: 'متن نهایی ذخیره‌شده'),
        ]),
        resolveToolLabel: label,
      );
      expect(outcome.resolvedContent, 'متن نهایی ذخیره‌شده');
      expect(outcome.status, AIChatStreamTurnStatus.success);
    });

    test('stream end without done is a recoverable reconnect error', () async {
      final c = AIChatStreamController();
      c.begin();
      c.runId = 'run-live';
      final outcome = await c.consume(
        Stream.fromIterable(const [
          AIStreamChunk(contentDelta: 'نیمه'),
        ]),
        resolveToolLabel: label,
        sseCursorRunId: 'run-live',
      );
      expect(outcome.status, AIChatStreamTurnStatus.chunkError);
      expect(outcome.errorCode, 'EMPTY_STREAM');
      expect(outcome.shouldReconnect, isTrue);
      expect(outcome.continueRunId, 'run-live');
    });

    test('done without visible output is empty', () async {
      final c = AIChatStreamController();
      c.begin();
      final outcome = await c.consume(
        Stream.fromIterable(const [AIStreamChunk(done: true)]),
        resolveToolLabel: label,
      );
      expect(outcome.status, AIChatStreamTurnStatus.empty);
      expect(outcome.hasVisibleOutput, isFalse);
      expect(outcome.resolvedContent, isEmpty);
    });

    test('chunk error keeps resume id and partial content', () async {
      final c = AIChatStreamController();
      c.begin();
      final outcome = await c.consume(
        Stream.fromIterable(const [
          AIStreamChunk(contentDelta: 'نیمه'),
          AIStreamChunk(
            error: 'قطع شد',
            recoverable: true,
            runId: 'run-resume',
            canContinue: true,
            agentBudget: AIStreamAgentBudget(stopMessageFa: 'ادامه دهید'),
          ),
        ]),
        resolveToolLabel: label,
        sseCursorRunId: 'cursor-run',
      );
      expect(outcome.status, AIChatStreamTurnStatus.chunkError);
      expect(outcome.errorMessage, 'قطع شد');
      expect(outcome.errorRecoverable, isTrue);
      expect(outcome.applyContinue, isTrue);
      expect(outcome.continueRunId, 'run-resume');
      expect(outcome.continueStopMessage, 'ادامه دهید');
      expect(outcome.hasPartialAssistant, isTrue);
      expect(outcome.partialContent, 'نیمه');
    });

    test('canContinue from function_results when chunk flag is absent', () async {
      final c = AIChatStreamController();
      c.begin();
      final outcome = await c.consume(
        Stream.fromIterable([
          const AIStreamChunk(contentDelta: 'گزارش'),
          AIStreamChunk(
            done: true,
            runId: 'run-budget',
            functionResults: {
              kAgentRunStorageKey: {
                'run_id': 'run-budget',
                'can_continue': true,
              },
              kAgentBudgetStorageKey: {
                'stop_message_fa': 'بودجه تمام شد',
              },
            },
          ),
        ]),
        resolveToolLabel: label,
      );
      expect(outcome.status, AIChatStreamTurnStatus.success);
      expect(outcome.continueRunId, 'run-budget');
      expect(outcome.continueStopMessage, 'بودجه تمام شد');
    });

    test('stream without done is recoverable reconnect with partial', () async {
      final c = AIChatStreamController();
      c.begin();
      final outcome = await c.consume(
        Stream.fromIterable(const [
          AIStreamChunk(contentDelta: 'فقط دلتا'),
        ]),
        resolveToolLabel: label,
      );
      expect(outcome.status, AIChatStreamTurnStatus.chunkError);
      expect(outcome.errorCode, 'EMPTY_STREAM');
      expect(outcome.shouldReconnect, isTrue);
      expect(outcome.hasPartialAssistant, isTrue);
      expect(outcome.partialContent, 'فقط دلتا');
    });
  });
}
