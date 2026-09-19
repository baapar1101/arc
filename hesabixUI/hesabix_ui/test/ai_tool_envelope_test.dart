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
      expect(spec.columns.any((c) => c.key == 'id' && c.label == 'شناسه'), isTrue);
      expect(AITableSpec.tryFromRecords([{'id': 1, 'name': 'تنها'}]), isNull);
    });

    test('picks the largest tool list from function_results', () {
      final specs = extractToolTableSpecsFromResults({
        '_agent_trace': [],
        'search_invoices': {
          'ok': true,
          'items': [
            {'id': 1, 'name': 'الف'},
            {'id': 2, 'name': 'ب'},
          ],
        },
        'search_persons': {
          'ok': true,
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

    test('skips failed envelopes and raw lists', () {
      expect(
        extractToolTableSpecsFromResults({
          'search_invoices': {
            'ok': false,
            'items': [
              {'id': 1, 'name': 'الف'},
              {'id': 2, 'name': 'ب'},
            ],
          },
        }),
        isEmpty,
      );
      expect(
        extractToolTableSpecsFromResults({
          'mystery': [
            {'id': 1, 'name': 'الف'},
            {'id': 2, 'name': 'ب'},
          ],
        }),
        isEmpty,
      );
    });

    test('skips _reasoning_trace and underscore keys', () {
      final specs = extractToolTableSpecsFromResults({
        '_agent_trace': [
          {'trace_id': 'a', 'step_id': '1', 'kind': 'tool'},
          {'trace_id': 'a', 'step_id': '2', 'kind': 'plan'},
        ],
        '_reasoning_trace': [
          {'trace_id': 't', 'step_id': '1', 'kind': 'reasoning', 'state': 'done'},
          {'trace_id': 't', 'step_id': '2', 'kind': 'plan', 'state': 'done'},
        ],
        '_citations': [
          {'id': 1, 'name': 'فاکتور'},
          {'id': 2, 'name': 'کالا'},
        ],
      });
      expect(specs, isEmpty);
    });

    test('skips lists whose columns look like agent trace', () {
      final specs = extractToolTableSpecsFromResults({
        'mystery': [
          {
            'trace_id': 'x',
            'step_id': '1',
            'kind': 'tool',
            'state': 'done',
            'layer': 'reasoning',
          },
          {
            'trace_id': 'x',
            'step_id': '2',
            'kind': 'plan',
            'state': 'done',
            'layer': 'reasoning',
          },
        ],
      });
      expect(specs, isEmpty);
    });
  });
}
