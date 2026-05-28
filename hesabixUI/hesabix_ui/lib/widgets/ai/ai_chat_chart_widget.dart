import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'ai_visualization_spec.dart';

export 'ai_visualization_spec.dart' show AIChartSpec, AIChartSeries;

class AIChatChartWidget extends StatelessWidget {
  final AIChartSpec spec;

  const AIChatChartWidget({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    if (!spec.hasData) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            spec.title,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (spec.unit != null) ...[
            const SizedBox(height: 4),
            Text(
              spec.unit!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (spec.effectiveSeries.length > 1) ...[
            const SizedBox(height: 8),
            _SeriesLegend(
              series: spec.effectiveSeries,
              colors: _chartColors(scheme, spec.effectiveSeries.length),
            ),
          ],
          const SizedBox(height: 16),
          if (spec.normalizedType == 'pie') ...[
            SizedBox(
              height: 200,
              child: _PieChartBody(spec: spec, scheme: scheme, theme: theme),
            ),
            const SizedBox(height: 12),
            _PieLabelsLegend(spec: spec, scheme: scheme, theme: theme),
          ] else
            SizedBox(
              height: 220,
              child: switch (spec.normalizedType) {
                'line' => _LineChartBody(spec: spec, scheme: scheme, theme: theme),
                _ => _BarChartBody(spec: spec, scheme: scheme, theme: theme),
              },
            ),
        ],
      ),
    );
  }

  static List<Color> _chartColors(ColorScheme scheme, int count) {
    final base = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
      Colors.teal,
      Colors.orange,
      Colors.indigo,
      Colors.pink,
    ];
    if (count <= base.length) return base.sublist(0, count);
    return List.generate(count, (i) => base[i % base.length]);
  }
}

class _SeriesLegend extends StatelessWidget {
  final List<AIChartSeries> series;
  final List<Color> colors;

  const _SeriesLegend({required this.series, required this.colors});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: List.generate(series.length, (i) {
        final name = series[i].name.trim();
        if (name.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors[i],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(name, style: theme.textTheme.labelSmall),
          ],
        );
      }),
    );
  }
}

class _BarChartBody extends StatelessWidget {
  final AIChartSpec spec;
  final ColorScheme scheme;
  final ThemeData theme;

  const _BarChartBody({
    required this.spec,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final seriesList = spec.effectiveSeries;
    final colors = AIChatChartWidget._chartColors(scheme, seriesList.length);
    final maxLen = seriesList
        .map((s) => s.values.length)
        .fold(0, (a, b) => a > b ? a : b);
    if (maxLen == 0) return const SizedBox.shrink();

    double maxY = 0;
    for (final s in seriesList) {
      for (final v in s.values) {
        if (v > maxY) maxY = v;
      }
    }
    final chartMax = maxY <= 0 ? 1.0 : maxY * 1.15;
    final groupCount = maxLen;
    final barWidth = seriesList.length > 1 ? 10.0 : 18.0;

    return BarChart(
      BarChartData(
        maxY: chartMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: chartMax / 4,
          getDrawingHorizontalLine: (v) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Text(
                _compactNumber(value),
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= spec.labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    spec.labels[i],
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(groupCount, (i) {
          return BarChartGroupData(
            x: i,
            barsSpace: 4,
            barRods: List.generate(seriesList.length, (si) {
              final vals = seriesList[si].values;
              final y = i < vals.length ? vals[i] : 0.0;
              return BarChartRodData(
                toY: y,
                color: colors[si],
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              );
            }),
          );
        }),
      ),
    );
  }
}

class _LineChartBody extends StatelessWidget {
  final AIChartSpec spec;
  final ColorScheme scheme;
  final ThemeData theme;

  const _LineChartBody({
    required this.spec,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final seriesList = spec.effectiveSeries;
    final colors = AIChatChartWidget._chartColors(scheme, seriesList.length);

    double maxY = 0;
    for (final s in seriesList) {
      for (final v in s.values) {
        if (v > maxY) maxY = v;
      }
    }
    final chartMax = maxY <= 0 ? 1.0 : maxY * 1.15;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: chartMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: chartMax / 4,
          getDrawingHorizontalLine: (v) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: chartMax / 4,
              getTitlesWidget: (value, meta) => Text(
                _compactNumber(value),
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= spec.labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    spec.labels[i],
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: List.generate(seriesList.length, (si) {
          final vals = seriesList[si].values;
          return LineChartBarData(
            spots: List.generate(
              vals.length,
              (i) => FlSpot(i.toDouble(), vals[i]),
            ),
            isCurved: true,
            color: colors[si],
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: vals.length <= 12,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3,
                color: colors[si],
                strokeWidth: 1,
                strokeColor: scheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: seriesList.length == 1,
              color: colors[si].withValues(alpha: 0.12),
            ),
          );
        }),
      ),
    );
  }
}

class _PieLabelsLegend extends StatelessWidget {
  final AIChartSpec spec;
  final ColorScheme scheme;
  final ThemeData theme;

  const _PieLabelsLegend({
    required this.spec,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final values = spec.effectiveSeries.first.values;
    final colors = AIChatChartWidget._chartColors(scheme, values.length);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: List.generate(values.length, (i) {
        final label = i < spec.labels.length ? spec.labels[i] : '${i + 1}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors[i % colors.length],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$label (${_compactNumber(values[i])})',
              style: theme.textTheme.labelSmall,
            ),
          ],
        );
      }),
    );
  }
}

class _PieChartBody extends StatelessWidget {
  final AIChartSpec spec;
  final ColorScheme scheme;
  final ThemeData theme;

  const _PieChartBody({
    required this.spec,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final series = spec.effectiveSeries.first;
    final values = series.values;
    final labels = spec.labels;
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();

    final colors = AIChatChartWidget._chartColors(scheme, values.length);

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 36,
        sections: List.generate(values.length, (i) {
          final pct = (values[i] / total * 100);
          final label = i < labels.length ? labels[i] : '';
          return PieChartSectionData(
            value: values[i],
            color: colors[i % colors.length],
            title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
            radius: 72,
            titleStyle: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
            badgeWidget: label.isNotEmpty && pct < 8
                ? null
                : null,
          );
        }),
      ),
    );
  }
}

String _compactNumber(double n) {
  if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(0)}K';
  return n.toStringAsFixed(0);
}
