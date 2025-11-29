import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  late final List<SettingsItem> _settingsItems;

  @override
  void initState() {
    super.initState();
    _settingsItems = [
      SettingsItem(
        title: 'storageManagement',
        description: 'storageManagementDescription',
        icon: Icons.cloud_upload_outlined,
        color: const Color(0xFF2196F3),
        route: '/user/profile/system-settings/storage',
      ),
      SettingsItem(
        title: 'پلن‌های ذخیره‌سازی',
        description: 'مدیریت پلن‌های ذخیره‌سازی و تعیین قیمت‌ها',
        icon: Icons.storage_outlined,
        color: const Color(0xFF00BCD4),
        route: '/user/profile/system-settings/storage-plans',
      ),
      SettingsItem(
        title: 'تنظیمات پکیج‌ها',
        description: 'مدیریت سناریوی درآمدزایی اسناد و پکیج‌ها',
        icon: Icons.layers_outlined,
        color: const Color(0xFF26A69A),
        route: '/user/profile/system-settings/document-monetization',
      ),
      SettingsItem(
        title: 'systemConfiguration',
        description: 'systemConfigurationDescription',
        icon: Icons.settings_outlined,
        color: const Color(0xFF4CAF50),
        route: '/user/profile/system-settings/configuration',
      ),
      SettingsItem(
        title: 'لینک‌های اشتراک',
        description: 'تعیین آدرس مقصد نمایش کارت حساب در لینک‌های عمومی',
        icon: Icons.link_outlined,
        color: const Color(0xFF8E24AA),
        route: '/user/profile/system-settings/share-links',
      ),
      SettingsItem(
        title: 'تنظیمات کیف‌پول',
        description: 'تعیین ارز پایه و سیاست‌ها',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF009688),
        route: '/user/profile/system-settings/wallet',
      ),
      SettingsItem(
        title: 'درگاه‌های پرداخت',
        description: 'مدیریت و پیکربندی درگاه‌ها',
        icon: Icons.payment_outlined,
        color: const Color(0xFF3F51B5),
        route: '/user/profile/system-settings/payment-gateways',
      ),
      SettingsItem(
        title: 'userManagement',
        description: 'userManagementDescription',
        icon: Icons.people_outlined,
        color: const Color(0xFFFF9800),
        route: '/user/profile/system-settings/users',
      ),
      SettingsItem(
        title: 'systemLogs',
        description: 'systemLogsDescription',
        icon: Icons.analytics_outlined,
        color: const Color(0xFF9C27B0),
        route: '/user/profile/system-settings/logs',
      ),
      SettingsItem(
        title: 'لاگ‌های سرویس‌ها',
        description: 'مشاهده لاگ‌های hesabix-api و hesabix-rq-worker و مدیریت سرویس‌ها',
        icon: Icons.terminal_outlined,
        color: const Color(0xFF607D8B),
        route: '/user/profile/system-settings/service-logs',
      ),
      SettingsItem(
        title: 'emailSettings',
        description: 'emailSettingsDescription',
        icon: Icons.email_outlined,
        color: const Color(0xFFE91E63),
        route: '/user/profile/system-settings/email',
      ),
      SettingsItem(
        title: 'مدیریت اعلان‌ها',
        description: 'ایجاد/ویرایش/انتشار اعلان‌های سیستمی',
        icon: Icons.notifications_active_outlined,
        color: const Color(0xFF795548),
        route: '/user/profile/system-settings/announcements',
      ),
      SettingsItem(
        title: 'تنظیمات نوتیفیکیشن',
        description: 'فعال/غیرفعال‌سازی کانال‌ها و ارسال تست',
        icon: Icons.notifications_outlined,
        color: const Color(0xFF607D8B),
        route: '/user/profile/system-settings/notifications',
      ),
      SettingsItem(
        title: 'قالب‌های نوتیفیکیشن',
        description: 'مدیریت قالب‌ها برای کانال‌ها و زبان‌ها',
        icon: Icons.description_outlined,
        color: const Color(0xFF455A64),
        route: '/user/profile/system-settings/notification-templates',
      ),
      SettingsItem(
        title: 'مدیریت کسب و کارها',
        description: 'مشاهده و مدیریت لیست همه کسب و کارهای سیستم',
        icon: Icons.business_outlined,
        color: const Color(0xFF1976D2),
        route: '/user/profile/system-settings/businesses',
      ),
      SettingsItem(
        title: 'تنظیمات AI',
        description: 'پیکربندی Provider، مدل و API Key',
        icon: Icons.smart_toy_outlined,
        color: const Color(0xFF9C27B0),
        route: '/user/profile/system-settings/ai-settings',
      ),
      SettingsItem(
        title: 'پلن‌های AI',
        description: 'مدیریت پلن‌های استفاده از AI و تعیین قیمت‌ها',
        icon: Icons.subscriptions_outlined,
        color: const Color(0xFF673AB7),
        route: '/user/profile/system-settings/ai-plans',
      ),
      SettingsItem(
        title: 'سرویس‌های زحل',
        description: 'مدیریت سرویس‌های استعلامات زحل و تنظیمات API',
        icon: Icons.search_outlined,
        color: const Color(0xFF00ACC1),
        route: '/user/profile/system-settings/zohal-services',
      ),
      SettingsItem(
        title: 'تنظیمات زحل',
        description: 'تنظیم API Key و پیکربندی سرویس زحل',
        icon: Icons.settings_outlined,
        color: const Color(0xFF00897B),
        route: '/user/profile/system-settings/zohal-settings',
      ),
      SettingsItem(
        title: 'Prompt های AI',
        description: 'مدیریت Prompt های پیش‌فرض برای نقش‌های مختلف',
        icon: Icons.text_fields_outlined,
        color: const Color(0xFF5E35B1),
        route: '/user/profile/system-settings/ai-prompts',
      ),
      SettingsItem(
        title: 'کدهای مالیاتی کالا',
        description: 'جستجو و ایمپورت لیست جدید از فایل XML',
        icon: Icons.qr_code_2_outlined,
        color: const Color(0xFF00695C),
        route: '/user/profile/system-settings/tax-product-codes',
      ),
      SettingsItem(
        title: 'تنظیمات Redis Cache',
        description: 'پیکربندی Redis برای بهبود عملکرد و کاهش بار دیتابیس',
        icon: Icons.memory_outlined,
        color: const Color(0xFFDC143C),
        route: '/user/profile/system-settings/redis',
      ),
      SettingsItem(
        title: 'مانیتورینگ سیستم',
        description: 'بررسی وضعیت سیستم، منابع سخت‌افزاری و سرویس‌ها',
        icon: Icons.monitor_heart_outlined,
        color: const Color(0xFFFF6B35),
        route: '/user/profile/system-settings/monitoring',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeSection(theme, colorScheme, t),
            const SizedBox(height: 24),
            _buildSettingsList(theme, colorScheme, t),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(ThemeData theme, ColorScheme colorScheme, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.1),
            colorScheme.primaryContainer.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.systemAdministration,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.systemSettingsDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_settingsItems.length}',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsList(ThemeData theme, ColorScheme colorScheme, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              t.availableSettings,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_settingsItems.length} ${t.availableSettings.toLowerCase()}',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount = 3;
            if (constraints.maxWidth < 600) {
              crossAxisCount = 2;
            } else if (constraints.maxWidth > 1200) {
              crossAxisCount = 4;
            }
            
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: _settingsItems.length,
              itemBuilder: (context, index) {
                return _buildSettingsCard(_settingsItems[index], theme, colorScheme, t);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSettingsCard(SettingsItem item, ThemeData theme, ColorScheme colorScheme, AppLocalizations t) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.go(item.route!),
          borderRadius: BorderRadius.circular(12),
          hoverColor: item.color.withValues(alpha: 0.05),
          splashColor: item.color.withValues(alpha: 0.1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: item.color.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    item.icon,
                    color: item.color,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _getLocalizedText(t, item.title),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  _getLocalizedText(t, item.description),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: item.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getLocalizedText(AppLocalizations t, String key) {
    switch (key) {
      case 'storageManagement':
        return t.storageManagement;
      case 'storageManagementDescription':
        return t.storageManagementDescription;
      case 'systemConfiguration':
        return t.systemConfiguration;
      case 'systemConfigurationDescription':
        return t.systemConfigurationDescription;
      case 'userManagement':
        return t.userManagement;
      case 'userManagementDescription':
        return t.userManagementDescription;
      case 'systemLogs':
        return t.systemLogs;
      case 'systemLogsDescription':
        return t.systemLogsDescription;
      case 'emailSettings':
        return t.emailSettings;
      case 'emailSettingsDescription':
        return t.emailSettingsDescription;
      default:
        return key;
    }
  }

}

class SettingsItem {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String? route;

  SettingsItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.route,
  });
}