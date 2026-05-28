import 'package:flutter/material.dart';

/// نوار ظرفیت context گفت‌وگو (تخمینی از سرور).
class AIChatContextMeter extends StatelessWidget {
  final double? usageRatio;
  final double? usagePercent;
  final bool historySummarized;

  const AIChatContextMeter({
    super.key,
    this.usageRatio,
    this.usagePercent,
    this.historySummarized = false,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (usageRatio ?? (usagePercent != null ? usagePercent! / 100 : null));
    if (ratio == null || ratio <= 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clamped = ratio.clamp(0.0, 1.0);
    final percentLabel = usagePercent?.toStringAsFixed(0) ??
        (clamped * 100).toStringAsFixed(0);
    final barColor = clamped >= 0.9
        ? scheme.error
        : clamped >= 0.72
            ? scheme.tertiary
            : scheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.memory_outlined, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'ظرفیت گفت‌وگو: $percentLabel٪',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (historySummarized) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '· تاریخچه خلاصه شد',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.tertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}
