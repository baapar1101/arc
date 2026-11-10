import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_users_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class UserAppPermissionsPage extends StatefulWidget {
  final int userId;
  final String userEmail;

  const UserAppPermissionsPage({
    super.key,
    required this.userId,
    required this.userEmail,
  });

  @override
  State<UserAppPermissionsPage> createState() => _UserAppPermissionsPageState();
}

class _UserAppPermissionsPageState extends State<UserAppPermissionsPage> {
  final _service = AdminUsersService(ApiClient());
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, bool> _permissions = {};

  static const _permissionKeys = [
    'support_operator',
    'system_settings',
    'user_management',
    'business_management',
  ];

  String _permissionLabel(String key) {
    return switch (key) {
      'support_operator' => adminTx(context, 'اپراتور پشتیبانی', 'Support operator'),
      'system_settings' => adminTx(context, 'تنظیمات سیستم', 'System settings'),
      'user_management' => adminTx(context, 'مدیریت کاربران', 'User management'),
      'business_management' => adminTx(context, 'مدیریت کسب‌وکارها', 'Business management'),
      _ => key,
    };
  }

  String _permissionDescription(String key) {
    return switch (key) {
      'support_operator' => adminTx(context, 'پنل پشتیبانی و تیکت‌ها', 'Support desk and tickets'),
      'system_settings' => adminTx(context, 'تنظیمات سراسری سیستم', 'Application-wide settings'),
      'user_management' => adminTx(context, 'کاربران در سطح اپلیکیشن', 'Application users'),
      'business_management' => adminTx(context, 'کسب‌وکارهای سیستم', 'System businesses'),
      _ => '',
    };
  }

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);
    
    try {
      final data = await _service.getUserAppPermissions(widget.userId);
      final appPerms = data['app_permissions'] as Map? ?? {};
      
      // Initialize all permissions
      final permissions = <String, bool>{};
      for (var key in _permissionKeys) {
        permissions[key] = appPerms[key] == true;
      }
      
      setState(() {
        _permissions = permissions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${t.errorLoadingSettings}: ${ErrorExtractor.forContext(e, context)}',
            ),
            backgroundColor: SemanticColorResolver.negative(context),
          ),
        );
      }
    }
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);
    
    try {
      await _service.updateUserAppPermissions(widget.userId, _permissions);
      
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settingsSavedSuccessfully),
            backgroundColor: SemanticColorResolver.positive(context),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${t.errorSavingSettings}: ${ErrorExtractor.forContext(e, context)}',
            ),
            backgroundColor: SemanticColorResolver.negative(context),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _confirmAndSetAllAppPermissions(bool enable) async {
    final t = AppLocalizations.of(context);
    if (!enable) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.permissionsConfirmDisableAllTitle),
          content: Text(t.appLevelPermissionsConfirmDisableBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.confirm),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      for (final k in _permissionKeys) {
        _permissions[k] = enable;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    return AdminCompactScaffold(
      title: adminTx(context, 'دسترسی‌های برنامه', 'App permissions'),
      subtitle: widget.userEmail,
      actions: [
        if (!_isLoading)
          IconButton(
            tooltip: _isSaving ? t.saving : t.save,
            onPressed: _isSaving ? null : _savePermissions,
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 20),
          ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: context.settingsHub.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Info Card
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(widget.userEmail[0].toUpperCase()),
                      ),
                      title: Text(widget.userEmail),
                      subtitle: Text(adminTx(context, 'دسترسی‌های سطح اپلیکیشن', 'Application permissions'), style: context.settingsHub.cardSubtitleStyle(Theme.of(context).textTheme, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Permissions List
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          adminTx(context, 'دسترسی‌ها', 'Permissions'),
                          style: context.settingsHub.cardTitleStyle(Theme.of(context).textTheme, color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ),
                      TextButton(
                        onPressed: _isSaving ? null : () => _confirmAndSetAllAppPermissions(true),
                        child: Text(t.permissionsEnableAll),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _isSaving ? null : () => _confirmAndSetAllAppPermissions(false),
                        child: Text(t.permissionsDisableAll),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  ..._permissionKeys.map((key) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      child: SwitchListTile(
                        title: Text(_permissionLabel(key), style: const TextStyle(fontSize: 13)),
                        subtitle: Text(_permissionDescription(key), style: const TextStyle(fontSize: 11)),
                        value: _permissions[key] ?? false,
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  _permissions[key] = value;
                                });
                              },
                        secondary: Icon(
                          _getIconForPermission(key),
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  IconData _getIconForPermission(String permission) {
    switch (permission) {
      case 'support_operator':
        return Icons.support_agent;
      case 'system_settings':
        return Icons.settings;
      case 'user_management':
        return Icons.people;
      case 'business_management':
        return Icons.business;
      default:
        return Icons.check_circle;
    }
  }
}



