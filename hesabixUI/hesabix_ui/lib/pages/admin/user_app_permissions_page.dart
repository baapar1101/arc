import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_users_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

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

  final Map<String, String> _permissionLabels = {
    'support_operator': 'اپراتور پشتیبانی',
    'system_settings': 'تنظیمات سیستم',
    'user_management': 'مدیریت کاربران',
    'business_management': 'مدیریت کسب‌وکارها',
  };

  final Map<String, String> _permissionDescriptions = {
    'support_operator': 'دسترسی به پنل پشتیبانی و مدیریت تیکت‌ها',
    'system_settings': 'دسترسی به تنظیمات سیستم',
    'user_management': 'مدیریت کاربران در سطح اپلیکیشن',
    'business_management': 'مدیریت کسب‌وکارها',
  };

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
      for (var key in _permissionLabels.keys) {
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
            backgroundColor: Colors.red,
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
            backgroundColor: Colors.green,
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
            backgroundColor: Colors.red,
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
      for (final k in _permissionLabels.keys) {
        _permissions[k] = enable;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت دسترسی‌ها'),
        actions: [
          if (!_isLoading)
            TextButton.icon(
              onPressed: _isSaving ? null : _savePermissions,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save, color: Colors.white),
              label: Text(
                _isSaving ? t.saving : t.save,
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
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
                      subtitle: const Text('مدیریت دسترسی‌های سطح اپلیکیشن'),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Permissions List
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          'دسترسی‌های سطح اپلیکیشن',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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
                  
                  ..._permissionLabels.entries.map((entry) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: SwitchListTile(
                        title: Text(entry.value),
                        subtitle: Text(_permissionDescriptions[entry.key] ?? ''),
                        value: _permissions[entry.key] ?? false,
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  _permissions[entry.key] = value;
                                });
                              },
                        secondary: Icon(
                          _getIconForPermission(entry.key),
                          color: Theme.of(context).primaryColor,
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



