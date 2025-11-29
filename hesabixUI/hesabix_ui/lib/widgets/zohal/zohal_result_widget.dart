import 'package:flutter/material.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;

/// اینترفیس پایه برای ویجت‌های نمایش نتیجه سرویس‌های زحل
abstract class ZohalResultWidget extends StatelessWidget {
  final Map<String, dynamic> result;
  final double? amountCharged;
  final double? remainingBalance;
  final String? walletCurrency;

  const ZohalResultWidget({
    super.key,
    required this.result,
    required this.amountCharged,
    required this.remainingBalance,
    required this.walletCurrency,
  });

  /// ساخت ویجت نتیجه
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = result['success'] as bool? ?? false;
    final responseBody = result['result']?['response_body'] as Map<String, dynamic>?;
    final message = responseBody?['message']?.toString() ?? '';

    if (!success) {
      return _buildErrorCard(context, theme, message);
    }

    return Card(
      margin: const EdgeInsets.all(16),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSuccessHeader(context, theme),
            const SizedBox(height: 16),
            ...buildResultContent(context),
            const SizedBox(height: 16),
            _buildChargeInfo(context, theme),
          ],
        ),
      ),
    );
  }

  /// ساخت هدر موفقیت
  Widget _buildSuccessHeader(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 8),
        Text(
          'استعلام موفق',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }

  /// ساخت کارت خطا
  Widget _buildErrorCard(BuildContext context, ThemeData theme, String message) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.error,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.isNotEmpty ? message : 'استعلام ناموفق',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ساخت اطلاعات هزینه
  Widget _buildChargeInfo(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        if (amountCharged != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('هزینه:', style: theme.textTheme.bodyMedium),
              Text(
                '${formatWithThousands(amountCharged!)} ${walletCurrency ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (remainingBalance != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('موجودی باقیمانده:', style: theme.textTheme.bodyMedium),
              Text(
                '${formatWithThousands(remainingBalance!)} ${walletCurrency ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// ساخت محتوای نتیجه - باید در کلاس‌های فرزند پیاده‌سازی شود
  List<Widget> buildResultContent(BuildContext context);
}
