/// کلید ذخیره trace در function_results (بک‌اند).
const kAgentTraceStorageKey = '_agent_trace';

/// استخراج trace از function_results پیام ذخیره‌شده.
List<AIAgentTraceStep> extractAgentTraceFromResults(Object? functionResults) {
  if (functionResults is! Map) return [];
  final raw = functionResults[kAgentTraceStorageKey];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => AIAgentTraceStep.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

/// رویدادهای استریم SSE چت AI
class AIStreamChunk {
  final String? contentDelta;
  final AIStreamToolEvent? toolEvent;
  final AIStreamStatusEvent? statusEvent;
  final AIAgentTraceStep? traceStep;
  final AIAgentTraceStep? traceStepUpdate;
  final int? heartbeatElapsedMs;
  final bool done;
  final Map<String, dynamic>? usage;
  final int? messageId;
  final Object? functionCalls;
  final Object? functionResults;
  final List<AIAgentTraceStep>? agentTrace;
  final String? error;

  const AIStreamChunk({
    this.contentDelta,
    this.toolEvent,
    this.statusEvent,
    this.traceStep,
    this.traceStepUpdate,
    this.heartbeatElapsedMs,
    this.done = false,
    this.usage,
    this.messageId,
    this.functionCalls,
    this.functionResults,
    this.agentTrace,
    this.error,
  });
}

/// یک گام در زنجیرهٔ agent (نمایش تایم‌لاین).
class AIAgentTraceStep {
  final String stepId;
  final String kind;
  final String state;
  final String? titleKey;
  final Map<String, dynamic>? titleParams;
  final String? bodyMarkdown;
  final String? tool;
  final String? toolKey;
  final int? iteration;

  const AIAgentTraceStep({
    required this.stepId,
    required this.kind,
    this.state = 'done',
    this.titleKey,
    this.titleParams,
    this.bodyMarkdown,
    this.tool,
    this.toolKey,
    this.iteration,
  });

  bool get isActive => state == 'active';
  bool get isError => state == 'error';

  factory AIAgentTraceStep.fromJson(Map<String, dynamic> json) {
    return AIAgentTraceStep(
      stepId: json['step_id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'plan',
      state: json['state'] as String? ?? 'done',
      titleKey: json['title_key'] as String?,
      titleParams: json['title_params'] is Map
          ? Map<String, dynamic>.from(json['title_params'] as Map)
          : null,
      bodyMarkdown: json['body_markdown'] as String?,
      tool: json['tool'] as String?,
      toolKey: json['tool_key'] as String?,
      iteration: json['iteration'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'step_id': stepId,
        'kind': kind,
        'state': state,
        if (titleKey != null) 'title_key': titleKey,
        if (titleParams != null) 'title_params': titleParams,
        if (bodyMarkdown != null) 'body_markdown': bodyMarkdown,
        if (tool != null) 'tool': tool,
        if (toolKey != null) 'tool_key': toolKey,
        if (iteration != null) 'iteration': iteration,
      };

  AIAgentTraceStep copyWith({String? state, String? bodyMarkdown}) {
    return AIAgentTraceStep(
      stepId: stepId,
      kind: kind,
      state: state ?? this.state,
      titleKey: titleKey,
      titleParams: titleParams,
      bodyMarkdown: bodyMarkdown ?? this.bodyMarkdown,
      tool: tool,
      toolKey: toolKey,
      iteration: iteration,
    );
  }
}

class AIStreamStatusEvent {
  final String phase;
  final String? step;
  final String? toolKey;
  final int? iteration;
  final int? maxIterations;

  const AIStreamStatusEvent({
    required this.phase,
    this.step,
    this.toolKey,
    this.iteration,
    this.maxIterations,
  });
}

class AIStreamToolEvent {
  final String type;
  final String tool;
  final String? toolKey;
  final String? label;
  final bool? success;
  final bool approvalRequired;

  const AIStreamToolEvent({
    required this.type,
    required this.tool,
    this.toolKey,
    this.label,
    this.success,
    this.approvalRequired = false,
  });

  bool get isStart => type == 'tool_start';
  bool get isEnd => type == 'tool_end';
}

/// فعالیت ابزار در UI (ترکیب start/end)
class AIToolActivity {
  final String tool;
  final String? toolKey;
  final String label;
  final bool running;
  final bool? success;
  final bool approvalRequired;

  const AIToolActivity({
    required this.tool,
    this.toolKey,
    required this.label,
    this.running = true,
    this.success,
    this.approvalRequired = false,
  });

  AIToolActivity copyWith({
    bool? running,
    bool? success,
    bool? approvalRequired,
  }) {
    return AIToolActivity(
      tool: tool,
      toolKey: toolKey,
      label: label,
      running: running ?? this.running,
      success: success ?? this.success,
      approvalRequired: approvalRequired ?? this.approvalRequired,
    );
  }
}
