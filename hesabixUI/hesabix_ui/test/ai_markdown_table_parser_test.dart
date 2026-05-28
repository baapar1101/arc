import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/ai/ai_markdown_table_parser.dart';
import 'package:hesabix_ui/widgets/ai/ai_visualization_spec.dart';

void main() {
  group('AIMarkdownTableParser', () {
    test('parses GFM pipe table with separator', () {
      const md = '''
| نام | مانده |
| --- | ---: |
| علی | 1500000 |
| شرکت الف | 980000 |
''';
      final spec = AIMarkdownTableParser.tryParseLines(md.trim().split('\n'));
      expect(spec, isNotNull);
      expect(spec!.columns.length, 2);
      expect(spec.rows.length, 2);
      expect(spec.cellText(spec.columns[0], spec.rows[0]), 'علی');
    });

    test('splitText extracts table from surrounding markdown', () {
      const md = '''
خلاصه:

| کالا | تعداد |
| --- | --- |
| الف | 3 |

پایان.
''';
      final parts = AIMarkdownTableParser.splitText(md);
      expect(parts.length, 3);
      expect(parts[0].text, contains('خلاصه'));
      expect(parts[1].tableSpec, isNotNull);
      expect(parts[2].text, contains('پایان'));
    });

    test('tryParseJsonLoose extracts JSON from noisy fence body', () {
      const body = 'جدول:\n{"headers":["a","b"],"rows":[["1","2"]]}';
      final spec = AITableSpec.tryParseJsonLoose(body);
      expect(spec, isNotNull);
      expect(spec!.hasData, isTrue);
    });
  });
}
