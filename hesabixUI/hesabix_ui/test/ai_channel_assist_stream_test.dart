import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_channel_assist_stream.dart';

void main() {
  test('consumeChannelAssistStream accumulates deltas and done fields', () async {
    final stream = Stream<AIStreamChunk>.fromIterable([
      const AIStreamChunk(
        statusEvent: AIStreamStatusEvent(phase: 'thinking'),
      ),
      const AIStreamChunk(contentDelta: 'سلام '),
      const AIStreamChunk(
        toolEvent: AIStreamToolEvent(type: 'tool_end', tool: 'get_crm_summary'),
      ),
      const AIStreamChunk(
        contentDelta: 'دنیا',
      ),
      const AIStreamChunk(
        done: true,
        finalContent: 'سلام دنیا کامل',
        functionResults: {
          kAgentCitationsStorageKey: [
            {'title': 'فاکتور ۱'},
          ],
        },
      ),
    ]);

    final outcome = await consumeChannelAssistStream(stream);
    expect(outcome.text, 'سلام دنیا کامل');
    expect(outcome.toolsUsed, ['get_crm_summary']);
    expect(outcome.citations, [
      {'title': 'فاکتور ۱'},
    ]);
    expect(outcome.error, isNull);
  });

  test('consumeChannelAssistStream keeps partial text on error', () async {
    final stream = Stream<AIStreamChunk>.fromIterable([
      const AIStreamChunk(contentDelta: 'نیمه‌کاره'),
      const AIStreamChunk(error: 'قطع ارتباط', done: true),
    ]);
    final outcome = await consumeChannelAssistStream(stream);
    expect(outcome.text, 'نیمه‌کاره');
    expect(outcome.error, 'قطع ارتباط');
  });
}
