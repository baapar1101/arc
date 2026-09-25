import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';

class AIChatSubagentSummary {
  final String subagentId;
  final String goal;
  final String status;
  final String? error;

  const AIChatSubagentSummary({
    required this.subagentId,
    required this.goal,
    required this.status,
    this.error,
  });

  factory AIChatSubagentSummary.fromJson(Map<String, dynamic> json) {
    return AIChatSubagentSummary(
      subagentId: (json['subagent_id'] as String? ?? '').trim(),
      goal: (json['goal'] as String? ?? '').trim(),
      status: (json['status'] as String? ?? 'running').trim(),
      error: json['error'] as String?,
    );
  }

  bool get isActive => status == 'running';
  bool get isError =>
      status == 'failed' ||
      status == 'cancelled' ||
      status == 'interrupted' ||
      (error != null && error!.trim().isNotEmpty && !isActive);

  AIAgentTraceStep toTraceStep() {
    final state = isActive ? 'active' : (isError ? 'error' : 'done');
    return AIAgentTraceStep(
      stepId: 'subagent_$subagentId',
      kind: 'subagent',
      state: state,
      titleKey: 'aiTraceSubagent',
      titleParams: {'goal': goal},
      bodyMarkdown: (error?.trim().isNotEmpty == true ? error : goal),
      tool: 'spawn_subagent',
      toolKey: 'aiToolSpawnSubagent',
      exploreTarget: subagentId,
      subagentId: subagentId,
    );
  }
}

bool functionResultsAwaitApproval(Object? functionResults) {
  if (functionResults is! Map) return false;
  return functionResults[kAwaitingApprovalStorageKey] == true;
}

List<AIChatMessage> mergeSubagentSummariesIntoMessages(
  List<AIChatMessage> messages,
  List<AIChatSubagentSummary> items,
) {
  if (items.isEmpty || messages.isEmpty) return messages;
  var lastIdx = -1;
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role == MessageRole.assistant) {
      lastIdx = i;
      break;
    }
  }
  if (lastIdx < 0) return messages;
  final last = messages[lastIdx];
  final existing = extractAgentTraceFromResults(last.functionResults);
  final byId = <String, AIAgentTraceStep>{};
  for (final step in existing) {
    final id = step.cancelableSubagentId ?? step.subagentId;
    if (id != null && id.isNotEmpty) {
      byId[id] = step;
    }
  }
  var changed = false;
  for (final item in items) {
    if (item.subagentId.isEmpty) continue;
    final next = item.toTraceStep();
    final prev = byId[item.subagentId];
    if (prev == null || prev.state != next.state) {
      byId[item.subagentId] = next;
      changed = true;
    }
  }
  if (!changed && existing.any((s) => s.kind == 'subagent')) {
    return messages;
  }
  if (byId.isEmpty) return messages;
  final mergedSteps = [
    ...existing.where((s) {
      final id = s.cancelableSubagentId ?? s.subagentId;
      return s.kind != 'subagent' || id == null || id.isEmpty;
    }),
    ...byId.values,
  ];
  final fr = last.functionResults is Map
      ? Map<String, dynamic>.from(last.functionResults as Map)
      : <String, dynamic>{};
  fr[kAgentTraceStorageKey] =
      mergedSteps.map((s) => s.toJson()).toList();
  final next = List<AIChatMessage>.from(messages);
  next[lastIdx] = AIChatMessage(
    id: last.id,
    sessionId: last.sessionId,
    role: last.role,
    content: last.content,
    functionCalls: last.functionCalls,
    functionResults: fr,
    tokensUsed: last.tokensUsed,
    createdAt: last.createdAt,
  );
  return next;
}
