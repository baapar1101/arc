import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';

/// استخراج عملیات در انتظار تأیید از function_results یک پیام.
List<Map<String, dynamic>> extractPendingApprovalOpsFromResults(
  Object? functionResults,
) {
  final ops = <Map<String, dynamic>>[];
  if (functionResults is! Map) return ops;

  for (final entry in functionResults.entries) {
    if (entry.key.toString().startsWith(kAgentTraceStorageKey)) continue;
    final added = _approvalOpFromEntry(entry.value);
    if (added != null) {
      ops.add(added);
    }
  }
  return ops;
}

Map<String, dynamic>? _approvalOpFromEntry(Object? value) {
  if (value is! Map) return null;
  final map = Map<String, dynamic>.from(value);
  if (map['error'] == 'APPROVAL_REQUIRED') {
    return map;
  }
  final nested = map['result'];
  if (nested is Map && nested['error'] == 'APPROVAL_REQUIRED') {
    return Map<String, dynamic>.from(nested);
  }
  return null;
}

/// عملیات در انتظار تأیید از آخرین پیام assistant در لیست.
List<Map<String, dynamic>> extractPendingApprovalOpsFromMessages(
  List<AIChatMessage> messages,
) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final msg = messages[i];
    if (msg.role != MessageRole.assistant) continue;
    return extractPendingApprovalOpsFromResults(msg.functionResults);
  }
  return [];
}

bool messagesHavePendingWriteApproval(List<AIChatMessage> messages) {
  return extractPendingApprovalOpsFromMessages(messages).isNotEmpty;
}
