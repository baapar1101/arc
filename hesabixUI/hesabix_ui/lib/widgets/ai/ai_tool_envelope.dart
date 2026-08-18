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
  kAgentCitationsStorageKey,
  kActivatedSkillsStorageKey,
  kReasoningTraceStorageKey,
};

const _traceLikeColumns = {
  'trace_id',
  'step_id',
  'kind',
  'state',
  'layer',
  'visibility',
  'title_key',
  'body_markdown',
};

bool _isInternalResultKey(String key) =>
    key.startsWith('_') || _skipResultKeys.contains(key);

bool _looksLikeTraceRecords(List<Map<String, dynamic>> records) {
  if (records.isEmpty) return false;
  var hits = 0;
  for (final row in records.take(8)) {
    final keys = row.keys.map((k) => k.toString()).toSet();
    final overlap = keys.intersection(_traceLikeColumns);
    if (overlap.contains('trace_id') ||
        (overlap.contains('step_id') && overlap.contains('kind')) ||
        overlap.length >= 3) {
      hits++;
    }
  }
  final sample = records.length < 8 ? records.length : 8;
  return hits >= (sample <= 1 ? 1 : (sample / 2).ceil());
}

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
    final key = entry.key.toString();
    if (_isInternalResultKey(key)) continue;
    final records = extractToolRecordsFromResult(entry.value);
    if (_looksLikeTraceRecords(records)) continue;
    final spec = AITableSpec.tryFromRecords(records);
    if (spec == null || !spec.hasData) continue;
    if (records.length > bestLen) {
      best = spec;
      bestLen = records.length;
    }
  }
  return best == null ? const [] : [best];
}
