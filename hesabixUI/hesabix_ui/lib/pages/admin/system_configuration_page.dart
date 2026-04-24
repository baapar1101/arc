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
  bool _smsDestinationRateEnabled = true;
  int _smsDestinationRateMaxSends = 40;
  int _smsDestinationRateWindowMinutes = 60;

  // امنیت کپچا و نرخ احراز هویت
  int _captchaMaxAttempts = 5;
  int _captchaLength = 5;
  int _captchaTtlSeconds = 180;
  String _captchaMode = 'numeric';
  bool _captchaBindIp = true;
  bool _captchaStrongImage = true;
  int _captchaRateMax = 20;
  int _captchaRateWindowSec = 60;
  int _loginRateMaxShort = 10;
  int _loginRateWindowShortSec = 60;
  int _loginRateMaxLong = 10;
  int _loginRateWindowLongSec = 300;
  int _registerRateMax = 5;
  int _registerRateWindowSec = 3600;
  int _forgotPasswordRateMax = 5;
  int _forgotPasswordRateWindowSec = 3600;
  int _resetPasswordRateMax = 10;
  int _resetPasswordRateWindowSec = 3600;
  int _passwordResetOtpRateMax = 5;
  int _passwordResetOtpRateWindowSec = 300;
  int _loginBackoffMaxFails = 5;
  int _loginBackoffWindowMinutes = 15;
  int _loginBackoffSeconds = 90;
  bool _firewallAutoBanOnLoginFail = false;
  int _firewallAutoBanDurationSec = 3600;

  bool _authReportLoading = false;
  Map<String, dynamic>? _authReport;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  static int _asConfigInt(Object? v, int defaultValue) {
    if (v == null) {
      return defaultValue;
    }
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.round();
    }
    return int.tryParse(v.toString()) ?? defaultValue;
  }

  static bool _asConfigBool(Object? v, bool defaultValue) {
    if (v == null) {
      return defaultValue;
    }
    if (v is bool) {
      return v;
    }
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') {
      return true;
    }
    if (s == 'false' || s == '0') {
      return false;
    }
    return defaultValue;
  }

  Future<void> _loadAuthReport() async {
    if (!mounted) return;
    setState(() => _authReportLoading = true);
    try {
      final r = await _service.getAuthSecurityReport(hours: 24, limit: 80);
      if (mounted) {
        setState(() => _authReport = r);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _authReport = null);
      }
    } finally {
      if (mounted) {
        setState(() => _authReportLoading = false);
      }
    }
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
          _smsDestinationRateEnabled = data['sms_destination_rate_enabled'] as bool? ?? true;
          _smsDestinationRateMaxSends = _asConfigInt(
            data['sms_destination_rate_max_sends'],
            40,
          );
          _smsDestinationRateWindowMinutes = _asConfigInt(
            data['sms_destination_rate_window_minutes'],
            60,
          );
          if (_smsDestinationRateWindowMinutes < 1) {
            _smsDestinationRateWindowMinutes = 1;
          }
          _captchaMaxAttempts = _asConfigInt(data['captcha_max_attempts'], 5);
          _captchaLength = _asConfigInt(data['captcha_length'], 5);
          _captchaTtlSeconds = _asConfigInt(data['captcha_ttl_seconds'], 180);
          final cm = data['captcha_mode']?.toString().trim() ?? 'numeric';
          _captchaMode = (cm == 'alphanumeric' || cm == 'numeric') ? cm : 'numeric';
          _captchaBindIp = _asConfigBool(data['captcha_bind_ip'], true);
          _captchaStrongImage = _asConfigBool(data['captcha_strong_image'], true);
          _captchaRateMax = _asConfigInt(data['captcha_rate_max'], 20);
          _captchaRateWindowSec = _asConfigInt(data['captcha_rate_window_sec'], 60);
          _loginRateMaxShort = _asConfigInt(data['login_rate_max_short'], 10);
          _loginRateWindowShortSec = _asConfigInt(data['login_rate_window_short_sec'], 60);
          _loginRateMaxLong = _asConfigInt(data['login_rate_max_long'], 10);
          _loginRateWindowLongSec = _asConfigInt(data['login_rate_window_long_sec'], 300);
          _registerRateMax = _asConfigInt(data['register_rate_max'], 5);
          _registerRateWindowSec = _asConfigInt(data['register_rate_window_sec'], 3600);
          _forgotPasswordRateMax = _asConfigInt(data['forgot_password_rate_max'], 5);
          _forgotPasswordRateWindowSec = _asConfigInt(data['forgot_password_rate_window_sec'], 3600);
          _resetPasswordRateMax = _asConfigInt(data['reset_password_rate_max'], 10);
          _resetPasswordRateWindowSec = _asConfigInt(data['reset_password_rate_window_sec'], 3600);
          _passwordResetOtpRateMax = _asConfigInt(data['password_reset_otp_rate_max'], 5);
          _passwordResetOtpRateWindowSec = _asConfigInt(data['password_reset_otp_rate_window_sec'], 300);
          _loginBackoffMaxFails = _asConfigInt(data['login_backoff_max_fails'], 5);
          _loginBackoffWindowMinutes = _asConfigInt(data['login_backoff_window_minutes'], 15);
          _loginBackoffSeconds = _asConfigInt(data['login_backoff_seconds'], 90);
          _firewallAutoBanOnLoginFail = _asConfigBool(data['firewall_auto_ban_on_login_fail'], false);
          _firewallAutoBanDurationSec = _asConfigInt(data['firewall_auto_ban_duration_sec'], 3600);
        });
        await _loadAuthReport();
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
                const SizedBox(height: 24),
                _buildSectionCard(
                  theme,
                  t.smsDestinationRateSettings,
                  Icons.sms_outlined,
                  [
                    _buildSwitchField(
                      label: t.smsDestinationRateEnabled,
                      value: _smsDestinationRateEnabled,
                      onChanged: (value) =>
                          setState(() => _smsDestinationRateEnabled = value),
                    ),
                    _buildNumberField(
                      label: t.smsDestinationRateMaxSends,
                      value: _smsDestinationRateMaxSends,
                      onChanged: (value) =>
                          setState(() => _smsDestinationRateMaxSends = value),
                      min: 0,
                      max: 1000000,
                      allowUnlimited: true,
                      unlimitedLabel: t.smsDestinationRateMaxSendsHelper,
                    ),
                    _buildNumberField(
                      label: t.smsDestinationRateWindowMinutes,
                      value: _smsDestinationRateWindowMinutes,
                      onChanged: (value) =>
                          setState(() => _smsDestinationRateWindowMinutes = value),
                      min: 1,
                      max: 10080,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  theme,
                  'امنیت کپچا و محدودیت نرخ احراز هویت',
                  Icons.shield_outlined,
                  [
                    _buildNumberField(
                      label: 'حداکثر تلاش اشتباه برای هر کپچا',
                      value: _captchaMaxAttempts,
                      onChanged: (v) => setState(() => _captchaMaxAttempts = v),
                      min: 1,
                      max: 30,
                    ),
                    _buildNumberField(
                      label: 'طول کد کپچا (۴ تا ۸)',
                      value: _captchaLength,
                      onChanged: (v) => setState(() => _captchaLength = v),
                      min: 4,
                      max: 8,
                    ),
                    _buildNumberField(
                      label: 'زمان انقضای کپچا (ثانیه، ۶۰–۶۰۰)',
                      value: _captchaTtlSeconds,
                      onChanged: (v) => setState(() => _captchaTtlSeconds = v),
                      min: 60,
                      max: 600,
                    ),
                    _buildDropdownField(
                      label: 'نوع کاراکتر کپچا',
                      value: _captchaMode,
                      items: const [
                        DropdownMenuItem(value: 'numeric', child: Text('فقط عدد')),
                        DropdownMenuItem(value: 'alphanumeric', child: Text('حروف انگلیسی + عدد')),
                      ],
                      onChanged: (v) => setState(() => _captchaMode = v ?? 'numeric'),
                    ),
                    _buildSwitchField(
                      label: 'اتصال کپچا به IP مشتری',
                      value: _captchaBindIp,
                      onChanged: (v) => setState(() => _captchaBindIp = v),
                    ),
                    _buildSwitchField(
                      label: 'تصویر کپچای قوی‌تر (نویز بیشتر)',
                      value: _captchaStrongImage,
                      onChanged: (v) => setState(() => _captchaStrongImage = v),
                    ),
                    _buildNumberField(
                      label: 'سقف درخواست تولید کپچا به‌ازای هر IP (در پنجره)',
                      value: _captchaRateMax,
                      onChanged: (v) => setState(() => _captchaRateMax = v),
                      min: 1,
                      max: 200,
                    ),
                    _buildNumberField(
                      label: 'پنجره نرخ تولید کپچا (ثانیه)',
                      value: _captchaRateWindowSec,
                      onChanged: (v) => setState(() => _captchaRateWindowSec = v),
                      min: 10,
                      max: 3600,
                    ),
                    const Divider(height: 32),
                    Text(
                      'محدودیت درخواست ورود (رمز عبور) به‌ازای هر IP',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    _buildNumberField(
                      label: 'کوتاه‌مدت: حداکثر درخواست',
                      value: _loginRateMaxShort,
                      onChanged: (v) => setState(() => _loginRateMaxShort = v),
                      min: 1,
                      max: 100,
                    ),
                    _buildNumberField(
                      label: 'کوتاه‌مدت: پنجره (ثانیه)',
                      value: _loginRateWindowShortSec,
                      onChanged: (v) => setState(() => _loginRateWindowShortSec = v),
                      min: 10,
                      max: 3600,
                    ),
                    _buildNumberField(
                      label: 'بلندمدت: حداکثر درخواست',
                      value: _loginRateMaxLong,
                      onChanged: (v) => setState(() => _loginRateMaxLong = v),
                      min: 1,
                      max: 500,
                    ),
                    _buildNumberField(
                      label: 'بلندمدت: پنجره (ثانیه)',
                      value: _loginRateWindowLongSec,
                      onChanged: (v) => setState(() => _loginRateWindowLongSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    const Divider(height: 32),
                    Text(
                      'Backoff پس از ورود ناموفق (بر اساس IP + شناسه)',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'با ۰ در «حداکثر خطا» این قابلیت غیرفعال می‌شود.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _buildNumberField(
                      label: 'حداکثر خطای رمز در پنجره (۰ = غیرفعال)',
                      value: _loginBackoffMaxFails,
                      onChanged: (v) => setState(() => _loginBackoffMaxFails = v),
                      min: 0,
                      max: 50,
                      allowUnlimited: false,
                    ),
                    _buildNumberField(
                      label: 'پنجره شمارش خطا (دقیقه)',
                      value: _loginBackoffWindowMinutes,
                      onChanged: (v) => setState(() => _loginBackoffWindowMinutes = v),
                      min: 1,
                      max: 1440,
                    ),
                    _buildNumberField(
                      label: 'مدت مسدودسازی پس از رسیدن به سقف (ثانیه)',
                      value: _loginBackoffSeconds,
                      onChanged: (v) => setState(() => _loginBackoffSeconds = v),
                      min: 0,
                      max: 3600,
                      allowUnlimited: true,
                      unlimitedLabel: 'بدون انتظار اجباری',
                    ),
                    const SizedBox(height: 12),
                    _buildSwitchField(
                      label: 'فایروال: بن خودکار IP پس از رسیدن به همان سقف خطای بالا',
                      value: _firewallAutoBanOnLoginFail,
                      onChanged: (v) => setState(() => _firewallAutoBanOnLoginFail = v),
                    ),
                    Text(
                      'نیازمند فعال بودن backoff (حداکثر خطا > 0). مدت بن جدا از انتظار backoff است.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _buildNumberField(
                      label: 'مدت بن خودکار در فایروال (ثانیه، ۶۰ تا ۸۶۴۰۰)',
                      value: _firewallAutoBanDurationSec,
                      onChanged: (v) => setState(() => _firewallAutoBanDurationSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    const Divider(height: 32),
                    Text(
                      'سایر محدودیت‌ها (به‌ازای هر IP)',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    _buildNumberField(
                      label: 'ثبت‌نام: حداکثر درخواست / پنجره (ثانیه در فیلد بعد)',
                      value: _registerRateMax,
                      onChanged: (v) => setState(() => _registerRateMax = v),
                      min: 1,
                      max: 100,
                    ),
                    _buildNumberField(
                      label: 'ثبت‌نام: پنجره (ثانیه)',
                      value: _registerRateWindowSec,
                      onChanged: (v) => setState(() => _registerRateWindowSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    _buildNumberField(
                      label: 'فراموشی رمز: حداکثر درخواست',
                      value: _forgotPasswordRateMax,
                      onChanged: (v) => setState(() => _forgotPasswordRateMax = v),
                      min: 1,
                      max: 100,
                    ),
                    _buildNumberField(
                      label: 'فراموشی رمز: پنجره (ثانیه)',
                      value: _forgotPasswordRateWindowSec,
                      onChanged: (v) => setState(() => _forgotPasswordRateWindowSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    _buildNumberField(
                      label: 'بازنشانی رمز با توکن: حداکثر درخواست',
                      value: _resetPasswordRateMax,
                      onChanged: (v) => setState(() => _resetPasswordRateMax = v),
                      min: 1,
                      max: 200,
                    ),
                    _buildNumberField(
                      label: 'بازنشانی رمز با توکن: پنجره (ثانیه)',
                      value: _resetPasswordRateWindowSec,
                      onChanged: (v) => setState(() => _resetPasswordRateWindowSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    _buildNumberField(
                      label: 'ارسال OTP بازیابی رمز: حداکثر درخواست',
                      value: _passwordResetOtpRateMax,
                      onChanged: (v) => setState(() => _passwordResetOtpRateMax = v),
                      min: 1,
                      max: 100,
                    ),
                    _buildNumberField(
                      label: 'ارسال OTP بازیابی رمز: پنجره (ثانیه)',
                      value: _passwordResetOtpRateWindowSec,
                      onChanged: (v) => setState(() => _passwordResetOtpRateWindowSec = v),
                      min: 60,
                      max: 86400,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  theme,
                  'گزارش امنیت احراز هویت (۲۴ ساعت اخیر)',
                  Icons.analytics_outlined,
                  [
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _authReportLoading ? null : _loadAuthReport,
                          icon: _authReportLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh, size: 20),
                          label: const Text('بروزرسانی گزارش'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_authReport == null && !_authReportLoading)
                      Text(
                        'داده‌ای برای نمایش نیست.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else if (_authReport != null) ...[
                      Text('مجموع رویدادها: ${_authReport!['total'] ?? 0}'),
                      const SizedBox(height: 8),
                      if ((_authReport!['by_type'] as Map?)?.isNotEmpty ?? false) ...[
                        Text('به تفکیک نوع', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        ...((_authReport!['by_type'] as Map).entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('${e.key}: ${e.value}'),
                          ),
                        )),
                        const SizedBox(height: 12),
                      ],
                      Text('آخرین رویدادها', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final item in (_authReport!['recent'] as List? ?? const []))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${item['event_type'] ?? ''}  ${item['client_ip'] != null ? '— ${item['client_ip']}' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                subtitle: Text(
                                  item['created_at']?.toString() ?? '',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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
        'sms_destination_rate_enabled': _smsDestinationRateEnabled,
        'sms_destination_rate_max_sends': _smsDestinationRateMaxSends,
        'sms_destination_rate_window_minutes': _smsDestinationRateWindowMinutes,
        'captcha_max_attempts': _captchaMaxAttempts,
        'captcha_length': _captchaLength,
        'captcha_ttl_seconds': _captchaTtlSeconds,
        'captcha_mode': _captchaMode,
        'captcha_bind_ip': _captchaBindIp,
        'captcha_strong_image': _captchaStrongImage,
        'captcha_rate_max': _captchaRateMax,
        'captcha_rate_window_sec': _captchaRateWindowSec,
        'login_rate_max_short': _loginRateMaxShort,
        'login_rate_window_short_sec': _loginRateWindowShortSec,
        'login_rate_max_long': _loginRateMaxLong,
        'login_rate_window_long_sec': _loginRateWindowLongSec,
        'register_rate_max': _registerRateMax,
        'register_rate_window_sec': _registerRateWindowSec,
        'forgot_password_rate_max': _forgotPasswordRateMax,
        'forgot_password_rate_window_sec': _forgotPasswordRateWindowSec,
        'reset_password_rate_max': _resetPasswordRateMax,
        'reset_password_rate_window_sec': _resetPasswordRateWindowSec,
        'password_reset_otp_rate_max': _passwordResetOtpRateMax,
        'password_reset_otp_rate_window_sec': _passwordResetOtpRateWindowSec,
        'login_backoff_max_fails': _loginBackoffMaxFails,
        'login_backoff_window_minutes': _loginBackoffWindowMinutes,
        'login_backoff_seconds': _loginBackoffSeconds,
        'firewall_auto_ban_on_login_fail': _firewallAutoBanOnLoginFail,
        'firewall_auto_ban_duration_sec': _firewallAutoBanDurationSec,
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
