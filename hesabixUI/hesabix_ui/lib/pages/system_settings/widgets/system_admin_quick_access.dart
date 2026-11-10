import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../theme/tokens/extensions.dart';
import '../../business/settings/business_settings_layout.dart';
import '../models/settings_item.dart';
import 'settings_card.dart';

/// نوار کارهای پرتکرار بالای هاب مدیر سیستم.
class SystemAdminQuickAccess extends StatelessWidget {
  final List<SettingsItem> items;

  const SystemAdminQuickAccess({super.key, required this.items});

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
                Icons.bolt_outlined,
                color: colorScheme.primary,
                size: hub.setupIconSize,
              ),
              SizedBox(width: hub.cardIconGap),
              Expanded(
                child: Text(
                  t.systemAdminQuickAccessTitle,
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
            t.systemAdminQuickAccessDescription,
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
            children: items.map((item) => SettingsCard(item: item)).toList(),
          ),
        ],
      ),
    );
  }
}
