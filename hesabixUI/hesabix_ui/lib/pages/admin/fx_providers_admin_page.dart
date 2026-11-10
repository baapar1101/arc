import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_fx_providers_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

/// مدیریت ارائه‌دهندگان نرخ ارز در سطح سیستم + مشاهده اسنپ‌شات مرکزی.
class FxProvidersAdminPage extends StatefulWidget {
  const FxProvidersAdminPage({super.key});

  @override
  State<FxProvidersAdminPage> createState() => _FxProvidersAdminPageState();
}

class _FxProvidersAdminPageState extends State<FxProvidersAdminPage> {
  late final AdminFxProvidersService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _rates = [];
  bool _loadingRates = false;
  String? _busyCode;

  @override
  void initState() {
    super.initState();
    _service = AdminFxProvidersService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listProviders();
      if (!mounted) return;
      setState(() {
        _providers = items;
        _loading = false;
      });
      await _loadRates();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _loadRates() async {
    setState(() => _loadingRates = true);
    try {
      final items = await _service.listGlobalRates();
      if (!mounted) return;
      setState(() {
        _rates = items;
        _loadingRates = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRates = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> p) async {
    final code = '${p['code']}';
    final nameCtrl = TextEditingController(text: '${p['display_name'] ?? ''}');
    final urlCtrl = TextEditingController(text: '${p['api_base_url'] ?? ''}');
    final keyCtrl = TextEditingController();
    final intervalCtrl = TextEditingController(
      text: '${p['fetch_interval_seconds'] ?? 900}',
    );
    final providerConfig = p['config'] is Map
        ? Map<String, dynamic>.from(p['config'] as Map)
        : <String, dynamic>{};
    var quoteUnit = '${providerConfig['quote_unit'] ?? 'IRT'}'.toUpperCase();
    var isActive = p['is_active'] == true;
    final hasKey = p['has_api_key'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('${adminTx(context, 'ویرایش', 'Edit')} $code'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'نام نمایشی', 'Display name'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'آدرس پایه API', 'API base address'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (code == 'navasan') ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: quoteUnit == 'IRR' ? 'IRR' : 'IRT',
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: adminTx(context, 'واحد قیمت‌های نوسان', 'Navasan quote unit'),
                            helperText: adminTx(context, 'پیش‌فرض تومان است؛ فقط اگر قیمت‌ها ریال باشند تغییر دهید.', 'Default is toman. Change this only if prices are in rial.'),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(value: 'IRT', child: Text(adminTx(context, 'تومان (IRT)', 'Toman (IRT)'))),
                            DropdownMenuItem(value: 'IRR', child: Text(adminTx(context, 'ریال (IRR)', 'Rial (IRR)'))),
                          ],
                          onChanged: (value) {
                            if (value != null) setLocal(() => quoteUnit = value);
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: hasKey
                              ? adminTx(context, 'کلید API (خالی = بدون تغییر)', 'API key (empty keeps the current key)')
                              : adminTx(context, 'کلید API', 'API key'),
                          border: const OutlineInputBorder(),
                          helperText: hasKey ? adminTx(context, 'کلید فعلی ذخیره شده است', 'A key is already saved') : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: intervalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'بازه واکشی (ثانیه)', 'Fetch interval (seconds)'),
                          helperText: adminTx(context, 'پیش‌فرض ۹۰۰، یعنی هر ۱۵ دقیقه. حداقل ۶۰.', 'Default is 900, every 15 minutes. Minimum is 60.'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(adminTx(context, 'فعال برای واکشی خودکار', 'Enabled for automatic fetch')),
                        value: isActive,
                        onChanged: (v) => setLocal(() => isActive = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(adminTx(context, 'انصراف', 'Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(adminTx(context, 'ذخیره', 'Save'))),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;

    final interval = int.tryParse(intervalCtrl.text.trim()) ?? 900;
    try {
      await _service.upsertProvider(
        code: code,
        body: {
          'display_name': nameCtrl.text.trim(),
          'api_base_url': urlCtrl.text.trim().isEmpty ? null : urlCtrl.text.trim(),
          'is_active': isActive,
          'fetch_interval_seconds': interval,
          if (code == 'navasan')
            'config': {...providerConfig, 'quote_unit': quoteUnit},
          if (keyCtrl.text.trim().isNotEmpty) 'api_key': keyCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: adminTx(context, 'ذخیره شد', 'Saved'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _run(String code, Future<Map<String, dynamic>> Function() action, String okMsg) async {
    setState(() => _busyCode = code);
    try {
      final r = await action();
      if (!mounted) return;
      final n = r['rates_upserted'];
      SnackBarHelper.show(
        context,
        message: n != null ? adminTx(context, '$okMsg ($n نرخ)', '$okMsg ($n rates)') : okMsg,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busyCode = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdminCompactScaffold(
      title: adminTx(context, 'ارائه‌دهندگان نرخ ارز', 'Exchange-rate providers'),
      subtitle: adminTx(context, 'منبع نرخ و تصویر لحظه‌ای مرکزی', 'Rate source and the central snapshot'),
      actions: [
        IconButton(
          tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: context.settingsHub.pagePadding,
                    children: [
                      Text(
                        adminTx(
                          context,
                          'واکشی نرخ متمرکز است تا محدودیت API رعایت شود. کسب‌وکارها فقط از تصویر ذخیره‌شده تسعیر می‌کنند.',
                          'Rates are fetched centrally so API limits are respected. Businesses revalue only from the stored snapshot.',
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      ..._providers.map((p) {
                        final code = '${p['code']}';
                        final busy = _busyCode == code;
                        final status = p['last_fetch_status']?.toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${p['display_name'] ?? code} ($code)',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                    ),
                                    if (p['is_active'] == true)
                                      Chip(label: Text(adminTx(context, 'فعال', 'Active')), visualDensity: VisualDensity.compact)
                                    else
                                      Chip(label: Text(adminTx(context, 'غیرفعال', 'Inactive')), visualDensity: VisualDensity.compact),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${adminTx(context, 'بازه', 'Interval')}: ${p['fetch_interval_seconds'] ?? 900} ${adminTx(context, 'ثانیه', 'sec')} · '
                                  '${adminTx(context, 'کلید', 'Key')}: ${p['has_db_api_key'] == true ? adminTx(context, 'دیتابیس', 'Database') : (p['api_key_source'] == 'env' ? 'env' : adminTx(context, 'ندارد', 'None'))} · '
                                  '${adminTx(context, 'وضعیت', 'Status')}: ${status ?? '—'}'
                                  '${p['last_fetch_at'] != null ? ' · ${p['last_fetch_at']}' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                if (p['last_fetch_error'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${p['last_fetch_error']}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: busy ? null : () => _edit(p),
                                      child: Text(adminTx(context, 'ویرایش', 'Edit')),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: busy
                                          ? null
                                          : () => _run(code, () => _service.testProvider(code), adminTx(context, 'تست موفق', 'Test succeeded')),
                                      child: busy
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Text(adminTx(context, 'تست و ذخیره', 'Test and save')),
                                    ),
                                    FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => _run(code, () => _service.fetchNow(code), adminTx(context, 'واکشی انجام شد', 'Fetch completed')),
                                      child: Text(adminTx(context, 'واکشی اکنون', 'Fetch now')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Text(adminTx(context, 'نرخ‌های ذخیره‌شده', 'Stored rates'), style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface)),
                      const SizedBox(height: 8),
                      if (_loadingRates)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_rates.isEmpty)
                        Text(adminTx(context, 'هنوز نرخی واکشی نشده است.', 'No rates have been fetched yet.'))
                      else
                        ..._rates.take(40).map((r) {
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${r['currency_code']} (${r['symbol']}) — ${r['name_fa'] ?? ''}',
                            ),
                            subtitle: Text(
                              '${adminTx(context, 'نقل', 'Quote')}: ${formatFxRateForDisplay(r['price_quote'])} ${r['quote_unit']} · '
                              '${adminTx(context, 'ریال', 'IRR')}: ${formatFxRateForDisplay(r['price_irr'])}',
                            ),
                          );
                        }),
                      if (_rates.length > 40)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(adminTx(context, '… و ${_rates.length - 40} مورد دیگر', '… and ${_rates.length - 40} more')),
                        ),
                    ],
                  ),
                ),
    );
  }
}
