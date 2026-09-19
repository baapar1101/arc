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

/// آخرین پیام کاربر است و هنوز پاسخ دستیار در تاریخچه نیست.
bool sessionAwaitsAssistantReply(List<AIChatMessage> messages) {
  if (messages.isEmpty) return false;
  return messages.last.role == MessageRole.user;
}

/// بعد از بستن صفحه، Last-Event-ID سرور یعنی «رویدادهایی که این کلاینت ندیده».
/// اگر حباب دستیار در UI نیست باید از صفر replay شود.
int sseReplayCursor({
  required bool uiHasAssistantPartial,
  required int serverLastEventId,
}) {
  if (!uiHasAssistantPartial) return 0;
  if (serverLastEventId < 0) return 0;
  return serverLastEventId;
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
