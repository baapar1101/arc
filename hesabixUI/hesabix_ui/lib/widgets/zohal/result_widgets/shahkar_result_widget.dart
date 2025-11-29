import 'package:flutter/material.dart';
import '../../zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای سرویس شاهکار
class ShahkarResultWidget extends ZohalResultWidget {
  const ShahkarResultWidget({
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
    final matched = data?['matched'] as bool? ?? false;

    return [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: matched
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: matched
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              matched ? Icons.check_circle : Icons.cancel,
              size: 64,
              color: matched
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(height: 16),
            Text(
              matched ? 'تطابق تأیید شد' : 'تطابق تأیید نشد',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: matched
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              matched
                  ? 'شماره موبایل با کد ملی مطابقت دارد'
                  : 'شماره موبایل با کد ملی مطابقت ندارد',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: matched
                    ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.9)
                    : theme.colorScheme.onErrorContainer.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ];
  }
}

