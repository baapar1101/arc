import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import '../../core/api_client.dart';
import '../../services/admin_system_settings_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

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
  String _defaultThemeId = 'classic_blue';
  String _defaultDisplayTimezone = 'Asia/Tehran';
  bool _enableRegistration = true;
  bool _enableEmailVerification = true;
  bool _enableMaintenanceMode = false;
  bool _supportTicketsEnabled = true;
  final TextEditingController _supportTicketsDisabledMessageCtrl = TextEditingController();
  bool _legacyApiImportEnabled = true;
  final TextEditingController _legacyApiImportDisabledMessageCtrl = TextEditingController();
  String _supportBillingMode = 'free';
  int _supportFreeQuotaPerMonth = 2;
  int _supportGracePeriodDays = 3;
  bool _supportAllowReadWithoutSub = true;
  bool _supportRequireSubToReply = true;
  bool _supportPaidPriorityBoost = true;
  final TextEditingController _supportInvoicePrefixCtrl = TextEditingController(text: 'SUP');
  int _sessionTimeout = 30;
  int _mcpOauthSessionDays = 30;
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

  int _configSection = 0;

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

  @override
  void dispose() {
    _supportTicketsDisabledMessageCtrl.dispose();
    _legacyApiImportDisabledMessageCtrl.dispose();
    _supportInvoicePrefixCtrl.dispose();
    super.dispose();
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
          _appName = data['app_name']?.toString() ?? BrandConfig.materialTitle;
          _appVersion = data['app_version']?.toString() ?? '1.0.23';
          _defaultLanguage = data['default_language']?.toString() ?? 'fa';
          _defaultTheme = data['default_theme']?.toString() ?? 'system';
          final themeIdRaw = data['default_theme_id']?.toString().trim().toLowerCase();
          _defaultThemeId = (themeIdRaw != null &&
                  const {
                    'classic_blue',
                    'turquoise_sea',
                    'emerald_forest',
                    'warm_copper',
                  }.contains(themeIdRaw))
              ? themeIdRaw
              : 'classic_blue';
          final tzRaw = data['default_timezone']?.toString().trim();
          _defaultDisplayTimezone = (tzRaw != null && tzRaw.isNotEmpty) ? tzRaw : 'Asia/Tehran';
          _enableRegistration = data['enable_registration'] as bool? ?? true;
          _enableEmailVerification = data['enable_email_verification'] as bool? ?? true;
          _enableMaintenanceMode = data['enable_maintenance_mode'] as bool? ?? false;
          _supportTicketsEnabled = data['support_tickets_enabled'] as bool? ?? true;
          _supportTicketsDisabledMessageCtrl.text =
              data['support_tickets_disabled_message']?.toString() ?? '';
          _legacyApiImportEnabled =
              data['legacy_api_import_enabled'] as bool? ?? true;
          _legacyApiImportDisabledMessageCtrl.text =
              data['legacy_api_import_disabled_message']?.toString() ?? '';
          final billingMode = data['support_billing_mode']?.toString() ?? 'free';
          _supportBillingMode =
              const ['free', 'paid', 'hybrid'].contains(billingMode) ? billingMode : 'free';
          _supportFreeQuotaPerMonth = _asConfigInt(data['support_free_quota_per_month'], 2);
          _supportGracePeriodDays = _asConfigInt(data['support_grace_period_days'], 3);
          _supportAllowReadWithoutSub =
              data['support_allow_read_without_subscription'] as bool? ?? true;
          _supportRequireSubToReply =
              data['support_require_subscription_to_reply'] as bool? ?? true;
          _supportPaidPriorityBoost = data['support_paid_priority_boost'] as bool? ?? true;
          _supportInvoicePrefixCtrl.text =
              data['support_invoice_prefix']?.toString().trim().isNotEmpty == true
                  ? data['support_invoice_prefix'].toString().trim()
                  : 'SUP';
          _sessionTimeout = data['session_timeout'] as int? ?? 30;
          _mcpOauthSessionDays = _asConfigInt(data['mcp_oauth_session_days'], 30);
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
        final err = ErrorExtractor.forContext(e, context);
        setState(() {
          _error = '${t.errorLoadingSettings}: $err';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t.errorLoadingSettings}: $err'),
            backgroundColor: SemanticColorResolver.negative(context),
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
      return AdminCompactScaffold(
        title: t.systemConfiguration,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _appName.isEmpty) {
      return AdminCompactScaffold(
        title: t.systemConfiguration,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                style: TextStyle(color: SemanticColorResolver.negative(context)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadConfiguration,
                child: Text(t.retry),
              ),
            ],
          ),
        ),
      );
    }

    return AdminCompactScaffold(
      title: t.systemConfiguration,
      subtitle: adminTx(context, 'هر بخش جدا ذخیره می‌شود', 'Each section saves on its own'),
      actions: [
        IconButton(
          tooltip: _isLoading ? t.saving : adminTx(context, 'ذخیره این بخش', 'Save this section'),
          onPressed: _isLoading ? null : _saveConfiguration,
          icon: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined, size: 20),
        ),
      ],
      body: SingleChildScrollView(
          padding: context.settingsHub.pagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    for (final entry in [
                      (0, adminTx(context, 'عمومی', 'General')),
                      (1, adminTx(context, 'ثبت‌نام', 'Registration')),
                      (2, adminTx(context, 'پشتیبانی', 'Support')),
                      (3, adminTx(context, 'امنیت', 'Security')),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2, style: const TextStyle(fontSize: 12)),
                        selected: _configSection == entry.$1,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _configSection = entry.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_configSection == 0) ...[
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
                    _buildDropdownField(
                      label: t.defaultColorTheme,
                      value: _defaultThemeId,
                      items: [
                        DropdownMenuItem(value: 'classic_blue', child: Text(t.themeClassicBlue)),
                        DropdownMenuItem(value: 'turquoise_sea', child: Text(t.themeTurquoiseSea)),
                        DropdownMenuItem(value: 'emerald_forest', child: Text(t.themeEmeraldForest)),
                        DropdownMenuItem(value: 'warm_copper', child: Text(t.themeWarmCopper)),
                      ],
                      onChanged: (value) => setState(() => _defaultThemeId = value!),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        t.defaultColorThemeHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _buildTextField(
                      label: adminTx(context, 'منطقهٔ زمانی نمایش (IANA)', 'Display timezone (IANA)'),
                      value: _defaultDisplayTimezone,
                      onChanged: (value) => setState(() => _defaultDisplayTimezone = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        adminTx(context, 'مثال: Asia/Tehran، UTC، Europe/Berlin. همهٔ تاریخ/زمان‌های ارسالی API بر اساس این منطقه نمایش داده می‌شوند.', 'Example: Asia/Tehran, UTC, Europe/Berlin. API dates are shown in this timezone.'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ],
                if (_configSection == 1) ...[
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
                    _buildNumberField(
                      label: adminTx(context, 'مدت اعتبار اتصال ChatGPT و ابزارهای هوش مصنوعی (روز)', 'ChatGPT and AI tool session (days)'),
                      value: _mcpOauthSessionDays,
                      onChanged: (value) => setState(() => _mcpOauthSessionDays = value),
                      min: 1,
                      max: 365,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        adminTx(context, 'پس از این مدت، کاربر باید اتصال حسابیکس را دوباره تایید کند. مقدار پیش‌فرض ۳۰ روز است.', 'After this, the user must approve the connection again. Default is 30 days.'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _buildDropdownField(
                      label: adminTx(context, 'محدودیت ایجاد کسب و کار', 'Who can create a business'),
                      value: _businessCreationRequirement,
                      items: [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text(adminTx(context, 'بدون محدودیت (همه کاربران)', 'No restriction')),
                        ),
                        DropdownMenuItem(
                          value: 'email_only',
                          child: Text(adminTx(context, 'فقط ایمیل تایید شده', 'Verified email only')),
                        ),
                        DropdownMenuItem(
                          value: 'mobile_only',
                          child: Text(adminTx(context, 'فقط شماره موبایل تایید شده', 'Verified mobile only')),
                        ),
                        DropdownMenuItem(
                          value: 'both',
                          child: Text(adminTx(context, 'هر دو (ایمیل و موبایل)', 'Both email and mobile')),
                        ),
                        DropdownMenuItem(
                          value: 'either',
                          child: Text(adminTx(context, 'هر کدام (ایمیل یا موبایل)', 'Either email or mobile')),
                        ),
                      ],
                      onChanged: (value) => setState(() => _businessCreationRequirement = value!),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        adminTx(context, 'این تنظیم تعیین می‌کند که چه کاربرانی می‌توانند کسب و کار جدید ایجاد کنند.', 'This controls which users can create a new business.'),
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
                  t.legacyApiImportSectionTitle,
                  Icons.cloud_sync_outlined,
                  [
                    _buildSwitchField(
                      label: t.legacyApiImportAllowUsersLabel,
                      value: _legacyApiImportEnabled,
                      onChanged: (value) =>
                          setState(() => _legacyApiImportEnabled = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        t.legacyApiImportAllowUsersDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: _legacyApiImportDisabledMessageCtrl,
                      minLines: 2,
                      maxLines: 6,
                      maxLength: 8192,
                      decoration: InputDecoration(
                        labelText: t.legacyApiImportDisabledNoticeLabel,
                        hintText: t.legacyApiImportDisabledNoticeHint,
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ],
                if (_configSection == 0) ...[
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
                ],
                if (_configSection == 2) ...[
                _buildSectionCard(
                  theme,
                  t.supportTicketsUserSectionTitle,
                  Icons.support_agent_outlined,
                  [
                    _buildSwitchField(
                      label: t.supportTicketsAllowUsersLabel,
                      value: _supportTicketsEnabled,
                      onChanged: (value) => setState(() => _supportTicketsEnabled = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        t.supportTicketsAllowUsersDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: _supportTicketsDisabledMessageCtrl,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 8192,
                      decoration: InputDecoration(
                        labelText: t.supportTicketsDisabledNoticeLabel,
                        hintText: t.supportTicketsDisabledNoticeHint,
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _supportBillingMode,
                      decoration: InputDecoration(
                        labelText: adminTx(context, 'حالت صورتحساب پشتیبانی', 'Support billing mode'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'free',
                          child: Text(adminTx(context, 'رایگان برای همه', 'Free for everyone')),
                        ),
                        DropdownMenuItem(
                          value: 'paid',
                          child: Text(adminTx(context, 'پشتیبانی غیررایگان', 'Paid support')),
                        ),
                        DropdownMenuItem(
                          value: 'hybrid',
                          child: Text(adminTx(context, 'ترکیبی (سهمیه + اشتراک)', 'Hybrid (quota + subscription)')),
                        ),
                      ],
                      onChanged: (v) => setState(() => _supportBillingMode = v ?? 'free'),
                    ),
                    if (_supportBillingMode == 'hybrid')
                      _buildNumberField(
                        label: adminTx(context, 'سهمیه رایگان ماهانه (تیکت)', 'Free monthly ticket quota'),
                        value: _supportFreeQuotaPerMonth,
                        onChanged: (value) => setState(() => _supportFreeQuotaPerMonth = value),
                        min: 0,
                        max: 1000,
                      ),
                    _buildNumberField(
                      label: adminTx(context, 'مهلت ارفاق بعد از انقضا (روز)', 'Grace period after expiry (days)'),
                      value: _supportGracePeriodDays,
                      onChanged: (value) => setState(() => _supportGracePeriodDays = value),
                      min: 0,
                      max: 90,
                    ),
                    TextFormField(
                      controller: _supportInvoicePrefixCtrl,
                      decoration: InputDecoration(
                        labelText: adminTx(context, 'پیشوند کد صورت‌حساب', 'Invoice code prefix'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    _buildSwitchField(
                      label: adminTx(context, 'مشاهده تیکت‌های قبلی بدون اشتراک', 'Read old tickets without a subscription'),
                      value: _supportAllowReadWithoutSub,
                      onChanged: (value) => setState(() => _supportAllowReadWithoutSub = value),
                    ),
                    _buildSwitchField(
                      label: adminTx(context, 'برای پاسخ هم اشتراک لازم باشد', 'Require a subscription to reply'),
                      value: _supportRequireSubToReply,
                      onChanged: (value) => setState(() => _supportRequireSubToReply = value),
                    ),
                    _buildSwitchField(
                      label: adminTx(context, 'اولویت‌دهی تیکت مشترکان در صف اپراتور', 'Prioritize subscriber tickets in the operator queue'),
                      value: _supportPaidPriorityBoost,
                      onChanged: (value) => setState(() => _supportPaidPriorityBoost = value),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ],
                if (_configSection == 3) ...[
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
                  adminTx(context, 'امنیت کپچا و محدودیت نرخ احراز هویت', 'Captcha and sign-in rate limits'),
                  Icons.shield_outlined,
                  [
                    _buildNumberField(
                      label: adminTx(context, 'حداکثر تلاش اشتباه برای هر کپچا', 'Wrong attempts per captcha'),
                      value: _captchaMaxAttempts,
                      onChanged: (v) => setState(() => _captchaMaxAttempts = v),
                      min: 1,
                      max: 30,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'طول کد کپچا (۴ تا ۸)', 'Captcha length (4–8)'),
                      value: _captchaLength,
                      onChanged: (v) => setState(() => _captchaLength = v),
                      min: 4,
                      max: 8,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'زمان انقضای کپچا (ثانیه، ۶۰–۶۰۰)', 'Captcha expiry (seconds, 60–600)'),
                      value: _captchaTtlSeconds,
                      onChanged: (v) => setState(() => _captchaTtlSeconds = v),
                      min: 60,
                      max: 600,
                    ),
                    _buildDropdownField(
                      label: adminTx(context, 'نوع کاراکتر کپچا', 'Captcha character set'),
                      value: _captchaMode,
                      items: [
                        DropdownMenuItem(
                          value: 'numeric',
                          child: Text(adminTx(context, 'فقط عدد', 'Digits only')),
                        ),
                        DropdownMenuItem(
                          value: 'alphanumeric',
                          child: Text(adminTx(context, 'حروف انگلیسی + عدد', 'Letters and digits')),
                        ),
                      ],
                      onChanged: (v) => setState(() => _captchaMode = v ?? 'numeric'),
                    ),
                    _buildSwitchField(
                      label: adminTx(context, 'اتصال کپچا به IP مشتری', 'Bind captcha to client IP'),
                      value: _captchaBindIp,
                      onChanged: (v) => setState(() => _captchaBindIp = v),
                    ),
                    _buildSwitchField(
                      label: adminTx(context, 'تصویر کپچای قوی‌تر (نویز بیشتر)', 'Stronger captcha image'),
                      value: _captchaStrongImage,
                      onChanged: (v) => setState(() => _captchaStrongImage = v),
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'سقف درخواست تولید کپچا به‌ازای هر IP (در پنجره)', 'Captcha requests per IP in the window'),
                      value: _captchaRateMax,
                      onChanged: (v) => setState(() => _captchaRateMax = v),
                      min: 1,
                      max: 200,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'پنجره نرخ تولید کپچا (ثانیه)', 'Captcha rate window (seconds)'),
                      value: _captchaRateWindowSec,
                      onChanged: (v) => setState(() => _captchaRateWindowSec = v),
                      min: 10,
                      max: 3600,
                    ),
                    const Divider(height: 32),
                    Text(
                      adminTx(context, 'محدودیت درخواست ورود (رمز عبور) به‌ازای هر IP', 'Password sign-in limit per IP'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    _buildNumberField(
                      label: adminTx(context, 'کوتاه‌مدت: حداکثر درخواست', 'Short window: max requests'),
                      value: _loginRateMaxShort,
                      onChanged: (v) => setState(() => _loginRateMaxShort = v),
                      min: 1,
                      max: 100,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'کوتاه‌مدت: پنجره (ثانیه)', 'Short window (seconds)'),
                      value: _loginRateWindowShortSec,
                      onChanged: (v) => setState(() => _loginRateWindowShortSec = v),
                      min: 10,
                      max: 3600,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'بلندمدت: حداکثر درخواست', 'Long window: max requests'),
                      value: _loginRateMaxLong,
                      onChanged: (v) => setState(() => _loginRateMaxLong = v),
                      min: 1,
                      max: 500,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'بلندمدت: پنجره (ثانیه)', 'Long window (seconds)'),
                      value: _loginRateWindowLongSec,
                      onChanged: (v) => setState(() => _loginRateWindowLongSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    const Divider(height: 32),
                    Text(
                      adminTx(context, 'Backoff پس از ورود ناموفق (بر اساس IP + شناسه)', 'Backoff after failed sign-in (IP + identifier)'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      adminTx(context, 'با ۰ در «حداکثر خطا» این قابلیت غیرفعال می‌شود.', 'Set the failure limit to 0 to turn this off.'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _buildNumberField(
                      label: adminTx(context, 'حداکثر خطای رمز در پنجره (۰ = غیرفعال)', 'Password failures in the window (0 = off)'),
                      value: _loginBackoffMaxFails,
                      onChanged: (v) => setState(() => _loginBackoffMaxFails = v),
                      min: 0,
                      max: 50,
                      allowUnlimited: false,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'پنجره شمارش خطا (دقیقه)', 'Failure counting window (minutes)'),
                      value: _loginBackoffWindowMinutes,
                      onChanged: (v) => setState(() => _loginBackoffWindowMinutes = v),
                      min: 1,
                      max: 1440,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'مدت مسدودسازی پس از رسیدن به سقف (ثانیه)', 'Lockout after the limit (seconds)'),
                      value: _loginBackoffSeconds,
                      onChanged: (v) => setState(() => _loginBackoffSeconds = v),
                      min: 0,
                      max: 3600,
                      allowUnlimited: true,
                      unlimitedLabel: adminTx(context, 'بدون انتظار اجباری', 'No forced wait'),
                    ),
                    const SizedBox(height: 12),
                    _buildSwitchField(
                      label: adminTx(context, 'فایروال: بن خودکار IP پس از رسیدن به همان سقف خطای بالا', 'Firewall: auto-ban IP after that failure limit'),
                      value: _firewallAutoBanOnLoginFail,
                      onChanged: (v) => setState(() => _firewallAutoBanOnLoginFail = v),
                    ),
                    Text(
                      adminTx(context, 'نیازمند فعال بودن backoff (حداکثر خطا > 0). مدت بن جدا از انتظار backoff است.', 'Requires backoff (failure limit > 0). Ban length is separate from the backoff wait.'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _buildNumberField(
                      label: adminTx(context, 'مدت بن خودکار در فایروال (ثانیه، ۶۰ تا ۸۶۴۰۰)', 'Auto-ban duration (seconds, 60–86400)'),
                      value: _firewallAutoBanDurationSec,
                      onChanged: (v) => setState(() => _firewallAutoBanDurationSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    const Divider(height: 32),
                    Text(
                      adminTx(context, 'سایر محدودیت‌ها (به‌ازای هر IP)', 'Other limits per IP'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    _buildNumberField(
                      label: adminTx(context, 'ثبت‌نام: حداکثر درخواست / پنجره (ثانیه در فیلد بعد)', 'Sign-up: max requests (window is the next field)'),
                      value: _registerRateMax,
                      onChanged: (v) => setState(() => _registerRateMax = v),
                      min: 1,
                      max: 100,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'ثبت‌نام: پنجره (ثانیه)', 'Sign-up window (seconds)'),
                      value: _registerRateWindowSec,
                      onChanged: (v) => setState(() => _registerRateWindowSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'فراموشی رمز: حداکثر درخواست', 'Forgot password: max requests'),
                      value: _forgotPasswordRateMax,
                      onChanged: (v) => setState(() => _forgotPasswordRateMax = v),
                      min: 1,
                      max: 100,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'فراموشی رمز: پنجره (ثانیه)', 'Forgot password window (seconds)'),
                      value: _forgotPasswordRateWindowSec,
                      onChanged: (v) => setState(() => _forgotPasswordRateWindowSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'بازنشانی رمز با توکن: حداکثر درخواست', 'Token reset: max requests'),
                      value: _resetPasswordRateMax,
                      onChanged: (v) => setState(() => _resetPasswordRateMax = v),
                      min: 1,
                      max: 200,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'بازنشانی رمز با توکن: پنجره (ثانیه)', 'Token reset window (seconds)'),
                      value: _resetPasswordRateWindowSec,
                      onChanged: (v) => setState(() => _resetPasswordRateWindowSec = v),
                      min: 60,
                      max: 86400,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'ارسال OTP بازیابی رمز: حداکثر درخواست', 'Password OTP: max requests'),
                      value: _passwordResetOtpRateMax,
                      onChanged: (v) => setState(() => _passwordResetOtpRateMax = v),
                      min: 1,
                      max: 100,
                    ),
                    _buildNumberField(
                      label: adminTx(context, 'ارسال OTP بازیابی رمز: پنجره (ثانیه)', 'Password OTP window (seconds)'),
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
                  adminTx(context, 'گزارش امنیت احراز هویت (۲۴ ساعت اخیر)', 'Sign-in security report (last 24 hours)'),
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
                          label: Text(adminTx(context, 'بروزرسانی گزارش', 'Refresh report')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_authReport == null && !_authReportLoading)
                      Text(
                        adminTx(context, 'داده‌ای برای نمایش نیست.', 'Nothing to show yet.'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else if (_authReport != null) ...[
                      Text(adminTx(
                        context,
                        'مجموع رویدادها: ${_authReport!['total'] ?? 0}',
                        'Total events: ${_authReport!['total'] ?? 0}',
                      )),
                      const SizedBox(height: 8),
                      if (_authReport!['by_type'] is Map &&
                          (_authReport!['by_type'] as Map).isNotEmpty) ...[
                        Text(
                          adminTx(context, 'به تفکیک نوع', 'By type'),
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        ...((_authReport!['by_type'] as Map).entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('${e.key}: ${e.value}'),
                          ),
                        )),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        adminTx(context, 'آخرین رویدادها', 'Latest events'),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final raw in (_authReport!['recent'] as List? ?? const []))
                              if (raw is Map)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${raw['event_type'] ?? ''}  ${raw['client_ip'] != null ? '— ${raw['client_ip']}' : ''}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  subtitle: Text(
                                    raw['created_at']?.toString() ?? '',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _saveConfiguration,
                    icon: _isLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save, size: 18),
                    label: Text(
                      _isLoading ? t.saving : adminTx(context, 'ذخیره این بخش', 'Save this section'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildSectionCard(ThemeData theme, String title, IconData icon, List<Widget> children) {
    final hub = context.settingsHub;
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: hub.categorySectionBottom),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(hub.categoryRadius),
        side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: hub.categoryBodyPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: hub.categoryIconSize),
                SizedBox(width: hub.categoryIconGap),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hub.categoryTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
            SizedBox(height: hub.listTitleGap),
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
      padding: const EdgeInsets.only(bottom: 8),
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
      padding: const EdgeInsets.only(bottom: 8),
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
      padding: const EdgeInsets.only(bottom: 8),
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
      padding: const EdgeInsets.only(bottom: 8),
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
      final all = <String, dynamic>{
        'app_name': _appName.trim(),
        'app_version': _appVersion.trim(),
        'default_language': _defaultLanguage,
        'default_theme': _defaultTheme,
        'default_theme_id': _defaultThemeId,
        'default_timezone': _defaultDisplayTimezone.trim(),
        'enable_maintenance_mode': _enableMaintenanceMode,
        'max_file_size': _maxFileSize,
        'max_users': _maxUsers,
        'enable_registration': _enableRegistration,
        'enable_email_verification': _enableEmailVerification,
        'session_timeout': _sessionTimeout,
        'mcp_oauth_session_days': _mcpOauthSessionDays,
        'business_creation_verification_requirement': _businessCreationRequirement,
        'legacy_api_import_enabled': _legacyApiImportEnabled,
        'legacy_api_import_disabled_message': _legacyApiImportDisabledMessageCtrl.text.trim(),
        'support_tickets_enabled': _supportTicketsEnabled,
        'support_tickets_disabled_message': _supportTicketsDisabledMessageCtrl.text.trim(),
        'support_billing_mode': _supportBillingMode,
        'support_free_quota_per_month': _supportFreeQuotaPerMonth,
        'support_grace_period_days': _supportGracePeriodDays,
        'support_allow_read_without_subscription': _supportAllowReadWithoutSub,
        'support_require_subscription_to_reply': _supportRequireSubToReply,
        'support_invoice_prefix': _supportInvoicePrefixCtrl.text.trim(),
        'support_paid_priority_boost': _supportPaidPriorityBoost,
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
      };
      const sections = <List<String>>[
        [
          'app_name',
          'app_version',
          'default_language',
          'default_theme',
          'default_theme_id',
          'default_timezone',
          'enable_maintenance_mode',
          'max_file_size',
          'max_users',
        ],
        [
          'enable_registration',
          'enable_email_verification',
          'session_timeout',
          'mcp_oauth_session_days',
          'business_creation_verification_requirement',
          'legacy_api_import_enabled',
          'legacy_api_import_disabled_message',
        ],
        [
          'support_tickets_enabled',
          'support_tickets_disabled_message',
          'support_billing_mode',
          'support_free_quota_per_month',
          'support_grace_period_days',
          'support_allow_read_without_subscription',
          'support_require_subscription_to_reply',
          'support_invoice_prefix',
          'support_paid_priority_boost',
        ],
        [
          'sms_destination_rate_enabled',
          'sms_destination_rate_max_sends',
          'sms_destination_rate_window_minutes',
          'captcha_max_attempts',
          'captcha_length',
          'captcha_ttl_seconds',
          'captcha_mode',
          'captcha_bind_ip',
          'captcha_strong_image',
          'captcha_rate_max',
          'captcha_rate_window_sec',
          'login_rate_max_short',
          'login_rate_window_short_sec',
          'login_rate_max_long',
          'login_rate_window_long_sec',
          'register_rate_max',
          'register_rate_window_sec',
          'forgot_password_rate_max',
          'forgot_password_rate_window_sec',
          'reset_password_rate_max',
          'reset_password_rate_window_sec',
          'password_reset_otp_rate_max',
          'password_reset_otp_rate_window_sec',
          'login_backoff_max_fails',
          'login_backoff_window_minutes',
          'login_backoff_seconds',
          'firewall_auto_ban_on_login_fail',
          'firewall_auto_ban_duration_sec',
        ],
      ];
      final keys = sections[_configSection];
      await _service.updateSystemConfiguration({
        for (final key in keys) key: all[key],
      });

      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showSuccess(context, message: t.settingsSavedSuccessfully);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        final err = ErrorExtractor.forContext(e, context);
        SnackBarHelper.showError(context, message: '${t.errorSavingSettings}: $err');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
