import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class MetricGauge extends StatelessWidget {
  final double value;
  final double maxValue;
  final String title;
  final String unit;
  final Color? color;

  const MetricGauge({
    super.key,
    required this.value,
    this.maxValue = 100.0,
    required this.title,
    this.unit = '%',
    this.color,
  });

  Color get _statusColor {
    if (color != null) return color!;
    final percent = (value / maxValue) * 100;
    if (percent < 50) return Colors.green;
    if (percent < 80) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = ((value / maxValue) * 100).clamp(0.0, 100.0);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              width: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 120,
                    width: 120,
                    child: CircularProgressIndicator(
                      value: percent / 100,
                      strokeWidth: 12,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${percent.toStringAsFixed(1)}$unit',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _statusColor,
                        ),
                      ),
                      Text(
                        '${value.toStringAsFixed(1)} / ${maxValue.toStringAsFixed(0)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

