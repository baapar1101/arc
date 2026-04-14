import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای استعلام نام صاحب کارت
class CardInquiryResultWidget extends ZohalResultWidget {
  const CardInquiryResultWidget({
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
    final name = data?['name']?.toString() ?? '';

    if (name.isEmpty) {
      return [
        Text(
          'نام صاحب کارت یافت نشد.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ];
    }

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.person,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'نام صاحب کارت',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ];
  }
}

