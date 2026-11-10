import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../theme/tokens/extensions.dart';
import '../admin_compact_scaffold.dart';
import 'system_report_registry.dart';

/// فهرست فشردهٔ گزارش‌های مدیریت سیستم.
class SystemReportsHubPage extends StatelessWidget {
  const SystemReportsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hub = context.settingsHub;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return AdminCompactScaffold(
      title: t.settingsSystemReports,
      subtitle: t.systemReportsHubIntro,
      body: ListView(
        padding: hub.pagePadding,
        children: [
          ...SystemReportRegistry.items.map((def) {
            return Padding(
              padding: EdgeInsets.only(bottom: hub.gridRunSpacing),
              child: Material(
                color: scheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(hub.cardRadius),
                  side: BorderSide(color: scheme.outline.withValues(alpha: 0.1)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(hub.cardRadius),
                  onTap: () => context.push(def.fullPath),
                  child: Padding(
                    padding: hub.cardPadding,
                    child: Row(
                      children: [
                        Container(
                          padding: hub.cardIconPadding,
                          decoration: BoxDecoration(
                            color: def.iconColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(hub.cardIconRadius),
                          ),
                          child: Icon(def.icon, color: def.iconColor, size: hub.cardIconSize),
                        ),
                        SizedBox(width: hub.cardIconGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                def.titleBuilder(t),
                                maxLines: hub.cardTitleMaxLines,
                                overflow: TextOverflow.ellipsis,
                                style: hub.cardTitleStyle(theme.textTheme, color: scheme.onSurface),
                              ),
                              SizedBox(height: hub.cardTitleGap),
                              Text(
                                def.descriptionBuilder(t),
                                maxLines: hub.cardSubtitleMaxLines,
                                overflow: TextOverflow.ellipsis,
                                style: hub.cardSubtitleStyle(
                                  theme.textTheme,
                                  color: scheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          rtl ? Icons.chevron_left : Icons.chevron_right,
                          size: hub.chevronSize,
                          color: scheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
