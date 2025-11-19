import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/calendar_switcher.dart';
import '../../widgets/language_switcher.dart';
import '../../widgets/theme_mode_switcher.dart';

class SettingsPage extends StatefulWidget {
  final int businessId;
  final LocaleController? localeController;
  final CalendarController? calendarController;
  final ThemeController? themeController;

  const SettingsPage({
    super.key,
    required this.businessId,
    this.localeController,
    this.calendarController,
    this.themeController,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بخش تنظیمات عمومی
            _buildSection(
              context,
              title: t.generalSettings,
              icon: Icons.settings,
              children: [
                _buildSettingItem(
                  context,
                  title: t.businessSettings,
                  subtitle: t.businessSettingsDescription,
                  icon: Icons.business,
                  onTap: () => context.go('/business/${widget.businessId}/settings/business'),
                ),
                _buildSettingItem(
                  context,
                  title: t.creditSettingsTitle,
                  subtitle: t.creditSettingsSubtitle,
                  icon: Icons.credit_score_outlined,
                  onTap: () => context.go('/business/${widget.businessId}/settings/credit'),
                ),
                _buildSettingItem(
                  context,
                  title: t.installmentsTitle,
                  subtitle: t.installmentsSettingsSubtitle,
                  icon: Icons.dashboard_customize_outlined,
                  onTap: () => context.go('/business/${widget.businessId}/settings/installments'),
                ),
                _buildSettingItem(
                  context,
                  title: t.usersAndPermissions,
                  subtitle: t.usersAndPermissionsDescription,
                  icon: Icons.people_outline,
                  onTap: () => context.go('/business/${widget.businessId}/users-permissions'),
                ),
                _buildSettingItem(
                  context,
                  title: t.printDocuments,
                  subtitle: t.printDocumentsDescription,
                  icon: Icons.print,
                  onTap: () => context.go('/business/${widget.businessId}/settings/print'),
                ),
                // Report Builder - Templates access
                _buildSettingItem(
                  context,
                  title: t.templates,
                  subtitle: t.printDocumentsDescription,
                  icon: Icons.picture_as_pdf,
                  onTap: () => context.go('/business/${widget.businessId}/report-templates'),
                ),
                _buildSettingItem(
                  context,
                  title: t.documentMonetizationTitle,
                  subtitle: t.documentMonetizationSubtitle,
                  icon: Icons.receipt_long_outlined,
                  onTap: () => context.go('/business/${widget.businessId}/document-monetization'),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // بخش تنظیمات ظاهری
            _buildSection(
              context,
              title: t.appearanceSettings,
              icon: Icons.palette,
              children: [
                _buildSettingItem(
                  context,
                  title: t.language,
                  subtitle: t.languageDescription,
                  icon: Icons.language,
                  trailing: widget.localeController != null
                      ? LanguageSwitcher(controller: widget.localeController!)
                      : null,
                ),
                _buildSettingItem(
                  context,
                  title: t.theme,
                  subtitle: t.themeDescription,
                  icon: Icons.brightness_6,
                  trailing: widget.themeController != null
                      ? ThemeModeSwitcher(controller: widget.themeController!)
                      : null,
                ),
                _buildSettingItem(
                  context,
                  title: t.calendar,
                  subtitle: t.calendarDescription,
                  icon: Icons.calendar_today,
                  trailing: widget.calendarController != null
                      ? CalendarSwitcher(controller: widget.calendarController!)
                      : null,
                ),
              ],
            ),
            
            
            const SizedBox(height: 24),
            
            // بخش تنظیمات پیشرفته
            _buildSection(
              context,
              title: t.advancedSettings,
              icon: Icons.engineering,
              children: [
                _buildSettingItem(
                  context,
                  title: t.dataBackup,
                  subtitle: t.dataBackupDescription,
                  icon: Icons.backup,
                  onTap: () => context.go('/business/${widget.businessId}/settings/backup'),
                ),
                _buildSettingItem(
                  context,
                  title: t.dataRestore,
                  subtitle: t.dataRestoreDescription,
                  icon: Icons.restore,
                  onTap: () => context.go('/business/${widget.businessId}/settings/restore'),
                ),
                _buildSettingItem(
                  context,
                  title: t.systemLogs,
                  subtitle: t.systemLogsDescription,
                  icon: Icons.assignment,
                  onTap: () => _showSystemLogsDialog(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: cs.primary, size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildSettingItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  // دیالوگ‌های تنظیمات
  // ignore: unused_element
  void _showDataBackupDialog(BuildContext context) {
    final t = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.dataBackup),
        content: Text(t.dataBackupDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to business dashboard for now (until backup functionality is implemented)
              context.go('/business/${widget.businessId}/dashboard');
            },
            child: Text(t.backup),
          ),
        ],
      ),
    );
  }
  // ignore: unused_element
  void _showDataRestoreDialog(BuildContext context) {
    final t = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.dataRestore),
        content: Text(t.dataRestoreDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to business dashboard for now (until restore functionality is implemented)
              context.go('/business/${widget.businessId}/dashboard');
            },
            child: Text(t.restore),
          ),
        ],
      ),
    );
  }

  void _showSystemLogsDialog(BuildContext context) {
    final t = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.systemLogs),
        content: Text(t.systemLogsDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to business dashboard for now (until system logs page is created)
              context.go('/business/${widget.businessId}/dashboard');
            },
            child: Text(t.view),
          ),
        ],
      ),
    );
  }
}
