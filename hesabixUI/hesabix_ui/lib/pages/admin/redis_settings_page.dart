import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/admin_system_settings_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

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
              'خطا در بارگذاری تنظیمات: ${ErrorExtractor.forContext(e, context)}';
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
          SnackBarHelper.showSuccess(context, message: 'تنظیمات Redis با موفقیت ذخیره شد و اتصال برقرار است');
        } else if (connectionStatus == 'connection_failed') {
          SnackBarHelper.showWarning(context, message: 'تنظیمات ذخیره شد اما اتصال به Redis برقرار نشد. لطفاً تنظیمات را بررسی کنید.');
        } else {
          SnackBarHelper.showSuccess(context, message: 'تنظیمات Redis با موفقیت ذخیره شد');
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
              'خطا در ذخیره تنظیمات: ${ErrorExtractor.forContext(e, context)}';
        });
        SnackBarHelper.showError(
        context,
        message:
            'خطا در ذخیره تنظیمات: ${ErrorExtractor.forContext(e, context)}',
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
            message: 'اتصال به Redis موفق بود!\n'
            'نسخه: ${result['redis_version'] ?? 'نامشخص'}\n'
            'حافظه استفاده شده: ${result['used_memory'] ?? 'نامشخص'}',
          );
        } else {
          SnackBarHelper.showError(
            context,
            message: 'اتصال به Redis ناموفق بود: ${result['message'] ?? 'خطای نامشخص'}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'خطا در تست اتصال: ${ErrorExtractor.forContext(e, context)}';
        });
        SnackBarHelper.showError(
        context,
        message: 'خطا در تست اتصال: ${ErrorExtractor.forContext(e, context)}',
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
      return Scaffold(
        appBar: AppBar(
          title: const Text('تنظیمات Redis Cache'),
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تنظیمات Redis Cache',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          if (!_isLoading && !_isLoadingData)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'بارگذاری مجدد',
              onPressed: _loadConfiguration,
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
                // Card برای اطلاعات کلی
                _buildInfoCard(theme),
                const SizedBox(height: 24),

                // Card برای تنظیمات اصلی
                _buildSectionCard(
                  theme,
                  'تنظیمات اتصال',
                  Icons.settings_outlined,
                  [
                    _buildSwitchField(
                      label: 'فعال/غیرفعال',
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                      description: 'فعال یا غیرفعال کردن استفاده از Redis برای Cache',
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'آدرس سرور (Host)',
                      controller: _hostController,
                      enabled: _enabled,
                      validator: (value) {
                        if (_enabled && (value == null || value.trim().isEmpty)) {
                          return 'آدرس سرور الزامی است';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'پورت (Port)',
                      controller: _portController,
                      enabled: _enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (_enabled) {
                          final port = int.tryParse(value ?? '');
                          if (port == null || port < 1 || port > 65535) {
                            return 'پورت باید بین 1 تا 65535 باشد';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'شماره دیتابیس (DB)',
                      controller: _dbController,
                      enabled: _enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (_enabled) {
                          final db = int.tryParse(value ?? '');
                          if (db == null || db < 0 || db > 15) {
                            return 'شماره دیتابیس باید بین 0 تا 15 باشد';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildPasswordField(
                      label: 'رمز عبور (Password)',
                      controller: _passwordController,
                      enabled: _enabled,
                      visible: _passwordVisible,
                      hasPassword: _hasPassword,
                      onToggleVisibility: () => setState(() => _passwordVisible = !_passwordVisible),
                      description: _hasPassword 
                        ? 'رمز عبور فعلی تنظیم شده است. برای تغییر، رمز جدید را وارد کنید.'
                        : 'رمز عبور Redis (اختیاری)',
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
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.1),
              theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.memory_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Redis Cache',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Redis برای بهبود عملکرد و کاهش بار دیتابیس استفاده می‌شود. '
                    'با فعال کردن Redis، API keys و system settings در cache ذخیره می‌شوند.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
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
            hintText: hasPassword ? 'رمز عبور فعلی تنظیم شده است' : 'رمز عبور (اختیاری)',
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
                  connected ? 'اتصال موفق' : 'اتصال ناموفق',
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
                'نسخه Redis: $version',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (connected && memory != null) ...[
              const SizedBox(height: 4),
              Text(
                'حافظه استفاده شده: $memory',
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
                    testPassed ? 'تست set/get موفق بود' : 'تست set/get ناموفق بود',
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
            label: const Text('تست اتصال'),
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
            label: const Text('ذخیره تنظیمات'),
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

