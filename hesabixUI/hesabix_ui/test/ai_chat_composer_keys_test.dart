import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_composer_keys.dart';

void main() {
  test('desktop Enter sends, Shift+Enter stays newline', () {
    expect(
      composerEnterShouldSend(shiftPressed: false, compactLayout: false),
      isTrue,
    );
    expect(
      composerEnterShouldSend(shiftPressed: true, compactLayout: false),
      isFalse,
    );
  });

  test('compact layout never treats Enter as send', () {
    expect(
      composerEnterShouldSend(shiftPressed: false, compactLayout: true),
      isFalse,
    );
    expect(
      composerEnterShouldSend(shiftPressed: true, compactLayout: true),
      isFalse,
    );
  });
}
