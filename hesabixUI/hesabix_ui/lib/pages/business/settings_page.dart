import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../theme/theme_controller.dart';
import '../../core/auth_store.dart';
import '../../services/business_user_service.dart';
import '../../models/business_user_model.dart';
import '../../core/api_client.dart';
import '../../utils/snackbar_helper.dart';
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
  final BusinessUserService _userService = BusinessUserService(ApiClient());
  bool _isLeaving = false;
  
  AuthStore? get _authStore => ApiClient.getAuthStore();
  
  @override
  void initState() {
    super.initState();
    // اضافه کردن listener برای rebuild صفحه وقتی currentBusiness تغییر کرد
    final authStore = _authStore;
    if (authStore != null) {
      authStore.addListener(_onAuthStoreChanged);
    }
  }
  
  @override
  void dispose() {
    final authStore = _authStore;
    if (authStore != null) {
      authStore.removeListener(_onAuthStoreChanged);
    }
    super.dispose();
  }
  
  void _onAuthStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final authStore = _authStore;
    // بررسی دقیق‌تر: آیا کاربر مالک این کسب و کار است؟
    // باید مطمئن شویم که currentBusiness برای همین businessId است و کاربر مالک است
    final currentBusiness = authStore?.currentBusiness;
    final isOwner = currentBusiness != null && 
                   currentBusiness.id == widget.businessId &&
                   (currentBusiness.isOwner == true);
    
    // اگر currentBusiness null است یا برای کسب و کار دیگری است، 
    // نمی‌توانیم مطمئن شویم که کاربر مالک است یا نه
    // در این حالت، دکمه خروج را نمایش نمی‌دهیم (برای امنیت)
    final canShowLeaveButton = currentBusiness != null && 
                              currentBusiness.id == widget.businessId &&
                              !isOwner;

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
                  title: 'ویرایش سال مالی جاری',
                  subtitle: 'ویرایش عنوان و تاریخ‌های سال مالی جاری',
                  icon: Icons.calendar_today,
                  onTap: () => context.go('/business/${widget.businessId}/settings/fiscal-year'),
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
                  title: 'تنظیمات فروش سریع',
                  subtitle: 'تنظیمات پیش‌فرض برای فروش سریع',
                  icon: Icons.point_of_sale_outlined,
                  onTap: () => context.go('/business/${widget.businessId}/settings/quick-sales'),
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
                  title: 'شماره‌گذاری اسناد',
                  subtitle: 'تنظیم نحوه شماره‌گذاری انواع اسناد',
                  icon: Icons.numbers,
                  onTap: () => context.go('/business/${widget.businessId}/settings/document-numbering'),
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
                _buildSettingItem(
                  context,
                  title: t.taxIntegrationTitle,
                  subtitle: t.taxIntegrationSubtitle,
                  icon: Icons.cloud_sync_outlined,
                  onTap: () => context.go('/business/${widget.businessId}/settings/tax'),
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
                  onTap: () => context.go('/business/${widget.businessId}/reports/activity-logs'),
                ),
              ],
            ),
            
            // بخش خروج از کسب و کار (فقط برای اعضای غیر از مالک)
            if (canShowLeaveButton) ...[
              const SizedBox(height: 24),
              _buildSection(
                context,
                title: 'عضویت در کسب و کار',
                icon: Icons.business_outlined,
                children: [
                  _buildSettingItem(
                    context,
                    title: 'خروج از کسب و کار',
                    subtitle: 'خروج از این کسب و کار و حذف دسترسی‌های شما',
                    icon: Icons.exit_to_app,
                    trailing: _isLeaving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                            ),
                          )
                        : Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
                    onTap: _isLeaving ? null : () => _handleLeave(context),
                  ),
                ],
              ),
            ],
            
            // بخش عملیات خطرناک (فقط برای مالک)
            if (isOwner) ...[
              const SizedBox(height: 24),
              _buildSection(
                context,
                title: 'عملیات خطرناک',
                icon: Icons.warning_amber_rounded,
                children: [
                  _buildSettingItem(
                    context,
                    title: 'حذف کسب و کار',
                    subtitle: 'حذف دائمی کسب و کار (30 روز قابل بازیابی)',
                    icon: Icons.delete_forever,
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
                    onTap: () => context.go('/business/${widget.businessId}/settings/delete'),
                  ),
                ],
              ),
            ],
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

  Future<void> _handleLeave(BuildContext context) async {
    final t = AppLocalizations.of(context);
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خروج از کسب و کار'),
        content: const Text(
          'آیا مطمئن هستید که می‌خواهید از این کسب و کار خارج شوید؟\n\n'
          'پس از خروج، دسترسی شما به این کسب و کار حذف خواهد شد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('خروج'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLeaving = true;
    });

    try {
      final request = LeaveBusinessRequest(businessId: widget.businessId);
      final response = await _userService.leaveBusiness(request);

      if (response.success && mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: response.message,
        );
        
        // Clear current business if it's the one we're leaving
        final authStore = _authStore;
        if (authStore != null && authStore.currentBusiness?.id == widget.businessId) {
          await authStore.clearCurrentBusiness();
        }
        
        // Navigate to businesses list
        if (mounted) {
          context.go('/user/profile/businesses');
        }
      } else if (mounted) {
        SnackBarHelper.showError(
          context,
          message: response.message,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در خروج از کسب و کار: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
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

}
