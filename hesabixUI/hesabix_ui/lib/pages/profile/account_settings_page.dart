import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/calendar_controller.dart';
import '../../core/auth_store.dart';

class AccountSettingsPage extends StatelessWidget {
  final CalendarController calendarController;
  final AuthStore authStore;

  const AccountSettingsPage({
    super.key,
    required this.calendarController,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(context, theme, colorScheme, t),
            const SizedBox(height: 24),

            // Settings Sections Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 1200
                    ? 3
                    : constraints.maxWidth > 800
                        ? 2
                        : 1;
                final spacing = constraints.maxWidth > 800 ? 16.0 : 12.0;
                // افزایش aspect ratio برای کاهش ارتفاع
                final aspectRatio = constraints.maxWidth > 1200
                    ? 1.8  // دسکتاپ بزرگ: عرض بیشتر از ارتفاع
                    : constraints.maxWidth > 800
                        ? 1.6  // دسکتاپ کوچک
                        : 2.2;  // موبایل: عرض خیلی بیشتر از ارتفاع

                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: aspectRatio,
                  children: [
                    _SettingsCard(
                      title: t.marketing,
                      description: 'مدیریت لینک معرفی و گزارش‌های بازاریابی',
                      icon: Icons.campaign,
                      color: Colors.orange,
                      onTap: () => context.go('/user/profile/marketing'),
                    ),
                    _SettingsCard(
                      title: 'اعلان‌ها و نوتیفیکیشن',
                      description: 'تنظیمات کانال‌های اعلان‌رسانی و نوتیفیکیشن',
                      icon: Icons.notifications_active,
                      color: Colors.blue,
                      onTap: () => context.go('/user/profile/notifications'),
                    ),
                    _SettingsCard(
                      title: 'امضا و تصویر کاربر',
                      description: 'بارگذاری و مدیریت امضای شخصی و تصویر پروفایل',
                      icon: Icons.border_color,
                      color: Colors.purple,
                      onTap: () => context.go('/user/profile/signature'),
                    ),
                    _SettingsCard(
                      title: 'کلیدهای API',
                      description: 'مدیریت کلیدهای API برای دسترسی به سیستم',
                      icon: Icons.key,
                      color: Colors.green,
                      onTap: () => context.go('/user/profile/api-keys'),
                    ),
                    _SettingsCard(
                      title: 'سشن‌های ورود',
                      description: 'مشاهده و مدیریت دستگاه‌های متصل به حساب کاربری',
                      icon: Icons.devices,
                      color: Colors.indigo,
                      onTap: () => context.go('/user/profile/sessions'),
                    ),
                    _SettingsCard(
                      title: t.changePassword,
                      description: 'تغییر کلمه عبور حساب کاربری',
                      icon: Icons.password,
                      color: Colors.red,
                      onTap: () => context.go('/user/profile/change-password'),
                    ),
                    _SettingsCard(
                      title: 'تایید شماره موبایل',
                      description: 'تایید شماره موبایل برای امنیت بیشتر',
                      icon: Icons.phone_android,
                      color: Colors.teal,
                      onTap: () => context.go('/user/profile/mobile-verification'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.settings,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تنظیمات حساب کاربری',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'مدیریت و تنظیم تمام بخش‌های حساب کاربری شما',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(isDesktop ? 16 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'مشاهده',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 12,
                          color: color,
                        ),
                      ],
                    ),
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

