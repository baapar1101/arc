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
    SystemReportDefinition(
      id: 'storage_usage',
      subPath: 'reports-storage',
      titleBuilder: (AppLocalizations t) =>
          t.localeName.startsWith('fa') ? 'مصرف ذخیره‌سازی' : 'Storage usage',
      descriptionBuilder: (AppLocalizations t) =>
          t.localeName.startsWith('fa') ? 'حجم فایل به تفکیک کسب‌وکار' : 'File volume by business',
      icon: Icons.cloud_outlined,
      iconColor: const Color(0xFF0277BD),
    ),
    SystemReportDefinition(
      id: 'inactive_businesses',
      subPath: 'reports-inactive-businesses',
      titleBuilder: (AppLocalizations t) =>
          t.localeName.startsWith('fa') ? 'کسب‌وکارهای کم‌فعال' : 'Inactive businesses',
      descriptionBuilder: (AppLocalizations t) => t.localeName.startsWith('fa')
          ? 'کسب‌وکارهایی که ۹۰ روز به‌روز نشده‌اند'
          : 'Businesses with no update for 90 days',
      icon: Icons.business_outlined,
      iconColor: const Color(0xFF6D4C41),
    ),
    SystemReportDefinition(
      id: 'failed_logins',
      subPath: 'reports-failed-logins',
      titleBuilder: (AppLocalizations t) =>
          t.localeName.startsWith('fa') ? 'شکست ورود' : 'Failed logins',
      descriptionBuilder: (AppLocalizations t) =>
          t.localeName.startsWith('fa') ? 'ورود و کپچای ناموفق' : 'Failed sign-in and captcha events',
      icon: Icons.lock_outline,
      iconColor: const Color(0xFFC62828),
    ),
    SystemReportDefinition(
      id: 'support_revenue',
      subPath: 'reports-support-revenue',
      titleBuilder: (AppLocalizations t) =>
          t.localeName.startsWith('fa') ? 'درآمد پشتیبانی' : 'Support revenue',
      descriptionBuilder: (AppLocalizations t) => t.localeName.startsWith('fa')
          ? 'اشتراک و صورت‌حساب پشتیبانی'
          : 'Support subscriptions and invoices',
      icon: Icons.payments_outlined,
      iconColor: const Color(0xFF2E7D32),
    ),
  ];
}
