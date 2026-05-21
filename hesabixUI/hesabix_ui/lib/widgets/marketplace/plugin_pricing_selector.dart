import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'plugin_marketplace_utils.dart';

typedef PluginPlanSelected = void Function(Map<String, dynamic> plan);

class PluginPricingSelector extends StatelessWidget {
  final List<Map<String, dynamic>> plans;
  final String walletCurrency;
  final Map<String, dynamic>? pluginStatus;
  final bool canBuy;
  final PluginPlanSelected? onSelectPlan;

  const PluginPricingSelector({
    super.key,
    required this.plans,
    required this.walletCurrency,
    required this.pluginStatus,
    required this.canBuy,
    this.onSelectPlan,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final savings = yearlySavingsPercent(plans);
    final isPurchased = pluginStatus != null && pluginStatus!.isNotEmpty;
    final currentPlanId = (pluginStatus?['plan_id'] as num?)?.toInt();

    // ترتیب نمایش: ماهانه، سالانه، مادام‌العمر
    final ordered = [...plans]..sort((a, b) {
        const order = {'monthly': 0, 'yearly': 1, 'lifetime': 2};
        final pa = order[a['period']?.toString()] ?? 9;
        final pb = order[b['period']?.toString()] ?? 9;
        return pa.compareTo(pb);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.pluginMarketplaceComparePlans, style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        ...ordered.map((pl) {
          final planId = (pl['id'] as num?)?.toInt();
          final period = pl['period']?.toString();
          final price = (pl['price'] ?? 0).toDouble();
          final symbol = currencySymbolFromPlan(pl, walletCurrency);
          final isCurrent = isPurchased && currentPlanId == planId;
          final isYearly = period == 'yearly';
          final isPopular = isYearly && savings != null && savings > 0;
          final equiv = equivalentMonthlyPrice(pl, symbol);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: isCurrent
                  ? cs.primaryContainer.withValues(alpha: 0.35)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isCurrent
                      ? cs.primary.withValues(alpha: 0.6)
                      : cs.outlineVariant.withValues(alpha: 0.45),
                  width: isCurrent || isPopular ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pluginPeriodLabel(t, period),
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (isPopular)
                          _Badge(label: t.pluginMarketplacePopularPlan, color: cs.tertiaryContainer, onColor: cs.onTertiaryContainer),
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          _Badge(label: t.pluginMarketplacePlanCurrent, color: cs.primaryContainer, onColor: cs.onPrimaryContainer),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatPluginPrice(price, symbol),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    if (equiv != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        t.pluginMarketplaceEquivalentMonthly(equiv),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                    if (isYearly && savings != null && savings > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        t.pluginMarketplaceSavingsPercent(savings),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Semantics(
                      button: true,
                      enabled: canBuy && !isCurrent && onSelectPlan != null,
                      label: pluginPeriodLabel(t, period),
                      child: FilledButton.icon(
                        onPressed: canBuy && !isCurrent && onSelectPlan != null
                            ? () => onSelectPlan!(pl)
                            : null,
                        icon: Icon(isCurrent ? Icons.check_circle : Icons.shopping_cart_checkout_outlined),
                        label: Text(isCurrent ? t.pluginMarketplacePlanPurchased : pluginPeriodLabel(t, period)),
                      ),
                    ),
                    if (!canBuy && !isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          t.pluginMarketplaceBuyDisabledTooltip,
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color onColor;

  const _Badge({required this.label, required this.color, required this.onColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: onColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
