import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای تبدیل حساب به شبا
class AccountToIbanResultWidget extends ZohalResultWidget {
  const AccountToIbanResultWidget({
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

    if (iban.isEmpty) {
      return [
        Text(
          'شماره شبا یافت نشد.',
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
            Text(
              'شماره شبا',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _copyToClipboard(context, iban),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SelectableText(
                        iban,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.content_copy,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('شماره شبا کپی شد')),
    );
  }
}
