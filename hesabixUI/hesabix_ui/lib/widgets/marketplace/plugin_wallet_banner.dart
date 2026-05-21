import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_named_route_locations.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../widgets/wallet/wallet_top_up_dialog.dart';

class PluginWalletBanner extends StatelessWidget {
  final int businessId;
  final double availableBalance;
  final String currencySymbol;
  final double? cheapestPlanPrice;
  final bool canViewInvoices;
  final VoidCallback? onAfterTopUp;

  const PluginWalletBanner({
    super.key,
    required this.businessId,
    required this.availableBalance,
    required this.currencySymbol,
    this.cheapestPlanPrice,
    this.canViewInvoices = true,
    this.onAfterTopUp,
  });

  bool get _lowBalance {
    final min = cheapestPlanPrice;
    if (min == null || min <= 0) return false;
    return availableBalance < min;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final formatted = formatWithThousands(availableBalance, decimalPlaces: 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: cs.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: cs.primaryContainer.withValues(alpha: 0.85),
                    child: Icon(Icons.account_balance_wallet, color: cs.onPrimaryContainer, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.pluginMarketplaceWalletBalance,
                          style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$formatted $currencySymbol',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_lowBalance) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: cs.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.pluginMarketplaceWalletLowBalance,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => WalletTopUpDialog.show(
                      context: context,
                      businessId: businessId,
                      currencyLabel: currencySymbol,
                      onSuccess: onAfterTopUp,
                    ),
                    icon: const Icon(Icons.add_card_outlined, size: 18),
                    label: Text(t.pluginMarketplaceWalletTopUp),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      BusinessNamedRoutes.goNamed(
                        context,
                        businessId: businessId,
                        routeName: 'business_wallet',
                      );
                    },
                    icon: const Icon(Icons.wallet_outlined, size: 18),
                    label: Text(t.pluginMarketplaceGoToWallet),
                  ),
                  if (canViewInvoices)
                    TextButton.icon(
                      onPressed: () {
                        BusinessNamedRoutes.goNamed(
                          context,
                          businessId: businessId,
                          routeName: 'business_plugin_marketplace_invoices',
                        );
                      },
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text(t.pluginMarketplaceInvoicesLink),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
