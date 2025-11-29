import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class AreaChartWidget extends StatelessWidget {
  final List<double> data;
  final String title;
  final Color color;
  final String unit;
  final double? maxY;

  const AreaChartWidget({
    super.key,
    required this.data,
    required this.title,
    required this.color,
    this.unit = '%',
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = maxY ?? (data.isNotEmpty ? data.reduce((a, b) => a > b ? a : b) * 1.1 : 100.0);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: data.isEmpty
                  ? Center(
                      child: Text(
                        'داده‌ای موجود نیست',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: maxValue / 4,
                          getDrawingHorizontalLine: (value) {
                            return FlLine(
                              color: Colors.grey.withOpacity(0.2),
                              strokeWidth: 1,
                            );
                          },
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: maxValue / 4,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  '${value.toInt()}$unit',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: false,
                            ),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: false,
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: List.generate(
                              data.length,
                              (index) => FlSpot(index.toDouble(), data[index]),
                            ),
                            isCurved: true,
                            color: color,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  color.withOpacity(0.3),
                                  color.withOpacity(0.1),
                                ],
                              ),
                            ),
                          ),
                        ],
                        minY: 0,
                        maxY: maxValue,
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (List<LineBarSpot> touchedSpots) {
                              return touchedSpots.map((LineBarSpot touchedSpot) {
                                return LineTooltipItem(
                                  '${touchedSpot.y.toStringAsFixed(1)}$unit',
                                  TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

