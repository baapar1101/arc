import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/tax_provider_admin_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class TaxProviderAdminPage extends StatefulWidget {
  const TaxProviderAdminPage({super.key});

  @override
  State<TaxProviderAdminPage> createState() => _TaxProviderAdminPageState();
}

class _TaxProviderAdminPageState extends State<TaxProviderAdminPage> {
  final _service = TaxProviderAdminService();
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController(text: 'https://avatsp.net');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _brokerCode = TextEditingController();
  final _contractDuration = TextEditingController(text: '365');

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
    _username.dispose();
    _password.dispose();
    _brokerCode.dispose();
    _contractDuration.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await _service.getFanavaSettings();
      if (!mounted) return;
      setState(() {
        _settings = result;
        _baseUrl.text = result['base_url']?.toString() ?? 'https://avatsp.net';
        _brokerCode.text = result['broker_code']?.toString() ?? '';
        _contractDuration.text = result['contract_duration_days']?.toString() ?? '365';
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
        _settings['username_configured'] != true &&
        _username.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: t.taxProviderNotConfigured);
      return;
    }
    if (_active &&
        _settings['password_configured'] != true &&
        _password.text.isEmpty) {
      SnackBarHelper.showError(context, message: t.taxProviderNotConfigured);
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await _service.saveFanavaSettings({
        'base_url': _baseUrl.text.trim(),
        'broker_code': int.tryParse(_brokerCode.text.trim()),
        'contract_duration_days': int.parse(_contractDuration.text.trim()),
        'is_active': _active,
        if (_username.text.trim().isNotEmpty) 'username': _username.text.trim(),
        if (_password.text.isNotEmpty) 'password': _password.text,
      });
      if (!mounted) return;
      setState(() {
        _settings = result;
        _active = result['is_active'] == true;
        _username.clear();
        _password.clear();
      });
      SnackBarHelper.show(context, message: t.taxProviderSaved);
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
    if (_username.text.trim().isNotEmpty ||
        _password.text.isNotEmpty ||
        _baseUrl.text.trim() != (_settings['base_url']?.toString() ?? 'https://avatsp.net') ||
        _brokerCode.text.trim() != (_settings['broker_code']?.toString() ?? '')) {
      SnackBarHelper.showError(context, message: t.taxProviderSaveBeforeTest);
      return;
    }
    setState(() => _testing = true);
    try {
      final result = await _service.testFanavaConnection();
      if (!mounted) return;
      final brokerCount = result['broker_count']?.toString() ?? '0';
      final activeCount = result['active_broker_count']?.toString() ?? '0';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.cloud_done_outlined),
          title: Text(t.taxProviderActiveState),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.taxProviderTestSuccess),
              const SizedBox(height: 12),
              Text('${t.taxProviderBrokerCount}: $brokerCount'),
              Text('${t.taxProviderActiveBrokerCount}: $activeCount'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t.close)),
          ],
        ),
      );
    } on DioException catch (error) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(error, context));
      }
    } catch (error) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(error, context));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty
        ? AppLocalizations.of(context).required
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.taxProviderAdminTitle)),
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
                                    Text(t.taxProviderAdminDescription),
                                    const SizedBox(height: 20),
                                    TextFormField(
                                      controller: _baseUrl,
                                      decoration: InputDecoration(labelText: t.taxProviderBaseUrl),
                                      validator: (value) {
                                        final required = _required(value);
                                        if (required != null) return required;
                                        final uri = Uri.tryParse(value!.trim());
                                        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
                                          return t.taxProviderInvalidUrl;
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _username,
                                      decoration: InputDecoration(
                                        labelText: t.taxProviderBrokerUsername,
                                        helperText: _settings['username_configured'] == true
                                            ? '${t.taxProviderBrokerUsernameHint} (${_settings['username_masked'] ?? '•••'})'
                                            : null,
                                      ),
                                      textDirection: TextDirection.ltr,
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _password,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                        labelText: t.taxProviderBrokerPassword,
                                        helperText: t.taxProviderBrokerPasswordHint,
                                      ),
                                      textDirection: TextDirection.ltr,
                                    ),
                                    const SizedBox(height: 12),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final code = TextFormField(
                                          controller: _brokerCode,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(labelText: t.taxProviderBrokerCode),
                                          validator: (value) {
                                            if (_active && (value == null || value.trim().isEmpty)) return _required(value);
                                            if (value != null && value.trim().isNotEmpty && int.tryParse(value.trim()) == null) {
                                              return t.taxProviderNumericBrokerCode;
                                            }
                                            return null;
                                          },
                                        );
                                        final duration = TextFormField(
                                          controller: _contractDuration,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(labelText: t.taxProviderContractDuration),
                                          validator: (value) {
                                            final parsed = int.tryParse(value?.trim() ?? '');
                                            if (parsed == null || parsed < 1 || parsed > 3650) return t.taxProviderContractRange;
                                            return null;
                                          },
                                        );
                                        if (constraints.maxWidth < 520) {
                                          return Column(children: [code, const SizedBox(height: 12), duration]);
                                        }
                                        return Row(children: [Expanded(child: code), const SizedBox(width: 12), Expanded(child: duration)]);
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: _active,
                                      onChanged: (value) => setState(() => _active = value),
                                      title: Text(t.taxProviderActivate),
                                      subtitle: Text(
                                        _active ? t.taxProviderEnabledHint : t.taxProviderDisabledHint,
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
                                  label: Text(t.taxProviderTest),
                                ),
                                FilledButton.icon(
                                  onPressed: (_saving || _testing) ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.save_outlined),
                                  label: Text(t.taxProviderSave),
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
