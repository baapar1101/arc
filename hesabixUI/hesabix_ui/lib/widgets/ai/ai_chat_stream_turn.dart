import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/utils/ai_content_sanitize.dart';

enum AIChatStreamTurnStatus { success, empty, chunkError }

enum AIChatLiveChunkAction { keepListening, completed }

/// انباشت یک نوبت استریم جدا از UI (UX-01).
class AIChatStreamTurn {
  String accumulated = '';
  Object? functionCalls;
  Object? functionResults;
  int? assistantMessageId;
  bool canContinue = false;
  String? finishedRunId;
  String? finishedStopMessage;
  String? resolvedModelCode;

  void addDelta(String? delta) {
    if (delta != null && delta.isNotEmpty) {
      accumulated += delta;
    }
  }

  void applyDone(
    AIStreamChunk chunk, {
    required String? streamRunId,
    String? sseCursorRunId,
  }) {
    functionCalls = chunk.functionCalls;
    functionResults = chunk.functionResults;
    assistantMessageId = chunk.messageId;
    canContinue =
        chunk.canContinue == true || agentRunCanContinue(chunk.functionResults);
    finishedRunId = chunk.runId ?? streamRunId ?? sseCursorRunId;
    final persisted = chunk.finalContent?.trim();
    if (persisted != null && persisted.isNotEmpty) {
      accumulated = persisted;
    }
    finishedStopMessage =
        chunk.agentBudget?.stopMessageFa ??
        extractContinueStopMessage(chunk.functionResults);
    final model = chunk.resolvedModel?.trim();
    if (model != null && model.isNotEmpty) {
      resolvedModelCode = model;
    }
  }
}

class AIChatStreamTurnOutcome {
  final AIChatStreamTurnStatus status;
  final String resolvedContent;
  final bool hasVisibleOutput;
  final int? assistantMessageId;
  final Object? functionCalls;
  final Object? functionResults;
  final DateTime? createdAt;
  final String? continueRunId;
  final String? continueStopMessage;
  /// اگر false باشد dialog شناسهٔ ادامه را دست نمی‌زند (خطای بدون resume).
  final bool applyContinue;
  final String? errorMessage;
  final bool errorRecoverable;
  final String? errorCode;
  final String? suggestedAction;
  final String? resolvedModelCode;
  final String? partialContent;
  final DateTime? partialCreatedAt;
  final Object? partialFunctionResults;

  const AIChatStreamTurnOutcome({
    required this.status,
    this.resolvedContent = '',
    this.hasVisibleOutput = false,
    this.assistantMessageId,
    this.functionCalls,
    this.functionResults,
    this.createdAt,
    this.continueRunId,
    this.continueStopMessage,
    this.applyContinue = true,
    this.errorMessage,
    this.errorRecoverable = false,
    this.errorCode,
    this.suggestedAction,
    this.resolvedModelCode,
    this.partialContent,
    this.partialCreatedAt,
    this.partialFunctionResults,
  });

  bool get shouldReconnect {
    if (status != AIChatStreamTurnStatus.chunkError) return false;
    if (!errorRecoverable) return false;
    final action = suggestedAction;
    if (action == 'reconnect' || action == 'continue') return true;
    return errorCode == 'STREAM_STALL' || errorCode == 'EMPTY_STREAM';
  }

  bool get shouldContinueRun =>
      suggestedAction == 'continue' || errorCode == 'RUN_IDLE';

  bool get hasPartialAssistant =>
      status == AIChatStreamTurnStatus.chunkError &&
      partialContent != null &&
      partialContent!.isNotEmpty;

  String get sanitizedResolvedContent =>
      sanitizeAssistantContent(resolvedContent);
}
