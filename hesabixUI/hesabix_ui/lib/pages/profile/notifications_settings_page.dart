import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/notifications_service.dart';
import '../../services/admin_system_settings_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  State<NotificationsSettingsPage> createState() => _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  final _svc = NotificationsService(ApiClient());
  final _adminSvc = AdminSystemSettingsService(ApiClient());
  bool _loading = true;
  String? _error;
  bool _telegram = true;
  bool _bale = true;
  bool _email = true;
  bool _sms = true;
  bool _inapp = true;
  bool _saving = false;
  // Admin advanced config
  final _tgTokenCtrl = TextEditingController();
  final _tgUsernameCtrl = TextEditingController();
  final _tgWebhookSecretCtrl = TextEditingController();
  final _tgSecretHeaderCtrl = TextEditingController();
  final _tgProxyBaseUrlCtrl = TextEditingController();
  final _tgProxyApiKeyCtrl = TextEditingController();
  final _baleTokenCtrl = TextEditingController();
  final _baleUsernameCtrl = TextEditingController();
  final _baleWebhookSecretCtrl = TextEditingController();
  final _smsProviderCtrl = TextEditingController();
  final _smsApiKeyCtrl = TextEditingController();
  final _smsSenderCtrl = TextEditingController();
  final _smsUsernameCtrl = TextEditingController();
  final _smsPasswordCtrl = TextEditingController();
  bool _smsIsFlash = false;
  String? _selectedSmsProvider;
  bool _smsProviderIsCustom = false;
  
  // لیست provider های از پیش تعریف شده
  static const List<String> _predefinedSmsProviders = [
    'behinsms',
    'behin_sms',
  ];
  static const String _customProviderValue = '__custom__';
  bool _adminLoading = true;
  bool _adminSaving = false;
  bool _webhookRegistering = false;
  bool? _webhookLastOk;
  String? _webhookLastMessage;
  String? _webhookLastUrl;
  bool _baleWebhookRegistering = false;
  bool? _baleWebhookLastOk;
  String? _baleWebhookLastMessage;
  String? _baleWebhookLastUrl;
  bool _tgProxyEnabled = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    _load();
  }

  void _checkAdminAccess() {
    final authStore = ApiClient.getAuthStore();
    if (authStore != null) {
      _isAdmin = authStore.isSuperAdmin || authStore.hasAppPermission('system_settings');
    }
  }

  @override
  void dispose() {
    _tgTokenCtrl.dispose();
    _tgUsernameCtrl.dispose();
    _tgWebhookSecretCtrl.dispose();
    _tgSecretHeaderCtrl.dispose();
    _tgProxyBaseUrlCtrl.dispose();
    _tgProxyApiKeyCtrl.dispose();
    _baleTokenCtrl.dispose();
    _baleUsernameCtrl.dispose();
    _baleWebhookSecretCtrl.dispose();
    _smsProviderCtrl.dispose();
    _smsApiKeyCtrl.dispose();
    _smsSenderCtrl.dispose();
    _smsUsernameCtrl.dispose();
    _smsPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final s = await _svc.getSettings();
      bool proxyEnabled = _tgProxyEnabled;
      // Load admin config (ignore errors silently if no permission)
      try {
        final admin = await _adminSvc.getNotificationsConfig();
        _tgTokenCtrl.text = '${admin['telegram_bot_token'] ?? ''}';
        _tgUsernameCtrl.text = '${admin['telegram_bot_username'] ?? ''}';
        _tgWebhookSecretCtrl.text = '${admin['telegram_webhook_secret'] ?? ''}';
        _tgSecretHeaderCtrl.text = '${admin['telegram_secret_header'] ?? ''}';
        _tgProxyBaseUrlCtrl.text = '${admin['telegram_proxy_base_url'] ?? ''}';
        _tgProxyApiKeyCtrl.text = '${admin['telegram_proxy_api_key'] ?? ''}';
        proxyEnabled = (admin['telegram_proxy_enabled'] ?? false) == true;
        _baleTokenCtrl.text = '${admin['bale_bot_token'] ?? ''}';
        _baleUsernameCtrl.text = '${admin['bale_bot_username'] ?? ''}';
        _baleWebhookSecretCtrl.text = '${admin['bale_webhook_secret'] ?? ''}';
        final providerName = '${admin['sms_provider_name'] ?? ''}';
        _smsApiKeyCtrl.text = '${admin['sms_api_key'] ?? ''}';
        _smsSenderCtrl.text = '${admin['sms_sender'] ?? ''}';
        _smsUsernameCtrl.text = '${admin['sms_provider_username'] ?? ''}';
        _smsPasswordCtrl.text = '${admin['sms_provider_password'] ?? ''}';
        _smsIsFlash = (admin['sms_is_flash'] ?? false) == true;
        
        // بررسی اینکه provider در لیست از پیش تعریف شده است یا نه
        if (providerName.isNotEmpty && _predefinedSmsProviders.contains(providerName)) {
          _selectedSmsProvider = providerName;
          _smsProviderIsCustom = false;
          _smsProviderCtrl.text = '';
        } else if (providerName.isNotEmpty) {
          _selectedSmsProvider = _customProviderValue;
          _smsProviderIsCustom = true;
          _smsProviderCtrl.text = providerName;
        } else {
          _selectedSmsProvider = null;
          _smsProviderIsCustom = false;
          _smsProviderCtrl.text = '';
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _telegram = (s['telegram_enabled'] ?? true) == true;
        _bale = (s['bale_enabled'] ?? true) == true;
        _email = (s['email_enabled'] ?? true) == true;
        _sms = (s['sms_enabled'] ?? true) == true;
        _inapp = (s['inapp_enabled'] ?? true) == true;
        _tgProxyEnabled = proxyEnabled;
        _loading = false;
        _adminLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
        _adminLoading = false;
      });
    }
  }

  static const String _defaultRealtimeEndpoint = 'wss://api.hesabix.com/ws/notifications';

  Future<void> _save(AppLocalizations t) async {
    setState(() => _saving = true);
    try {
      await _svc.updateSettings(
        telegramEnabled: _telegram,
        baleEnabled: _bale,
        emailEnabled: _email,
        smsEnabled: _sms,
        inappEnabled: _inapp,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.notificationsSaveSuccess);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            '${t.notificationsSaveError}\n${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _testChannel(String channel, String channelLabel, AppLocalizations t) async {
    try {
      await _svc.sendTest(channel);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.notificationsTestSuccess(channelLabel));
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: '${t.notificationsTestError(channelLabel)}');
    }
  }

  Future<void> _saveAdvanced(AppLocalizations t) async {
    setState(() => _adminSaving = true);
    try {
      await _adminSvc.putNotificationsConfig(_collectAdvancedPayload());
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.notificationsAdvancedSaveSuccess);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            '${t.notificationsAdvancedSaveError}\n${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (!mounted) return;
      setState(() => _adminSaving = false);
    }
  }

  Future<void> _registerTelegramWebhook(AppLocalizations t) async {
    setState(() => _webhookRegistering = true);
    try {
      final res = await _adminSvc.registerTelegramWebhook();
      final ok = (res['ok'] ?? false) == true;
      final description = res['description']?.toString();
      final webhookUrl = res['webhook_url']?.toString();
      if (!mounted) return;
      setState(() {
        _webhookLastOk = ok;
        _webhookLastMessage = description?.isNotEmpty == true ? description : null;
        _webhookLastUrl = webhookUrl;
      });
      if (ok) {
        SnackBarHelper.show(context, message: t.notificationsTelegramConnectionSuccess);
      } else {
        final msg = description?.isNotEmpty == true ? description! : t.notificationsTelegramConnectionError;
        SnackBarHelper.showError(context, message: msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _webhookLastOk = false;
        _webhookLastMessage = ErrorExtractor.userMessage(e);
      });
      SnackBarHelper.showError(
        context,
        message:
            '${t.notificationsTelegramConnectionError}\n${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (!mounted) return;
      setState(() => _webhookRegistering = false);
    }
  }

  Future<void> _registerBaleWebhook(AppLocalizations t) async {
    setState(() => _baleWebhookRegistering = true);
    try {
      final res = await _adminSvc.registerBaleWebhook();
      final ok = (res['ok'] ?? false) == true;
      final description = res['description']?.toString();
      final webhookUrl = res['webhook_url']?.toString();
      if (!mounted) return;
      setState(() {
        _baleWebhookLastOk = ok;
        _baleWebhookLastMessage = description?.isNotEmpty == true ? description : null;
        _baleWebhookLastUrl = webhookUrl;
      });
      if (ok) {
        SnackBarHelper.show(context, message: t.notificationsBaleConnectionSuccess);
      } else {
        final msg = description?.isNotEmpty == true ? description! : t.notificationsBaleConnectionError;
        SnackBarHelper.showError(context, message: msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _baleWebhookLastOk = false;
        _baleWebhookLastMessage = ErrorExtractor.userMessage(e);
      });
      SnackBarHelper.showError(
        context,
        message:
            '${t.notificationsBaleConnectionError}\n${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (!mounted) return;
      setState(() => _baleWebhookRegistering = false);
    }
  }

  Map<String, dynamic> _collectAdvancedPayload() {
    // تعیین نام provider: اگر custom است از TextField، وگرنه از dropdown
    String providerName = '';
    if (_selectedSmsProvider == _customProviderValue) {
      providerName = _smsProviderCtrl.text.trim();
    } else if (_selectedSmsProvider != null) {
      providerName = _selectedSmsProvider!;
    }
    
    return {
      'telegram_bot_token': _tgTokenCtrl.text.trim(),
      'telegram_bot_username': _tgUsernameCtrl.text.trim(),
      'telegram_webhook_secret': _tgWebhookSecretCtrl.text.trim(),
      'telegram_secret_header': _tgSecretHeaderCtrl.text.trim(),
      'telegram_proxy_enabled': _tgProxyEnabled,
      'telegram_proxy_base_url': _tgProxyBaseUrlCtrl.text.trim(),
      'telegram_proxy_api_key': _tgProxyApiKeyCtrl.text.trim(),
      'bale_bot_token': _baleTokenCtrl.text.trim(),
      'bale_bot_username': _baleUsernameCtrl.text.trim(),
      'bale_webhook_secret': _baleWebhookSecretCtrl.text.trim(),
      'sms_provider_name': providerName,
      'sms_api_key': _smsApiKeyCtrl.text.trim(),
      'sms_sender': _smsSenderCtrl.text.trim(),
      'sms_provider_username': _smsUsernameCtrl.text.trim(),
      'sms_provider_password': _smsPasswordCtrl.text.trim(),
      'sms_is_flash': _smsIsFlash,
    };
  }

  Future<void> _copyToClipboard(String value, String confirmationMessage) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    SnackBarHelper.show(context, message: confirmationMessage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 8),
            Text('${t.dataLoadingError}\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: Text(t.retry)),
          ],
        ),
      );
    }


    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(t, theme, colorScheme),
          const SizedBox(height: 16),
          _buildTelegramCard(t, theme, colorScheme),
          const SizedBox(height: 16),
          _buildBaleCard(t, theme, colorScheme),
          const SizedBox(height: 16),
          _buildEmailCard(t, theme, colorScheme),
          const SizedBox(height: 16),
          _buildSmsCard(t, theme, colorScheme),
          const SizedBox(height: 16),
          _buildInAppCard(t, theme, colorScheme),
          const SizedBox(height: 16),
          _buildRealtimeCard(t, theme, colorScheme, _defaultRealtimeEndpoint),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.notificationsSettingsTitle,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                t.notificationsSettingsSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(t),
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(t.save),
        ),
      ],
    );
  }

  Widget _buildTelegramCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _telegram,
            onChanged: (v) => setState(() => _telegram = v),
            title: Text(t.notificationsChannelTelegram),
            subtitle: Text(t.notificationsChannelTelegramDescription),
            secondary: Icon(
              Icons.telegram,
              color: _telegram ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            activeColor: colorScheme.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          if (_telegram) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // دکمه تست
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _testChannel('telegram', t.notificationsChannelTelegram, t),
                      icon: const Icon(Icons.send_outlined, size: 20),
                      label: Text(t.notificationsTestButton(t.notificationsChannelTelegram)),
                    ),
                  ),
                  // تنظیمات پیشرفته ادمین
                  if (_isAdmin) ...[
                    const SizedBox(height: 24),
                    _buildTelegramAdvancedSection(t, theme, colorScheme),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBaleCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _bale,
            onChanged: (v) => setState(() => _bale = v),
            title: Text(t.notificationsChannelBale),
            subtitle: Text(t.notificationsChannelBaleDescription),
            secondary: Icon(
              Icons.chat_bubble_outline,
              color: _bale ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            activeColor: colorScheme.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          if (_bale) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _testChannel('bale', t.notificationsChannelBale, t),
                      icon: const Icon(Icons.send_outlined, size: 20),
                      label: Text(t.notificationsTestButton(t.notificationsChannelBale)),
                    ),
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(height: 24),
                    _buildBaleAdvancedSection(t, theme, colorScheme),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmailCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _email,
            onChanged: (v) => setState(() => _email = v),
            title: Text(t.notificationsChannelEmail),
            subtitle: Text(t.notificationsChannelEmailDescription),
            secondary: Icon(
              Icons.email_outlined,
              color: _email ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            activeColor: colorScheme.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          if (_email) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _testChannel('email', t.notificationsChannelEmail, t),
                  icon: const Icon(Icons.send_outlined, size: 20),
                  label: Text(t.notificationsTestButton(t.notificationsChannelEmail)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmsCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _sms,
            onChanged: (v) => setState(() => _sms = v),
            title: Text(t.notificationsChannelSms),
            subtitle: Text(t.notificationsChannelSmsDescription),
            secondary: Icon(
              Icons.sms_outlined,
              color: _sms ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            activeColor: colorScheme.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          if (_sms) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // دکمه تست
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _testChannel('sms', t.notificationsChannelSms, t),
                      icon: const Icon(Icons.send_outlined, size: 20),
                      label: Text(t.notificationsTestButton(t.notificationsChannelSms)),
                    ),
                  ),
                  // تنظیمات پیشرفته ادمین
                  if (_isAdmin) ...[
                    const SizedBox(height: 24),
                    _buildSmsAdvancedSection(t, theme, colorScheme),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInAppCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _inapp,
            onChanged: (v) => setState(() => _inapp = v),
            title: Text(t.notificationsChannelInApp),
            subtitle: Text(t.notificationsChannelInAppDescription),
            secondary: Icon(
              Icons.notifications_active_outlined,
              color: _inapp ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            activeColor: colorScheme.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          if (_inapp) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _testChannel('inapp', t.notificationsChannelInApp, t),
                  icon: const Icon(Icons.send_outlined, size: 20),
                  label: Text(t.notificationsTestButton(t.notificationsChannelInApp)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTelegramAdvancedSection(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(Icons.admin_panel_settings_outlined, color: colorScheme.primary),
        title: Text(
          'تنظیمات پیشرفته تلگرام',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'تنظیمات ادمین برای پیکربندی تلگرام',
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (_adminLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Column(
              children: [
                _buildCredentialField(_tgTokenCtrl, t.notificationsFieldTelegramToken, helper: t.notificationsFieldTelegramTokenHint),
                const SizedBox(height: 12),
                _buildCredentialField(_tgUsernameCtrl, t.notificationsFieldTelegramUsername),
                const SizedBox(height: 12),
                _buildCredentialField(_tgWebhookSecretCtrl, t.notificationsFieldTelegramWebhookSecret, helper: t.notificationsFieldTelegramWebhookSecretHint),
                const SizedBox(height: 12),
                _buildCredentialField(_tgSecretHeaderCtrl, t.notificationsFieldTelegramSecretHeader),
              ],
            ),
            const SizedBox(height: 12),
            _buildWebhookControls(t, theme, colorScheme),
            const SizedBox(height: 24),
            _buildProxySection(t, theme, colorScheme),
            const SizedBox(height: 16),
            Text(
              t.notificationsAdvancedRestartHint,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _adminSaving ? null : () => _saveAdvanced(t),
                icon: _adminSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(t.notificationsAdvancedSave),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBaleAdvancedSection(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(Icons.admin_panel_settings_outlined, color: colorScheme.primary),
        title: Text(
          t.notificationsBaleAdvancedTitle,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          t.notificationsBaleAdvancedSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (_adminLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Column(
              children: [
                _buildCredentialField(_baleTokenCtrl, t.notificationsFieldBaleToken, helper: t.notificationsFieldBaleTokenHint),
                const SizedBox(height: 12),
                _buildCredentialField(_baleUsernameCtrl, t.notificationsFieldBaleUsername),
                const SizedBox(height: 12),
                _buildCredentialField(_baleWebhookSecretCtrl, t.notificationsFieldBaleWebhookSecret),
              ],
            ),
            const SizedBox(height: 16),
            _buildBaleWebhookControls(t, theme, colorScheme),
            const SizedBox(height: 16),
            Text(
              t.notificationsAdvancedRestartHint,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _adminSaving ? null : () => _saveAdvanced(t),
                icon: _adminSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(t.notificationsAdvancedSave),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmsAdvancedSection(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(Icons.admin_panel_settings_outlined, color: colorScheme.primary),
        title: Text(
          'تنظیمات پیشرفته پیامک',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'تنظیمات ادمین برای پیکربندی SMS',
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (_adminLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Column(
              children: [
                // Dropdown برای انتخاب Provider
                DropdownButtonFormField<String>(
                  value: _selectedSmsProvider,
                  decoration: InputDecoration(
                    labelText: t.notificationsFieldSmsProvider,
                    helperText: 'انتخاب provider از لیست یا وارد کردن نام دلخواه',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    ..._predefinedSmsProviders.map((provider) => DropdownMenuItem(
                      value: provider,
                      child: Text(provider),
                    )),
                    const DropdownMenuItem(
                      value: _customProviderValue,
                      child: Text('سایر (Custom)'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSmsProvider = value;
                      _smsProviderIsCustom = (value == _customProviderValue);
                      if (!_smsProviderIsCustom) {
                        _smsProviderCtrl.text = '';
                      }
                    });
                  },
                ),
                // TextField برای Custom Provider
                if (_smsProviderIsCustom) ...[
                  const SizedBox(height: 12),
                  _buildCredentialField(
                    _smsProviderCtrl, 
                    'نام Provider (Custom)',
                    helper: 'نام provider دلخواه را وارد کنید',
                  ),
                ],
                const SizedBox(height: 12),
                _buildCredentialField(_smsApiKeyCtrl, t.notificationsFieldSmsApiKey, helper: t.notificationsFieldSmsApiKeyHint),
                const SizedBox(height: 12),
                _buildCredentialField(_smsSenderCtrl, t.notificationsFieldSmsSender, helper: t.notificationsFieldSmsSenderHint),
                const SizedBox(height: 12),
                _buildCredentialField(_smsUsernameCtrl, 'نام کاربری SMS Provider'),
                const SizedBox(height: 12),
                TextField(
                  controller: _smsPasswordCtrl,
                  decoration: InputDecoration(
                    labelText: 'کلمه عبور SMS Provider',
                    helperText: 'کلمه عبور حساب بهین اس ام اس',
                    border: const OutlineInputBorder(),
                  ),
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.next,
                  enableSuggestions: false,
                  autocorrect: false,
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _smsIsFlash,
                  onChanged: (val) => setState(() {
                    _smsIsFlash = val;
                  }),
                  title: const Text('ارسال Flash Message'),
                  subtitle: const Text('پیامک بدون ذخیره در حافظه نمایش داده می‌شود'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              t.notificationsAdvancedRestartHint,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _adminSaving ? null : () => _saveAdvanced(t),
                icon: _adminSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(t.notificationsAdvancedSave),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRealtimeCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme, String endpoint) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.notificationsWebsocketInfoTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              t.notificationsWebsocketInfoDescription(endpoint),
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.code, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      endpoint,
                      style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    tooltip: t.copyLink,
                    onPressed: () => _copyToClipboard(endpoint, t.copied),
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCredentialField(TextEditingController controller, String label, {String? helper}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      textDirection: TextDirection.ltr,
      textInputAction: TextInputAction.next,
      enableSuggestions: false,
      autocorrect: false,
    );
  }

  Widget _buildBaleWebhookControls(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    final statusColor = _baleWebhookLastOk == true ? colorScheme.primary : colorScheme.error;
    final backgroundColor = (_baleWebhookLastOk == true ? colorScheme.primaryContainer : colorScheme.errorContainer).withValues(alpha: 0.3);
    final statusText = _baleWebhookLastOk == true ? t.notificationsBaleConnected : t.notificationsBaleConnectionError;
    final displayMessage = _baleWebhookLastMessage?.isNotEmpty == true ? _baleWebhookLastMessage! : statusText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: _baleWebhookRegistering ? null : () => _registerBaleWebhook(t),
          icon: _baleWebhookRegistering
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link_outlined),
          label: Text(t.notificationsBaleConnectButton),
        ),
        if (_baleWebhookLastOk != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _baleWebhookLastOk == true ? Icons.check_circle_outline : Icons.error_outline,
                      color: statusColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (_baleWebhookLastUrl?.isNotEmpty == true)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _baleWebhookLastUrl!,
                            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          tooltip: t.copyLink,
                          onPressed: () => _copyToClipboard(_baleWebhookLastUrl!, t.copied),
                          icon: const Icon(Icons.copy_all_outlined),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildWebhookControls(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    final statusColor = _webhookLastOk == true ? colorScheme.primary : colorScheme.error;
    final backgroundColor = (_webhookLastOk == true ? colorScheme.primaryContainer : colorScheme.errorContainer).withValues(alpha: 0.3);
    final statusText = _webhookLastOk == true ? t.notificationsTelegramConnected : t.notificationsTelegramConnectionError;
    final displayMessage = _webhookLastMessage?.isNotEmpty == true ? _webhookLastMessage! : statusText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: _webhookRegistering ? null : () => _registerTelegramWebhook(t),
          icon: _webhookRegistering
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link_outlined),
          label: Text(t.notificationsTelegramConnectButton),
        ),
        if (_webhookLastOk != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _webhookLastOk == true ? Icons.check_circle_outline : Icons.error_outline,
                      color: statusColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (_webhookLastUrl?.isNotEmpty == true)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _webhookLastUrl!,
                            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          tooltip: t.copyLink,
                          onPressed: () => _copyToClipboard(_webhookLastUrl!, t.copied),
                          icon: const Icon(Icons.copy_all_outlined),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildProxySection(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    final showFields = _tgProxyEnabled || _tgProxyBaseUrlCtrl.text.isNotEmpty || _tgProxyApiKeyCtrl.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.notificationsProxySectionTitle,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          t.notificationsProxySectionSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          value: _tgProxyEnabled,
          onChanged: (val) => setState(() {
            _tgProxyEnabled = val;
          }),
          title: Text(t.notificationsProxyEnableLabel),
          contentPadding: EdgeInsets.zero,
        ),
        if (showFields) ...[
          const SizedBox(height: 12),
          _buildCredentialField(_tgProxyBaseUrlCtrl, t.notificationsFieldTelegramProxyBaseUrl),
          const SizedBox(height: 12),
          _buildCredentialField(_tgProxyApiKeyCtrl, t.notificationsFieldTelegramProxyApiKey),
        ],
      ],
    );
  }
}

