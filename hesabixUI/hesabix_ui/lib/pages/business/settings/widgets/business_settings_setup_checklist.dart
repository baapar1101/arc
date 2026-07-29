import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../system_settings/models/settings_item.dart';
import '../business_settings_layout.dart';
import 'business_settings_card.dart';

/// Quick setup checklist for new business owners.
class BusinessSettingsSetupChecklist extends StatelessWidget {
  final List<SettingsItem> items;

  const BusinessSettingsSetupChecklist({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch_outlined, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.businessSettingsSetupTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t.businessSettingsSetupDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          BusinessSettingsLayout.buildTwoColumnGrid(
            context: context,
            children: items
                .map(
                  (item) => BusinessSettingsCard(
                    item: item,
                    onTap: () => context.push(item.route),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
