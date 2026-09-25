import 'package:flutter/material.dart';

/// تأیید خرید مهارت پولی از کیف پول
class AISkillPurchaseConfirmDialog extends StatelessWidget {
  final String skillTitle;
  final double price;
  final String currencySymbol;
  final double walletBalance;

  const AISkillPurchaseConfirmDialog({
    super.key,
    required this.skillTitle,
    required this.price,
    required this.currencySymbol,
    required this.walletBalance,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String skillTitle,
    required double price,
    required String currencySymbol,
    required double walletBalance,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AISkillPurchaseConfirmDialog(
        skillTitle: skillTitle,
        price: price,
        currencySymbol: currencySymbol,
        walletBalance: walletBalance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shortfall = price - walletBalance;
    final insufficient = shortfall > 0;

    return AlertDialog(
      title: const Text('تأیید خرید مهارت'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('مهارت', skillTitle),
          _row('مبلغ', '$price $currencySymbol'),
          const Divider(height: 20),
          _row('موجودی کیف پول', '$walletBalance $currencySymbol'),
          if (insufficient) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'موجودی کافی نیست. کمبود: ${shortfall.toStringAsFixed(0)} $currencySymbol',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'مبلغ از کیف پول کسر می‌شود.',
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
        FilledButton(
          onPressed: insufficient ? null : () => Navigator.pop(context, true),
          child: const Text('خرید و نصب'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
