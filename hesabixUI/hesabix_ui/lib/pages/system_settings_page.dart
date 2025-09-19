import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class SystemSettingsPage extends StatelessWidget {
  const SystemSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.systemSettings),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: Container(
        color: colorScheme.surface,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        size: 32,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.systemSettings,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'تنظیمات پیشرفته سیستم - فقط برای ادمین‌ها',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Settings Cards
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.5,
                    children: [
                      _buildSettingCard(
                        context,
                        icon: Icons.people,
                        title: 'مدیریت کاربران',
                        subtitle: 'مدیریت کاربران سیستم',
                        color: Colors.blue,
                      ),
                      _buildSettingCard(
                        context,
                        icon: Icons.business,
                        title: 'مدیریت کسب و کارها',
                        subtitle: 'مدیریت کسب و کارهای ثبت شده',
                        color: Colors.green,
                      ),
                      _buildSettingCard(
                        context,
                        icon: Icons.security,
                        title: 'امنیت سیستم',
                        subtitle: 'تنظیمات امنیتی و دسترسی‌ها',
                        color: Colors.orange,
                      ),
                      _buildSettingCard(
                        context,
                        icon: Icons.analytics,
                        title: 'گزارش‌گیری',
                        subtitle: 'گزارش‌های سیستم و آمار',
                        color: Colors.purple,
                      ),
                      _buildSettingCard(
                        context,
                        icon: Icons.backup,
                        title: 'پشتیبان‌گیری',
                        subtitle: 'مدیریت پشتیبان‌ها',
                        color: Colors.teal,
                      ),
                      _buildSettingCard(
                        context,
                        icon: Icons.tune,
                        title: 'تنظیمات پیشرفته',
                        subtitle: 'تنظیمات تخصصی سیستم',
                        color: Colors.indigo,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Warning Message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: Colors.amber[700],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'توجه: این بخش فقط برای ادمین‌های سیستم قابل دسترسی است. تغییرات در این بخش می‌تواند بر عملکرد کل سیستم تأثیر بگذارد.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.amber[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // TODO: Navigate to specific setting
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title - در حال توسعه'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: color,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
