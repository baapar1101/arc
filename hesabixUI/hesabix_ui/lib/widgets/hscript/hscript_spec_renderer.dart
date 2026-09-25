import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// رندرکننده Report Spec ساختاریافته HScript در پنل.
class HScriptSpecRenderer extends StatelessWidget {
  const HScriptSpecRenderer({
    super.key,
    required this.spec,
    this.error,
  });

  final Map<String, dynamic>? spec;
  final Map<String, dynamic>? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (error != null) {
      return _ErrorPanel(error: error!, scheme: cs, theme: theme);
    }
    if (spec == null) {
      return Center(
        child: Text(
          'برای پیش‌نمایش، اسکریپت را اجرا کنید.',
          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final blocks = (spec!['blocks'] is List) ? (spec!['blocks'] as List) : const [];
    final title = spec!['title']?.toString();
    final layout = spec!['layout']?.toString() ?? 'document';
    final numberFormat = _readNumberFormat(spec!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (title != null && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        if (layout == 'dashboard')
          _DashboardComposer(
            blocks: blocks,
            columns: _readDashboardColumns(spec!),
            numberFormat: numberFormat,
          )
        else
          ...blocks.whereType<Map>().map(
                (b) => _BlockView(
                  block: Map<String, dynamic>.from(b),
                  numberFormat: numberFormat,
                ),
              ),
      ],
    );
  }
}

int _readDashboardColumns(Map<String, dynamic> spec) {
  final meta = spec['meta'];
  if (meta is Map && meta['dashboard_columns'] != null) {
    final n = int.tryParse(meta['dashboard_columns'].toString());
    if (n == 6 || n == 12 || n == 24) return n!;
  }
  return 12;
}

Map<String, dynamic>? _readNumberFormat(Map<String, dynamic> spec) {
  final meta = spec['meta'];
  if (meta is Map && meta['number_format'] is Map) {
    return Map<String, dynamic>.from(meta['number_format'] as Map);
  }
  return null;
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.scheme, required this.theme});
  final Map<String, dynamic> error;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error['code']?.toString() ?? 'ERROR',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(error['message']?.toString() ?? 'خطای ناشناخته'),
          if (error['line'] != null) ...[
            const SizedBox(height: 6),
            Text(
              'خط ${error['line']}${error['column'] != null ? '، ستون ${error['column']}' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (error['hint'] != null) ...[
            const SizedBox(height: 8),
            Text(
              error['hint'].toString(),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardComposer extends StatelessWidget {
  const _DashboardComposer({
    required this.blocks,
    required this.columns,
    this.numberFormat,
  });
  final List blocks;
  final int columns;
  final Map<String, dynamic>? numberFormat;

  @override
  Widget build(BuildContext context) {
    final rows = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];
    var used = 0;

    void flush() {
      if (current.isNotEmpty) {
        rows.add(current);
        current = <Map<String, dynamic>>[];
        used = 0;
      }
    }

    for (final raw in blocks.whereType<Map>()) {
      final m = Map<String, dynamic>.from(raw);
      final type = m['type']?.toString() ?? '';
      if (type == 'row_break' || type == 'page_break') {
        flush();
        continue;
      }
      if (type == 'title' || type == 'heading' || type == 'section' || type == 'text' || type == 'paragraph') {
        flush();
        rows.add([m]);
        continue;
      }
      final span = _spanOf(m, columns);
      if (used > 0 && used + span > columns) flush();
      current.add(m);
      used += span;
      if (used >= columns) flush();
    }
    flush();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gap = 10.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows) ...[
              if (row.length == 1 && _isFullBleed(row.first))
                _BlockView(block: row.first, numberFormat: numberFormat)
              else
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final b in row)
                      SizedBox(
                        width: _widthForSpan(width, gap, _spanOf(b, columns), columns),
                        child: _BlockView(block: b, numberFormat: numberFormat),
                      ),
                  ],
                ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  bool _isFullBleed(Map<String, dynamic> b) {
    final t = b['type']?.toString() ?? '';
    return t == 'title' || t == 'heading' || t == 'section' || t == 'text' || t == 'paragraph';
  }

  int _spanOf(Map<String, dynamic> b, int cols) {
    final raw = b['span'];
    final parsed = raw == null ? null : int.tryParse(raw.toString());
    if (parsed != null && parsed >= 1 && parsed <= cols) return parsed;
    final t = b['type']?.toString() ?? '';
    if (t == 'kpi' || t == 'card' || t == 'gauge') return (cols / 3).round().clamp(1, cols);
    if (t == 'chart') return (cols / 2).round().clamp(1, cols);
    return cols;
  }

  double _widthForSpan(double total, double gap, int span, int cols) {
    final unit = (total - gap * (cols - 1).clamp(0, 100)) / cols;
    final w = unit * span + gap * (span - 1);
    return w.clamp(120.0, total);
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, this.numberFormat});
  final Map<String, dynamic> block;
  final Map<String, dynamic>? numberFormat;

  @override
  Widget build(BuildContext context) {
    final type = block['type']?.toString() ?? '';
    switch (type) {
      case 'title':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            block['text']?.toString() ?? '',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      case 'heading':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            block['text']?.toString() ?? '',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      case 'section':
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            block['title']?.toString() ?? '',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      case 'paragraph':
      case 'text':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(block['text']?.toString() ?? ''),
        );
      case 'kpi':
      case 'card':
        return _KpiCard(block: block, numberFormat: numberFormat);
      case 'table':
        return _TableBlock(block: block, numberFormat: numberFormat);
      case 'chart':
        return _ChartBlock(block: block);
      case 'gauge':
        return _GaugeBlock(block: block);
      case 'qr':
      case 'barcode':
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Icon(type == 'qr' ? Icons.qr_code_2 : Icons.view_week),
            title: Text(block['label']?.toString() ?? type.toUpperCase()),
            subtitle: Text(block['data']?.toString() ?? ''),
          ),
        );
      case 'page_break':
        return const Divider(height: 32);
      case 'row_break':
        return const SizedBox(height: 8);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.block, this.numberFormat});
  final Map<String, dynamic> block;
  final Map<String, dynamic>? numberFormat;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = block['label']?.toString() ?? block['title']?.toString() ?? '';
    final value = _formatValue(
      block['value'],
      block['format']?.toString(),
      numberFormat: numberFormat,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (block['hint'] != null || block['subtitle'] != null) ...[
              const SizedBox(height: 4),
              Text(
                (block['hint'] ?? block['subtitle']).toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TableBlock extends StatelessWidget {
  const _TableBlock({required this.block, this.numberFormat});
  final Map<String, dynamic> block;
  final Map<String, dynamic>? numberFormat;

  @override
  Widget build(BuildContext context) {
    final cols = (block['columns'] is List)
        ? (block['columns'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final rows = (block['rows'] is List)
        ? (block['rows'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final title = block['title']?.toString();
    final formats = (block['formats'] is Map)
        ? Map<String, dynamic>.from(block['formats'] as Map)
        : const <String, dynamic>{};

    if (cols.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null && title.isNotEmpty)
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                rows.isEmpty ? 'داده‌ای برای نمایش وجود ندارد.' : 'ستون‌های جدول مشخص نشده است.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final c in cols) DataColumn(label: Text(c)),
              ],
              rows: [
                for (final r in rows.take(200))
                  DataRow(
                    cells: [
                      for (final c in cols)
                        DataCell(
                          Text(
                            _formatValue(
                              r[c],
                              formats[c]?.toString(),
                              numberFormat: numberFormat,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'ردیفی یافت نشد.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          if (rows.length > 200)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('نمایش ۲۰۰ ردیف از ${rows.length}', textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}

class _ChartBlock extends StatelessWidget {
  const _ChartBlock({required this.block});
  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chartType = block['chart_type']?.toString() ?? 'bar';
    final title = block['title']?.toString() ?? chartType;
    final raw = (block['data'] is List) ? (block['data'] as List) : const [];
    final points = <({String label, double value})>[];
    for (final item in raw.whereType<Map>()) {
      if (item.containsKey('label')) {
        points.add((
          label: item['label']?.toString() ?? '',
          value: _toDouble(item['value']),
        ));
      } else {
        points.add((
          label: item['x']?.toString() ?? '',
          value: _toDouble(item['y']),
        ));
      }
    }
    if (points.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: chartType == 'pie'
                  ? PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: [
                          for (var i = 0; i < points.length; i++)
                            PieChartSectionData(
                              value: points[i].value <= 0 ? 0.001 : points[i].value,
                              title: points[i].label,
                              radius: 56,
                              color: _colorAt(cs, i),
                              titleStyle: const TextStyle(fontSize: 10, color: Colors.white),
                            ),
                        ],
                      ),
                    )
                  : chartType == 'line' || chartType == 'area'
                      ? LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: true),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= points.length) return const SizedBox.shrink();
                                    return Text(points[i].label, style: const TextStyle(fontSize: 10));
                                  },
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: [
                                  for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value),
                                ],
                                isCurved: true,
                                color: cs.primary,
                                barWidth: 3,
                                belowBarData: BarAreaData(
                                  show: chartType == 'area',
                                  color: cs.primary.withValues(alpha: 0.2),
                                ),
                                dotData: const FlDotData(show: true),
                              ),
                            ],
                          ),
                        )
                      : BarChart(
                          BarChartData(
                            gridData: const FlGridData(show: true),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= points.length) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(points[i].label, style: const TextStyle(fontSize: 10)),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barGroups: [
                              for (var i = 0; i < points.length; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: points[i].value,
                                      color: _colorAt(cs, i),
                                      width: 14,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorAt(ColorScheme cs, int i) {
    const extras = [Colors.teal, Colors.orange, Colors.indigo, Colors.pink];
    final base = [cs.primary, cs.secondary, cs.tertiary, cs.error, ...extras];
    return base[i % base.length];
  }
}

class _GaugeBlock extends StatelessWidget {
  const _GaugeBlock({required this.block});
  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final value = _toDouble(block['value']);
    final minV = _toDouble(block['min'] ?? 0);
    final maxV = _toDouble(block['max'] ?? 100);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final progress = ((value - minV) / range).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(block['label']?.toString() ?? 'Gauge'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text('${_formatValue(value, null)} / ${_formatValue(maxV, null)}'),
          ],
        ),
      ),
    );
  }
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

String _formatValue(dynamic value, String? format, {Map<String, dynamic>? numberFormat}) {
  if (value == null) return '—';
  if (format == null || format.isEmpty || format == 'raw' || format == 'plain') {
    return value.toString();
  }
  final n = _toDouble(value);
  // اگر عدد نبود، همان متن
  if (value is! num && double.tryParse(value.toString().replaceAll(',', '')) == null) {
    return value.toString();
  }

  final parts = format.split(':');
  final kind = parts.first.toLowerCase();
  int? decimals = parts.length > 1 ? int.tryParse(parts[1]) : null;
  final thousandsSep = (numberFormat?['thousands_sep'] ?? ',').toString();
  final decimalSep = (numberFormat?['decimal_sep'] ?? '.').toString();

  String group(String intPart) {
    if (thousandsSep.isEmpty) return intPart;
    return intPart.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => thousandsSep);
  }

  String render(double v, int d) {
    final fixed = v.toStringAsFixed(d);
    final split = fixed.split('.');
    final intPart = split[0].startsWith('-') ? split[0].substring(1) : split[0];
    final sign = split[0].startsWith('-') ? '-' : '';
    final grouped = group(intPart);
    if (d <= 0) return '$sign$grouped';
    return '$sign$grouped$decimalSep${split.length > 1 ? split[1] : ''.padRight(d, '0')}';
  }

  switch (kind) {
    case 'currency':
    case 'money':
    case 'rial':
    case 'toman':
      return render(n, decimals ?? 0);
    case 'percent':
    case 'pct':
    case '%':
      return '${render(n, decimals ?? 1)}%';
    case 'integer':
    case 'int':
      return render(n, 0);
    case 'decimal':
    case 'float':
      return render(n, decimals ?? 2);
    case 'number':
    case 'num':
    case 'n':
      final d = decimals ?? ((n == n.roundToDouble()) ? 0 : 2);
      return render(n, d);
    default:
      return value.toString();
  }
}
