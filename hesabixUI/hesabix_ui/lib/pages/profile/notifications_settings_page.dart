import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/notifications_service.dart';
import '../../services/admin_system_settings_service.dart';

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
  bool _email = true;
  bool _sms = true;
  bool _inapp = true;
  bool _saving = false;
  // Admin advanced config
  final _tgTokenCtrl = TextEditingController();
  final _tgUsernameCtrl = TextEditingController();
  final _tgWebhookSecretCtrl = TextEditingController();
  final _tgSecretHeaderCtrl = TextEditingController();
  final _smsProviderCtrl = TextEditingController();
  final _smsApiKeyCtrl = TextEditingController();
  final _smsSenderCtrl = TextEditingController();
  bool _adminLoading = true;
  bool _adminSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tgTokenCtrl.dispose();
    _tgUsernameCtrl.dispose();
    _tgWebhookSecretCtrl.dispose();
    _tgSecretHeaderCtrl.dispose();
    _smsProviderCtrl.dispose();
    _smsApiKeyCtrl.dispose();
    _smsSenderCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final s = await _svc.getSettings();
      // Load admin config (ignore errors silently if no permission)
      try {
        final admin = await _adminSvc.getNotificationsConfig();
        _tgTokenCtrl.text = '${admin['telegram_bot_token'] ?? ''}';
        _tgUsernameCtrl.text = '${admin['telegram_bot_username'] ?? ''}';
        _tgWebhookSecretCtrl.text = '${admin['telegram_webhook_secret'] ?? ''}';
        _tgSecretHeaderCtrl.text = '${admin['telegram_secret_header'] ?? ''}';
        _smsProviderCtrl.text = '${admin['sms_provider_name'] ?? ''}';
        _smsApiKeyCtrl.text = '${admin['sms_api_key'] ?? ''}';
        _smsSenderCtrl.text = '${admin['sms_sender'] ?? ''}';
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _telegram = (s['telegram_enabled'] ?? true) == true;
        _email = (s['email_enabled'] ?? true) == true;
        _sms = (s['sms_enabled'] ?? true) == true;
        _inapp = (s['inapp_enabled'] ?? true) == true;
        _loading = false;
        _adminLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _adminLoading = false;
      });
    }
  }

  static const String _defaultRealtimeEndpoint = 'wss://api.hesabix.com/ws/notifications?api_key=YOUR_API_KEY';

  Future<void> _save(AppLocalizations t) async {
    setState(() => _saving = true);
    try {
      await _svc.updateSettings(
        telegramEnabled: _telegram,
        emailEnabled: _email,
        smsEnabled: _sms,
        inappEnabled: _inapp,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.notificationsSaveSuccess)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.notificationsSaveError}\n$e')));
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _testChannel(String channel, String channelLabel, AppLocalizations t) async {
    try {
      await _svc.sendTest(channel);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.notificationsTestSuccess(channelLabel))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.notificationsTestError(channelLabel)}\n$e')));
    }
  }

  Future<void> _saveAdvanced(AppLocalizations t) async {
    setState(() => _adminSaving = true);
    try {
      await _adminSvc.putNotificationsConfig(_collectAdvancedPayload());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.notificationsAdvancedSaveSuccess)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.notificationsAdvancedSaveError}\n$e')));
    } finally {
      if (!mounted) return;
      setState(() => _adminSaving = false);
    }
  }

  Map<String, dynamic> _collectAdvancedPayload() {
    return {
      'telegram_bot_token': _tgTokenCtrl.text.trim(),
      'telegram_bot_username': _tgUsernameCtrl.text.trim(),
      'telegram_webhook_secret': _tgWebhookSecretCtrl.text.trim(),
      'telegram_secret_header': _tgSecretHeaderCtrl.text.trim(),
      'sms_provider_name': _smsProviderCtrl.text.trim(),
      'sms_api_key': _smsApiKeyCtrl.text.trim(),
      'sms_sender': _smsSenderCtrl.text.trim(),
    };
  }

  Future<void> _copyToClipboard(String value, String confirmationMessage) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(confirmationMessage)));
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

    final channelOptions = <_ChannelOption>[
      _ChannelOption(
        key: 'telegram',
        enabled: _telegram,
        icon: Icons.telegram,
        title: t.notificationsChannelTelegram,
        description: t.notificationsChannelTelegramDescription,
        onChanged: (v) => setState(() => _telegram = v),
        onTest: () => _testChannel('telegram', t.notificationsChannelTelegram, t),
      ),
      _ChannelOption(
        key: 'email',
        enabled: _email,
        icon: Icons.email_outlined,
        title: t.notificationsChannelEmail,
        description: t.notificationsChannelEmailDescription,
        onChanged: (v) => setState(() => _email = v),
        onTest: () => _testChannel('email', t.notificationsChannelEmail, t),
      ),
      _ChannelOption(
        key: 'sms',
        enabled: _sms,
        icon: Icons.sms_outlined,
        title: t.notificationsChannelSms,
        description: t.notificationsChannelSmsDescription,
        onChanged: (v) => setState(() => _sms = v),
        onTest: () => _testChannel('sms', t.notificationsChannelSms, t),
      ),
      _ChannelOption(
        key: 'inapp',
        enabled: _inapp,
        icon: Icons.notifications_active_outlined,
        title: t.notificationsChannelInApp,
        description: t.notificationsChannelInAppDescription,
        onChanged: (v) => setState(() => _inapp = v),
        onTest: () => _testChannel('inapp', t.notificationsChannelInApp, t),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(t, theme, colorScheme),
          const SizedBox(height: 16),
          _buildChannelsCard(t, theme, colorScheme, channelOptions),
          const SizedBox(height: 16),
          _buildTestCard(t, theme, colorScheme, channelOptions),
          const SizedBox(height: 16),
          _buildRealtimeCard(t, theme, colorScheme, _defaultRealtimeEndpoint),
          const SizedBox(height: 16),
          _buildAdvancedSection(t, theme, colorScheme),
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

  Widget _buildChannelsCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme, List<_ChannelOption> options) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.notificationsChannelsSectionTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  t.notificationsChannelsSectionSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < options.length; i++) ...[
            SwitchListTile.adaptive(
              value: options[i].enabled,
              onChanged: options[i].onChanged,
              title: Text(options[i].title),
              subtitle: Text(options[i].description),
              secondary: Icon(
                options[i].icon,
                color: options[i].enabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              activeColor: colorScheme.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (i != options.length - 1) const Divider(height: 1),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTestCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme, List<_ChannelOption> options) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.notificationsTestSectionTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              t.notificationsTestSectionSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final option in options)
                  OutlinedButton.icon(
                    onPressed: option.enabled ? () => option.onTest() : null,
                    icon: Icon(option.icon, size: 20),
                    label: Text(t.notificationsTestButton(option.title)),
                  ),
              ],
            ),
          ],
        ),
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

  Widget _buildAdvancedSection(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.admin_panel_settings_outlined, color: colorScheme.primary),
          title: Text(t.notificationsAdvancedSectionTitle, style: theme.textTheme.titleMedium),
          subtitle: Text(
            t.notificationsAdvancedSectionSubtitle,
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
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  t.notificationsAdvancedTelegramHeader,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 24),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  t.notificationsAdvancedSmsHeader,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  _buildCredentialField(_smsProviderCtrl, t.notificationsFieldSmsProvider),
                  const SizedBox(height: 12),
                  _buildCredentialField(_smsApiKeyCtrl, t.notificationsFieldSmsApiKey, helper: t.notificationsFieldSmsApiKeyHint),
                  const SizedBox(height: 12),
                  _buildCredentialField(_smsSenderCtrl, t.notificationsFieldSmsSender, helper: t.notificationsFieldSmsSenderHint),
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
}

class _ChannelOption {
  const _ChannelOption({
    required this.key,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.description,
    required this.onChanged,
    required this.onTest,
  });

  final String key;
  final bool enabled;
  final IconData icon;
  final String title;
  final String description;
  final ValueChanged<bool> onChanged;
  final Future<void> Function() onTest;
}
