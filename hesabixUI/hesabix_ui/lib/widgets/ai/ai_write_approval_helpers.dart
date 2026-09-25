import 'package:hesabix_ui/models/ai_models.dart';

/// استخراج عملیات در انتظار تأیید از function_results یک پیام.
List<Map<String, dynamic>> extractPendingApprovalOpsFromResults(
  Object? functionResults,
) {
  final ops = <Map<String, dynamic>>[];
  if (functionResults is! Map) return ops;

  for (final entry in functionResults.entries) {
    if (entry.key.toString().startsWith('_')) continue;
    final added = _approvalOpFromEntry(entry.value);
    if (added != null) {
      ops.add(added);
    }
  }
  return _dedupePendingApprovalOps(ops);
}

List<Map<String, dynamic>> _dedupePendingApprovalOps(
  List<Map<String, dynamic>> ops,
) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final op in ops) {
    final approvalId = (op['approval_id'] as String?)?.trim();
    final key = (approvalId != null && approvalId.isNotEmpty)
        ? 'id:$approvalId'
        : 'fn:${op['function']}:${op['arguments']}';
    if (!seen.add(key)) continue;
    out.add(op);
  }
  return out;
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

/// عملیات در انتظار تأیید از پیام‌ها یا استریم جاری همان جلسه.
List<Map<String, dynamic>> collectPendingApprovalOps({
  required List<AIChatMessage> messages,
  required int? sessionId,
  required bool streamPending,
  required int? pendingApprovalSessionId,
  required List<Map<String, dynamic>> streamOps,
}) {
  if (sessionId == null) return [];
  final fromMessages = extractPendingApprovalOpsFromMessages(messages);
  if (fromMessages.isNotEmpty) return fromMessages;
  if (streamPending &&
      (pendingApprovalSessionId == null ||
          pendingApprovalSessionId == sessionId) &&
      streamOps.isNotEmpty) {
    return List<Map<String, dynamic>>.from(streamOps);
  }
  return [];
}
