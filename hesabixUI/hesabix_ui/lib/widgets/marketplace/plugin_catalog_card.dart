import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'plugin_icon_avatar.dart';
import 'plugin_marketplace_utils.dart';
import 'plugin_status_badge.dart';

class PluginCatalogCard extends StatelessWidget {
  final Map<String, dynamic> plugin;
  final Map<String, dynamic>? pluginStatus;
  final String walletCurrency;
  final int? trialDays;
  final bool trialAllowed;
  final VoidCallback onOpen;

  const PluginCatalogCard({
    super.key,
    required this.plugin,
    required this.pluginStatus,
    required this.walletCurrency,
    required this.trialAllowed,
    this.trialDays,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final name = plugin['name']?.toString() ?? '-';
    final category = plugin['category']?.toString();
    final description = plugin['description']?.toString() ?? '';
    final plans = (plugin['plans'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final minPrice = cheapestPlanPrice(plans);
    final symbol = plans.isNotEmpty
        ? currencySymbolFromPlan(plans.first, walletCurrency)
        : walletCurrency;
    final fromPrice = minPrice != null ? t.pluginMarketplaceFromPrice(formatPluginPrice(minPrice, symbol)) : null;
    final highlights = pluginDescriptionHighlights(description);
    final isPurchased = pluginStatus != null && pluginStatus!.isNotEmpty;
    final showTrialChip = trialAllowed && !isPurchased && !hasUsedTrial(pluginStatus);

    return Semantics(
      button: true,
      label: name,
      child: Material(
        color: cs.surfaceContainerLow,
        elevation: 0,
        surfaceTintColor: cs.surfaceTint.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PluginStatusStrip(pluginStatus: pluginStatus),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PluginIconAvatar(
                          iconUrl: plugin['icon_url']?.toString(),
                          category: category,
                          name: name,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (category != null && category.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _CategoryChip(label: pluginCategoryLabel(t, category)),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_left, color: cs.outline, size: 22),
                      ],
                    ),
                    if (isPurchased) ...[
                      const SizedBox(height: 10),
                      PluginStatusBadge(
                        pluginStatus: pluginStatus,
                        compact: true,
                        totalTrialDays: trialDays,
                      ),
                    ],
                    if (showTrialChip) ...[
                      const SizedBox(height: 8),
                      _TrialChip(days: trialDays ?? 7),
                    ],
                    if (highlights.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...highlights.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_circle_outline, size: 14, color: cs.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  line,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (fromPrice != null)
                          Expanded(
                            child: Text(
                              fromPrice,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        FilledButton.tonal(
                          onPressed: onOpen,
                          child: Text(t.pluginMarketplaceViewAndBuy),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TrialChip extends StatelessWidget {
  final int days;
  const _TrialChip({required this.days});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.free_breakfast_outlined, size: 14, color: cs.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            t.pluginMarketplaceFreeTrialDays(days),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
