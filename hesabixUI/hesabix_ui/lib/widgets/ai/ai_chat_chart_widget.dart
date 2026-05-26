import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// مشخصات نمودار — JSON در بلوک ```chart
class AIChartSpec {
  final String type;
  final String title;
  final List<String> labels;
  final List<double> values;
  final String? unit;

  const AIChartSpec({
    required this.type,
    required this.title,
    required this.labels,
    required this.values,
    this.unit,
  });

  factory AIChartSpec.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['labels'];
    final rawValues = json['values'];
    return AIChartSpec(
      type: json['type'] as String? ?? 'bar',
      title: json['title'] as String? ?? 'نمودار',
      labels: rawLabels is List
          ? rawLabels.map((e) => e.toString()).toList()
          : [],
      values: rawValues is List
          ? rawValues.map((e) => (e as num).toDouble()).toList()
          : [],
      unit: json['unit'] as String?,
    );
  }

  static AIChartSpec? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw.trim()) as Map<String, dynamic>;
      return AIChartSpec.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

class AIChatChartWidget extends StatelessWidget {
  final AIChartSpec spec;

  const AIChatChartWidget({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (spec.values.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxY = spec.values.reduce((a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 1.0 : maxY * 1.15;

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
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
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
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(spec.values.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: spec.values[i],
                        color: scheme.primary,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _compactNumber(double n) {
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }
}
