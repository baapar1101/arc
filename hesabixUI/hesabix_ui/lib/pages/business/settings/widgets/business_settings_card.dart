import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

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
    final t = AppLocalizations.of(context);
    final effectiveColor = isDanger ? colorScheme.error : item.color;
    final borderColor = isHighlighted
        ? effectiveColor
        : isDanger
            ? colorScheme.error.withValues(alpha: 0.35)
            : colorScheme.outline.withValues(alpha: 0.1);

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
      color: isDanger ? colorScheme.errorContainer.withValues(alpha: 0.25) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: isHighlighted ? 2 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : handleTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: effectiveColor.withValues(alpha: 0.05),
          splashColor: effectiveColor.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(item.icon, color: effectiveColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        BusinessSettingsLocalizationHelper.getTitle(t, item.title),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDanger ? colorScheme.error : colorScheme.onSurface,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        BusinessSettingsLocalizationHelper.getDescription(
                          t,
                          item.description,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
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
                    size: 20,
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
