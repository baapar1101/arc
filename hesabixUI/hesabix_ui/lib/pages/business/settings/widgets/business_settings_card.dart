import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../../theme/tokens/extensions.dart';
import '../../../system_settings/models/settings_item.dart';
import '../business_settings_localization_helper.dart';

/// Business settings hub card with RTL-aware navigation affordance.
class BusinessSettingsCard extends StatelessWidget {
  final SettingsItem item;
  final VoidCallback? onTap;
  final bool isHighlighted;
  final bool isDanger;
  final bool isLoading;

  const BusinessSettingsCard({
    super.key,
    required this.item,
    this.onTap,
    this.isHighlighted = false,
    this.isDanger = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hub = context.settingsHub;
    final t = AppLocalizations.of(context);
    final effectiveColor = isDanger ? colorScheme.error : item.color;
    final borderColor = isHighlighted
        ? effectiveColor
        : isDanger
            ? colorScheme.error.withValues(alpha: 0.35)
            : colorScheme.outline.withValues(alpha: 0.1);
    final radius = BorderRadius.circular(hub.cardRadius);

    void handleTap() {
      if (isLoading) return;
      if (onTap != null) {
        onTap!();
        return;
      }
      if (item.route.isNotEmpty) {
        context.push(item.route);
      }
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDanger ? colorScheme.errorContainer.withValues(alpha: 0.25) : null,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: borderColor, width: isHighlighted ? 2 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : handleTap,
          borderRadius: radius,
          hoverColor: effectiveColor.withValues(alpha: 0.05),
          splashColor: effectiveColor.withValues(alpha: 0.1),
          child: Padding(
            padding: hub.cardPadding,
            child: Row(
              children: [
                Container(
                  padding: hub.cardIconPadding,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(hub.cardIconRadius),
                  ),
                  child: Icon(item.icon, color: effectiveColor, size: hub.cardIconSize),
                ),
                SizedBox(width: hub.cardIconGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        BusinessSettingsLocalizationHelper.getTitle(t, item.title),
                        style: hub.cardTitleStyle(
                          theme.textTheme,
                          color: isDanger ? colorScheme.error : colorScheme.onSurface,
                        ),
                        maxLines: hub.cardTitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: hub.cardTitleGap),
                      Text(
                        BusinessSettingsLocalizationHelper.getDescription(
                          t,
                          item.description,
                        ),
                        style: hub.cardSubtitleStyle(
                          theme.textTheme,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: hub.cardSubtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  SizedBox(
                    width: hub.chevronSize,
                    height: hub.chevronSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: effectiveColor,
                    ),
                  )
                else
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                    size: hub.chevronSize,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
