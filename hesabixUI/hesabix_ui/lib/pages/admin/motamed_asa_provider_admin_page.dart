import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/tax_provider_admin_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class MotamedAsaProviderAdminPage extends StatefulWidget {
  const MotamedAsaProviderAdminPage({super.key});

  @override
  State<MotamedAsaProviderAdminPage> createState() => _MotamedAsaProviderAdminPageState();
}

class _MotamedAsaProviderAdminPageState extends State<MotamedAsaProviderAdminPage> {
  static const _defaultBaseUrl = 'https://api-v2.asatsp.ir';

  final _service = TaxProviderAdminService();
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController(text: _defaultBaseUrl);
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();

  Map<String, dynamic> _settings = const {};
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _active = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _clientId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await _service.getMotamedAsaSettings();
      if (!mounted) return;
      setState(() {
        _settings = result;
        _baseUrl.text = result['base_url']?.toString() ?? _defaultBaseUrl;
        _active = result['is_active'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = ErrorExtractor.forContext(error, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_active &&
        ((_settings['client_id_configured'] != true && _clientId.text.trim().isEmpty) ||
            (_settings['client_secret_configured'] != true && _clientSecret.text.isEmpty))) {
      SnackBarHelper.showError(context, message: t.motamedAsaNotConfigured);
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await _service.saveMotamedAsaSettings({
        'base_url': _baseUrl.text.trim(),
        'is_active': _active,
        if (_clientId.text.trim().isNotEmpty) 'client_id': _clientId.text.trim(),
        if (_clientSecret.text.isNotEmpty) 'client_secret': _clientSecret.text,
      });
      if (!mounted) return;
      setState(() {
        _settings = result;
        _active = result['is_active'] == true;
        _clientId.clear();
        _clientSecret.clear();
      });
      SnackBarHelper.show(context, message: t.motamedAsaSaved);
    } catch (error) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(error, context));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    final t = AppLocalizations.of(context);
    if (_clientId.text.trim().isNotEmpty ||
        _clientSecret.text.isNotEmpty ||
        _baseUrl.text.trim() != (_settings['base_url']?.toString() ?? _defaultBaseUrl)) {
      SnackBarHelper.showError(context, message: t.taxProviderSaveBeforeTest);
      return;
    }
    setState(() => _testing = true);
    try {
      final result = await _service.testMotamedAsaConnection();
      if (!mounted) return;
      String state(bool value) => value ? t.taxProviderActive : t.taxProviderInactive;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.cloud_done_outlined),
          title: Text(t.motamedAsaAdminTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.motamedAsaTestSuccess),
              const SizedBox(height: 12),
              if (result['display_name'] != null) Text(result['display_name'].toString()),
              Text('${t.motamedAsaHostedOnboarding}: ${state(result['hosted_onboarding'] == true)}'),
              Text('${t.motamedAsaCredentialHandover}: ${state(result['credential_handover'] == true)}'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t.close)),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(error, context));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.motamedAsaAdminTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(t.reload)),
                    ],
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.motamedAsaAdminDescription),
                                    const SizedBox(height: 20),
                                    TextFormField(
                                      controller: _baseUrl,
                                      textDirection: TextDirection.ltr,
                                      decoration: InputDecoration(labelText: t.motamedAsaBaseUrl),
                                      validator: (value) {
                                        final uri = Uri.tryParse(value?.trim() ?? '');
                                        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
                                          return t.taxProviderInvalidUrl;
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _clientId,
                                      textDirection: TextDirection.ltr,
                                      decoration: InputDecoration(
                                        labelText: t.motamedAsaPartnerClientId,
                                        hintText: 'v2-partner-12345',
                                        helperText: _settings['client_id_configured'] == true
                                            ? '${t.motamedAsaKeepSecretHint} (${_settings['client_id_masked'] ?? '•••'})'
                                            : null,
                                      ),
                                      validator: (value) {
                                        final text = value?.trim() ?? '';
                                        if (text.isNotEmpty && !text.startsWith('v2-partner-')) {
                                          return t.motamedAsaPartnerClientIdInvalid;
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _clientSecret,
                                      obscureText: true,
                                      textDirection: TextDirection.ltr,
                                      decoration: InputDecoration(
                                        labelText: t.motamedAsaPartnerClientSecret,
                                        helperText: t.motamedAsaKeepSecretHint,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: _active,
                                      onChanged: (value) => setState(() => _active = value),
                                      title: Text(t.motamedAsaActivate),
                                      subtitle: Text(
                                        _active ? t.motamedAsaEnabledHint : t.motamedAsaDisabledHint,
                                        style: TextStyle(color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                    if (_settings['updated_at'] != null) ...[
                                      const SizedBox(height: 8),
                                      Text('${t.taxProviderActiveState}: ${_settings['is_active'] == true ? t.taxProviderActive : t.taxProviderInactive}'),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: (_saving || _testing) ? null : _testConnection,
                                  icon: _testing
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.network_check),
                                  label: Text(t.motamedAsaCheckConnection),
                                ),
                                FilledButton.icon(
                                  onPressed: (_saving || _testing) ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.save_outlined),
                                  label: Text(t.motamedAsaSave),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
