import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/system_settings_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class AIPlansAdminPage extends StatefulWidget {
  const AIPlansAdminPage({super.key});

  @override
  State<AIPlansAdminPage> createState() => _AIPlansAdminPageState();
}

class _AIPlansAdminPageState extends State<AIPlansAdminPage> {
  late final AIService _aiService;
  late final SystemSettingsService _settingsService;
  bool _loading = true;
  String? _error;
  List<AIPlan> _plans = [];
  String? _walletCurrencyCode;
  String? _walletCurrencyTitle;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _settingsService = SystemSettingsService(api);
    _load();
  }

  String get _walletCurrencyLabel {
    final t = _walletCurrencyTitle;
    final c = _walletCurrencyCode;
    if (t != null && t.isNotEmpty) {
      if (c != null && c.isNotEmpty && c != t) {
        return '$t ($c)';
      }
      return t;
    }
    if (c != null && c.isNotEmpty) return c;
    return '';
  }

  static String _formatNumForField(dynamic v) {
    if (v == null) return '';
    if (v is int) return v.toString();
    if (v is double) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toString();
    }
    if (v is num) {
      final d = v.toDouble();
      if (d == d.roundToDouble()) return d.toInt().toString();
      return d.toString();
    }
    return v.toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _aiService.listAIPlans(),
        _settingsService.getWalletSettings(),
      ]);
      final plans = results[0] as List<AIPlan>;
      final wallet = Map<String, dynamic>.from(results[1] as Map);
      setState(() {
        _plans = plans;
        _walletCurrencyCode = wallet['wallet_base_currency_code']?.toString();
        _walletCurrencyTitle = wallet['wallet_base_currency_title']?.toString();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _buildPricingConfig(
    AIPlanType planType,
    TextEditingController monthlyPrice,
    TextEditingController yearlyPrice,
    TextEditingController payInput,
    TextEditingController payOutput,
  ) {
    final pc = <String, dynamic>{};
    if (planType == AIPlanType.subscription || planType == AIPlanType.hybrid) {
      pc['subscription'] = <String, dynamic>{
        'monthly_price': _parseDecimal(monthlyPrice.text),
        'yearly_price': _parseDecimal(yearlyPrice.text),
      };
    }
    if (planType == AIPlanType.payAsGo || planType == AIPlanType.hybrid) {
      pc['pay_as_go'] = <String, dynamic>{
        'price_per_1k_input_tokens': _parseDecimal(payInput.text),
        'price_per_1k_output_tokens': _parseDecimal(payOutput.text),
      };
    }
    return pc;
  }

  double _parseDecimal(String raw) {
    final s = raw.replaceAll(',', '').trim();
    if (s.isEmpty) return 0;
    return double.tryParse(s) ?? 0;
  }

  int? _parseOptionalInt(String raw) {
    final s = raw.replaceAll(',', '').trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  Future<void> _showPlanFormDialog({AIPlan? plan}) async {
    final isEdit = plan != null;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: plan?.name ?? '');
    final codeController = TextEditingController(text: plan?.code ?? '');
    final descriptionController = TextEditingController(text: plan?.description ?? '');
    final tokensLimitController = TextEditingController(text: plan?.tokensLimit?.toString() ?? '');
    final monthlyTokensLimitController = TextEditingController(
      text: plan?.monthlyTokensLimit?.toString() ?? '',
    );

    final monthlyPriceController = TextEditingController();
    final yearlyPriceController = TextEditingController();
    final payInput1kController = TextEditingController();
    final payOutput1kController = TextEditingController();

    final pc = plan?.pricingConfig ?? const <String, dynamic>{};
    final sub = Map<String, dynamic>.from((pc['subscription'] as Map?) ?? const {});
    final pay = Map<String, dynamic>.from((pc['pay_as_go'] as Map?) ?? const {});
    monthlyPriceController.text = _formatNumForField(sub['monthly_price']);
    yearlyPriceController.text = _formatNumForField(sub['yearly_price']);
    payInput1kController.text = _formatNumForField(pay['price_per_1k_input_tokens']);
    payOutput1kController.text = _formatNumForField(pay['price_per_1k_output_tokens']);

    AIPlanType selectedPlanType = plan?.planType ?? AIPlanType.free;
    bool isActive = plan?.isActive ?? true;
    bool autoRenew = plan?.autoRenew ?? false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currencySuffix = _walletCurrencyLabel.isNotEmpty ? ' ($_walletCurrencyLabel)' : '';
          final pricingHint = _walletCurrencyLabel.isEmpty
              ? 'مبالغ قیمت اشتراک و نرخ توکن در همان واحد ارز پایه کیف پول سیستم (تنظیمات کیف پول) ثبت می‌شوند.'
              : 'مبالغ زیر به واحد ارز پایه کیف پول است: $_walletCurrencyLabel';

          return Dialog(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEdit ? 'ویرایش پلن' : 'ایجاد پلن جدید',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          color: Theme.of(context).colorScheme.onPrimary,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.account_balance_wallet_outlined,
                                        color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        pricingHint,
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: nameController,
                              decoration: const InputDecoration(labelText: 'نام پلن'),
                              validator: (v) => v?.isEmpty ?? true ? 'الزامی است' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: codeController,
                              decoration: const InputDecoration(labelText: 'کد پلن'),
                              enabled: !isEdit,
                              validator: (v) => v?.isEmpty ?? true ? 'الزامی است' : null,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<AIPlanType>(
                              key: ValueKey<AIPlanType>(selectedPlanType),
                              initialValue: selectedPlanType,
                              decoration: const InputDecoration(labelText: 'نوع پلن'),
                              items: AIPlanType.values.map((type) {
                                String label;
                                switch (type) {
                                  case AIPlanType.free:
                                    label = 'رایگان';
                                    break;
                                  case AIPlanType.subscription:
                                    label = 'اشتراک';
                                    break;
                                  case AIPlanType.payAsGo:
                                    label = 'پرداخت به ازای استفاده';
                                    break;
                                  case AIPlanType.hybrid:
                                    label = 'ترکیبی';
                                    break;
                                }
                                return DropdownMenuItem(value: type, child: Text(label));
                              }).toList(),
                              onChanged: (v) => setDialogState(() => selectedPlanType = v!),
                            ),
                            if (selectedPlanType == AIPlanType.subscription ||
                                selectedPlanType == AIPlanType.hybrid) ...[
                              const SizedBox(height: 16),
                              Text(
                                'قیمت اشتراک$currencySuffix',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: monthlyPriceController,
                                decoration: InputDecoration(
                                  labelText: 'قیمت ماهانه$currencySuffix',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: yearlyPriceController,
                                decoration: InputDecoration(
                                  labelText: 'قیمت سالانه$currencySuffix',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ],
                              ),
                            ],
                            if (selectedPlanType == AIPlanType.payAsGo ||
                                selectedPlanType == AIPlanType.hybrid) ...[
                              const SizedBox(height: 16),
                              Text(
                                'نرخ پرداخت به‌ازای استفاده (هر ۱۰۰۰ توکن)$currencySuffix',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: payInput1kController,
                                decoration: InputDecoration(
                                  labelText: 'قیمت هر ۱۰۰۰ توکن ورودی$currencySuffix',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: payOutput1kController,
                                decoration: InputDecoration(
                                  labelText: 'قیمت هر ۱۰۰۰ توکن خروجی$currencySuffix',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: tokensLimitController,
                              decoration: const InputDecoration(
                                labelText: 'محدودیت توکن (کل / سقف کمکی)',
                                helperText: 'اختیاری؛ اگر سقف ماهانه خالی باشد برای سهمیه ماهانه استفاده می‌شود',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: monthlyTokensLimitController,
                              decoration: const InputDecoration(
                                labelText: 'محدودیت ماهانه توکن',
                                helperText: 'برای پلن‌های رایگان، اشتراک و ترکیبی؛ اولویت با این مقدار است',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: descriptionController,
                              decoration: const InputDecoration(labelText: 'توضیحات'),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: const Text('فعال'),
                              value: isActive,
                              onChanged: (v) => setDialogState(() => isActive = v),
                            ),
                            SwitchListTile(
                              title: const Text('تمدید خودکار'),
                              value: autoRenew,
                              onChanged: (v) => setDialogState(() => autoRenew = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('لغو'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            try {
                              final pricingConfig = _buildPricingConfig(
                                selectedPlanType,
                                monthlyPriceController,
                                yearlyPriceController,
                                payInput1kController,
                                payOutput1kController,
                              );
                              final data = <String, dynamic>{
                                'name': nameController.text.trim(),
                                'code': codeController.text.trim(),
                                'plan_type': selectedPlanType.value,
                                'pricing_config': pricingConfig,
                                'description': descriptionController.text.trim(),
                                'is_active': isActive,
                                'auto_renew': autoRenew,
                              };
                              final tl = _parseOptionalInt(tokensLimitController.text);
                              final mtl = _parseOptionalInt(monthlyTokensLimitController.text);
                              if (isEdit) {
                                data['tokens_limit'] = tl;
                                data['monthly_tokens_limit'] = mtl;
                              } else {
                                if (tl != null) data['tokens_limit'] = tl;
                                if (mtl != null) data['monthly_tokens_limit'] = mtl;
                              }
                              if (isEdit) {
                                await _aiService.updateAIPlan(plan.id!, data);
                              } else {
                                await _aiService.createAIPlan(data);
                              }
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              _load();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطا: ${ErrorExtractor.forContext(e, context)}')),
                              );
                            }
                          },
                          child: Text(isEdit ? 'ذخیره' : 'ایجاد'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      nameController.dispose();
      codeController.dispose();
      descriptionController.dispose();
      tokensLimitController.dispose();
      monthlyTokensLimitController.dispose();
      monthlyPriceController.dispose();
      yearlyPriceController.dispose();
      payInput1kController.dispose();
      payOutput1kController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('پلن‌های AI')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _plans.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('پلن‌های AI')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('خطا: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('پلن‌های AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showPlanFormDialog(),
            tooltip: 'ایجاد پلن جدید',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _plans.isEmpty
            ? const Center(child: Text('پلنی وجود ندارد'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _plans.length,
                itemBuilder: (context, index) {
                  final plan = _plans[index];
                  String planTypeLabel;
                  switch (plan.planType) {
                    case AIPlanType.free:
                      planTypeLabel = 'رایگان';
                      break;
                    case AIPlanType.subscription:
                      planTypeLabel = 'اشتراک';
                      break;
                    case AIPlanType.payAsGo:
                      planTypeLabel = 'پرداخت به ازای استفاده';
                      break;
                    case AIPlanType.hybrid:
                      planTypeLabel = 'ترکیبی';
                      break;
                  }
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(plan.name),
                      subtitle: Text('$planTypeLabel • ${plan.code}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (plan.isActive)
                            const Icon(Icons.check_circle, color: Colors.green)
                          else
                            const Icon(Icons.cancel, color: Colors.grey),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showPlanFormDialog(plan: plan),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              if (await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('حذف پلن'),
                                      content: const Text('آیا از حذف این پلن اطمینان دارید؟'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('لغو'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('حذف'),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false) {
                                try {
                                  if (plan.id != null) {
                                    await _aiService.deleteAIPlan(plan.id!);
                                    _load();
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('خطا: ${ErrorExtractor.forContext(e, context)}')),
                                    );
                                  }
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
