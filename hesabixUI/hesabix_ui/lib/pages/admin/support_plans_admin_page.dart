import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/services/support_billing_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

class SupportPlansAdminPage extends StatefulWidget {
  const SupportPlansAdminPage({super.key});

  @override
  State<SupportPlansAdminPage> createState() => _SupportPlansAdminPageState();
}

class _SupportPlansAdminPageState extends State<SupportPlansAdminPage> {
  late final AdminSupportBillingService _service;
  late final CurrencyService _currencyService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = const [];
  List<Map<String, dynamic>> _currencies = const [];

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _service = AdminSupportBillingService(api);
    _currencyService = CurrencyService(api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _service.listPlans();
      final currencies = await _currencyService.listCurrencies();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _currencies = currencies;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _showForm({Map<String, dynamic>? initial}) async {
    final isEdit = initial != null;
    final nameCtrl = TextEditingController(text: initial?['name']?.toString() ?? '');
    final codeCtrl = TextEditingController(text: initial?['code']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: '${initial?['price'] ?? 0}');
    final descCtrl = TextEditingController(text: initial?['description']?.toString() ?? '');
    final sortCtrl = TextEditingController(text: '${initial?['sort_order'] ?? 0}');
    int periodMonths = (initial?['period_months'] as int?) ?? 1;
    int? currencyId = initial?['currency_id'] as int?;
    if (currencyId == null && _currencies.isNotEmpty) {
      final irr = _currencies.cast<Map?>().firstWhere(
            (c) => c?['code'] == 'IRR',
            orElse: () => _currencies.first,
          );
      currencyId = irr?['id'] as int?;
    }
    bool isFree = initial?['is_free'] == true;
    bool isActive = initial?['is_active'] ?? true;
    bool priority = initial?['includes_priority_support'] == true;
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isEdit ? 'ویرایش پلن پشتیبانی' : 'پلن پشتیبانی جدید'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'نام'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'الزامی' : null,
                    ),
                    TextFormField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'کد'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'الزامی' : null,
                    ),
                    DropdownButtonFormField<int>(
                      value: periodMonths,
                      decoration: const InputDecoration(labelText: 'مدت (ماه)'),
                      items: const [1, 3, 6, 12]
                          .map((m) => DropdownMenuItem(value: m, child: Text('$m ماهه')))
                          .toList(),
                      onChanged: (v) => setLocal(() => periodMonths = v ?? 1),
                    ),
                    DropdownButtonFormField<int>(
                      value: currencyId,
                      decoration: const InputDecoration(labelText: 'ارز'),
                      items: _currencies
                          .map(
                            (c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text('${c['code']} — ${c['name'] ?? c['title'] ?? ''}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => currencyId = v),
                    ),
                    TextFormField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(labelText: 'قیمت (ریال)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      enabled: !isFree,
                    ),
                    TextFormField(
                      controller: sortCtrl,
                      decoration: const InputDecoration(labelText: 'ترتیب نمایش'),
                      keyboardType: TextInputType.number,
                    ),
                    TextFormField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'توضیحات'),
                      maxLines: 2,
                    ),
                    SwitchListTile(
                      title: const Text('رایگان'),
                      value: isFree,
                      onChanged: (v) => setLocal(() {
                        isFree = v;
                        if (v) priceCtrl.text = '0';
                      }),
                    ),
                    SwitchListTile(
                      title: const Text('فعال'),
                      value: isActive,
                      onChanged: (v) => setLocal(() => isActive = v),
                    ),
                    SwitchListTile(
                      title: const Text('پشتیبانی اولویت‌دار'),
                      value: priority,
                      onChanged: (v) => setLocal(() => priority = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final payload = {
      'name': nameCtrl.text.trim(),
      'code': codeCtrl.text.trim(),
      'period_months': periodMonths,
      'currency_id': currencyId,
      'price': isFree ? 0 : (int.tryParse(priceCtrl.text) ?? 0),
      'is_free': isFree,
      'is_active': isActive,
      'includes_priority_support': priority,
      'sort_order': int.tryParse(sortCtrl.text) ?? 0,
      'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
    };
    try {
      if (isEdit) {
        await _service.updatePlan(initial['id'] as int, payload);
      } else {
        await _service.createPlan(payload);
      }
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'ذخیره شد');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف/غیرفعال‌سازی'),
        content: Text('پلن «${plan['name']}» حذف یا غیرفعال شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deletePlan(plan['id'] as int);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'انجام شد');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('پلن‌های پشتیبانی'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () => _showForm(), icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _plans.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = _plans[i];
                    return Card(
                      child: ListTile(
                        title: Text('${p['name']} (${p['period_months']} ماهه)'),
                        subtitle: Text(
                          'کد: ${p['code']} · قیمت: ${formatWithThousands(p['price'], decimalPlaces: 0)} ریال · '
                          '${p['is_active'] == true ? 'فعال' : 'غیرفعال'}'
                          '${p['is_free'] == true ? ' · رایگان' : ''}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showForm(initial: p),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(p),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
