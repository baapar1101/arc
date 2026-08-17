import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';

/// نشانهٔ ادامهٔ run قطع‌شده برای بنر چت.
class AIChatResumeHint {
  final String? runId;
  final String? stopMessageFa;

  const AIChatResumeHint({this.runId, this.stopMessageFa});

  bool get canContinue => runId != null && runId!.isNotEmpty;
}

AIChatResumeHint resumeHintFromFunctionResults(
  Object? functionResults, {
  String? fallbackStopMessage,
}) {
  if (!agentRunCanContinue(functionResults)) {
    return const AIChatResumeHint();
  }
  final run = extractAgentRunFromResults(functionResults);
  final runId = run?['run_id']?.toString();
  if (runId == null || runId.isEmpty) {
    return const AIChatResumeHint();
  }
  final fromBudget = extractContinueStopMessage(functionResults);
  final stop = (fromBudget != null && fromBudget.isNotEmpty)
      ? fromBudget
      : fallbackStopMessage;
  return AIChatResumeHint(runId: runId, stopMessageFa: stop);
}

/// فقط آخرین پیام assistant را می‌بیند — هم‌تراز منطق قبلی dialog.
AIChatResumeHint resumeHintFromMessages(
  List<AIChatMessage> messages, {
  String? fallbackStopMessage,
}) {
  for (final msg in messages.reversed) {
    if (msg.role != MessageRole.assistant) continue;
    return resumeHintFromFunctionResults(
      msg.functionResults,
      fallbackStopMessage: fallbackStopMessage,
    );
  }
  return const AIChatResumeHint();
}
