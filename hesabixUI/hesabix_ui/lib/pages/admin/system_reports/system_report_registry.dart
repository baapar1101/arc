import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// تعریف یک گزارش در پنل «گزارشات» مدیریت سیستم.
///
/// برای افزودن گزارش جدید:
/// 1) یک نمونهٔ جدید به [SystemReportRegistry.items] اضافه کنید.
/// 2) مسیر متناظر را در `main.dart` زیر `system-settings` ثبت کنید (`subPath`).
/// 3) رشته‌های l10n مورد استفاده در [titleBuilder] و [descriptionBuilder] را به `app_*.arb` بیفزایید.
@immutable
class SystemReportDefinition {
  const SystemReportDefinition({
    required this.id,
    required this.subPath,
    required this.titleBuilder,
    required this.descriptionBuilder,
    required this.icon,
    required this.iconColor,
  });

  final String id;
  final String subPath;
  final String Function(AppLocalizations t) titleBuilder;
  final String Function(AppLocalizations t) descriptionBuilder;
  final IconData icon;
  final Color iconColor;

  String get fullPath => '/user/profile/system-settings/$subPath';
}

class SystemReportRegistry {
  SystemReportRegistry._();

  static final List<SystemReportDefinition> items = <SystemReportDefinition>[
    SystemReportDefinition(
      id: 'active_users',
      subPath: 'reports-active-users',
      titleBuilder: (AppLocalizations t) => t.systemReportActiveUsersTitle,
      descriptionBuilder: (AppLocalizations t) => t.systemReportActiveUsersDescription,
      icon: Icons.sensors_rounded,
      iconColor: const Color(0xFF00796B),
    ),
    SystemReportDefinition(
      id: 'signups_timeline',
      subPath: 'reports-signups-timeline',
      titleBuilder: (AppLocalizations t) => t.systemReportSignupsTitle,
      descriptionBuilder: (AppLocalizations t) => t.systemReportSignupsDescription,
      icon: Icons.timeline_outlined,
      iconColor: const Color(0xFF6A1B9A),
    ),
  ];
}
