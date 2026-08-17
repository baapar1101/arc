import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_visualization_spec.dart';

const _listKeys = [
  'records',
  'items',
  'data',
  'results',
  'invoices',
  'products',
  'persons',
  'leads',
  'deals',
  'documents',
  'rows',
];

const _skipResultKeys = {
  kAgentTraceStorageKey,
  kAgentBudgetStorageKey,
  kAgentTodosStorageKey,
  kAgentRunStorageKey,
};

bool markdownLooksLikeTable(String content) {
  final t = content.trim();
  if (t.isEmpty) return false;
  return t.contains('| ---') ||
      t.contains('|---') ||
      t.contains('```table');
}

Object? _unwrapToolEntry(Object? entry) {
  if (entry is! Map) return entry;
  if (entry.containsKey('result') && entry.containsKey('name')) {
    return entry['result'];
  }
  return entry;
}

List<Map<String, dynamic>> extractToolRecordsFromResult(Object? result) {
  final payload = _unwrapToolEntry(result);
  if (payload is List) {
    return payload
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (payload is! Map) return [];
  final map = Map<String, dynamic>.from(payload);
  for (final key in _listKeys) {
    final raw = map[key];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  }
  return [];
}

/// حداکثر یک جدول از بزرگ‌ترین لیست رکورد در function_results.
List<AITableSpec> extractToolTableSpecsFromResults(Object? functionResults) {
  if (functionResults is! Map) return [];
  AITableSpec? best;
  var bestLen = 0;
  for (final entry in functionResults.entries) {
    if (_skipResultKeys.contains(entry.key.toString())) continue;
    final records = extractToolRecordsFromResult(entry.value);
    final spec = AITableSpec.tryFromRecords(records);
    if (spec == null || !spec.hasData) continue;
    if (records.length > bestLen) {
      best = spec;
      bestLen = records.length;
    }
  }
  return best == null ? const [] : [best];
}
