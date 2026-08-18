import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/ai_markdown_normalize.dart';

void main() {
  test('collapses spaced bold delimiters including zwnj', () {
    expect(
      normalizeAssistantMarkdown('** متن **'),
      '**متن**',
    );
    expect(
      normalizeAssistantMarkdown('**فروش ماه**'),
      '**فروش ماه**',
    );
    expect(
      normalizeAssistantMarkdown('**\u200cگزارش\u200c**'),
      '**گزارش**',
    );
    expect(
      normalizeAssistantMarkdown('نکته: ** مهم ** و بقیه'),
      'نکته: **مهم** و بقیه',
    );
  });

  test('leaves fenced and inline code untouched', () {
    const src = 'متن `** raw **` و\n```\n** keep **\n```';
    expect(normalizeAssistantMarkdown(src), src);
  });
}
