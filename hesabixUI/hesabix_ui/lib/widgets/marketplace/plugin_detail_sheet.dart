import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'plugin_icon_avatar.dart';
import 'plugin_marketplace_utils.dart';
import 'plugin_pricing_selector.dart';
import 'plugin_status_badge.dart';

class PluginDetailSheet extends StatefulWidget {
  final Map<String, dynamic> plugin;
  final Map<String, dynamic>? pluginStatus;
  final String walletCurrency;
  final bool canBuy;
  final bool trialAllowed;
  final int? trialDays;
  final bool hasUsedTrial;
  final Future<void> Function()? onStartTrial;
  final void Function(Map<String, dynamic> plan)? onPurchasePlan;

  const PluginDetailSheet({
    super.key,
    required this.plugin,
    required this.pluginStatus,
    required this.walletCurrency,
    required this.canBuy,
    required this.trialAllowed,
    this.trialDays,
    required this.hasUsedTrial,
    this.onStartTrial,
    this.onPurchasePlan,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> plugin,
    required Map<String, dynamic>? pluginStatus,
    required String walletCurrency,
    required bool canBuy,
    required bool trialAllowed,
    int? trialDays,
    required bool hasUsedTrial,
    Future<void> Function()? onStartTrial,
    void Function(Map<String, dynamic> plan)? onPurchasePlan,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => PluginDetailSheet(
        plugin: plugin,
        pluginStatus: pluginStatus,
        walletCurrency: walletCurrency,
        canBuy: canBuy,
        trialAllowed: trialAllowed,
        trialDays: trialDays,
        hasUsedTrial: hasUsedTrial,
        onStartTrial: onStartTrial,
        onPurchasePlan: onPurchasePlan,
      ),
    );
  }

  @override
  State<PluginDetailSheet> createState() => _PluginDetailSheetState();
}

class _PluginDetailSheetState extends State<PluginDetailSheet> {
  bool _expandedDescription = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final name = widget.plugin['name']?.toString() ?? '-';
    final code = widget.plugin['code']?.toString();
    final category = widget.plugin['category']?.toString();
    final description = widget.plugin['description']?.toString() ?? '';
    final plans = (widget.plugin['plans'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final isPurchased = widget.pluginStatus != null && widget.pluginStatus!.isNotEmpty;
    final showTrial = widget.trialAllowed && !isPurchased && !widget.hasUsedTrial;

    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.92;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(t.pluginMarketplaceDetailTitle, style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PluginIconAvatar(
                          iconUrl: widget.plugin['icon_url']?.toString(),
                          category: category,
                          name: name,
                          size: 56,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                              if (category != null && category.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  pluginCategoryLabel(t, category),
                                  style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (isPurchased) ...[
                      const SizedBox(height: 12),
                      PluginStatusBadge(
                        pluginStatus: widget.pluginStatus,
                        totalTrialDays: widget.trialDays,
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(description, style: theme.textTheme.bodyMedium, maxLines: _expandedDescription ? null : 6),
                      if (description.length > 200)
                        TextButton(
                          onPressed: () => setState(() => _expandedDescription = !_expandedDescription),
                          child: Text(_expandedDescription ? t.pluginMarketplaceReadLess : t.pluginMarketplaceReadMore),
                        ),
                    ],
                    if (showTrial && widget.onStartTrial != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: widget.canBuy ? () async { await widget.onStartTrial!(); } : null,
                        icon: const Icon(Icons.free_breakfast_outlined),
                        label: Text(t.pluginMarketplaceStartTrial),
                      ),
                    ],
                    if (plans.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      PluginPricingSelector(
                        plans: plans,
                        walletCurrency: widget.walletCurrency,
                        pluginStatus: widget.pluginStatus,
                        canBuy: widget.canBuy,
                        onSelectPlan: widget.onPurchasePlan,
                      ),
                    ],
                    if (code != null && code.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        t.pluginMarketplacePluginCodeSupport(code),
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
