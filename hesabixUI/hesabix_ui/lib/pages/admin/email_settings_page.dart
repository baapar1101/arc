import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/email_models.dart';
import 'package:hesabix_ui/services/email_service.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';

class EmailSettingsPage extends StatefulWidget {
  const EmailSettingsPage({super.key});

  @override
  State<EmailSettingsPage> createState() => _EmailSettingsPageState();
}

class _EmailSettingsPageState extends State<EmailSettingsPage> {
  final EmailService _emailService = EmailService();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isTesting = false;
  List<EmailConfig> _configs = [];
  EmailConfig? _selectedConfig;

  // Form controllers
  final _nameController = TextEditingController();
  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpUsernameController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _fromEmailController = TextEditingController();
  final _fromNameController = TextEditingController();
  bool _useTls = true;
  bool _useSsl = false;
  bool _isActive = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _initializeApiClient();
    _loadConfigs();
  }

  void _initializeApiClient() {
    // Initialize ApiClient - it will get AuthStore from global state
    // AuthStore should be bound in main.dart or app initialization
  }

  @override
  void dispose() {
    _nameController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpUsernameController.dispose();
    _smtpPasswordController.dispose();
    _fromEmailController.dispose();
    _fromNameController.dispose();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    setState(() => _isLoading = true);
    try {
      final response = await _emailService.getEmailConfigs();
      setState(() {
        _configs = response.data;
        // Select the default config, or first one if no default
        _selectedConfig = _configs.where((config) => config.isDefault).isNotEmpty 
            ? _configs.where((config) => config.isDefault).first
            : (_configs.isNotEmpty ? _configs.first : null);
      });
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final t = AppLocalizations.of(context);
      
      if (_isEditing && _selectedConfig != null) {
        // Update existing config
        final request = UpdateEmailConfigRequest(
          name: _nameController.text,
          smtpHost: _smtpHostController.text,
          smtpPort: int.parse(_smtpPortController.text),
          smtpUsername: _smtpUsernameController.text,
          smtpPassword: _smtpPasswordController.text,
          useTls: _useTls,
          useSsl: _useSsl,
          fromEmail: _fromEmailController.text,
          fromName: _fromNameController.text,
          isActive: _isActive,
        );

        await _emailService.updateEmailConfig(_selectedConfig!.id, request);
        _showSuccessSnackBar(t.emailConfigUpdatedSuccessfully);
      } else {
        // Create new config
        final request = CreateEmailConfigRequest(
          name: _nameController.text,
          smtpHost: _smtpHostController.text,
          smtpPort: int.parse(_smtpPortController.text),
          smtpUsername: _smtpUsernameController.text,
          smtpPassword: _smtpPasswordController.text,
          useTls: _useTls,
          useSsl: _useSsl,
          fromEmail: _fromEmailController.text,
          fromName: _fromNameController.text,
          isActive: _isActive,
        );

        await _emailService.createEmailConfig(request);
        _showSuccessSnackBar(t.emailConfigSavedSuccessfully);
      }
      
      if (!mounted) return;
      _loadConfigs();
      _clearForm();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testConnection() async {
    if (_selectedConfig == null) return;
    final config = _selectedConfig!;

    setState(() => _isTesting = true);
    try {
      final response = await _emailService.testEmailConfig(config.id);
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      if (response.connected) {
        _showSuccessSnackBar(t.connectionSuccessful);
      } else {
        // نمایش Dialog با جزئیات خطا
        _showConnectionErrorDialog(
          response.errorMessage ?? t.connectionFailed,
        );
      }
    } catch (e) {
      if (!mounted) return;
      // نمایش Dialog با جزئیات خطا
      _showConnectionErrorDialog(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _showConnectionErrorDialog(String errorMessage) async {
    if (!mounted) return;
    final t = AppLocalizations.of(context);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                t.connectionFailed,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'جزئیات خطا:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.3),
                  ),
                ),
                child: SelectableText(
                  errorMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'راهکارهای پیشنهادی:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              _buildSuggestionItem('بررسی صحت آدرس میزبان SMTP'),
              _buildSuggestionItem('بررسی صحت شماره پورت'),
              _buildSuggestionItem('بررسی صحت نام کاربری و رمز عبور'),
              _buildSuggestionItem('بررسی تنظیمات TLS/SSL'),
              _buildSuggestionItem('بررسی فایروال و تنظیمات شبکه'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('بستن'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Clipboard.setData(ClipboardData(text: errorMessage));
              _showSuccessSnackBar('جزئیات خطا در کلیپ‌بورد کپی شد');
            },
            child: const Text('کپی خطا'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setAsDefault(EmailConfig config) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.setDefaultConfirm),
        content: Text(t.setDefaultConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _emailService.setDefaultEmailConfig(config.id);
      _showSuccessSnackBar(t.defaultSetSuccessfully);
      // Force refresh the configs and update selected config
      await _loadConfigs();
      // Update selected config to the one that was just set as default
      _selectedConfig = _configs.firstWhere((c) => c.id == config.id);
    } catch (e) {
      _showErrorSnackBar(t.defaultSetFailed);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendTestEmail() async {
    if (_selectedConfig == null) return;

    try {
      final t = AppLocalizations.of(context);
      await _emailService.sendCustomEmail(
        to: _fromEmailController.text,
        subject: t.testEmailSubject,
        body: t.testEmailBody,
        configId: _selectedConfig!.id,
      );
      _showSuccessSnackBar(t.testEmailSentSuccessfully);
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  void _clearForm() {
    _nameController.clear();
    _smtpHostController.clear();
    _smtpPortController.clear();
    _smtpUsernameController.clear();
    _smtpPasswordController.clear();
    _fromEmailController.clear();
    _fromNameController.clear();
    _useTls = true;
    _useSsl = false;
    _isActive = true;
    _isEditing = false;
    _selectedConfig = null;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(t.emailSettings),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConfigList(theme, colorScheme, t),
                  const SizedBox(height: 24),
                  _buildConfigForm(theme, colorScheme, t),
                ],
              ),
            ),
    );
  }

  Widget _buildConfigList(ThemeData theme, ColorScheme colorScheme, AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.emailConfigurations,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_configs.isEmpty)
              Text(
                t.noEmailConfigurations,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              )
            else
              ..._configs.map((config) => _buildConfigItem(config, theme, colorScheme, t)),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigItem(EmailConfig config, ThemeData theme, ColorScheme colorScheme, AppLocalizations t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          config.isActive ? Icons.email : Icons.email_outlined,
          color: config.isActive ? Colors.green : colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        title: Row(
          children: [
            Text(config.name),
            if (config.isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t.currentDefault,
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text('${config.smtpHost}:${config.smtpPort}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (config.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  t.active,
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editConfig(config),
              tooltip: t.edit,
            ),
            if (!config.isDefault)
              IconButton(
                icon: const Icon(Icons.star_outline),
                onPressed: () => _setAsDefault(config),
                tooltip: t.makeDefault,
              ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: config.isDefault ? null : () => _deleteConfig(config.id),
              tooltip: config.isDefault ? t.cannotDeleteDefault : t.delete,
            ),
          ],
        ),
        onTap: () => _selectConfig(config),
      ),
    );
  }

  Widget _buildConfigForm(ThemeData theme, ColorScheme colorScheme, AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? t.editEmailConfiguration : t.addEmailConfiguration,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: t.configurationName,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return t.requiredField;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _smtpHostController,
                      decoration: InputDecoration(
                        labelText: t.smtpHost,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return t.requiredField;
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _smtpPortController,
                      decoration: InputDecoration(
                        labelText: t.smtpPort,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        EnglishDigitsFormatter(),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return t.requiredField;
                        }
                        if (int.tryParse(value) == null) {
                          return t.invalidPort;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _smtpUsernameController,
                      decoration: InputDecoration(
                        labelText: t.smtpUsername,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return t.requiredField;
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _smtpPasswordController,
                decoration: InputDecoration(
                  labelText: t.smtpPassword,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return t.requiredField;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fromEmailController,
                      decoration: InputDecoration(
                        labelText: t.fromEmail,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return t.requiredField;
                        }
                        if (!value.contains('@')) {
                          return t.invalidEmail;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _fromNameController,
                      decoration: InputDecoration(
                        labelText: t.fromName,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return t.requiredField;
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _useTls,
                    onChanged: (value) => setState(() => _useTls = value ?? false),
                  ),
                  Text(t.useTls),
                  const SizedBox(width: 24),
                  Checkbox(
                    value: _useSsl,
                    onChanged: (value) => setState(() => _useSsl = value ?? false),
                  ),
                  Text(t.useSsl),
                  const SizedBox(width: 24),
                  Checkbox(
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value ?? false),
                  ),
                  Text(t.isActive),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveConfig,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isEditing ? t.updateConfiguration : t.saveConfiguration),
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_selectedConfig != null) ...[
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isTesting ? null : _testConnection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                        child: _isTesting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(t.testConnection),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _sendTestEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: Text(t.sendTestEmail),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectConfig(EmailConfig config) async {
    setState(() => _selectedConfig = config);
  }

  Future<void> _editConfig(EmailConfig config) async {
    setState(() {
      _selectedConfig = config;
      _isEditing = true;
      _nameController.text = config.name;
      _smtpHostController.text = config.smtpHost;
      _smtpPortController.text = config.smtpPort.toString();
      _smtpUsernameController.text = config.smtpUsername;
      _smtpPasswordController.clear(); // Password is not returned for security
      _fromEmailController.text = config.fromEmail;
      _fromNameController.text = config.fromName;
      _useTls = config.useTls;
      _useSsl = config.useSsl;
      _isActive = config.isActive;
    });
  }

  Future<void> _deleteConfig(int configId) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deleteConfiguration),
        content: Text(t.deleteConfigurationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
      await _emailService.deleteEmailConfig(configId);
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      _showSuccessSnackBar(t.emailConfigDeletedSuccessfully);
      _loadConfigs();
      } catch (e) {
        _showErrorSnackBar(e.toString());
      }
    }
  }
}
