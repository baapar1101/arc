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
                final spacing = constraints.maxWidth > 800 ? 12.0 : 10.0;
                // افزایش aspect ratio برای کاهش ارتفاع و کوچکتر کردن کارت‌ها
                final aspectRatio = constraints.maxWidth > 1200
                    ? 2.4  // دسکتاپ بزرگ: کارت‌های کوچکتر و پهن‌تر
                    : constraints.maxWidth > 800
                        ? 2.1  // تبلت: کارت‌های کوچکتر
                        : 2.5;  // موبایل: کارت‌های کوچکتر و پهن‌تر

                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: aspectRatio,
                  children: [
                    _SettingsCard(
                      title: t.accountSettingsAppearanceTitle,
                      description: t.accountSettingsAppearanceDescription,
                      icon: Icons.palette_outlined,
                      color: Colors.deepPurple,
                      onTap: () => context.go('/user/profile/appearance-settings'),
                    ),
                    _SettingsCard(
                      title: t.marketing,
                      description: t.accountSettingsMarketingDescription,
                      icon: Icons.campaign,
                      color: Colors.orange,
                      onTap: () => context.go('/user/profile/marketing'),
                    ),
                    _SettingsCard(
                      title: t.accountSettingsNotificationsTitle,
                      description: t.accountSettingsNotificationsDescription,
                      icon: Icons.notifications_active,
                      color: Colors.blue,
                      onTap: () => context.go('/user/profile/notifications'),
                    ),
                    _SettingsCard(
                      title: t.accountSettingsSignatureTitle,
                      description: t.accountSettingsSignatureDescription,
                      icon: Icons.border_color,
                      color: Colors.purple,
                      onTap: () => context.go('/user/profile/signature'),
                    ),
                    _SettingsCard(
                      title: t.accountSettingsApiKeysTitle,
                      description: t.accountSettingsApiKeysDescription,
                      icon: Icons.key,
                      color: Colors.green,
                      onTap: () => context.go('/user/profile/api-keys'),
                    ),
                    _SettingsCard(
                      title: t.accountSettingsLoginSessionsTitle,
                      description: t.accountSettingsLoginSessionsDescription,
                      icon: Icons.devices,
                      color: Colors.indigo,
                      onTap: () => context.go('/user/profile/sessions'),
                    ),
                    _SettingsCard(
                      title: t.changePassword,
                      description: t.accountSettingsChangePasswordDescription,
                      icon: Icons.password,
                      color: Colors.red,
                      onTap: () => context.go('/user/profile/change-password'),
                    ),
                    _SettingsCard(
                      title: t.accountSettingsVerificationTitle,
                      description: t.accountSettingsVerificationDescription,
                      icon: Icons.verified_user,
                      color: Colors.teal,
                      onTap: () => context.go('/user/profile/verification'),
                    ),
                    _SettingsCard(
                      title: t.accountSettingsNotificationHistoryTitle,
                      description: t.accountSettingsNotificationHistoryDescription,
                      icon: Icons.history,
                      color: Colors.indigo,
                      onTap: () => context.go('/user/profile/notification-history'),
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
    final bool isDark = theme.brightness == Brightness.dark;
    final Color onHeader = isDark ? colorScheme.onSurface : Colors.white;
    final Color subtitleOnHeader =
        isDark ? colorScheme.onSurfaceVariant : Colors.white.withValues(alpha: 0.9);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHighest : null,
        gradient: isDark
            ? null
            : LinearGradient(
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
            color: isDark
                ? colorScheme.shadow.withValues(alpha: 0.12)
                : colorScheme.primary.withValues(alpha: 0.3),
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
              color: isDark
                  ? colorScheme.onSurface.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.settings,
              color: onHeader,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.accountSettingsTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: onHeader,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.accountSettingsSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: subtitleOnHeader,
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
    final t = AppLocalizations.of(context);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 800;
    final isMobile = width <= 600;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(isDesktop ? 12 : isMobile ? 10 : 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
                    padding: EdgeInsets.all(isDesktop ? 8 : 7),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: isDesktop ? 20 : 18,
                    ),
                  ),
                  SizedBox(height: isDesktop ? 10 : 8),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      fontSize: isDesktop ? 15 : 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
                      fontSize: isDesktop ? 11 : 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 8 : 7,
                      vertical: isDesktop ? 4 : 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.view,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: isDesktop ? 10 : 9,
                          ),
                        ),
                        SizedBox(width: 3),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: isDesktop ? 11 : 10,
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

