import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Bar chart: created vs resolved tickets per day.
class SupportActivityChart extends StatelessWidget {
  final List<Map<String, dynamic>> activity;

  const SupportActivityChart({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (activity.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('داده‌ای برای نمایش وجود ندارد')),
      );
    }

    final maxVal = activity.fold<int>(0, (m, d) {
      final c = (d['created_count'] is int ? d['created_count'] as int : int.tryParse('${d['created_count']}') ?? 0);
      final r = (d['resolved_count'] is int ? d['resolved_count'] as int : int.tryParse('${d['resolved_count']}') ?? 0);
      return [m, c, r].reduce((a, b) => a > b ? a : b);
    }).toDouble();

    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal < 1 ? 4 : maxVal * 1.2,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: theme.colorScheme.outline.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text('${v.toInt()}', style: theme.textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= activity.length) return const SizedBox.shrink();
                  final date = '${activity[i]['date'] ?? ''}';
                  final short = date.length >= 5 ? date.substring(5) : date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(short, style: theme.textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(activity.length, (i) {
            final created = activity[i]['created_count'] is int
                ? (activity[i]['created_count'] as int).toDouble()
                : double.tryParse('${activity[i]['created_count']}') ?? 0;
            final resolved = activity[i]['resolved_count'] is int
                ? (activity[i]['resolved_count'] as int).toDouble()
                : double.tryParse('${activity[i]['resolved_count']}') ?? 0;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: created,
                  color: theme.colorScheme.primary,
                  width: 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                BarChartRodData(
                  toY: resolved,
                  color: Colors.green,
                  width: 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
              barsSpace: 4,
            );
          }),
        ),
      ),
    );
  }
}
