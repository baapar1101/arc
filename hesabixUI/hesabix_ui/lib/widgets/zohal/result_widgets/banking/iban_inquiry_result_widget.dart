import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای استعلام شبا
class IbanInquiryResultWidget extends ZohalResultWidget {
  const IbanInquiryResultWidget({
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
    final bankName = data?['bank_name']?.toString() ?? '';
    final isTransferable = data?['is_transferable'] as bool? ?? false;

    if (name.isEmpty) {
      return [
        Text(
          'اطلاعات حساب یافت نشد.',
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
              Icons.account_balance_wallet,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            _buildInfoRow(context, theme, 'نام صاحب حساب', name),
            const SizedBox(height: 12),
            if (bankName.isNotEmpty)
              _buildInfoRow(context, theme, 'نام بانک', bankName),
            const SizedBox(height: 12),
            _buildTransferableRow(context, theme, isTransferable),
          ],
        ),
      ),
    ];
  }

  Widget _buildInfoRow(
    BuildContext context,
    ThemeData theme,
    String label,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferableRow(BuildContext context, ThemeData theme, bool isTransferable) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTransferable 
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isTransferable ? Icons.check_circle : Icons.cancel,
            color: isTransferable 
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isTransferable ? 'قابل انتقال وجه است' : 'غیرقابل انتقال وجه',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isTransferable
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
