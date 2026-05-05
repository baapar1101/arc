import 'dart:convert';

/// Plain-text representation of a workflow execution log line for clipboard.
String formatWorkflowExecutionLogForClipboard(Map<String, dynamic> log) {
  final ts = log['timestamp']?.toString() ?? log['created_at']?.toString();
  final level = (log['level']?.toString() ?? 'info').toUpperCase();
  final message = log['message']?.toString() ?? '';
  final data = log['data'];
  final buf = StringBuffer();
  if (ts != null && ts.isNotEmpty) {
    buf.writeln(ts);
  }
  buf.writeln('[$level] $message');
  if (data != null) {
    try {
      buf.writeln(const JsonEncoder.withIndent('  ').convert(data));
    } catch (_) {
      buf.writeln(data.toString());
    }
  }
  return buf.toString().trim();
}

String formatWorkflowExecutionLogsForClipboard(List<Map<String, dynamic>> logs) {
  if (logs.isEmpty) return '';
  return logs.map(formatWorkflowExecutionLogForClipboard).join('\n\n---\n\n');
}
