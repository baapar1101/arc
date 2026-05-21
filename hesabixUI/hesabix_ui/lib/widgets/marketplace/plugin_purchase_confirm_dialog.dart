import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'plugin_marketplace_utils.dart';

class PluginPurchaseConfirmDialog extends StatelessWidget {
  final String pluginName;
  final String periodLabel;
  final double price;
  final String currencySymbol;
  final double walletBalance;
  final String walletCurrency;

  const PluginPurchaseConfirmDialog({
    super.key,
    required this.pluginName,
    required this.periodLabel,
    required this.price,
    required this.currencySymbol,
    required this.walletBalance,
    required this.walletCurrency,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String pluginName,
    required String periodLabel,
    required double price,
    required String currencySymbol,
    required double walletBalance,
    required String walletCurrency,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => PluginPurchaseConfirmDialog(
        pluginName: pluginName,
        periodLabel: periodLabel,
        price: price,
        currencySymbol: currencySymbol,
        walletBalance: walletBalance,
        walletCurrency: walletCurrency,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shortfall = price - walletBalance;
    final insufficient = shortfall > 0;

    return AlertDialog(
      title: Text(t.pluginMarketplaceConfirmPurchaseTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(t.pluginMarketplaceConfirmPurchasePlugin, pluginName),
            _Row(t.pluginMarketplaceConfirmPurchasePlan, periodLabel),
            _Row(t.pluginMarketplaceConfirmPurchaseAmount, formatPluginPrice(price, currencySymbol)),
            const Divider(height: 20),
            _Row(
              t.pluginMarketplaceConfirmWalletBalance,
              formatPluginPrice(walletBalance, walletCurrency),
            ),
            if (insufficient) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t.pluginMarketplaceInsufficientFundsBody(
                    formatPluginPrice(price, currencySymbol),
                    formatPluginPrice(walletBalance, walletCurrency),
                    formatPluginPrice(shortfall, currencySymbol),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              t.pluginMarketplacePaymentFromWallet,
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: insufficient ? null : () => Navigator.pop(context, true),
          child: Text(t.pluginMarketplaceConfirmPay),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
