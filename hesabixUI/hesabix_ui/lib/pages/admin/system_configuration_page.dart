import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class SystemConfigurationPage extends StatefulWidget {
  const SystemConfigurationPage({super.key});

  @override
  State<SystemConfigurationPage> createState() => _SystemConfigurationPageState();
}

class _SystemConfigurationPageState extends State<SystemConfigurationPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Configuration values
  String _appName = 'Hesabix';
  String _appVersion = '1.0.0';
  String _defaultLanguage = 'fa';
  String _defaultTheme = 'system';
  bool _enableRegistration = true;
  bool _enableEmailVerification = true;
  bool _enableMaintenanceMode = false;
  int _sessionTimeout = 30;
  int _maxFileSize = 10;
  int _maxUsers = 1000;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

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
          TextButton(
            onPressed: _isLoading ? null : _saveConfiguration,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t.save),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withOpacity(0.1),
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
                      label: 'Application Name',
                      value: _appName,
                      onChanged: (value) => setState(() => _appName = value),
                    ),
                    _buildTextField(
                      label: 'Application Version',
                      value: _appVersion,
                      onChanged: (value) => setState(() => _appVersion = value),
                    ),
                    _buildDropdownField(
                      label: 'Default Language',
                      value: _defaultLanguage,
                      items: const [
                        DropdownMenuItem(value: 'fa', child: Text('فارسی')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (value) => setState(() => _defaultLanguage = value!),
                    ),
                    _buildDropdownField(
                      label: 'Default Theme',
                      value: _defaultTheme,
                      items: const [
                        DropdownMenuItem(value: 'system', child: Text('System')),
                        DropdownMenuItem(value: 'light', child: Text('Light')),
                        DropdownMenuItem(value: 'dark', child: Text('Dark')),
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
                      label: 'Enable User Registration',
                      value: _enableRegistration,
                      onChanged: (value) => setState(() => _enableRegistration = value),
                    ),
                    _buildSwitchField(
                      label: 'Enable Email Verification',
                      value: _enableEmailVerification,
                      onChanged: (value) => setState(() => _enableEmailVerification = value),
                    ),
                    _buildNumberField(
                      label: 'Session Timeout (minutes)',
                      value: _sessionTimeout,
                      onChanged: (value) => setState(() => _sessionTimeout = value),
                      min: 5,
                      max: 1440,
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
                      label: 'Maintenance Mode',
                      value: _enableMaintenanceMode,
                      onChanged: (value) => setState(() => _enableMaintenanceMode = value),
                    ),
                    _buildNumberField(
                      label: 'Max File Size (MB)',
                      value: _maxFileSize,
                      onChanged: (value) => setState(() => _maxFileSize = value),
                      min: 1,
                      max: 1000,
                    ),
                    _buildNumberField(
                      label: 'Max Users',
                      value: _maxUsers,
                      onChanged: (value) => setState(() => _maxUsers = value),
                      min: 1,
                      max: 10000,
                    ),
                  ],
                ),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: value.toString(),
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final intValue = int.tryParse(value);
                if (intValue != null && intValue >= min && intValue <= max) {
                  onChanged(intValue);
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
                onPressed: value > min ? () => onChanged(value - 1) : null,
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
      // Simulate API call
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).save),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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
