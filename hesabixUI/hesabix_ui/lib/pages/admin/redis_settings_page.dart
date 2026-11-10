import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/admin_system_settings_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class RedisSettingsPage extends StatefulWidget {
  const RedisSettingsPage({super.key});

  @override
  State<RedisSettingsPage> createState() => _RedisSettingsPageState();
}

class _RedisSettingsPageState extends State<RedisSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _service = AdminSystemSettingsService(ApiClient());
  
  bool _isLoading = false;
  bool _isLoadingData = true;
  bool _isTestingConnection = false;
  String? _error;
  Map<String, dynamic>? _testResult;

  // Redis configuration values
  bool _enabled = false;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _dbController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _hasPassword = false; // برای تشخیص اینکه آیا password تنظیم شده یا نه

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _dbController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    setState(() {
      _isLoadingData = true;
      _error = null;
    });

    try {
      final data = await _service.getRedisConfiguration();
      if (mounted) {
        setState(() {
          _enabled = data['enabled'] as bool? ?? false;
          _hostController.text = data['host']?.toString() ?? 'localhost';
          _portController.text = (data['port'] ?? 6379).toString();
          _dbController.text = (data['db'] ?? 0).toString();
          _hasPassword = data['password']?.toString() == '***' || 
                       (data['password'] != null && data['password'].toString().isNotEmpty);
          // اگر password وجود دارد، فیلد را خالی می‌گذاریم (برای امنیت)
          _passwordController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        setState(() {
          _error =
              '${adminTx(context, 'خطا در بارگذاری تنظیمات', 'Could not load settings')}: ${ErrorExtractor.forContext(e, context)}';
        });
        SnackBarHelper.showError(
        context,
        message:
            '${t.errorLoadingSettings}: ${ErrorExtractor.forContext(e, context)}',
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

  Future<void> _saveConfiguration() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _testResult = null;
    });

    try {
      final data = <String, dynamic>{
        'enabled': _enabled,
        'host': _hostController.text.trim(),
        'port': int.tryParse(_portController.text) ?? 6379,
        'db': int.tryParse(_dbController.text) ?? 0,
      };

      // اگر password تغییر کرده یا حذف شده
      if (_passwordController.text.isNotEmpty) {
        data['password'] = _passwordController.text;
      } else if (!_hasPassword && _enabled) {
        // اگر قبلاً password نداشتیم و الان فعال کردیم، password را null می‌فرستیم
        data['password'] = null;
      }
      // اگر password خالی است و قبلاً داشتیم، برای حذف password خالی می‌فرستیم
      else if (_hasPassword && _passwordController.text.isEmpty) {
        data['password'] = '';
      }

      final result = await _service.updateRedisConfiguration(data);
      
      if (mounted) {
        final t = AppLocalizations.of(context);
        final connectionStatus = result['connection_status']?.toString() ?? 'unknown';
        
        if (connectionStatus == 'connected') {
          SnackBarHelper.showSuccess(context, message: adminTx(context, 'تنظیمات ذخیره شد و اتصال برقرار است', 'Settings saved and the connection works'));
        } else if (connectionStatus == 'connection_failed') {
          SnackBarHelper.showWarning(context, message: adminTx(context, 'تنظیمات ذخیره شد، ولی اتصال برقرار نشد', 'Settings were saved, but the connection failed'));
        } else {
          SnackBarHelper.showSuccess(context, message: adminTx(context, 'تنظیمات ذخیره شد', 'Settings saved'));
        }

        // به‌روزرسانی _hasPassword
        setState(() {
          _hasPassword = result['password']?.toString() == '***' || 
                       (result['password'] != null && result['password'].toString().isNotEmpty);
          _passwordController.clear(); // پاک کردن password بعد از ذخیره
        });

        // بارگذاری مجدد برای دریافت connection_status
        await _loadConfiguration();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              '${adminTx(context, 'خطا در ذخیره تنظیمات', 'Could not save settings')}: ${ErrorExtractor.forContext(e, context)}';
        });
        SnackBarHelper.showError(
        context,
        message:
            '${adminTx(context, 'خطا در ذخیره تنظیمات', 'Could not save settings')}: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _testResult = null;
      _error = null;
    });

    try {
      final result = await _service.testRedisConnection();
      if (mounted) {
        setState(() {
          _testResult = result;
        });

        final connected = result['connected'] as bool? ?? false;
        if (connected) {
          SnackBarHelper.showSuccess(
            context,
            message: adminTx(context, 'اتصال برقرار شد', 'Connected') + '\n'
            '${adminTx(context, 'نسخه', 'Version')}: ${result['redis_version'] ?? adminTx(context, 'نامشخص', 'Unknown')}\n'
            '${adminTx(context, 'حافظه', 'Memory')}: ${result['used_memory'] ?? adminTx(context, 'نامشخص', 'Unknown')}',
          );
        } else {
          SnackBarHelper.showError(
            context,
            message: '${adminTx(context, 'اتصال ناموفق بود', 'Connection failed')}: ${result['message'] ?? adminTx(context, 'خطای نامشخص', 'Unknown error')}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              '${adminTx(context, 'خطا در تست اتصال', 'Connection test failed')}: ${ErrorExtractor.forContext(e, context)}';
        });
        SnackBarHelper.showError(
        context,
        message: '${adminTx(context, 'خطا در تست اتصال', 'Connection test failed')}: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    if (_isLoadingData) {
      return AdminCompactScaffold(
        title: adminTx(context, 'ردیس', 'Redis'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return AdminCompactScaffold(
      title: adminTx(context, 'ردیس', 'Redis'),
      subtitle: adminTx(context, 'کش و صف پس‌زمینه', 'Cache and background queue'),
      actions: [
        if (!_isLoading)
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: adminTx(context, 'بارگذاری مجدد', 'Reload'),
            onPressed: _loadConfiguration,
          ),
      ],
      body: SingleChildScrollView(
          padding: context.settingsHub.pagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card برای اطلاعات کلی
                _buildInfoCard(theme),
                const SizedBox(height: 24),

                // Card برای تنظیمات اصلی
                _buildSectionCard(
                  theme,
                  adminTx(context, 'تنظیمات اتصال', 'Connection'),
                  Icons.settings_outlined,
                  [
                    _buildSwitchField(
                      label: adminTx(context, 'فعال', 'Enabled'),
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                      description: adminTx(context, 'ردیس برای کش استفاده شود', 'Use Redis for cache'),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: adminTx(context, 'آدرس سرور', 'Host'),
                      controller: _hostController,
                      enabled: _enabled,
                      validator: (value) {
                        if (_enabled && (value == null || value.trim().isEmpty)) {
                          return adminTx(context, 'آدرس سرور الزامی است', 'Host is required');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: adminTx(context, 'پورت', 'Port'),
                      controller: _portController,
                      enabled: _enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (_enabled) {
                          final port = int.tryParse(value ?? '');
                          if (port == null || port < 1 || port > 65535) {
                            return adminTx(context, 'پورت باید بین ۱ و ۶۵۵۳۵ باشد', 'Port must be between 1 and 65535');
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: adminTx(context, 'شماره دیتابیس', 'Database number'),
                      controller: _dbController,
                      enabled: _enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (_enabled) {
                          final db = int.tryParse(value ?? '');
                          if (db == null || db < 0 || db > 15) {
                            return adminTx(context, 'شماره دیتابیس باید بین ۰ و ۱۵ باشد', 'Database number must be between 0 and 15');
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildPasswordField(
                      label: adminTx(context, 'رمز عبور', 'Password'),
                      controller: _passwordController,
                      enabled: _enabled,
                      visible: _passwordVisible,
                      hasPassword: _hasPassword,
                      onToggleVisibility: () => setState(() => _passwordVisible = !_passwordVisible),
                      description: _hasPassword 
                        ? adminTx(context, 'رمز فعلی ذخیره شده است. برای تغییر، رمز جدید را وارد کنید.', 'A password is saved. Enter a new one to replace it.')
                        : adminTx(context, 'رمز ردیس، اختیاری', 'Redis password, optional'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Card برای تست اتصال
                if (_testResult != null) ...[
                  _buildTestResultCard(theme),
                  const SizedBox(height: 24),
                ],

                // دکمه‌های عملیات
                _buildActionButtons(theme),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.memory_outlined, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adminTx(context, 'کش ردیس', 'Redis cache'),
                    style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    adminTx(
                      context,
                      'کش را نگه می‌دارد تا بار دیتابیس کمتر شود.',
                      'Holds cache so the database does less work.',
                    ),
                    style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    ThemeData theme,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
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

  Widget _buildSwitchField({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? description,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: enabled 
          ? theme.colorScheme.surface 
          : theme.colorScheme.surface.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    required bool visible,
    required bool hasPassword,
    required VoidCallback onToggleVisibility,
    String? description,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: !visible,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: enabled 
              ? theme.colorScheme.surface 
              : theme.colorScheme.surface.withValues(alpha: 0.5),
            suffixIcon: IconButton(
              icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
              onPressed: enabled ? onToggleVisibility : null,
            ),
            hintText: hasPassword ? adminTx(context, 'رمز فعلی ذخیره شده است', 'A password is already saved') : adminTx(context, 'رمز عبور، اختیاری', 'Password, optional'),
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTestResultCard(ThemeData theme) {
    final connected = _testResult?['connected'] as bool? ?? false;
    final message = _testResult?['message']?.toString() ?? '';
    final version = _testResult?['redis_version']?.toString();
    final memory = _testResult?['used_memory']?.toString();
    final testPassed = _testResult?['test_passed'] as bool? ?? false;

    return Card(
      elevation: 2,
      color: connected 
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
        : theme.colorScheme.errorContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.check_circle : Icons.error,
                  color: connected 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.error,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  connected ? adminTx(context, 'اتصال موفق', 'Connected') : adminTx(context, 'اتصال ناموفق', 'Not connected'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: connected 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
            ),
            if (connected && version != null) ...[
              const SizedBox(height: 8),
              Text(
                '${adminTx(context, 'نسخه ردیس', 'Redis version')}: $version',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (connected && memory != null) ...[
              const SizedBox(height: 4),
              Text(
                '${adminTx(context, 'حافظه استفاده‌شده', 'Memory used')}: $memory',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (connected) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    testPassed ? Icons.check : Icons.close,
                    size: 16,
                    color: testPassed 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    testPassed ? adminTx(context, 'تست خواندن و نوشتن موفق بود', 'Read and write test passed') : adminTx(context, 'تست خواندن و نوشتن ناموفق بود', 'Read and write test failed'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: testPassed 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isLoading || _isTestingConnection ? null : _testConnection,
            icon: _isTestingConnection
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check),
            label: Text(adminTx(context, 'تست اتصال', 'Test connection')),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isLoading || _isTestingConnection ? null : _saveConfiguration,
            icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.save),
            label: Text(adminTx(context, 'ذخیره تنظیمات', 'Save settings')),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

