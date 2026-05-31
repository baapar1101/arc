import 'package:flutter/foundation.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';

/// برچسب ابزار برای رویدادهای استریم (معمولاً از l10n).
typedef AIChatToolLabelResolver =
    String Function(String toolName, String? toolKey);

/// مدیریت state استریم چت AI — جدا از [AIChatDialog] برای خوانایی و تست.
class AIChatStreamController extends ChangeNotifier {
  String? content;
  List<AIToolActivity> toolActivities = [];
  List<AIAgentTraceStep> traceSteps = [];
  String? statusPhase;
  String? statusStep;
  int? iteration;
  int? maxIterations;
  int elapsedSeconds = 0;
  double? contextUsageRatio;
  double? contextUsagePercent;
  bool contextHistorySummarized = false;
  DateTime? startedAt;
  DateTime? timestamp;
  bool pendingWriteApproval = false;
  List<Map<String, dynamic>> pendingApprovalOps = [];

  DateTime? _lastUiUpdate;
  static const _contentThrottleMs = 16;

  bool get isActive =>
      content != null || traceSteps.isNotEmpty || toolActivities.isNotEmpty;

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
    timestamp = DateTime.now();
    pendingWriteApproval = false;
    pendingApprovalOps = [];
    _lastUiUpdate = null;
    notifyListeners();
  }

  void clear() {
    content = null;
    toolActivities = [];
    traceSteps = [];
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
    _lastUiUpdate = null;
    notifyListeners();
  }

  /// دادهٔ پیام نیمه‌کاره هنگام توقف توسط کاربر.
  ({
    String partialContent,
    List<AIToolActivity> tools,
    List<AIAgentTraceStep> trace,
    DateTime? createdAt,
  })?
  snapshotForCancel() {
    final partial = content?.trim() ?? '';
    if (partial.isEmpty && toolActivities.isEmpty && traceSteps.isEmpty) {
      return null;
    }
    return (
      partialContent: partial.isEmpty ? '…' : partial,
      tools: List<AIToolActivity>.from(toolActivities),
      trace: List<AIAgentTraceStep>.from(traceSteps),
      createdAt: timestamp,
    );
  }

  Object? functionResultsWithTrace(Object? functionResults) {
    if (traceSteps.isEmpty) return functionResults;
    final map = functionResults is Map
        ? Map<String, dynamic>.from(functionResults as Map)
        : <String, dynamic>{};
    map[kAgentTraceStorageKey] = traceSteps.map((e) => e.toJson()).toList();
    return map;
  }

  void applyChunk(
    AIStreamChunk chunk, {
    required AIChatToolLabelResolver resolveToolLabel,
  }) {
    if (chunk.contextUsage != null) {
      contextUsageRatio = chunk.contextUsage!.usageRatio;
      contextUsagePercent = chunk.contextUsage!.usagePercent;
      contextHistorySummarized = chunk.contextUsage!.historySummarized;
      notifyListeners();
      return;
    }
    if (chunk.traceStep != null) {
      _applyTraceStep(chunk.traceStep!);
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
        chunk.statusEvent != null ||
        chunk.toolEvent != null ||
        chunk.heartbeatElapsedMs != null;

    if (immediate) {
      content = accumulated;
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
    content = accumulated;
    notifyListeners();
    return true;
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
    if (step.kind == 'observation' && step.tool != null) {
      for (var i = 0; i < traceSteps.length; i++) {
        final existing = traceSteps[i];
        if (existing.kind == 'tool' &&
            existing.tool == step.tool &&
            existing.isActive) {
          traceSteps[i] = existing.copyWith(state: 'done');
        }
      }
    }
    if (step.stepId.isEmpty) {
      traceSteps.add(step);
      return;
    }
    final idx = traceSteps.indexWhere((s) => s.stepId == step.stepId);
    if (idx >= 0) {
      traceSteps[idx] = step;
    } else {
      traceSteps.add(step);
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
}
