import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/ai/ai_tool_envelope.dart';
import 'package:hesabix_ui/widgets/ai/ai_visualization_spec.dart';

void main() {
  group('tool envelope', () {
    test('extracts records from nested result envelope', () {
      final records = extractToolRecordsFromResult({
        'name': 'search_invoices',
        'result': {
          '_envelope': 1,
          'items': [
            {'id': 1, 'name': 'الف', 'amount': 10},
            {'id': 2, 'name': 'ب', 'amount': 20},
          ],
        },
      });
      expect(records, hasLength(2));
      expect(records.first['name'], 'الف');
    });

    test('builds table spec from records and skips singleton lists', () {
      final spec = AITableSpec.tryFromRecords([
        {'id': 1, 'name': 'الف'},
        {'id': 2, 'name': 'ب'},
        {'id': 3, 'name': 'ج'},
      ]);
      expect(spec, isNotNull);
      expect(spec!.hasData, isTrue);
      expect(spec.columns.length, greaterThanOrEqualTo(2));
      expect(AITableSpec.tryFromRecords([{'id': 1, 'name': 'تنها'}]), isNull);
    });

    test('picks the largest tool list from function_results', () {
      final specs = extractToolTableSpecsFromResults({
        '_agent_trace': [],
        'search_invoices': {
          'items': [
            {'id': 1, 'name': 'الف'},
            {'id': 2, 'name': 'ب'},
          ],
        },
        'search_persons': {
          'items': [
            {'id': 1, 'name': 'علی', 'balance': 1},
            {'id': 2, 'name': 'رضا', 'balance': 2},
            {'id': 3, 'name': 'مینا', 'balance': 3},
          ],
        },
      });
      expect(specs, hasLength(1));
      expect(specs.first.rows, hasLength(3));
    });
  });
}
