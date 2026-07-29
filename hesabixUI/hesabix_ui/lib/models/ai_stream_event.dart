/// کلید ذخیره trace در function_results (بک‌اند).
const kAgentTraceStorageKey = '_agent_trace';
const kAgentBudgetStorageKey = '_agent_budget';
const kAgentTodosStorageKey = '_agent_todos';

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

AIStreamAgentBudget? extractAgentBudgetFromResults(Object? functionResults) {
  if (functionResults is! Map) return null;
  final raw = functionResults[kAgentBudgetStorageKey];
  if (raw is! Map) return null;
  return AIStreamAgentBudget.fromJson(Map<String, dynamic>.from(raw));
}

/// استخراج برنامهٔ کاری agent از function_results پیام ذخیره‌شده.
AISessionTodoSnapshot? extractAgentTodosFromResults(Object? functionResults) {
  if (functionResults is! Map) return null;
  final raw = functionResults[kAgentTodosStorageKey];
  if (raw is! Map) return null;
  return AISessionTodoSnapshot.fromJson(Map<String, dynamic>.from(raw));
}

/// رویدادهای استریم SSE چت AI
class AIStreamChunk {
  final String? contentDelta;
  final AIStreamToolEvent? toolEvent;
  final AIStreamStatusEvent? statusEvent;
  final AIAgentTraceStep? traceStep;
  final AIAgentTraceStep? traceStepUpdate;
  final AIStreamContextUsage? contextUsage;
  final AIStreamAgentBudget? agentBudget;
  final int? heartbeatElapsedMs;
  final AISessionTodoSnapshot? todoSnapshot;
  final bool done;
  final Map<String, dynamic>? usage;
  final int? messageId;
  final Object? functionCalls;
  final Object? functionResults;
  final List<AIAgentTraceStep>? agentTrace;
  final String? error;
  final bool recoverable;
  final String? suggestedAction;
  final String? requestedModel;
  final String? resolvedModel;

  const AIStreamChunk({
    this.contentDelta,
    this.toolEvent,
    this.statusEvent,
    this.traceStep,
    this.traceStepUpdate,
    this.contextUsage,
    this.agentBudget,
    this.heartbeatElapsedMs,
    this.todoSnapshot,
    this.done = false,
    this.usage,
    this.messageId,
    this.functionCalls,
    this.functionResults,
    this.agentTrace,
    this.error,
    this.recoverable = false,
    this.suggestedAction,
    this.requestedModel,
    this.resolvedModel,
  });
}

/// یک گام در زنجیرهٔ agent (نمایش تایم‌لاین).
class AIAgentTraceStep {
  final String? traceId;
  final String stepId;
  final String kind;
  final String state;
  final String? layer;
  final String? visibility;
  final int? retryAttempt;
  final String? titleKey;
  final Map<String, dynamic>? titleParams;
  final String? bodyMarkdown;
  final String? tool;
  final String? toolKey;
  final int? iteration;
  // ---- فیلدهای غنی‌سازی (جدید) ----
  final int? elapsedMs;       // زمان اجرای tool به میلی‌ثانیه
  final int? resultCount;     // تعداد رکوردهای برگشتی
  final List<String>? citations; // منابع/رکوردهای مرجع
  final String? bundleId;
  final String? exploreTarget;
  final List<Map<String, dynamic>>? entityRefs;
  final int? findingsCount;
  final String? hypothesis;
  final String? confidence;

  const AIAgentTraceStep({
    this.traceId,
    required this.stepId,
    required this.kind,
    this.state = 'done',
    this.layer,
    this.visibility,
    this.retryAttempt,
    this.titleKey,
    this.titleParams,
    this.bodyMarkdown,
    this.tool,
    this.toolKey,
    this.iteration,
    this.elapsedMs,
    this.resultCount,
    this.citations,
    this.bundleId,
    this.exploreTarget,
    this.entityRefs,
    this.findingsCount,
    this.hypothesis,
    this.confidence,
  });

  bool get isActive => state == 'active';
  bool get isError => state == 'error';
  bool get isReasoningLayer =>
      layer == 'reasoning' ||
      (layer == null &&
          kind != 'answer' &&
          kind != 'system');
  bool get isAnswerLayer => layer == 'answer' || kind == 'answer';

  /// نمایش زمان اجرا به صورت خوانا
  String? get elapsedLabel {
    final ms = elapsedMs;
    if (ms == null) return null;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  factory AIAgentTraceStep.fromJson(Map<String, dynamic> json) {
    final rawCitations = json['citations'];
    final rawRefs = json['entity_refs'];
    return AIAgentTraceStep(
      traceId: json['trace_id'] as String?,
      stepId: json['step_id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'plan',
      state: json['state'] as String? ?? 'done',
      layer: json['layer'] as String?,
      visibility: json['visibility'] as String?,
      retryAttempt: json['retry_attempt'] as int?,
      titleKey: json['title_key'] as String?,
      titleParams: json['title_params'] is Map
          ? Map<String, dynamic>.from(json['title_params'] as Map)
          : null,
      bodyMarkdown: json['body_markdown'] as String?,
      tool: json['tool'] as String?,
      toolKey: json['tool_key'] as String?,
      iteration: json['iteration'] as int?,
      elapsedMs: json['elapsed_ms'] as int?,
      resultCount: json['result_count'] as int?,
      citations: rawCitations is List
          ? rawCitations.whereType<String>().toList()
          : null,
      bundleId: json['bundle_id'] as String?,
      exploreTarget: json['explore_target'] as String?,
      entityRefs: rawRefs is List
          ? rawRefs
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : null,
      findingsCount: json['findings_count'] as int?,
      hypothesis: json['hypothesis'] as String?,
      confidence: json['confidence'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (traceId != null) 'trace_id': traceId,
        'step_id': stepId,
        'kind': kind,
        'state': state,
        if (layer != null) 'layer': layer,
        if (visibility != null) 'visibility': visibility,
        if (retryAttempt != null) 'retry_attempt': retryAttempt,
        if (titleKey != null) 'title_key': titleKey,
        if (titleParams != null) 'title_params': titleParams,
        if (bodyMarkdown != null) 'body_markdown': bodyMarkdown,
        if (tool != null) 'tool': tool,
        if (toolKey != null) 'tool_key': toolKey,
        if (iteration != null) 'iteration': iteration,
        if (elapsedMs != null) 'elapsed_ms': elapsedMs,
        if (resultCount != null) 'result_count': resultCount,
        if (citations != null) 'citations': citations,
        if (bundleId != null) 'bundle_id': bundleId,
        if (exploreTarget != null) 'explore_target': exploreTarget,
        if (entityRefs != null) 'entity_refs': entityRefs,
        if (findingsCount != null) 'findings_count': findingsCount,
        if (hypothesis != null) 'hypothesis': hypothesis,
        if (confidence != null) 'confidence': confidence,
      };

  AIAgentTraceStep copyWith({
    String? state,
    String? bodyMarkdown,
    int? elapsedMs,
    int? resultCount,
  }) {
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
      elapsedMs: elapsedMs ?? this.elapsedMs,
      resultCount: resultCount ?? this.resultCount,
      citations: citations,
    );
  }
}

/// وضعیت پر شدن context گفت‌وگو (تخمینی).
class AIStreamContextUsage {
  final int? estimatedTokens;
  final int? budgetTokens;
  final double? usageRatio;
  final double? usagePercent;
  final bool historySummarized;
  final bool contextRetried;

  const AIStreamContextUsage({
    this.estimatedTokens,
    this.budgetTokens,
    this.usageRatio,
    this.usagePercent,
    this.historySummarized = false,
    this.contextRetried = false,
  });

  factory AIStreamContextUsage.fromJson(Map<String, dynamic> json) {
    return AIStreamContextUsage(
      estimatedTokens: json['estimated_tokens'] as int?,
      budgetTokens: json['budget_tokens'] as int?,
      usageRatio: (json['usage_ratio'] as num?)?.toDouble(),
      usagePercent: (json['usage_percent'] as num?)?.toDouble(),
      historySummarized: json['history_summarized'] as bool? ?? false,
      contextRetried: json['context_retried'] as bool? ?? false,
    );
  }
}

/// بودجهٔ یکپارچهٔ agent (توکن، زمان، استدلال).
class AIStreamAgentBudget {
  final int? iteration;
  final int? maxIterations;
  final int? tokensUsed;
  final int? maxTotalTokens;
  final double? elapsedSec;
  final double? wallClockSec;
  final int? unproductiveRounds;
  final int? maxUnproductiveRounds;
  final String? reasoningEffort;
  final String? stopReason;
  final String? stopMessageFa;

  const AIStreamAgentBudget({
    this.iteration,
    this.maxIterations,
    this.tokensUsed,
    this.maxTotalTokens,
    this.elapsedSec,
    this.wallClockSec,
    this.unproductiveRounds,
    this.maxUnproductiveRounds,
    this.reasoningEffort,
    this.stopReason,
    this.stopMessageFa,
  });

  factory AIStreamAgentBudget.fromJson(Map<String, dynamic> json) {
    return AIStreamAgentBudget(
      iteration: json['iteration'] as int?,
      maxIterations: json['max_iterations'] as int?,
      tokensUsed: json['tokens_used'] as int?,
      maxTotalTokens: json['max_total_tokens'] as int?,
      elapsedSec: (json['elapsed_sec'] as num?)?.toDouble(),
      wallClockSec: (json['wall_clock_sec'] as num?)?.toDouble(),
      unproductiveRounds: json['unproductive_rounds'] as int?,
      maxUnproductiveRounds: json['max_unproductive_rounds'] as int?,
      reasoningEffort: json['reasoning_effort'] as String?,
      stopReason: json['stop_reason'] as String?,
      stopMessageFa: json['stop_message_fa'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (iteration != null) 'iteration': iteration,
        if (maxIterations != null) 'max_iterations': maxIterations,
        if (tokensUsed != null) 'tokens_used': tokensUsed,
        if (maxTotalTokens != null) 'max_total_tokens': maxTotalTokens,
        if (elapsedSec != null) 'elapsed_sec': elapsedSec,
        if (wallClockSec != null) 'wall_clock_sec': wallClockSec,
        if (unproductiveRounds != null)
          'unproductive_rounds': unproductiveRounds,
        if (maxUnproductiveRounds != null)
          'max_unproductive_rounds': maxUnproductiveRounds,
        if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
        if (stopReason != null) 'stop_reason': stopReason,
        if (stopMessageFa != null) 'stop_message_fa': stopMessageFa,
      };
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
  final Map<String, dynamic>? approvalDetail;

  const AIStreamToolEvent({
    required this.type,
    required this.tool,
    this.toolKey,
    this.label,
    this.success,
    this.approvalRequired = false,
    this.approvalDetail,
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

/// یک آیتم در برنامهٔ کاری agent.
class AISessionTodoItem {
  final String id;
  final String title;
  final String? description;
  final String status;
  final int order;
  final String? linkedTool;
  final String? errorMessage;

  const AISessionTodoItem({
    required this.id,
    required this.title,
    this.description,
    this.status = 'pending',
    this.order = 0,
    this.linkedTool,
    this.errorMessage,
  });

  bool get isPending => status == 'pending';
  bool get isInProgress => status == 'in_progress';
  bool get isDone => status == 'done';
  bool get isSkipped => status == 'skipped';
  bool get isError => status == 'error';
  bool get isTerminal => isDone || isSkipped || isError;

  factory AISessionTodoItem.fromJson(Map<String, dynamic> json) {
    return AISessionTodoItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'pending',
      order: json['order'] as int? ?? 0,
      linkedTool: json['linked_tool'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description != null) 'description': description,
        'status': status,
        'order': order,
        if (linkedTool != null) 'linked_tool': linkedTool,
        if (errorMessage != null) 'error_message': errorMessage,
      };
}

/// خلاصهٔ برنامهٔ کاری agent (استریم یا ذخیره‌شده).
class AISessionTodoSnapshot {
  final List<AISessionTodoItem> items;
  final AISessionTodoSummary summary;
  final String? planTitle;

  const AISessionTodoSnapshot({
    required this.items,
    required this.summary,
    this.planTitle,
  });

  bool get isEmpty => items.isEmpty;
  bool get hasActiveItem => items.any((i) => i.isInProgress);
  bool get isFullyComplete =>
      items.isNotEmpty && items.every((i) => i.isTerminal);

  factory AISessionTodoSnapshot.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => AISessionTodoItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <AISessionTodoItem>[];
    items.sort((a, b) => a.order.compareTo(b.order));
    final rawSummary = json['summary'];
    return AISessionTodoSnapshot(
      items: items,
      summary: rawSummary is Map
          ? AISessionTodoSummary.fromJson(Map<String, dynamic>.from(rawSummary))
          : AISessionTodoSummary.fromItems(items),
      planTitle: json['plan_title'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
        'summary': summary.toJson(),
        if (planTitle != null) 'plan_title': planTitle,
      };
}

class AISessionTodoSummary {
  final int total;
  final int completed;
  final int inProgress;
  final int pending;

  const AISessionTodoSummary({
    required this.total,
    required this.completed,
    this.inProgress = 0,
    this.pending = 0,
  });

  double get progress =>
      total <= 0 ? 0 : (completed / total).clamp(0.0, 1.0);

  factory AISessionTodoSummary.fromJson(Map<String, dynamic> json) {
    return AISessionTodoSummary(
      total: json['total'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
      inProgress: json['in_progress'] as int? ?? 0,
      pending: json['pending'] as int? ?? 0,
    );
  }

  factory AISessionTodoSummary.fromItems(List<AISessionTodoItem> items) {
    final total = items.length;
    final completed = items.where((i) => i.isDone || i.isSkipped).length;
    final inProgress = items.where((i) => i.isInProgress).length;
    return AISessionTodoSummary(
      total: total,
      completed: completed,
      inProgress: inProgress,
      pending: total - completed - inProgress,
    );
  }

  Map<String, dynamic> toJson() => {
        'total': total,
        'completed': completed,
        'in_progress': inProgress,
        'pending': pending,
      };
}
