import 'package:flutter/foundation.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/utils/ai_content_sanitize.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_stream_turn.dart';

/// برچسب ابزار برای رویدادهای استریم (معمولاً از l10n).
typedef AIChatToolLabelResolver =
    String Function(String toolName, String? toolKey);

/// مدیریت state استریم چت AI — جدا از [AIChatDialog] برای خوانایی و تست.
class AIChatStreamController extends ChangeNotifier {
  String? content;
  List<AIToolActivity> toolActivities = [];
  List<AIAgentTraceStep> traceSteps = [];
  AISessionTodoSnapshot? todoSnapshot;
  String? statusPhase;
  String? statusStep;
  int? iteration;
  int? maxIterations;
  int elapsedSeconds = 0;
  double? contextUsageRatio;
  double? contextUsagePercent;
  bool contextHistorySummarized = false;
  AIStreamAgentBudget? agentBudget;
  String? runId;
  DateTime? startedAt;
  DateTime? timestamp;
  bool pendingWriteApproval = false;
  List<Map<String, dynamic>> pendingApprovalOps = [];

  DateTime? _lastUiUpdate;
  static const _contentThrottleMs = 16;

  bool get isActive =>
      content != null ||
      traceSteps.isNotEmpty ||
      toolActivities.isNotEmpty ||
      (todoSnapshot != null && !todoSnapshot!.isEmpty);

  void begin({String phase = 'connecting'}) {
    startedAt = DateTime.now();
    elapsedSeconds = 0;
    statusPhase = phase;
    statusStep = null;
    iteration = null;
    maxIterations = null;
    content = '';
    toolActivities = [];
    traceSteps = [];
    todoSnapshot = null;
    timestamp = DateTime.now();
    pendingWriteApproval = false;
    pendingApprovalOps = [];
    agentBudget = null;
    runId = null;
    _lastUiUpdate = null;
    notifyListeners();
  }

  void clear() {
    content = null;
    toolActivities = [];
    traceSteps = [];
    todoSnapshot = null;
    statusPhase = null;
    statusStep = null;
    iteration = null;
    maxIterations = null;
    elapsedSeconds = 0;
    startedAt = null;
    // contextUsage* بین پیام‌ها حفظ می‌شود
    timestamp = null;
    pendingWriteApproval = false;
    pendingApprovalOps = [];
    agentBudget = null;
    _lastUiUpdate = null;
    notifyListeners();
  }

  /// دادهٔ پیام نیمه‌کاره هنگام توقف توسط کاربر.
  ({
    String partialContent,
    List<AIToolActivity> tools,
    List<AIAgentTraceStep> trace,
    AISessionTodoSnapshot? todos,
    DateTime? createdAt,
  })?
  snapshotForCancel() {
    final partial = content?.trim() ?? '';
    if (partial.isEmpty &&
        toolActivities.isEmpty &&
        traceSteps.isEmpty &&
        (todoSnapshot == null || todoSnapshot!.isEmpty)) {
      return null;
    }
    return (
      partialContent: partial.isEmpty ? '…' : partial,
      tools: List<AIToolActivity>.from(toolActivities),
      trace: List<AIAgentTraceStep>.from(traceSteps),
      todos: todoSnapshot,
      createdAt: timestamp,
    );
  }

  Object? functionResultsWithTrace(Object? functionResults) {
    final map = functionResults is Map
        ? Map<String, dynamic>.from(functionResults)
        : <String, dynamic>{};
    if (traceSteps.isNotEmpty) {
      map[kAgentTraceStorageKey] = finalizeAgentTraceForDisplay(traceSteps)
          .map((e) => e.toJson())
          .toList();
    }
    if (agentBudget != null) {
      map[kAgentBudgetStorageKey] = agentBudget!.toJson();
    }
    if (todoSnapshot != null && !todoSnapshot!.isEmpty) {
      map[kAgentTodosStorageKey] = todoSnapshot!.toJson();
    }
    if (runId != null && runId!.isNotEmpty) {
      map[kAgentRunStorageKey] = {
        'run_id': runId,
        if (agentBudget?.stopReason != null) 'stop_reason': agentBudget!.stopReason,
        'can_continue': true,
      };
    }
    if (map.isEmpty) return functionResults;
    return map;
  }

  void applyChunk(
    AIStreamChunk chunk, {
    required AIChatToolLabelResolver resolveToolLabel,
  }) {
    if (chunk.runId != null && chunk.runId!.isNotEmpty) {
      runId = chunk.runId;
    }
    if (chunk.contextUsage != null) {
      contextUsageRatio = chunk.contextUsage!.usageRatio;
      contextUsagePercent = chunk.contextUsage!.usagePercent;
      contextHistorySummarized = chunk.contextUsage!.historySummarized;
      notifyListeners();
      return;
    }
    if (chunk.agentBudget != null) {
      agentBudget = chunk.agentBudget;
      if (chunk.agentBudget!.iteration != null) {
        iteration = chunk.agentBudget!.iteration;
      }
      if (chunk.agentBudget!.maxIterations != null) {
        maxIterations = chunk.agentBudget!.maxIterations;
      }
      if (iteration != null && maxIterations != null) {
        statusStep = '$iteration/$maxIterations';
      }
      notifyListeners();
      return;
    }
    if (chunk.traceStep != null) {
      _applyTraceStep(chunk.traceStep!);
      notifyListeners();
      return;
    }
    if (chunk.todoSnapshot != null) {
      todoSnapshot = chunk.todoSnapshot;
      notifyListeners();
      return;
    }
    if (chunk.statusEvent != null) {
      statusPhase = chunk.statusEvent!.phase;
      statusStep = chunk.statusEvent!.step;
      if (chunk.statusEvent!.phase == 'agent_progress') {
        iteration = chunk.statusEvent!.iteration;
        maxIterations = chunk.statusEvent!.maxIterations;
        if (iteration != null && maxIterations != null) {
          statusStep = '$iteration/$maxIterations';
        }
      }
      if (chunk.statusEvent!.phase == 'exploring') {
        statusPhase = 'exploring';
      }
      if (chunk.statusEvent!.phase == 'awaiting_approval') {
        statusPhase = 'awaiting_approval';
        pendingWriteApproval = true;
      }
      notifyListeners();
      return;
    }
    if (chunk.heartbeatElapsedMs != null) {
      elapsedSeconds = (chunk.heartbeatElapsedMs! / 1000).ceil();
      if (startedAt != null &&
          (statusPhase == null || statusPhase == 'connecting')) {
        statusPhase = 'thinking';
      }
      notifyListeners();
      return;
    }
    if (chunk.toolEvent != null) {
      _applyToolEvent(chunk.toolEvent!, resolveToolLabel: resolveToolLabel);
      notifyListeners();
      return;
    }
    if (chunk.contentDelta != null &&
        chunk.contentDelta!.isNotEmpty &&
        statusPhase != 'writing') {
      statusPhase = 'writing';
      statusStep = null;
    }
  }

  /// به‌روزرسانی متن انباشته — throttle برای content delta.
  bool updateAccumulatedContent(String accumulated, AIStreamChunk chunk) {
    final immediate =
        chunk.traceStep != null ||
        chunk.todoSnapshot != null ||
        chunk.statusEvent != null ||
        chunk.toolEvent != null ||
        chunk.heartbeatElapsedMs != null ||
        chunk.agentBudget != null;

    if (immediate) {
      content = sanitizeAssistantContent(accumulated);
      notifyListeners();
      return true;
    }

    if (chunk.contentDelta == null || chunk.contentDelta!.isEmpty) {
      return false;
    }

    final now = DateTime.now();
    final shouldUpdate =
        _lastUiUpdate == null ||
        now.difference(_lastUiUpdate!) >=
            const Duration(milliseconds: _contentThrottleMs);
    if (!shouldUpdate) return false;

    _lastUiUpdate = now;
    content = sanitizeAssistantContent(accumulated);
    notifyListeners();
    return true;
  }

  void applyDoneMetadata(AIStreamChunk chunk) {
    var changed = false;
    if (chunk.agentBudget != null) {
      agentBudget = chunk.agentBudget;
      changed = true;
    }
    if (chunk.runId != null && chunk.runId!.isNotEmpty) {
      runId = chunk.runId;
      changed = true;
    }
    if (chunk.awaitingApproval == true) {
      pendingWriteApproval = true;
      statusPhase = 'awaiting_approval';
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void mergeAgentTraceFromDone(List<AIAgentTraceStep>? agentTrace) {
    if (agentTrace == null || agentTrace.isEmpty) return;
    if (traceSteps.isEmpty) {
      traceSteps = List<AIAgentTraceStep>.from(agentTrace);
      notifyListeners();
      return;
    }

    final existingById = <String, AIAgentTraceStep>{};
    for (final step in traceSteps) {
      if (step.stepId.isNotEmpty) {
        existingById[step.stepId] = step;
      }
    }

    final merged = <AIAgentTraceStep>[];
    for (final step in agentTrace) {
      if (step.stepId.isNotEmpty && existingById.containsKey(step.stepId)) {
        merged.add(step);
        existingById.remove(step.stepId);
      } else {
        merged.add(step);
      }
    }
    if (existingById.isNotEmpty) {
      merged.addAll(existingById.values);
    }

    traceSteps = merged;
    notifyListeners();
  }

  void _applyTraceStep(AIAgentTraceStep step) {
    var next = step;
    final body = next.bodyMarkdown;
    if (body != null && body.isNotEmpty) {
      final clean = sanitizeAssistantContent(body);
      if (clean != body) {
        next = next.copyWith(bodyMarkdown: clean);
      }
    }
    if (next.kind == 'observation' && next.tool != null) {
      for (var i = 0; i < traceSteps.length; i++) {
        final existing = traceSteps[i];
        if (existing.kind == 'tool' &&
            existing.tool == next.tool &&
            existing.isActive) {
          traceSteps[i] = existing.copyWith(state: 'done');
        }
      }
    }
    if (next.stepId.isEmpty) {
      traceSteps.add(next);
      return;
    }
    final idx = traceSteps.indexWhere((s) => s.stepId == next.stepId);
    if (idx >= 0) {
      traceSteps[idx] = next;
    } else {
      traceSteps.add(next);
    }
  }

  void _applyToolEvent(
    AIStreamToolEvent event, {
    required AIChatToolLabelResolver resolveToolLabel,
  }) {
    final label = event.label ?? resolveToolLabel(event.tool, event.toolKey);
    statusPhase = 'running_tool';
    statusStep = event.tool;
    final idx = toolActivities.indexWhere((a) => a.tool == event.tool);

    if (event.isStart) {
      final activity = AIToolActivity(
        tool: event.tool,
        toolKey: event.toolKey,
        label: label,
        running: true,
      );
      if (idx >= 0) {
        toolActivities[idx] = activity;
      } else {
        toolActivities.add(activity);
      }
      return;
    }

    if (event.isEnd) {
      final activity = AIToolActivity(
        tool: event.tool,
        toolKey: event.toolKey,
        label: label,
        running: false,
        success: event.success,
        approvalRequired: event.approvalRequired,
      );
      if (idx >= 0) {
        toolActivities[idx] = activity;
      } else {
        toolActivities.add(activity);
      }
      if (event.approvalRequired) {
        pendingWriteApproval = true;
        if (event.approvalDetail != null) {
          final detail = Map<String, dynamic>.from(event.approvalDetail!);
          final fn = detail['function'] as String?;
          final exists = pendingApprovalOps.any(
            (o) =>
                o['function'] == fn &&
                o['arguments'].toString() == detail['arguments'].toString(),
          );
          if (!exists) {
            pendingApprovalOps = [...pendingApprovalOps, detail];
          }
        }
      }
    }
  }

  AIChatLiveChunkAction ingestLiveChunk(
    AIStreamChunk chunk,
    AIChatStreamTurn turn, {
    required AIChatToolLabelResolver resolveToolLabel,
    String? sseCursorRunId,
    void Function()? onContentTick,
  }) {
    applyChunk(chunk, resolveToolLabel: resolveToolLabel);
    turn.addDelta(chunk.contentDelta);
    if (chunk.done) {
      turn.applyDone(
        chunk,
        streamRunId: runId,
        sseCursorRunId: sseCursorRunId,
      );
      applyDoneMetadata(chunk);
      mergeAgentTraceFromDone(chunk.agentTrace);
      return AIChatLiveChunkAction.completed;
    }
    if (updateAccumulatedContent(turn.accumulated, chunk)) {
      onContentTick?.call();
    }
    return AIChatLiveChunkAction.keepListening;
  }

  AIChatStreamTurnOutcome completeSuccessTurn(AIChatStreamTurn turn) {
    var resolved = sanitizeAssistantContent(turn.accumulated);
    if (resolved.trim().isEmpty && traceSteps.isNotEmpty) {
      resolved = extractContentFromTraceSteps(traceSteps);
    }
    final visible = resolved.isNotEmpty ||
        toolActivities.isNotEmpty ||
        traceSteps.isNotEmpty;
    return AIChatStreamTurnOutcome(
      status: visible
          ? AIChatStreamTurnStatus.success
          : AIChatStreamTurnStatus.empty,
      resolvedContent: resolved,
      hasVisibleOutput: visible,
      assistantMessageId: turn.assistantMessageId,
      functionCalls: turn.functionCalls,
      functionResults: functionResultsWithTrace(turn.functionResults),
      createdAt: timestamp,
      continueRunId: turn.canContinue ? turn.finishedRunId : null,
      continueStopMessage: turn.canContinue ? turn.finishedStopMessage : null,
      resolvedModelCode: turn.resolvedModelCode,
    );
  }

  AIChatStreamTurnOutcome completeErrorTurn(
    AIStreamChunk chunk, {
    String? sseCursorRunId,
  }) {
    final snap = snapshotForCancel();
    final resumeId = chunk.runId ?? runId ?? sseCursorRunId;
    final offerContinue = chunk.canContinue == true || resumeId != null;
    return AIChatStreamTurnOutcome(
      status: AIChatStreamTurnStatus.chunkError,
      hasVisibleOutput: snap != null,
      applyContinue: offerContinue,
      errorMessage: chunk.error,
      errorRecoverable: chunk.recoverable,
      continueRunId: offerContinue ? resumeId : null,
      continueStopMessage: offerContinue
          ? (chunk.agentBudget?.stopMessageFa ?? agentBudget?.stopMessageFa)
          : null,
      partialContent: snap?.partialContent,
      partialCreatedAt: snap?.createdAt,
      partialFunctionResults: functionResultsWithTrace(null),
    );
  }

  /// حلقهٔ نوبت استریم بدون BuildContext — dialog فقط نتیجه را به UI می‌زند.
  Future<AIChatStreamTurnOutcome> consume(
    Stream<AIStreamChunk> chunks, {
    required AIChatToolLabelResolver resolveToolLabel,
    String? sseCursorRunId,
    void Function()? onContentTick,
  }) async {
    final turn = AIChatStreamTurn();
    await for (final chunk in chunks) {
      if (chunk.error != null) {
        return completeErrorTurn(chunk, sseCursorRunId: sseCursorRunId);
      }
      final action = ingestLiveChunk(
        chunk,
        turn,
        resolveToolLabel: resolveToolLabel,
        sseCursorRunId: sseCursorRunId,
        onContentTick: onContentTick,
      );
      if (action == AIChatLiveChunkAction.completed) {
        break;
      }
    }
    return completeSuccessTurn(turn);
  }
}
