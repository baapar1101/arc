/// رویدادهای استریم SSE چت AI
class AIStreamChunk {
  final String? contentDelta;
  final AIStreamToolEvent? toolEvent;
  final bool done;
  final Map<String, dynamic>? usage;
  final int? messageId;
  final Object? functionCalls;
  final Object? functionResults;
  final String? error;

  const AIStreamChunk({
    this.contentDelta,
    this.toolEvent,
    this.done = false,
    this.usage,
    this.messageId,
    this.functionCalls,
    this.functionResults,
    this.error,
  });
}

class AIStreamToolEvent {
  final String type;
  final String tool;
  final String? label;
  final bool? success;
  final bool approvalRequired;

  const AIStreamToolEvent({
    required this.type,
    required this.tool,
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
  final String label;
  final bool running;
  final bool? success;
  final bool approvalRequired;

  const AIToolActivity({
    required this.tool,
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
      label: label,
      running: running ?? this.running,
      success: success ?? this.success,
      approvalRequired: approvalRequired ?? this.approvalRequired,
    );
  }
}
