import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/credit_models.dart';
import 'package:hesabix_ui/services/credit_api_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class CreditSettingsPage extends StatefulWidget {
  final int businessId;
  const CreditSettingsPage({super.key, required this.businessId});

  @override
  State<CreditSettingsPage> createState() => _CreditSettingsPageState();
}

class _CreditSettingsPageState extends State<CreditSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  CreditSettings? _settings;

  final _defaultLimitController = TextEditingController();
  final _graceDaysController = TextEditingController();
  final _lateFeeRateController = TextEditingController();
  final _autoBlockDaysController = TextEditingController();
  String _strategy = 'single-default';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await CreditApiService.getCreditSettings(widget.businessId);
      _settings = s;
      _defaultLimitController.text = s.defaultLimit?.toString() ?? '';
      _graceDaysController.text = s.graceDays?.toString() ?? '';
      _lateFeeRateController.text = s.lateFeeRate?.toString() ?? '';
      _autoBlockDaysController.text = s.autoBlockAfterDays?.toString() ?? '';
      _strategy = s.strategy;
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final parsedDefaultLimit = _defaultLimitController.text.trim().isEmpty ? null : double.tryParse(_defaultLimitController.text.trim());
      final parsedGrace = _graceDaysController.text.trim().isEmpty ? null : int.tryParse(_graceDaysController.text.trim());
      final parsedLateRate = _lateFeeRateController.text.trim().isEmpty ? null : double.tryParse(_lateFeeRateController.text.trim());
      final parsedAutoBlock = _autoBlockDaysController.text.trim().isEmpty ? null : int.tryParse(_autoBlockDaysController.text.trim());
      final toUpdate = CreditSettings(
        businessId: _settings!.businessId,
        isEnabled: _settings!.isEnabled,
        defaultLimit: parsedDefaultLimit,
        graceDays: parsedGrace,
        lateFeeRate: parsedLateRate,
        autoBlockAfterDays: parsedAutoBlock,
        strategy: _strategy,
      );
      final saved = await CreditApiService.updateCreditSettings(widget.businessId, toUpdate);
      setState(() {
        _settings = saved;
      });
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.savedSuccessfully)));
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.creditSettingsTitle),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: Text(t.creditEnableTitle),
                        subtitle: Text(t.creditEnableSubtitle),
                        value: _settings?.isEnabled ?? false,
                        onChanged: (v) {
                          setState(() {
                            _settings = _settings?.copyWith(isEnabled: v) ?? CreditSettings(
                              businessId: widget.businessId,
                              isEnabled: v,
                              strategy: _strategy,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _numberField(
                        label: t.creditDefaultLimit,
                        controller: _defaultLimitController,
                        suffix: t.currencyToman,
                      ),
                      const SizedBox(height: 8),
                      _numberField(
                        label: t.creditGraceDays,
                        controller: _graceDaysController,
                      ),
                      const SizedBox(height: 8),
                      _numberField(
                        label: t.creditLateFeeRatePercent,
                        controller: _lateFeeRateController,
                        suffix: '%',
                      ),
                      const SizedBox(height: 8),
                      _numberField(
                        label: t.creditAutoBlockAfterDays,
                        controller: _autoBlockDaysController,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _strategy,
                        items: const [
                          DropdownMenuItem(value: 'single-default', child: Text('سقف پیش‌فرض یکنواخت')),
                          DropdownMenuItem(value: 'by-group', child: Text('بر اساس گروه/نقش')),
                          DropdownMenuItem(value: 'per-user', child: Text('سقف اختصاصی برای هر کاربر')),
                        ],
                        onChanged: (v) => setState(() => _strategy = v ?? 'single-default'),
                        decoration: InputDecoration(labelText: t.creditStrategy),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                            label: Text(t.save),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _loading ? null : _load,
                            icon: const Icon(Icons.refresh),
                            label: Text(t.reload),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _numberField({required String label, required TextEditingController controller, String? suffix}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
  }
}

extension on CreditSettings {
  CreditSettings copyWith({
    bool? isEnabled,
    double? defaultLimit,
    int? graceDays,
    double? lateFeeRate,
    int? autoBlockAfterDays,
    String? strategy,
  }) {
    return CreditSettings(
      businessId: businessId,
      isEnabled: isEnabled ?? this.isEnabled,
      defaultLimit: defaultLimit ?? this.defaultLimit,
      graceDays: graceDays ?? this.graceDays,
      lateFeeRate: lateFeeRate ?? this.lateFeeRate,
      autoBlockAfterDays: autoBlockAfterDays ?? this.autoBlockAfterDays,
      strategy: strategy ?? this.strategy,
    );
  }
}


