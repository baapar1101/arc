import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/system_settings_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class AIPlansAdminPage extends StatefulWidget {
  final bool embedded;
  const AIPlansAdminPage({super.key, this.embedded = false});

  @override
  State<AIPlansAdminPage> createState() => _AIPlansAdminPageState();
}

class _AIPlansAdminPageState extends State<AIPlansAdminPage> {
  late final AIService _aiService;
  late final SystemSettingsService _settingsService;
  bool _loading = true;
  String? _error;
  List<AIPlan> _plans = [];
  List<AIModelCatalogItem> _catalogModels = [];
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

  String _planTypeLabel(AIPlanType type) {
    switch (type) {
      case AIPlanType.free:
        return adminTx(context, 'رایگان', 'Free');
      case AIPlanType.subscription:
        return adminTx(context, 'اشتراک', 'Subscription');
      case AIPlanType.payAsGo:
        return adminTx(context, 'پرداخت به ازای استفاده', 'Pay as you go');
      case AIPlanType.hybrid:
        return adminTx(context, 'ترکیبی', 'Hybrid');
      case AIPlanType.byok:
        return adminTx(context, 'ارائه‌دهنده اختصاصی', 'Bring your own key');
    }
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
        _aiService.listAIModels(onlyActive: true),
      ]);
      final plans = results[0] as List<AIPlan>;
      final wallet = Map<String, dynamic>.from(results[1] as Map);
      final models = results[2] as List<AIModelCatalogItem>;
      setState(() {
        _plans = plans;
        _catalogModels = models;
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
    Set<String> allowedModels,
    String? defaultModel,
    Map<String, Map<String, double>> perModelRates, {
    Set<String>? byokProviders,
    bool requireConnectionTest = true,
  }) {
    final pc = <String, dynamic>{};
    if (planType == AIPlanType.byok) {
      pc['byok'] = true;
      pc['require_connection_test'] = requireConnectionTest;
      pc['allowed_providers'] = (byokProviders?.toList() ?? ['openai', 'anthropic']);
      pc['platform_fee'] = <String, dynamic>{
        'monthly_price': _parseDecimal(monthlyPrice.text),
        'yearly_price': _parseDecimal(yearlyPrice.text),
      };
      // سازگاری با مسیر صورتحساب اشتراک
      pc['subscription'] = pc['platform_fee'];
      return pc;
    }
    if (allowedModels.isNotEmpty) {
      pc['allowed_models'] = allowedModels.toList();
    }
    if (defaultModel != null && defaultModel.isNotEmpty) {
      pc['default_model'] = defaultModel;
    }
    if (planType == AIPlanType.subscription || planType == AIPlanType.hybrid) {
      pc['subscription'] = <String, dynamic>{
        'monthly_price': _parseDecimal(monthlyPrice.text),
        'yearly_price': _parseDecimal(yearlyPrice.text),
      };
    }
    if (planType == AIPlanType.payAsGo || planType == AIPlanType.hybrid) {
      final payAsGo = <String, dynamic>{
        'price_per_1k_input_tokens': _parseDecimal(payInput.text),
        'price_per_1k_output_tokens': _parseDecimal(payOutput.text),
      };
      if (perModelRates.isNotEmpty) {
        payAsGo['models'] = perModelRates.map(
          (code, rates) => MapEntry(
            code,
            <String, dynamic>{
              'price_per_1k_input_tokens': rates['input'] ?? 0,
              'price_per_1k_output_tokens': rates['output'] ?? 0,
            },
          ),
        );
      }
      pc['pay_as_go'] = payAsGo;
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

  String _modelLabel(String code) {
    for (final m in _catalogModels) {
      if (m.code == code) return m.displayName;
    }
    return code;
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
    final sub = Map<String, dynamic>.from(
      (pc['platform_fee'] as Map?) ?? (pc['subscription'] as Map?) ?? const {},
    );
    final pay = Map<String, dynamic>.from((pc['pay_as_go'] as Map?) ?? const {});
    monthlyPriceController.text = _formatNumForField(sub['monthly_price']);
    yearlyPriceController.text = _formatNumForField(sub['yearly_price']);
    payInput1kController.text = _formatNumForField(pay['price_per_1k_input_tokens']);
    payOutput1kController.text = _formatNumForField(pay['price_per_1k_output_tokens']);

    AIPlanType selectedPlanType = plan?.planType ?? AIPlanType.free;
    bool isActive = plan?.isActive ?? true;
    bool autoRenew = plan?.autoRenew ?? false;
    bool requireConnectionTest = pc['require_connection_test'] != false;
    final byokProviders = <String>{
      ...((pc['allowed_providers'] as List?)?.map((e) => e.toString()) ?? ['openai', 'anthropic']),
    };

    final existingAllowed = <String>{
      ...((pc['allowed_models'] as List?)?.map((e) => e.toString()) ?? []),
    };
    if (existingAllowed.isEmpty && _catalogModels.isNotEmpty) {
      existingAllowed.addAll(_catalogModels.map((m) => m.code));
    }
    var selectedAllowed = Set<String>.from(existingAllowed);
    String? selectedDefault = pc['default_model']?.toString();
    if (selectedDefault != null && !selectedAllowed.contains(selectedDefault)) {
      selectedDefault = selectedAllowed.isNotEmpty ? selectedAllowed.first : null;
    }

    final modelRates = <String, Map<String, TextEditingController>>{};
    final modelsMap = (pay['models'] as Map?) ?? const {};
    for (final code in selectedAllowed) {
      final rates = Map<String, dynamic>.from((modelsMap[code] as Map?) ?? const {});
      modelRates[code] = {
        'input': TextEditingController(
          text: _formatNumForField(rates['price_per_1k_input_tokens']),
        ),
        'output': TextEditingController(
          text: _formatNumForField(rates['price_per_1k_output_tokens']),
        ),
      };
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currencySuffix = _walletCurrencyLabel.isNotEmpty ? ' ($_walletCurrencyLabel)' : '';
          final pricingHint = _walletCurrencyLabel.isEmpty
              ? adminTx(
                  context,
                  'قیمت اشتراک و نرخ توکن با ارز پایه کیف پول سیستم ثبت می‌شود.',
                  'Subscription prices and token rates use the system wallet currency.',
                )
              : adminTx(
                  context,
                  'مبالغ زیر با ارز پایه کیف پول است: $_walletCurrencyLabel',
                  'Amounts below use the wallet currency: $_walletCurrencyLabel',
                );

          return Dialog(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEdit ? adminTx(context, 'ویرایش پلن', 'Edit plan') : adminTx(context, 'پلن جدید', 'New plan'),
                            style: context.settingsHub.cardTitleStyle(
                              Theme.of(context).textTheme,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
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
                              decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'نام پلن', 'Plan name')),
                              validator: (v) => (v?.isEmpty ?? true) ? adminTx(context, 'الزامی است', 'Required') : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: codeController,
                              decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'کد پلن', 'Plan code')),
                              enabled: !isEdit,
                              validator: (v) => (v?.isEmpty ?? true) ? adminTx(context, 'الزامی است', 'Required') : null,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<AIPlanType>(
                              key: ValueKey<AIPlanType>(selectedPlanType),
                              initialValue: selectedPlanType,
                              decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'نوع پلن', 'Plan type')),
                              items: AIPlanType.values.map((type) {
                                return DropdownMenuItem(value: type, child: Text(_planTypeLabel(type)));
                              }).toList(),
                              onChanged: (v) => setDialogState(() => selectedPlanType = v!),
                            ),
                            if (selectedPlanType == AIPlanType.byok) ...[
                              const SizedBox(height: 12),
                              Text(
                                adminTx(
                                  context,
                                  'مالک کسب‌وکار آدرس و کلید خودش را تنظیم می‌کند و هزینه مدل را مستقیم به ارائه‌دهنده می‌پردازد.',
                                  'The business owner sets their own address and key, and pays the provider directly.',
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                adminTx(context, 'کارمزد پلتفرم (اختیاری)$currencySuffix', 'Platform fee (optional)$currencySuffix'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: monthlyPriceController,
                                decoration: InputDecoration(
                                  labelText: adminTx(context, 'کارمزد ماهانه$currencySuffix', 'Monthly fee$currencySuffix'),
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
                                  labelText: adminTx(context, 'کارمزد سالانه$currencySuffix', 'Yearly fee$currencySuffix'),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(adminTx(context, 'ارائه‌دهندگان مجاز', 'Allowed providers'), style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final p in const ['openai', 'anthropic', 'local'])
                                    FilterChip(
                                      label: Text(p),
                                      selected: byokProviders.contains(p),
                                      onSelected: (v) {
                                        setDialogState(() {
                                          if (v) {
                                            byokProviders.add(p);
                                          } else if (byokProviders.length > 1) {
                                            byokProviders.remove(p);
                                          }
                                        });
                                      },
                                    ),
                                ],
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(adminTx(context, 'الزام تست اتصال موفق قبل از استفاده', 'Require a successful connection test before use')),
                                value: requireConnectionTest,
                                onChanged: (v) => setDialogState(() => requireConnectionTest = v),
                              ),
                            ],
                            if (selectedPlanType == AIPlanType.subscription ||
                                selectedPlanType == AIPlanType.hybrid) ...[
                              const SizedBox(height: 16),
                              Text(
                                adminTx(context, 'قیمت اشتراک$currencySuffix', 'Subscription price$currencySuffix'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: monthlyPriceController,
                                decoration: InputDecoration(
                                  labelText: adminTx(context, 'قیمت ماهانه$currencySuffix', 'Monthly price$currencySuffix'),
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
                                  labelText: adminTx(context, 'قیمت سالانه$currencySuffix', 'Yearly price$currencySuffix'),
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
                                adminTx(context, 'نرخ پرداخت به‌ازای استفاده (هر ۱۰۰۰ توکن)$currencySuffix', 'Pay-as-you-go rate (per 1,000 tokens)$currencySuffix'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                adminTx(context, 'نرخ پیش‌فرض، اگر برای مدلی نرخ جدا نباشد', 'Default rate when a model has no separate rate'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: payInput1kController,
                                decoration: InputDecoration(
                                  labelText: adminTx(context, 'قیمت هر ۱۰۰۰ توکن ورودی$currencySuffix', 'Price per 1,000 input tokens$currencySuffix'),
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
                                  labelText: adminTx(context, 'قیمت هر ۱۰۰۰ توکن خروجی$currencySuffix', 'Price per 1,000 output tokens$currencySuffix'),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ],
                              ),
                              if (modelRates.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text(
                                  adminTx(context, 'نرخ اختصاصی هر مدل', 'Rate for each model'),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                ...modelRates.entries.map((entry) {
                                  final label = _modelLabel(entry.key);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(label, style: Theme.of(context).textTheme.labelLarge),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: entry.value['input'],
                                                decoration: InputDecoration(
                                                  labelText: adminTx(context, 'ورودی / ۱k$currencySuffix', 'Input / 1k$currencySuffix'),
                                                ),
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextFormField(
                                                controller: entry.value['output'],
                                                decoration: InputDecoration(
                                                  labelText: adminTx(context, 'خروجی / ۱k$currencySuffix', 'Output / 1k$currencySuffix'),
                                                ),
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                            if (selectedPlanType != AIPlanType.byok) ...[
                            const SizedBox(height: 16),
                            Text(
                              adminTx(context, 'مدل‌های مجاز در این پلن', 'Models allowed on this plan'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            if (_catalogModels.isEmpty)
                              Text(
                                adminTx(context, 'ابتدا در زبانهٔ مدل‌ها حداقل یک مدل تعریف کنید.', 'Define at least one model on the Models tab first.'),
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: _catalogModels.map((m) {
                                  final selected = selectedAllowed.contains(m.code);
                                  return FilterChip(
                                    label: Text(m.displayName),
                                    selected: selected,
                                    onSelected: (v) {
                                      setDialogState(() {
                                        if (v) {
                                          selectedAllowed.add(m.code);
                                          modelRates.putIfAbsent(
                                            m.code,
                                            () => {
                                              'input': TextEditingController(),
                                              'output': TextEditingController(),
                                            },
                                          );
                                        } else {
                                          selectedAllowed.remove(m.code);
                                          modelRates.remove(m.code);
                                          if (selectedDefault == m.code) {
                                            selectedDefault = selectedAllowed.isEmpty
                                                ? null
                                                : selectedAllowed.first;
                                          }
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            if (selectedAllowed.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: selectedDefault,
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: adminTx(context, 'مدل پیش‌فرض پلن', 'Default plan model'),
                                ),
                                items: selectedAllowed
                                    .map(
                                      (code) => DropdownMenuItem(
                                        value: code,
                                        child: Text(_modelLabel(code)),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setDialogState(() => selectedDefault = v),
                              ),
                            ],
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: tokensLimitController,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: adminTx(context, 'محدودیت توکن', 'Token limit'),
                                helperText: adminTx(
                                  context,
                                  'اختیاری؛ اگر سقف ماهانه خالی باشد برای سهمیه ماهانه استفاده می‌شود',
                                  'Optional. Used as the monthly quota when the monthly cap is empty',
                                ),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: monthlyTokensLimitController,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: adminTx(context, 'محدودیت ماهانه توکن', 'Monthly token limit'),
                                helperText: adminTx(context, 'برای پلن رایگان، اشتراک و ترکیبی؛ این مقدار اولویت دارد', 'For free, subscription, and hybrid plans; this value takes priority'),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            ],
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: descriptionController,
                              decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'توضیحات', 'Description')),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: Text(adminTx(context, 'فعال', 'Active')),
                              value: isActive,
                              onChanged: (v) => setDialogState(() => isActive = v),
                            ),
                            SwitchListTile(
                              title: Text(adminTx(context, 'تمدید خودکار', 'Auto renew')),
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
                          child: Text(adminTx(context, 'لغو', 'Cancel')),
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
                                selectedAllowed,
                                selectedDefault,
                                {
                                  for (final e in modelRates.entries)
                                    e.key: {
                                      'input': _parseDecimal(e.value['input']!.text),
                                      'output': _parseDecimal(e.value['output']!.text),
                                    },
                                },
                                byokProviders: byokProviders,
                                requireConnectionTest: requireConnectionTest,
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
                                SnackBar(content: Text('${adminTx(context, 'خطا', 'Error')}: ${ErrorExtractor.forContext(e, context)}')),
                              );
                            }
                          },
                          child: Text(isEdit ? adminTx(context, 'ذخیره', 'Save') : adminTx(context, 'ایجاد', 'Create')),
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
        appBar: aiHubAppBar(
          embedded: widget.embedded,
          title: Text(adminTx(context, 'پلن‌های AI', 'AI plans')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _plans.isEmpty) {
      return Scaffold(
        appBar: aiHubAppBar(
          embedded: widget.embedded,
          title: Text(adminTx(context, 'پلن‌های AI', 'AI plans')),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${adminTx(context, 'خطا', 'Error')}: $_error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: aiHubAppBar(
        embedded: widget.embedded,
        title: Text(adminTx(context, 'پلن‌های AI', 'AI plans')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: () => _showPlanFormDialog(),
            tooltip: adminTx(context, 'پلن جدید', 'New plan'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _plans.isEmpty
            ? Center(child: Text(adminTx(context, 'پلنی وجود ندارد', 'No plans yet')))
            : ListView.builder(
                padding: context.settingsHub.pagePadding,
                itemCount: _plans.length,
                itemBuilder: (context, index) {
                  final plan = _plans[index];
                  String planTypeLabel = _planTypeLabel(plan.planType);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        plan.name,
                        style: context.settingsHub.cardTitleStyle(
                          Theme.of(context).textTheme,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text('$planTypeLabel · ${plan.code}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (plan.isActive)
                            Icon(Icons.check_circle, color: SemanticColorResolver.positive(context))
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
                                    builder: (dialogContext) => AlertDialog(
                                      title: Text(adminTx(context, 'حذف پلن', 'Delete plan')),
                                      content: Text(adminTx(context, 'این پلن حذف شود؟', 'Delete this plan?')),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext, false),
                                          child: Text(adminTx(context, 'لغو', 'Cancel')),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(dialogContext, true),
                                          child: Text(adminTx(context, 'حذف', 'Delete')),
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
                                      SnackBar(content: Text('${adminTx(context, 'خطا', 'Error')}: ${ErrorExtractor.forContext(e, context)}')),
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
