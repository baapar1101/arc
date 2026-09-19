import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_fx_providers_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

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
    var isActive = p['is_active'] == true;
    final hasKey = p['has_api_key'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('ویرایش $code'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'نام نمایشی',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'آدرس پایه API',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: keyCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: hasKey
                              ? 'کلید API (خالی = بدون تغییر)'
                              : 'کلید API',
                          border: const OutlineInputBorder(),
                          helperText: hasKey ? 'کلید فعلی ذخیره شده است (***)' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: intervalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'بازه واکشی (ثانیه)',
                          helperText: 'پیش‌فرض ۹۰۰ = هر ۱۵ دقیقه؛ حداقل ۶۰',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('فعال برای واکشی خودکار'),
                        value: isActive,
                        onChanged: (v) => setLocal(() => isActive = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
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
          if (keyCtrl.text.trim().isNotEmpty) 'api_key': keyCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'ذخیره شد');
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
        message: n != null ? '$okMsg ($n نرخ)' : okMsg,
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('ارائه‌دهندگان نرخ ارز'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'واکشی نرخ به‌صورت متمرکز انجام می‌شود (نه به‌ازای هر کسب‌وکار) تا محدودیت API رعایت شود. '
                        'کسب‌وکارها فقط از اسنپ‌شات ذخیره‌شده ثبت تسعیر می‌کنند.',
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
                                      const Chip(label: Text('فعال'), visualDensity: VisualDensity.compact)
                                    else
                                      const Chip(label: Text('غیرفعال'), visualDensity: VisualDensity.compact),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'بازه: ${p['fetch_interval_seconds'] ?? 900} ثانیه · '
                                  'کلید: ${p['has_db_api_key'] == true ? 'دیتابیس' : (p['api_key_source'] == 'env' ? 'env' : 'ندارد')} · '
                                  'وضعیت: ${status ?? '—'}'
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
                                      child: const Text('ویرایش'),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: busy
                                          ? null
                                          : () => _run(code, () => _service.testProvider(code), 'تست موفق'),
                                      child: busy
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Text('تست و ذخیره'),
                                    ),
                                    FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => _run(code, () => _service.fetchNow(code), 'واکشی انجام شد'),
                                      child: const Text('واکشی اکنون'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Text('اسنپ‌شات مرکزی', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_loadingRates)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_rates.isEmpty)
                        const Text('هنوز نرخی واکشی نشده است.')
                      else
                        ..._rates.take(40).map((r) {
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${r['currency_code']} (${r['symbol']}) — ${r['name_fa'] ?? ''}',
                            ),
                            subtitle: Text(
                              'نقل: ${formatFxRateForDisplay(r['price_quote'])} ${r['quote_unit']} · '
                              'ریال: ${formatFxRateForDisplay(r['price_irr'])}',
                            ),
                          );
                        }),
                      if (_rates.length > 40)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('… و ${_rates.length - 40} مورد دیگر'),
                        ),
                    ],
                  ),
                ),
    );
  }
}
