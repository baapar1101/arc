import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../../theme/tokens/extensions.dart';
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
    final hub = context.settingsHub;
    final t = AppLocalizations.of(context);

    return Container(
      margin: hub.setupMargin,
      padding: hub.setupPadding,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(hub.categoryRadius),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.rocket_launch_outlined,
                color: colorScheme.primary,
                size: hub.setupIconSize,
              ),
              SizedBox(width: hub.cardIconGap),
              Expanded(
                child: Text(
                  t.businessSettingsSetupTitle,
                  style: hub.listTitleStyle(
                    theme.textTheme,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: hub.setupTitleGap),
          Text(
            t.businessSettingsSetupDescription,
            style: hub.cardSubtitleStyle(
              theme.textTheme,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: hub.listTitleGap),
          BusinessSettingsLayout.buildResponsiveGrid(
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
