import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای استعلام چک برگشتی
class BouncedChequeResultWidget extends ZohalResultWidget {
  const BouncedChequeResultWidget({
    super.key,
    required super.result,
    required super.amountCharged,
    required super.remainingBalance,
    required super.walletCurrency,
  });

  @override
  List<Widget> buildResultContent(BuildContext context) {
    final theme = Theme.of(context);
    final responseBody = result['result']?['response_body'] as Map<String, dynamic>?;
    final data = responseBody?['data'] as Map<String, dynamic>?;
    
    final count = data?['count'] as int? ?? 0;

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: count > 0
                ? theme.colorScheme.error.withValues(alpha: 0.5)
                : theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              count > 0 ? Icons.warning : Icons.check_circle,
              size: 64,
              color: count > 0
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'تعداد چک‌های برگشتی',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: count > 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'این فرد دارای $count چک برگشتی است',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'این فرد چک برگشتی ندارد',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}
