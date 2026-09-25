import 'dart:convert';

/// یک سری داده برای نمودار (تک‌سری یا چندسری).
class AIChartSeries {
  final String name;
  final List<double> values;

  const AIChartSeries({required this.name, required this.values});

  factory AIChartSeries.fromJson(Map<String, dynamic> json) {
    final raw = json['values'];
    return AIChartSeries(
      name: json['name'] as String? ?? '',
      values: raw is List
          ? raw.map((e) => (e as num).toDouble()).toList()
          : [],
    );
  }
}

/// مشخصات نمودار — JSON در بلوک ```chart
class AIChartSpec {
  static const supportedTypes = {'bar', 'line', 'pie'};

  final String type;
  final String title;
  final List<String> labels;
  final List<double> values;
  final List<AIChartSeries> series;
  final String? unit;

  const AIChartSpec({
    required this.type,
    required this.title,
    required this.labels,
    required this.values,
    this.series = const [],
    this.unit,
  });

  String get normalizedType {
    final t = type.toLowerCase().trim();
    return supportedTypes.contains(t) ? t : 'bar';
  }

  /// سری‌های مؤثر: اگر `series` خالی باشد از `values` تک‌سری می‌سازد.
  List<AIChartSeries> get effectiveSeries {
    if (series.isNotEmpty) return series;
    if (values.isNotEmpty) {
      return [AIChartSeries(name: '', values: values)];
    }
    return [];
  }

  bool get hasData =>
      effectiveSeries.any((s) => s.values.isNotEmpty);

  /// بازهٔ محور Y شامل مقادیر منفی.
  ///
  /// اگر فقط `maxY` ست شود و `minY` خالی بماند، fl_chart از `toY` منفی
  /// `minY` را تا کف داده پایین می‌آورد ولی `horizontalInterval` روی
  /// `maxY/4` می‌ماند (مثلاً ۰٫۲۵). حلقهٔ شبکه میلیون‌ها تکرار می‌شود و UI فریز می‌شود.
  (double minY, double maxY) get yAxisBounds {
    var minV = 0.0;
    var maxV = 0.0;
    var any = false;
    for (final series in effectiveSeries) {
      for (final raw in series.values) {
        if (!raw.isFinite) continue;
        if (!any) {
          minV = maxV = raw;
          any = true;
        } else {
          if (raw < minV) minV = raw;
          if (raw > maxV) maxV = raw;
        }
      }
    }
    if (!any) return (0.0, 1.0);

    final minY = minV < 0 ? minV * 1.15 : 0.0;
    final maxY = maxV > 0 ? maxV * 1.15 : 0.0;
    if (maxY <= minY) {
      return (minY, minY + 1.0);
    }
    return (minY, maxY);
  }

  /// فاصلهٔ شبکه/برچسب؛ حداکثر حدود ۴ خط تا حلقهٔ fl_chart منفجر نشود.
  double get yGridInterval {
    final (minY, maxY) = yAxisBounds;
    final span = maxY - minY;
    if (!span.isFinite || span <= 0) return 1.0;
    final interval = span / 4;
    return interval > 0 ? interval : 1.0;
  }

  factory AIChartSpec.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['labels'];
    final rawValues = json['values'];
    final rawSeries = json['series'];

    List<AIChartSeries> parsedSeries = [];
    if (rawSeries is List) {
      parsedSeries = rawSeries
          .whereType<Map>()
          .map((e) => AIChartSeries.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return AIChartSpec(
      type: json['type'] as String? ?? 'bar',
      title: json['title'] as String? ?? 'نمودار',
      labels: rawLabels is List
          ? rawLabels.map((e) => e.toString()).toList()
          : [],
      values: rawValues is List
          ? rawValues.map((e) => (e as num).toDouble()).toList()
          : [],
      series: parsedSeries,
      unit: json['unit'] as String?,
    );
  }

  static AIChartSpec? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map<String, dynamic>) {
        if (decoded is Map) {
          return AIChartSpec.fromJson(Map<String, dynamic>.from(decoded));
        }
        return null;
      }
      return AIChartSpec.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

/// ستون جدول
class AITableColumn {
  final String key;
  final String label;
  final String align;

  const AITableColumn({
    required this.key,
    required this.label,
    this.align = 'right',
  });

  factory AITableColumn.fromJson(Map<String, dynamic> json, {int? index}) {
    return AITableColumn(
      key: json['key'] as String? ?? 'col_$index',
      label: json['label'] as String? ?? json['key'] as String? ?? '',
      align: json['align'] as String? ?? 'right',
    );
  }

  factory AITableColumn.fromHeader(String header, int index) {
    return AITableColumn(
      key: 'col_$index',
      label: header,
      align: 'right',
    );
  }
}

/// برچسب فارسی ستون جدول خودکار از کلید envelope.
String tableColumnLabelFa(String key) {
  switch (key) {
    case 'id':
      return 'شناسه';
    case 'code':
      return 'کد';
    case 'name':
    case 'title':
      return 'نام';
    case 'amount':
    case 'total':
    case 'price':
      return 'مبلغ';
    case 'quantity':
    case 'qty':
      return 'تعداد';
    case 'date':
    case 'created_at':
      return 'تاریخ';
    case 'status':
      return 'وضعیت';
    case 'balance':
      return 'مانده';
    case 'type':
      return 'نوع';
    case 'description':
      return 'شرح';
    default:
      return key;
  }
}

class AITableSpec {
  final String? title;
  final List<AITableColumn> columns;
  final List<Map<String, dynamic>> rows;

  const AITableSpec({
    this.title,
    required this.columns,
    required this.rows,
  });

  bool get hasData => columns.isNotEmpty && rows.isNotEmpty;

  factory AITableSpec.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    final rawColumns = json['columns'];
    final rawRows = json['rows'];

    List<AITableColumn> columns = [];
    if (rawColumns is List && rawColumns.isNotEmpty) {
      columns = rawColumns
          .asMap()
          .entries
          .map((e) {
            final item = e.value;
            if (item is String) {
              return AITableColumn.fromHeader(item, e.key);
            }
            if (item is Map) {
              return AITableColumn.fromJson(
                Map<String, dynamic>.from(item),
                index: e.key,
              );
            }
            return AITableColumn.fromHeader('', e.key);
          })
          .toList();
    } else if (rawHeaders is List) {
      columns = rawHeaders
          .asMap()
          .entries
          .map((e) => AITableColumn.fromHeader(e.value.toString(), e.key))
          .toList();
    }

    List<Map<String, dynamic>> rows = [];
    if (rawRows is List) {
      for (var i = 0; i < rawRows.length; i++) {
        final row = rawRows[i];
        if (row is Map) {
          rows.add(Map<String, dynamic>.from(row));
        } else if (row is List) {
          final map = <String, dynamic>{};
          for (var c = 0; c < columns.length && c < row.length; c++) {
            map[columns[c].key] = row[c];
          }
          rows.add(map);
        }
      }
    }

    return AITableSpec(
      title: json['title'] as String?,
      columns: columns,
      rows: rows,
    );
  }

  static AITableSpec? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map<String, dynamic>) {
        if (decoded is Map) {
          return AITableSpec.fromJson(Map<String, dynamic>.from(decoded));
        }
        return null;
      }
      return AITableSpec.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// JSON کامل یا زیررشتهٔ `{...}` داخل متن اضافی.
  static AITableSpec? tryParseJsonLoose(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final direct = tryParse(trimmed);
    if (direct != null && direct.hasData) return direct;

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final sub = tryParse(trimmed.substring(start, end + 1));
      if (sub != null && sub.hasData) return sub;
    }
    return null;
  }

  /// جدول از رکوردهای envelope ابزار (نه markdown).
  static AITableSpec? tryFromRecords(
    List<Map<String, dynamic>> records, {
    String? title,
    int maxColumns = 6,
    int minRows = 2,
  }) {
    if (records.length < minRows) return null;
    final keyCount = <String, int>{};
    for (final row in records) {
      for (final entry in row.entries) {
        final value = entry.value;
        if (value is Map || value is List) continue;
        if (entry.key.startsWith('_')) continue;
        keyCount[entry.key] = (keyCount[entry.key] ?? 0) + 1;
      }
    }
    final keys = keyCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final columns = keys
        .take(maxColumns)
        .map(
          (e) => AITableColumn(
            key: e.key,
            label: tableColumnLabelFa(e.key),
            align: 'right',
          ),
        )
        .toList();
    if (columns.length < 2) return null;
    return AITableSpec(
      title: title,
      columns: columns,
      rows: records,
    );
  }

  String cellText(AITableColumn col, Map<String, dynamic> row) {
    final v = row[col.key];
    if (v == null) return '—';
    if (v is num) {
      if (v == v.roundToDouble()) return v.toStringAsFixed(0);
      return v.toStringAsFixed(2);
    }
    return v.toString();
  }
}
