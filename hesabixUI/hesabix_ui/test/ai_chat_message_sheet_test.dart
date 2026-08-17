import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_message_sheet.dart';

void main() {
  test('user message shows edit and fork, not assistant feedback', () {
    final flags = AIChatMessageSheetFlags.fromMessage(
      AIChatMessage(
        id: 9,
        sessionId: 1,
        role: MessageRole.user,
        content: 'گزارش فروش',
      ),
      canApplyHScript: false,
    );
    expect(flags.userEdit, isTrue);
    expect(flags.assistantEdit, isFalse);
    expect(flags.fork, isTrue);
    expect(flags.assistantFeedback, isFalse);
    expect(flags.applyHScript, isFalse);
  });

  test('assistant message with id shows edit, fork, and feedback', () {
    final flags = AIChatMessageSheetFlags.fromMessage(
      AIChatMessage(
        id: 3,
        sessionId: 1,
        role: MessageRole.assistant,
        content: 'پاسخ',
      ),
      canApplyHScript: true,
    );
    expect(flags.userEdit, isFalse);
    expect(flags.assistantEdit, isTrue);
    expect(flags.fork, isTrue);
    expect(flags.assistantFeedback, isTrue);
  });

  test('hscript extract enables apply row when callback is allowed', () {
    final flags = AIChatMessageSheetFlags.fromMessage(
      AIChatMessage(
        sessionId: 1,
        role: MessageRole.assistant,
        content: '```hscript\nreport.sales()\n```',
      ),
      canApplyHScript: true,
    );
    expect(flags.applyHScript, isTrue);
    expect(flags.fork, isFalse);
  });
}
