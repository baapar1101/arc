import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_citation_chips.dart';

void main() {
  test('extracts stored citations and builds invoice path', () {
    final sources = extractCitationSourcesFromResults({
      kAgentCitationsStorageKey: [
        {
          'id': 44,
          'name': 'فاکتور بهار',
          'entity': 'invoice',
          'source': 'search_invoices',
        },
      ],
    });
    expect(sources, hasLength(1));
    expect(sources.first.label, contains('فاکتور بهار'));
    expect(sources.first.relativePath, 'invoice/44/edit');
  });

  test('person entity maps to customer-360', () {
    final src = AICitationSource(id: 9, name: 'مشتری', entity: 'person');
    expect(src.relativePath, 'crm/customer-360/9');
  });

  test('ungrounded warning only when moneyish and no sources', () {
    expect(
      ungroundedNumericWarning('جمع ۱۲٬۰۰۰٬۰۰۰ ریال', const []),
      isNotNull,
    );
    expect(
      ungroundedNumericWarning('جمع ۱۲٬۰۰۰٬۰۰۰ ریال', [
        const AICitationSource(id: 1, name: 'فاکتور'),
      ]),
      isNull,
    );
    expect(ungroundedNumericWarning('سلام، چطور کمک کنم؟', const []), isNull);
  });
}
