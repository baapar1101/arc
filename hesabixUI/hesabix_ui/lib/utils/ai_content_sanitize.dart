import 'package:hesabix_ui/models/ai_stream_event.dart';

/// حذف توکن‌های Harmony و نشت tool call از متن قابل‌نمایش.
String sanitizeAssistantContent(String text) {
  if (text.isEmpty) return text;
  var cleaned = text;

  final toolLeak = RegExp(
    r'<\|start\|>assistant<\|channel\|>commentary'
    r'(?:\s+to=functions\.(\w+))?'
    r'(?:\s*<\|constrain\|>\w+)?'
    r'<\|message\|>(\{.*?\})<\|call\|>',
    dotAll: true,
  );
  cleaned = cleaned.replaceAll(toolLeak, '');

  final tail = RegExp(r'<\|start\|>.*', dotAll: true);
  cleaned = cleaned.replaceAll(tail, '');

  final control = RegExp(
    r'<\|(?:start|end|channel|message|call|constrain)\|>[^<\n]*',
  );
  cleaned = cleaned.replaceAll(control, '');

  cleaned = cleaned.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return cleaned.trim();
}

/// trace ذخیره‌شده را برای نمایش تاریخی آماده می‌کند.
List<AIAgentTraceStep> finalizeAgentTraceForDisplay(
  List<AIAgentTraceStep> steps,
) {
  return steps.map((step) {
    var next = step;
    if (step.isActive) {
      next = next.copyWith(state: 'done');
    }
    final body = next.bodyMarkdown;
    if (body != null && body.isNotEmpty) {
      final clean = sanitizeAssistantContent(body);
      if (clean != body) {
        next = next.copyWith(bodyMarkdown: clean);
      }
    }
    return next;
  }).toList();
}
