import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import '../../core/api_client.dart';
import '../../services/admin_system_settings_service.dart';

class SystemConfigurationPage extends StatefulWidget {
  const SystemConfigurationPage({super.key});

  @override
  State<SystemConfigurationPage> createState() => _SystemConfigurationPageState();
}

class _SystemConfigurationPageState extends State<SystemConfigurationPage> {
  final _formKey = GlobalKey<FormState>();
  final _service = AdminSystemSettingsService(ApiClient());
  bool _isLoading = false;
  bool _isLoadingData = true;
  String? _error;

  // Configuration values
  String _appName = '';
  String _appVersion = '';
  String _defaultLanguage = 'fa';
  String _defaultTheme = 'system';
  bool _enableRegistration = true;
  bool _enableEmailVerification = true;
  bool _enableMaintenanceMode = false;
  int _sessionTimeout = 30;
  int _maxFileSize = 10;
  int _maxUsers = 0;
  String _businessCreationRequirement = 'none';

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    setState(() {
      _isLoadingData = true;
      _error = null;
    });

    try {
      final data = await _service.getSystemConfiguration();
      if (mounted) {
        setState(() {
          _appName = data['app_name']?.toString() ?? 'Hesabix';
          _appVersion = data['app_version']?.toString() ?? '1.0.23';
          _defaultLanguage = data['default_language']?.toString() ?? 'fa';
          _defaultTheme = data['default_theme']?.toString() ?? 'system';
          _enableRegistration = data['enable_registration'] as bool? ?? true;
          _enableEmailVerification = data['enable_email_verification'] as bool? ?? true;
          _enableMaintenanceMode = data['enable_maintenance_mode'] as bool? ?? false;
          _sessionTimeout = data['session_timeout'] as int? ?? 30;
          _maxFileSize = data['max_file_size'] as int? ?? 10;
          _maxUsers = data['max_users'] as int? ?? 0;
          final reqValueRaw = data['business_creation_verification_requirement'];
          String? reqValue;
          if (reqValueRaw != null) {
            reqValue = reqValueRaw.toString().trim();
          }
          _businessCreationRequirement = (reqValue != null && reqValue.isNotEmpty && 
              const ['none', 'email_only', 'mobile_only', 'both', 'either'].contains(reqValue))
              ? reqValue
              : 'none';
        });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        setState(() {
          _error = '${t.errorLoadingSettings}: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t.errorLoadingSettings}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            t.systemConfiguration,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/user/profile/system-settings'),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null && _appName.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            t.systemConfiguration,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/user/profile/system-settings'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadConfiguration,
                child: Text(t.retry),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.systemConfiguration,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveConfiguration,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, size: 18),
              label: Text(
                _isLoading ? t.saving : t.save,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.1),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionCard(
                  theme,
                  t.generalSettings,
                  Icons.settings_outlined,
                  [
                    _buildTextField(
                      label: t.applicationName,
                      value: _appName,
                      onChanged: (value) => setState(() => _appName = value),
                    ),
                    _buildTextField(
                      label: t.applicationVersion,
                      value: _appVersion,
                      onChanged: (value) => setState(() => _appVersion = value),
                    ),
                    _buildDropdownField(
                      label: t.defaultLanguage,
                      value: _defaultLanguage,
                      items: [
                        DropdownMenuItem(value: 'fa', child: Text(t.persian)),
                        DropdownMenuItem(value: 'en', child: Text(t.english)),
                      ],
                      onChanged: (value) => setState(() => _defaultLanguage = value!),
                    ),
                    _buildDropdownField(
                      label: t.defaultTheme,
                      value: _defaultTheme,
                      items: [
                        DropdownMenuItem(value: 'system', child: Text(t.system)),
                        DropdownMenuItem(value: 'light', child: Text(t.light)),
                        DropdownMenuItem(value: 'dark', child: Text(t.dark)),
                      ],
                      onChanged: (value) => setState(() => _defaultTheme = value!),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  theme,
                  t.securitySettings,
                  Icons.security_outlined,
                  [
                    _buildSwitchField(
                      label: t.enableUserRegistration,
                      value: _enableRegistration,
                      onChanged: (value) => setState(() => _enableRegistration = value),
                    ),
                    _buildSwitchField(
                      label: t.enableEmailVerification,
                      value: _enableEmailVerification,
                      onChanged: (value) => setState(() => _enableEmailVerification = value),
                    ),
                    _buildNumberField(
                      label: t.sessionTimeoutMinutes,
                      value: _sessionTimeout,
                      onChanged: (value) => setState(() => _sessionTimeout = value),
                      min: 0,
                      max: 1440,
                      allowUnlimited: true,
                      unlimitedLabel: t.unlimited,
                    ),
                    _buildDropdownField(
                      label: 'محدودیت ایجاد کسب و کار',
                      value: _businessCreationRequirement,
                      items: [
                        const DropdownMenuItem(
                          value: 'none',
                          child: Text('بدون محدودیت (همه کاربران)'),
                        ),
                        const DropdownMenuItem(
                          value: 'email_only',
                          child: Text('فقط ایمیل تایید شده'),
                        ),
                        const DropdownMenuItem(
                          value: 'mobile_only',
                          child: Text('فقط شماره موبایل تایید شده'),
                        ),
                        const DropdownMenuItem(
                          value: 'both',
                          child: Text('هر دو (ایمیل و موبایل)'),
                        ),
                        const DropdownMenuItem(
                          value: 'either',
                          child: Text('هر کدام (ایمیل یا موبایل)'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _businessCreationRequirement = value!),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'این تنظیم تعیین می‌کند که چه کاربرانی می‌توانند کسب و کار جدید ایجاد کنند.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  theme,
                  t.maintenanceSettings,
                  Icons.build_outlined,
                  [
                    _buildSwitchField(
                      label: t.maintenanceMode,
                      value: _enableMaintenanceMode,
                      onChanged: (value) => setState(() => _enableMaintenanceMode = value),
                    ),
                    _buildNumberField(
                      label: t.maxFileSizeMB,
                      value: _maxFileSize,
                      onChanged: (value) => setState(() => _maxFileSize = value),
                      min: 1,
                      max: 1000,
                    ),
                    _buildNumberField(
                      label: t.maxUsers,
                      value: _maxUsers,
                      onChanged: (value) => setState(() => _maxUsers = value),
                      min: 0,
                      max: 10000,
                      allowUnlimited: true,
                      unlimitedLabel: t.unlimited,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // دکمه ذخیره بزرگ و واضح در پایین صفحه
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveConfiguration,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isLoading ? t.saving : t.save,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 24), // فاصله اضافی برای اطمینان از نمایش کامل
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(ThemeData theme, String title, IconData icon, List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('$label-$value'),
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSwitchField({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    required int min,
    required int max,
    bool allowUnlimited = false,
    String? unlimitedLabel,
  }) {
    final t = AppLocalizations.of(context);
    final effectiveMin = allowUnlimited && min == 0 ? 0 : min;
    final displayValue = value.toString();
    final finalUnlimitedLabel = unlimitedLabel ?? t.unlimited;
    final suffixText = value == 0 && allowUnlimited ? ' ($finalUnlimitedLabel)' : '';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('$label-$value'),
              initialValue: displayValue,
              decoration: InputDecoration(
                labelText: label,
                helperText: allowUnlimited ? t.zeroMeansUnlimited : null,
                suffixText: suffixText,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                EnglishDigitsFormatter(),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ],
              onChanged: (inputValue) {
                final intValue = int.tryParse(inputValue);
                if (intValue != null) {
                  if (intValue == 0 && allowUnlimited) {
                    onChanged(0);
                  } else if (intValue >= effectiveMin && intValue <= max) {
                    onChanged(intValue);
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 16),
          Column(
            children: [
              IconButton(
                onPressed: value < max ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add),
              ),
              IconButton(
                onPressed: value > effectiveMin ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveConfiguration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _service.updateSystemConfiguration({
        'app_name': _appName.trim(),
        'app_version': _appVersion.trim(),
        'default_language': _defaultLanguage,
        'default_theme': _defaultTheme,
        'enable_registration': _enableRegistration,
        'enable_email_verification': _enableEmailVerification,
        'enable_maintenance_mode': _enableMaintenanceMode,
        'session_timeout': _sessionTimeout,
        'max_file_size': _maxFileSize,
        'max_users': _maxUsers,
        'business_creation_verification_requirement': _businessCreationRequirement,
      });

      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settingsSavedSuccessfully),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t.errorSavingSettings}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
