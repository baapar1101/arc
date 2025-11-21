import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/notifications_service.dart';
import '../../services/telegram_integration_service.dart';
import 'package:intl/intl.dart';

class UserNotificationsPage extends StatefulWidget {
  const UserNotificationsPage({super.key});

  @override
  State<UserNotificationsPage> createState() => _UserNotificationsPageState();
}

class _UserNotificationsPageState extends State<UserNotificationsPage> {
  final _svc = NotificationsService(ApiClient());
  final _telegramSvc = TelegramIntegrationService(ApiClient());
  bool _loading = true;
  String? _error;
  bool _telegram = true;
  bool _email = true;
  bool _sms = true;
  bool _inapp = true;
  bool _saving = false;
  // Telegram connection state
  bool _telegramLinked = false;
  String? _telegramConnectedAt;
  bool _telegramLoading = false;
  bool _telegramConnecting = false;
  String? _telegramLinkToken;
  String? _telegramDeepLink;
  DateTime? _telegramLinkExpiresAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final s = await _svc.getSettings();
      await _loadTelegramStatus();
      if (!mounted) return;
      setState(() {
        _telegram = (s['telegram_enabled'] ?? true) == true;
        _email = (s['email_enabled'] ?? true) == true;
        _sms = (s['sms_enabled'] ?? true) == true;
        _inapp = (s['inapp_enabled'] ?? true) == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadTelegramStatus() async {
    try {
      setState(() => _telegramLoading = true);
      final status = await _telegramSvc.getStatus();
      if (!mounted) return;
      setState(() {
        _telegramLinked = status['linked'] == true;
        _telegramConnectedAt = status['connected_at']?.toString();
        _telegramLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _telegramLinked = false;
        _telegramLoading = false;
      });
    }
  }

  Future<void> _connectTelegram(AppLocalizations t) async {
    try {
      setState(() => _telegramConnecting = true);
      final linkData = await _telegramSvc.createLink();
      if (!mounted) return;
      setState(() {
        _telegramLinkToken = linkData['link_token']?.toString();
        _telegramDeepLink = linkData['deep_link']?.toString();
        final expiresAtStr = linkData['expires_at']?.toString();
        if (expiresAtStr != null) {
          _telegramLinkExpiresAt = DateTime.tryParse(expiresAtStr);
        }
        _telegramConnecting = false;
      });
      _pollTelegramStatus(t);
    } catch (e) {
      if (!mounted) return;
      setState(() => _telegramConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.notificationsTelegramConnectionError}\n$e')),
      );
    }
  }

  Future<void> _pollTelegramStatus(AppLocalizations t) async {
    int attempts = 0;
    const maxAttempts = 120;
    while (attempts < maxAttempts && mounted) {
      await Future.delayed(const Duration(seconds: 5));
      await _loadTelegramStatus();
      if (_telegramLinked) {
        setState(() {
          _telegramLinkToken = null;
          _telegramDeepLink = null;
          _telegramLinkExpiresAt = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.notificationsTelegramConnectionSuccess)),
        );
        break;
      }
      attempts++;
    }
    if (!_telegramLinked && mounted) {
      setState(() {
        _telegramLinkToken = null;
        _telegramDeepLink = null;
        _telegramLinkExpiresAt = null;
      });
    }
  }

  Future<void> _disconnectTelegram(AppLocalizations t) async {
    try {
      setState(() => _telegramLoading = true);
      await _telegramSvc.unlink();
      if (!mounted) return;
      setState(() {
        _telegramLinked = false;
        _telegramConnectedAt = null;
        _telegramLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.notificationsTelegramDisconnectSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _telegramLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.notificationsTelegramDisconnectError}\n$e')),
      );
    }
  }

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
      ),
      _ChannelOption(
        key: 'email',
        enabled: _email,
        icon: Icons.email_outlined,
        title: t.notificationsChannelEmail,
        description: t.notificationsChannelEmailDescription,
        onChanged: (v) => setState(() => _email = v),
      ),
      _ChannelOption(
        key: 'sms',
        enabled: _sms,
        icon: Icons.sms_outlined,
        title: t.notificationsChannelSms,
        description: t.notificationsChannelSmsDescription,
        onChanged: (v) => setState(() => _sms = v),
      ),
      _ChannelOption(
        key: 'inapp',
        enabled: _inapp,
        icon: Icons.notifications_active_outlined,
        title: t.notificationsChannelInApp,
        description: t.notificationsChannelInAppDescription,
        onChanged: (v) => setState(() => _inapp = v),
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
            if (options[i].key == 'telegram') ...[
              _buildTelegramChannelTile(t, theme, colorScheme, options[i]),
            ] else ...[
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
            ],
            if (i != options.length - 1) const Divider(height: 1),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTelegramChannelTile(AppLocalizations t, ThemeData theme, ColorScheme colorScheme, _ChannelOption option) {
    return Column(
      children: [
        SwitchListTile.adaptive(
          value: option.enabled,
          onChanged: option.onChanged,
          title: Text(option.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(option.description),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _telegramLinked ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: _telegramLinked ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _telegramLinked ? t.notificationsTelegramConnected : t.notificationsTelegramNotConnected,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _telegramLinked ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_telegramLinked && _telegramConnectedAt != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.notificationsTelegramConnectedSince(
                          DateFormat('yyyy/MM/dd').format(DateTime.parse(_telegramConnectedAt!)),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (option.enabled && !_telegramLinked) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.notificationsTelegramConnectionWarning,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          secondary: Icon(
            option.icon,
            color: option.enabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          activeColor: colorScheme.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (_telegramLinked) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _telegramLoading ? null : () => _disconnectTelegram(t),
                    icon: _telegramLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link_off, size: 18),
                    label: Text(t.notificationsTelegramDisconnectButton),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_telegramConnecting || _telegramLoading) ? null : () => _connectTelegram(t),
                    icon: _telegramConnecting || _telegramLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link, size: 18),
                    label: Text(_telegramConnecting ? t.notificationsTelegramConnecting : t.notificationsTelegramConnectButton),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_telegramLinkToken != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.notificationsTelegramLinkInstructions(_telegramLinkToken!),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_telegramDeepLink != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _telegramDeepLink!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: t.copyLink,
                          onPressed: () => _copyToClipboard(_telegramDeepLink!, t.copied),
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                        ),
                      ],
                    ),
                  ],
                  if (_telegramLinkExpiresAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      t.notificationsTelegramLinkExpiresIn(
                        _telegramLinkExpiresAt!.difference(DateTime.now()).inMinutes,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
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
  });

  final String key;
  final bool enabled;
  final IconData icon;
  final String title;
  final String description;
  final ValueChanged<bool> onChanged;
}

