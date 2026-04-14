import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای تبدیل کارت به شبا
class CardToIbanResultWidget extends ZohalResultWidget {
  const CardToIbanResultWidget({
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
    
    final iban = data?['IBAN']?.toString() ?? '';
    final bankName = data?['bank_name']?.toString() ?? '';
    final name = data?['name']?.toString() ?? '';

    if (iban.isEmpty) {
      return [
        Text(
          'اطلاعات شبا یافت نشد.',
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
              Icons.account_balance,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            if (name.isNotEmpty) ...[
              _buildInfoRow(context, theme, 'نام صاحب حساب', name),
              const SizedBox(height: 12),
            ],
            _buildInfoRow(
              context,
              theme,
              'شماره شبا',
              iban,
              onTap: () => _copyToClipboard(context, iban),
              isCopyable: true,
            ),
            if (bankName.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInfoRow(context, theme, 'نام بانک', bankName),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _buildInfoRow(
    BuildContext context,
    ThemeData theme,
    String label,
    String value, {
    bool isCopyable = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: isCopyable ? (onTap ?? () => _copyToClipboard(context, value)) : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isCopyable 
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
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
            if (isCopyable)
              Icon(
                Icons.content_copy,
                size: 20,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کپی شد')),
    );
  }
}
