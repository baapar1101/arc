import 'package:hesabix_ui/models/ai_stream_event.dart';

class AIChannelAssistProgress {
  final String text;
  final String? phase;
  final List<String> toolsUsed;

  const AIChannelAssistProgress({
    required this.text,
    this.phase,
    this.toolsUsed = const [],
  });
}

class AIChannelAssistOutcome {
  final String text;
  final List<String> toolsUsed;
  final List<Map<String, dynamic>> citations;
  final String? error;

  const AIChannelAssistOutcome({
    required this.text,
    this.toolsUsed = const [],
    this.citations = const [],
    this.error,
  });
}

/// مصرف استریم کانال (CRM/تیکت) با متن زنده، ابزار و استناد.
Future<AIChannelAssistOutcome> consumeChannelAssistStream(
  Stream<AIStreamChunk> stream, {
  void Function(AIChannelAssistProgress progress)? onProgress,
}) async {
  final buffer = StringBuffer();
  final tools = <String>[];
  var citations = <Map<String, dynamic>>[];
  String? phase;
  String? error;

  await for (final chunk in stream) {
    if (chunk.statusEvent != null) {
      phase = chunk.statusEvent!.phase;
    }
    if (chunk.toolEvent != null &&
        chunk.toolEvent!.type == 'tool_end' &&
        chunk.toolEvent!.tool.trim().isNotEmpty) {
      final name = chunk.toolEvent!.tool.trim();
      if (!tools.contains(name)) tools.add(name);
    }
    if (chunk.contentDelta != null && chunk.contentDelta!.isNotEmpty) {
      buffer.write(chunk.contentDelta);
      phase = 'writing';
    }
    if (chunk.error != null && chunk.error!.trim().isNotEmpty) {
      error = chunk.error;
    }
    if (chunk.done) {
      final finished = (chunk.finalContent ?? '').trim();
      if (finished.isNotEmpty) {
        buffer
          ..clear()
          ..write(finished);
      }
      final fr = chunk.functionResults;
      if (fr is Map && fr[kAgentCitationsStorageKey] is List) {
        citations = (fr[kAgentCitationsStorageKey] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    onProgress?.call(
      AIChannelAssistProgress(
        text: buffer.toString(),
        phase: phase,
        toolsUsed: List<String>.from(tools),
      ),
    );
  }

  return AIChannelAssistOutcome(
    text: buffer.toString(),
    toolsUsed: tools,
    citations: citations,
    error: error,
  );
}
