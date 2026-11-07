import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../../services/system_settings_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class PayPageSystemSettingsPage extends StatefulWidget {
  const PayPageSystemSettingsPage({super.key});

  @override
  State<PayPageSystemSettingsPage> createState() => _PayPageSystemSettingsPageState();
}

class _PayPageSystemSettingsPageState extends State<PayPageSystemSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  late final SystemSettingsService _service;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _effectiveUrl = '';

  @override
  void initState() {
    super.initState();
    _service = SystemSettingsService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getPayPageSystemSettings();
      _urlController.text = (data['public_base_url'] ?? '').toString();
      _effectiveUrl = (data['effective_public_base_url'] ?? '').toString();
    } catch (e) {
      if (mounted) {
        _error = ErrorExtractor.forContext(e, context);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final data = await _service.updatePayPageSystemSettings(_urlController.text.trim());
      _urlController.text = (data['public_base_url'] ?? '').toString();
      _effectiveUrl = (data['effective_public_base_url'] ?? '').toString();
      if (mounted) {
        setState(() {});
        SnackBarHelper.showSuccess(context, message: t.payPageDomainSaved);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.settingsPayPageDomain),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(t.save, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error)),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(t.retry)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.payPageDomainUrlLabel,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(t.payPageDomainUrlHint, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _urlController,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: t.payPageDomainUrlLabel,
                              hintText: 'https://hesabix.ir',
                              prefixIcon: const Icon(Icons.qr_code_2_outlined),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final text = (value ?? '').trim();
                              if (text.isEmpty) return null;
                              final lower = text.toLowerCase();
                              if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
                                return t.payPageDomainUrlInvalid;
                              }
                              return null;
                            },
                          ),
                          if (_effectiveUrl.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(t.payPageDomainEffectiveUrl, style: theme.textTheme.bodySmall),
                            const SizedBox(height: 4),
                            SelectableText(
                              _effectiveUrl,
                              textDirection: TextDirection.ltr,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save),
                            label: Text(_saving ? t.saving : t.save),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
