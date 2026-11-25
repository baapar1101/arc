import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/system_settings_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class WalletSettingsPage extends StatefulWidget {
  const WalletSettingsPage({super.key});

  @override
  State<WalletSettingsPage> createState() => _WalletSettingsPageState();
}

class _WalletSettingsPageState extends State<WalletSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final SystemSettingsService _settingsService;
  late final CurrencyService _currencyService;

  bool _loading = true;
  String? _error;
  String? _selectedCurrencyCode;
  List<Map<String, dynamic>> _currencies = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _settingsService = SystemSettingsService(api);
    _currencyService = CurrencyService(api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _settingsService.getWalletSettings();
      final list = await _currencyService.listCurrencies();
      setState(() {
        _currencies = list;
        _selectedCurrencyCode = (settings['wallet_base_currency_code'] ?? 'IRR').toString();
      });
    } catch (e) {
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await _settingsService.setWalletBaseCurrencyCode(_selectedCurrencyCode ?? 'IRR');
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.saved);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: '${t.error}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AdminCompactScaffold(
      title: t.walletSettingsTitle,
      subtitle: adminTx(context, 'ارز پایه کیف پول سیستم', 'Base currency of the system wallet'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: Text(adminTx(context, 'تلاش مجدد', 'Retry'))),
                    ],
                  ),
                )
              : Padding(
                  padding: context.settingsHub.pagePadding,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCurrencyCode,
                          decoration: InputDecoration(isDense: true, labelText: t.walletBaseCurrency),
                          items: _currencies
                              .map((c) => DropdownMenuItem<String>(
                                    value: (c['code'] ?? '').toString(),
                                    child: Text('${c['title']} (${c['code']})'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedCurrencyCode = v),
                          validator: (v) => (v == null || v.isEmpty) ? t.walletCurrencyRequired : null,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save, size: 18),
                          label: Text(t.save),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}


