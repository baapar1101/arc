import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../services/system_settings_service.dart';
import '../../services/document_monetization_service.dart';
import '../../services/business_api_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class DocumentMonetizationAdminPage extends StatefulWidget {
  const DocumentMonetizationAdminPage({super.key});

  @override
  State<DocumentMonetizationAdminPage> createState() => _DocumentMonetizationAdminPageState();
}

class _DocumentMonetizationAdminPageState extends State<DocumentMonetizationAdminPage> {
  late final DocumentMonetizationService _service;
  late final SystemSettingsService _settingsService;
  final TextEditingController _businessIdController = TextEditingController();
  final TextEditingController _singleDocPriceController = TextEditingController(text: '0');
  final TextEditingController _singleDocDescriptionController = TextEditingController();
  final TextEditingController _targetBusinessIdsController = TextEditingController();
  // برای بخش اعمال سیاست به کسب‌وکارهای موجود
  final TextEditingController _bulkPolicyBusinessIdsController = TextEditingController();
  final TextEditingController _bulkPolicyPriorityController = TextEditingController(text: '100');
  final TextEditingController _bulkPolicyTitleController = TextEditingController();
  // برای per_document
  final TextEditingController _bulkPerDocFeeController = TextEditingController(text: '0');
  final TextEditingController _bulkPerDocDescriptionController = TextEditingController();
  // برای volume
  final TextEditingController _bulkVolumeTierAmountController = TextEditingController(text: '0');
  final TextEditingController _bulkVolumePricePerTierController = TextEditingController(text: '0');
  final TextEditingController _bulkVolumeFreeThresholdController = TextEditingController(text: '0');

  bool _loadingPlans = true;
  bool _loadingPolicies = false;
  bool _applyToAllBusinesses = true;
  bool _singleDocAutoCharge = true;
  bool _singleDocCascade = true;
  bool _applyingBulkPolicy = false;
  double _bulkProgress = 0;
  String? _bulkStatus;
  String? _error;

  List<Map<String, dynamic>> _plans = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _policies = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _defaultPolicies = const <Map<String, dynamic>>[];
  int? _selectedBusinessId;
  String? _walletCurrencyCode;
  String? _walletCurrencyTitle;
  bool _loadingDefaultPolicies = false;
  bool _savingDefaultPolicies = false;
  // برای بخش اعمال سیاست به کسب‌وکارهای موجود
  String? _selectedBulkPolicyType;
  bool _bulkPolicyApplyToAll = true;
  bool _bulkPolicyAutoCharge = true;
  bool _bulkPolicyCascade = true;
  String? _bulkVolumeCycle = 'monthly';
  bool _applyingBulkPolicyToExisting = false;
  double _bulkPolicyProgress = 0;
  String? _bulkPolicyStatus;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _service = DocumentMonetizationService(api);
    _settingsService = SystemSettingsService(api);
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loadingPlans = true;
      _loadingDefaultPolicies = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.listSubscriptionPlans(),
        _settingsService.getWalletSettings(),
        _service.getDefaultPolicies(),
      ]);
      final plans = results[0] as List<Map<String, dynamic>>;
      final walletSettings = Map<String, dynamic>.from(results[1] as Map);
      final defaultPolicies = results[2] as List<Map<String, dynamic>>;
      setState(() {
        _plans = plans;
        _walletCurrencyCode = walletSettings['wallet_base_currency_code'] as String?;
        _walletCurrencyTitle = walletSettings['wallet_base_currency_title'] as String?;
        _defaultPolicies = defaultPolicies;
        _loadingPlans = false;
        _loadingDefaultPolicies = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loadingPlans = false;
        _loadingDefaultPolicies = false;
      });
    }
  }

  Future<void> _loadPolicies() async {
    final raw = _businessIdController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _error = 'شناسه کسب‌وکار را وارد کنید';
      });
      return;
    }
    final id = int.tryParse(raw);
    if (id == null) {
      setState(() {
        _error = 'شناسه کسب‌وکار نامعتبر است';
      });
      return;
    }
    setState(() {
      _loadingPolicies = true;
      _error = null;
      _selectedBusinessId = id;
    });
    try {
      final policies = await _service.listBusinessPoliciesAdmin(id);
      setState(() {
        _policies = policies;
        _loadingPolicies = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loadingPolicies = false;
      });
    }
  }

  Future<void> _showPlanDialog({Map<String, dynamic>? initial}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: initial?['name'] ?? '');
    final codeCtrl = TextEditingController(text: initial?['code'] ?? '');
    final periodCtrl = TextEditingController(text: initial?['period_months']?.toString() ?? '1');
    final priceCtrl = TextEditingController(text: initial?['price']?.toString() ?? '0');
    bool isActive = initial?['is_active'] ?? true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInnerState) => AlertDialog(
          title: Text(initial == null ? 'پلن جدید' : 'ویرایش پلن'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'نام پلن'),
                      validator: (v) => v == null || v.isEmpty ? 'نام الزامی است' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'کد پلن'),
                      enabled: initial == null,
                      validator: (v) => v == null || v.isEmpty ? 'کد الزامی است' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: periodCtrl,
                      decoration: const InputDecoration(labelText: 'مدت (ماه)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'مدت الزامی است';
                        final val = int.tryParse(v);
                        if (val == null || val <= 0) return 'مدت نامعتبر است';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priceCtrl,
                      decoration: InputDecoration(labelText: 'قیمت ($_walletCurrencyLabel)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => v == null || v.isEmpty ? 'قیمت الزامی است' : null,
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'ارز پایه',
                        prefixIcon: Icon(Icons.currency_exchange),
                      ),
                      child: Text(_walletCurrencyLabel),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('فعال'),
                      value: isActive,
                      onChanged: (v) => setInnerState(() => isActive = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final map = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'code': codeCtrl.text.trim(),
                  'period_months': int.parse(periodCtrl.text.trim()),
                  'price': double.tryParse(priceCtrl.text.trim()) ?? 0,
                  'is_active': isActive,
                };
                try {
                  if (initial == null) {
                    await _service.createSubscriptionPlan(map);
                  } else {
                    await _service.updateSubscriptionPlan(initial['id'] as int, map);
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _loadInitial();
                } catch (e) {
                  if (!context.mounted) return;
                  SnackBarHelper.show(
                    context,
                    message: ErrorExtractor.forContext(e, context),
                  );
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
          ),
        );
      },
    );
  }

  Future<void> _showPolicyDialog({Map<String, dynamic>? initial}) async {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: initial?['title'] ?? '');
    final priorityCtrl = TextEditingController(text: initial?['priority']?.toString() ?? '100');
    final configCtrl = TextEditingController(
      text: initial == null ? '{\n  "fee_amount": 0\n}' : const JsonEncoder.withIndent('  ').convert(initial['config'] ?? {}),
    );
    bool isActive = initial?['is_active'] ?? true;
    String policyType = (initial?['policy_type'] ?? 'per_document') as String;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInnerState) => AlertDialog(
          title: Text(initial == null ? 'سیاست جدید' : 'ویرایش سیاست'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'عنوان'),
                      validator: (v) => v == null || v.isEmpty ? 'عنوان الزامی است' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: policyType,
                      decoration: const InputDecoration(labelText: 'نوع سیاست'),
                      items: const [
                        DropdownMenuItem(value: 'free', child: Text('رایگان')),
                        DropdownMenuItem(value: 'subscription', child: Text('اشتراک')),
                        DropdownMenuItem(value: 'per_document', child: Text('به‌ازای هر سند')),
                        DropdownMenuItem(value: 'volume', child: Text('حجمی/تناوبی')),
                        DropdownMenuItem(value: 'hybrid', child: Text('ترکیبی')),
                      ],
                      onChanged: (v) => setInnerState(() => policyType = v ?? policyType),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priorityCtrl,
                      decoration: const InputDecoration(labelText: 'اولویت'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => v == null || v.isEmpty ? 'اولویت الزامی است' : null,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('فعال'),
                      value: isActive,
                      onChanged: (v) => setInnerState(() => isActive = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: configCtrl,
                      decoration: const InputDecoration(
                        labelText: 'پیکربندی (JSON)',
                        alignLabelWithHint: true,
                      ),
                      maxLines: 8,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'پیکربندی الزامی است';
                        try {
                          jsonDecode(v);
                          return null;
                        } catch (_) {
                          return 'فرمت JSON نامعتبر است';
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (_selectedBusinessId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ابتدا کسب‌وکار را انتخاب کنید')));
                  return;
                }
                try {
                  final config = jsonDecode(configCtrl.text) as Map<String, dynamic>;
                  final payload = <String, dynamic>{
                    "title": titleCtrl.text.trim(),
                    "policy_type": policyType,
                    "priority": int.parse(priorityCtrl.text.trim()),
                    "is_active": isActive,
                    "config": config,
                  };
                  if (initial != null) {
                    payload["id"] = initial["id"];
                  }
                  await _service.saveBusinessPolicyAdmin(_selectedBusinessId!, payload);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _loadPolicies();
                } catch (e) {
                  if (!context.mounted) return;
                  SnackBarHelper.show(
                    context,
                    message: ErrorExtractor.forContext(e, context),
                  );
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _businessIdController.dispose();
    _singleDocPriceController.dispose();
    _singleDocDescriptionController.dispose();
    _targetBusinessIdsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('سناریوی درآمدزایی اسناد'),
      ),
      body: _loadingPlans && _plans.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadInitial();
                if (_selectedBusinessId != null) {
                  await _loadPolicies();
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ),
                    _buildDefaultPoliciesCard(theme),
                    const SizedBox(height: 24),
                    _buildBulkApplyPolicyCard(theme),
                    const SizedBox(height: 24),
                    _buildSingleDocumentPolicyCard(theme),
                    const SizedBox(height: 24),
                    _buildPlansCard(theme),
                    const SizedBox(height: 24),
                    _buildPoliciesCard(theme),
                  ],
                ),
              ),
            ),
      floatingActionButton: _selectedBusinessId != null
          ? FloatingActionButton.extended(
              onPressed: () => _showPolicyDialog(),
              icon: const Icon(Icons.add),
              label: const Text('سیاست جدید'),
            )
          : null,
    );
  }

  Widget _buildDefaultPoliciesCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سیاست‌های پیش‌فرض کسب‌وکارهای جدید',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'این سیاست‌ها به صورت خودکار برای هر کسب‌وکار جدید اعمال می‌شوند. اولویت‌ها به ترتیب از کم به زیاد بررسی می‌شوند.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'سیاست‌ها به ترتیب اولویت بررسی می‌شوند. عدد کمتر = اولویت بالاتر',
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadingDefaultPolicies)
              const Center(child: CircularProgressIndicator())
            else if (_defaultPolicies.isEmpty)
              const Text('هیچ سیاست پیش‌فرضی تعریف نشده است')
            else
              ..._defaultPolicies.asMap().entries.map((entry) {
                final index = entry.key;
                final policy = entry.value;
                return _buildDefaultPolicyTile(theme, index, policy);
              }),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: _savingDefaultPolicies ? null : _saveDefaultPolicies,
                  icon: _savingDefaultPolicies
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('ذخیره تغییرات'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultPolicyTile(ThemeData theme, int index, Map<String, dynamic> policy) {
    final policyType = policy['policy_type'] as String? ?? '';
    final title = policy['title'] as String? ?? '';
    final priority = policy['priority'] as int? ?? 100;
    final isActive = policy['is_active'] as bool? ?? true;
    final config = policy['config'] as Map<String, dynamic>? ?? {};

    String typeLabel = '';
    IconData typeIcon = Icons.policy;
    switch (policyType) {
      case 'free':
        typeLabel = 'رایگان';
        typeIcon = Icons.check_circle_outline;
        break;
      case 'subscription':
        typeLabel = 'پکیج نامحدود';
        typeIcon = Icons.all_inclusive;
        break;
      case 'volume':
        typeLabel = 'حجمی';
        typeIcon = Icons.analytics;
        break;
      case 'per_document':
        typeLabel = 'تک سند';
        typeIcon = Icons.receipt;
        break;
      case 'hybrid':
        typeLabel = 'ترکیبی';
        typeIcon = Icons.merge_type;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(typeIcon),
        title: Text(title),
        subtitle: Text('نوع: $typeLabel | اولویت: $priority'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: isActive,
              onChanged: (value) {
                setState(() {
                  _defaultPolicies[index] = {...policy, 'is_active': value};
                });
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editDefaultPolicy(index, policy),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'اولویت',
                          helperText: 'عدد کمتر = اولویت بالاتر',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        controller: TextEditingController(text: priority.toString()),
                        onChanged: (value) {
                          final newPriority = int.tryParse(value);
                          if (newPriority != null) {
                            setState(() {
                              _defaultPolicies[index] = {...policy, 'priority': newPriority};
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(labelText: 'عنوان'),
                        controller: TextEditingController(text: title),
                        onChanged: (value) {
                          setState(() {
                            _defaultPolicies[index] = {...policy, 'title': value};
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (config.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تنظیمات:',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          const JsonEncoder.withIndent('  ').convert(config),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDefaultPolicy(int index, Map<String, dynamic> policy) async {
    final policyType = policy['policy_type'] as String? ?? '';
    final config = Map<String, dynamic>.from(policy['config'] as Map? ?? {});
    
    // برای انواع مختلف سیاست، فرم‌های مختلف نمایش می‌دهیم
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('ویرایش تنظیمات: ${policy['title']}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: _buildPolicyConfigEditor(policyType, config, (newConfig) {
                setState(() {
                  _defaultPolicies[index] = {...policy, 'config': newConfig};
                });
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('بستن'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPolicyConfigEditor(String policyType, Map<String, dynamic> config, Function(Map<String, dynamic>) onUpdate) {
    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{};
    
    // ایجاد کنترلرها بر اساس نوع سیاست
    if (policyType == 'per_document') {
      controllers['fee_amount'] = TextEditingController(text: (config['fee_amount'] ?? 0).toString());
      controllers['auto_charge_wallet'] = TextEditingController(text: (config['auto_charge_wallet'] ?? true).toString());
      controllers['cascade'] = TextEditingController(text: (config['cascade'] ?? false).toString());
      controllers['description'] = TextEditingController(text: config['description'] ?? '');
    } else if (policyType == 'volume') {
      controllers['cycle'] = TextEditingController(text: config['cycle'] ?? 'monthly');
      controllers['tier_amount'] = TextEditingController(text: (config['tier_amount'] ?? 0).toString());
      controllers['price_per_tier'] = TextEditingController(text: (config['price_per_tier'] ?? 0).toString());
      controllers['free_threshold_amount'] = TextEditingController(text: (config['free_threshold_amount'] ?? 0).toString());
      controllers['cascade'] = TextEditingController(text: (config['cascade'] ?? true).toString());
    } else if (policyType == 'subscription') {
      controllers['cascade'] = TextEditingController(text: (config['cascade'] ?? true).toString());
    }

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (policyType == 'per_document') ...[
            TextFormField(
              controller: controllers['fee_amount'],
              decoration: const InputDecoration(labelText: 'هزینه هر سند'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                final newConfig = {
                  'fee_amount': double.tryParse(controllers['fee_amount']!.text) ?? 0,
                  'auto_charge_wallet': controllers['auto_charge_wallet']!.text == 'true',
                  'cascade': controllers['cascade']!.text == 'true',
                  'description': controllers['description']!.text,
                };
                onUpdate(newConfig);
              },
            ),
            SwitchListTile(
              title: const Text('کسر خودکار از کیف‌پول'),
              value: controllers['auto_charge_wallet']!.text == 'true',
              onChanged: (value) {
                controllers['auto_charge_wallet']!.text = value.toString();
                final newConfig = {
                  'fee_amount': double.tryParse(controllers['fee_amount']!.text) ?? 0,
                  'auto_charge_wallet': value,
                  'cascade': controllers['cascade']!.text == 'true',
                  'description': controllers['description']!.text,
                };
                onUpdate(newConfig);
              },
            ),
            SwitchListTile(
              title: const Text('اجازه ادامه سیاست‌های بعدی (cascade)'),
              value: controllers['cascade']!.text == 'true',
              onChanged: (value) {
                controllers['cascade']!.text = value.toString();
                final newConfig = {
                  'fee_amount': double.tryParse(controllers['fee_amount']!.text) ?? 0,
                  'auto_charge_wallet': controllers['auto_charge_wallet']!.text == 'true',
                  'cascade': value,
                  'description': controllers['description']!.text,
                };
                onUpdate(newConfig);
              },
            ),
            TextFormField(
              controller: controllers['description'],
              decoration: const InputDecoration(labelText: 'توضیح (اختیاری)'),
              onChanged: (_) {
                final newConfig = {
                  'fee_amount': double.tryParse(controllers['fee_amount']!.text) ?? 0,
                  'auto_charge_wallet': controllers['auto_charge_wallet']!.text == 'true',
                  'cascade': controllers['cascade']!.text == 'true',
                  'description': controllers['description']!.text,
                };
                onUpdate(newConfig);
              },
            ),
          ] else if (policyType == 'volume') ...[
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'دوره'),
              initialValue: controllers['cycle']!.text,
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('هفتگی')),
                DropdownMenuItem(value: 'monthly', child: Text('ماهانه')),
                DropdownMenuItem(value: 'yearly', child: Text('سالانه')),
              ],
              onChanged: (value) {
                if (value != null) {
                  controllers['cycle']!.text = value;
                  final newConfig = {
                    'cycle': value,
                    'tier_amount': double.tryParse(controllers['tier_amount']!.text) ?? 0,
                    'price_per_tier': double.tryParse(controllers['price_per_tier']!.text) ?? 0,
                    'free_threshold_amount': double.tryParse(controllers['free_threshold_amount']!.text) ?? 0,
                    'cascade': controllers['cascade']!.text == 'true',
                  };
                  onUpdate(newConfig);
                }
              },
            ),
            TextFormField(
              controller: controllers['tier_amount'],
              decoration: const InputDecoration(labelText: 'مبلغ هر پله'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                final newConfig = {
                  'cycle': controllers['cycle']!.text,
                  'tier_amount': double.tryParse(controllers['tier_amount']!.text) ?? 0,
                  'price_per_tier': double.tryParse(controllers['price_per_tier']!.text) ?? 0,
                  'free_threshold_amount': double.tryParse(controllers['free_threshold_amount']!.text) ?? 0,
                  'cascade': controllers['cascade']!.text == 'true',
                };
                onUpdate(newConfig);
              },
            ),
            TextFormField(
              controller: controllers['price_per_tier'],
              decoration: const InputDecoration(labelText: 'قیمت هر پله'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                final newConfig = {
                  'cycle': controllers['cycle']!.text,
                  'tier_amount': double.tryParse(controllers['tier_amount']!.text) ?? 0,
                  'price_per_tier': double.tryParse(controllers['price_per_tier']!.text) ?? 0,
                  'free_threshold_amount': double.tryParse(controllers['free_threshold_amount']!.text) ?? 0,
                  'cascade': controllers['cascade']!.text == 'true',
                };
                onUpdate(newConfig);
              },
            ),
            TextFormField(
              controller: controllers['free_threshold_amount'],
              decoration: const InputDecoration(labelText: 'آستانه رایگان'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                final newConfig = {
                  'cycle': controllers['cycle']!.text,
                  'tier_amount': double.tryParse(controllers['tier_amount']!.text) ?? 0,
                  'price_per_tier': double.tryParse(controllers['price_per_tier']!.text) ?? 0,
                  'free_threshold_amount': double.tryParse(controllers['free_threshold_amount']!.text) ?? 0,
                  'cascade': controllers['cascade']!.text == 'true',
                };
                onUpdate(newConfig);
              },
            ),
            SwitchListTile(
              title: const Text('اجازه ادامه سیاست‌های بعدی (cascade)'),
              value: controllers['cascade']!.text == 'true',
              onChanged: (value) {
                controllers['cascade']!.text = value.toString();
                final newConfig = {
                  'cycle': controllers['cycle']!.text,
                  'tier_amount': double.tryParse(controllers['tier_amount']!.text) ?? 0,
                  'price_per_tier': double.tryParse(controllers['price_per_tier']!.text) ?? 0,
                  'free_threshold_amount': double.tryParse(controllers['free_threshold_amount']!.text) ?? 0,
                  'cascade': value,
                };
                onUpdate(newConfig);
              },
            ),
          ] else if (policyType == 'subscription') ...[
            SwitchListTile(
              title: const Text('اجازه ادامه سیاست‌های بعدی (cascade)'),
              value: controllers['cascade']!.text == 'true',
              onChanged: (value) {
                controllers['cascade']!.text = value.toString();
                onUpdate({'cascade': value});
              },
            ),
          ] else ...[
            const Text('این نوع سیاست تنظیمات خاصی ندارد'),
          ],
        ],
      ),
    );
  }

  Future<void> _saveDefaultPolicies() async {
    setState(() {
      _savingDefaultPolicies = true;
      _error = null;
    });
    try {
      // مرتب‌سازی بر اساس اولویت
      final sorted = List<Map<String, dynamic>>.from(_defaultPolicies);
      sorted.sort((a, b) => (a['priority'] as int? ?? 100).compareTo(b['priority'] as int? ?? 100));
      
      await _service.setDefaultPolicies(sorted);
      if (!mounted) return;
      setState(() {
        _defaultPolicies = sorted;
        _savingDefaultPolicies = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سیاست‌های پیش‌فرض با موفقیت ذخیره شدند')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'خطا در ذخیره: ${ErrorExtractor.forContext(e, context)}';
        _savingDefaultPolicies = false;
      });
    }
  }

  Widget _buildBulkApplyPolicyCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اعمال سیاست به کسب‌وکارهای موجود',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'اعمال سیاست‌های مختلف به صورت انبوه برای کسب‌وکارهای موجود',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'می‌توانید سیاست‌های مختلف را به صورت انبوه برای کسب‌وکارهای موجود اعمال کنید',
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'نوع سیاست',
                prefixIcon: Icon(Icons.policy),
              ),
              initialValue: _selectedBulkPolicyType,
              items: const [
                DropdownMenuItem(value: 'free', child: Text('رایگان')),
                DropdownMenuItem(value: 'subscription', child: Text('پکیج نامحدود')),
                DropdownMenuItem(value: 'volume', child: Text('حجمی')),
                DropdownMenuItem(value: 'per_document', child: Text('تک سند')),
                DropdownMenuItem(value: 'hybrid', child: Text('ترکیبی')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedBulkPolicyType = value;
                });
              },
            ),
            if (_selectedBulkPolicyType != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _bulkPolicyTitleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان سیاست',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bulkPolicyPriorityController,
                decoration: const InputDecoration(
                  labelText: 'اولویت',
                  helperText: 'عدد کمتر = اولویت بالاتر',
                  prefixIcon: Icon(Icons.sort),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),
              // تنظیمات بر اساس نوع سیاست
              _buildBulkPolicyConfigFields(theme),
              const SizedBox(height: 16),
              // انتخاب دامنه اعمال
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool>(
                      value: true,
                      // ignore: deprecated_member_use
                      groupValue: _bulkPolicyApplyToAll,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setState(() => _bulkPolicyApplyToAll = v ?? true),
                      title: const Text('همه کسب‌وکارها'),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      value: false,
                      // ignore: deprecated_member_use
                      groupValue: _bulkPolicyApplyToAll,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setState(() => _bulkPolicyApplyToAll = v ?? false),
                      title: const Text('لیست شناسه‌ها'),
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: _bulkPolicyApplyToAll ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextField(
                    controller: _bulkPolicyBusinessIdsController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'شناسه کسب‌وکارها (با ویرگول یا خط جدید جدا کنید)',
                      prefixIcon: Icon(Icons.list_alt_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _applyingBulkPolicyToExisting ? null : _applyBulkPolicyToExisting,
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('اعمال سیاست'),
              ),
              if (_applyingBulkPolicyToExisting) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _bulkPolicyProgress == 0 ? null : _bulkPolicyProgress),
                if (_bulkPolicyStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _bulkPolicyStatus!,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBulkPolicyConfigFields(ThemeData theme) {
    if (_selectedBulkPolicyType == null) return const SizedBox.shrink();

    switch (_selectedBulkPolicyType) {
      case 'free':
        return const SizedBox.shrink();
      case 'subscription':
        return Column(
          children: [
            SwitchListTile(
              title: const Text('اجازه ادامه سیاست‌های بعدی (cascade)'),
              value: _bulkPolicyCascade,
              onChanged: (value) => setState(() => _bulkPolicyCascade = value),
            ),
          ],
        );
      case 'per_document':
        return Column(
          children: [
            TextField(
              controller: _bulkPerDocFeeController,
              decoration: InputDecoration(
                labelText: 'هزینه هر سند ($_walletCurrencyLabel)',
                prefixIcon: const Icon(Icons.price_change_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('کسر خودکار از کیف‌پول'),
              value: _bulkPolicyAutoCharge,
              onChanged: (value) => setState(() => _bulkPolicyAutoCharge = value),
            ),
            SwitchListTile(
              title: const Text('اجازه ادامه سیاست‌های بعدی (cascade)'),
              value: _bulkPolicyCascade,
              onChanged: (value) => setState(() => _bulkPolicyCascade = value),
            ),
            TextField(
              controller: _bulkPerDocDescriptionController,
              decoration: const InputDecoration(
                labelText: 'توضیح (اختیاری)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
          ],
        );
      case 'volume':
        return Column(
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'دوره',
                prefixIcon: Icon(Icons.calendar_today),
              ),
              initialValue: _bulkVolumeCycle,
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('هفتگی')),
                DropdownMenuItem(value: 'monthly', child: Text('ماهانه')),
                DropdownMenuItem(value: 'yearly', child: Text('سالانه')),
              ],
              onChanged: (value) => setState(() => _bulkVolumeCycle = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bulkVolumeTierAmountController,
              decoration: InputDecoration(
                labelText: 'مبلغ هر پله ($_walletCurrencyLabel)',
                prefixIcon: const Icon(Icons.analytics),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bulkVolumePricePerTierController,
              decoration: InputDecoration(
                labelText: 'قیمت هر پله ($_walletCurrencyLabel)',
                prefixIcon: const Icon(Icons.attach_money),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bulkVolumeFreeThresholdController,
              decoration: InputDecoration(
                labelText: 'آستانه رایگان ($_walletCurrencyLabel)',
                prefixIcon: const Icon(Icons.free_breakfast),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('اجازه ادامه سیاست‌های بعدی (cascade)'),
              value: _bulkPolicyCascade,
              onChanged: (value) => setState(() => _bulkPolicyCascade = value),
            ),
          ],
        );
      case 'hybrid':
        return Column(
          children: [
            SwitchListTile(
              title: const Text('اجازه ادامه سیاست‌های بعدی (cascade)'),
              value: _bulkPolicyCascade,
              onChanged: (value) => setState(() => _bulkPolicyCascade = value),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _applyBulkPolicyToExisting() async {
    if (_selectedBulkPolicyType == null) {
      _showSnack('نوع سیاست را انتخاب کنید');
      return;
    }

    final title = _bulkPolicyTitleController.text.trim();
    if (title.isEmpty) {
      _showSnack('عنوان سیاست را وارد کنید');
      return;
    }

    final priority = int.tryParse(_bulkPolicyPriorityController.text.trim());
    if (priority == null || priority < 0) {
      _showSnack('اولویت معتبر وارد کنید');
      return;
    }

    // ساخت config بر اساس نوع سیاست
    Map<String, dynamic> config = {};
    if (_selectedBulkPolicyType == 'per_document') {
      final fee = double.tryParse(_bulkPerDocFeeController.text.replaceAll(',', '').trim());
      if (fee == null || fee <= 0) {
        _showSnack('مبلغ معتبر وارد کنید');
        return;
      }
      config = {
        'fee_amount': fee,
        'auto_charge_wallet': _bulkPolicyAutoCharge,
        'cascade': _bulkPolicyCascade,
      };
      final desc = _bulkPerDocDescriptionController.text.trim();
      if (desc.isNotEmpty) {
        config['description'] = desc;
      }
    } else if (_selectedBulkPolicyType == 'volume') {
      final tierAmount = double.tryParse(_bulkVolumeTierAmountController.text.replaceAll(',', '').trim());
      final pricePerTier = double.tryParse(_bulkVolumePricePerTierController.text.replaceAll(',', '').trim());
      final freeThreshold = double.tryParse(_bulkVolumeFreeThresholdController.text.replaceAll(',', '').trim());
      if (tierAmount == null || tierAmount <= 0 || pricePerTier == null || pricePerTier <= 0) {
        _showSnack('مقادیر معتبر وارد کنید');
        return;
      }
      config = {
        'cycle': _bulkVolumeCycle ?? 'monthly',
        'tier_amount': tierAmount,
        'price_per_tier': pricePerTier,
        'free_threshold_amount': freeThreshold ?? 0,
        'cascade': _bulkPolicyCascade,
      };
    } else if (_selectedBulkPolicyType == 'subscription' || _selectedBulkPolicyType == 'hybrid') {
      config = {
        'cascade': _bulkPolicyCascade,
      };
    }

    // دریافت لیست کسب‌وکارها
    List<int> targetIds = <int>[];
    try {
      if (_bulkPolicyApplyToAll) {
        _showSnack('در حال آماده‌سازی لیست کسب‌وکارها...');
        targetIds = await _fetchAllBusinessIds();
      } else {
        targetIds = _parseBusinessIds(_bulkPolicyBusinessIdsController.text);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          'خطا در دریافت لیست کسب‌وکارها: ${ErrorExtractor.forContext(e, context)}',
        );
      }
      return;
    }

    if (targetIds.isEmpty) {
      _showSnack('هیچ کسب‌وکاری برای اعمال سیاست مشخص نشد');
      return;
    }

    final payload = <String, dynamic>{
      'title': title,
      'policy_type': _selectedBulkPolicyType,
      'priority': priority,
      'is_active': true,
      'config': config,
    };

    setState(() {
      _applyingBulkPolicyToExisting = true;
      _bulkPolicyProgress = 0;
      _bulkPolicyStatus = 'در حال اعمال برای ${targetIds.length} کسب‌وکار';
    });

    int success = 0;
    int failed = 0;

    for (int i = 0; i < targetIds.length; i++) {
      final businessId = targetIds[i];
      try {
        await _service.saveBusinessPolicyAdmin(businessId, payload);
        success++;
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
      setState(() {
        _bulkPolicyProgress = (i + 1) / targetIds.length;
        _bulkPolicyStatus = 'اعمال ${i + 1} از ${targetIds.length} (موفق: $success | ناموفق: $failed)';
      });
    }

    if (!mounted) return;
    setState(() {
      _applyingBulkPolicyToExisting = false;
      _bulkPolicyProgress = 0;
      _bulkPolicyStatus = 'موفق: $success | ناموفق: $failed';
    });
    _showSnack('اعمال سیاست انجام شد (موفق: $success | ناموفق: $failed)');
  }

  Widget _buildSingleDocumentPolicyCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'هزینه ثبت تکی اسناد',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'تعیین نرخ پایه برای ثبت هر سند حسابداری و اعمال آن بر روی همه یا بخشی از کسب‌وکارها',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'با این قابلیت می‌توانید سیاست per_document را به صورت انبوه برای کسب‌وکارها ثبت کنید.',
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _singleDocPriceController,
                    decoration: InputDecoration(
                      labelText: 'هزینه هر سند ($_walletCurrencyLabel)',
                      prefixIcon: Icon(Icons.price_change_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'ارز پایه',
                      prefixIcon: Icon(Icons.currency_exchange),
                    ),
                    child: Text(_walletCurrencyLabel),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _singleDocDescriptionController,
                    decoration: const InputDecoration(
                      labelText: 'توضیح سیاست (اختیاری)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                FilterChip(
                  label: const Text('کسر خودکار از کیف‌پول'),
                  selected: _singleDocAutoCharge,
                  onSelected: (v) => setState(() => _singleDocAutoCharge = v),
                ),
                FilterChip(
                  label: const Text('اجازهٔ ادامه سیاست‌های بعدی (cascade)'),
                  selected: _singleDocCascade,
                  onSelected: (v) => setState(() => _singleDocCascade = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    value: true,
                    // ignore: deprecated_member_use
                    groupValue: _applyToAllBusinesses,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _applyToAllBusinesses = v ?? true),
                    title: const Text('همهٔ کسب‌وکارها'),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    value: false,
                    // ignore: deprecated_member_use
                    groupValue: _applyToAllBusinesses,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _applyToAllBusinesses = v ?? false),
                    title: const Text('شناسه‌های دلخواه'),
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _applyToAllBusinesses ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextField(
                  controller: _targetBusinessIdsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'شناسه کسب‌وکارها (با ویرگول یا خط جدید جدا کنید)',
                    prefixIcon: Icon(Icons.list_alt_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _applyingBulkPolicy ? null : _applySingleDocumentPolicy,
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('اعمال سیاست'),
                  ),
                ),
              ],
            ),
            if (_applyingBulkPolicy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _bulkProgress == 0 ? null : _bulkProgress),
              if (_bulkStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  _bulkStatus!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _applySingleDocumentPolicy() async {
    final rawPrice = _singleDocPriceController.text.replaceAll(',', '').trim();
    final price = double.tryParse(rawPrice);
    if (price == null || price <= 0) {
      _showSnack('مبلغ معتبر وارد کنید');
      return;
    }
    List<int> targetIds = <int>[];
    try {
      if (_applyToAllBusinesses) {
        _showSnack('در حال آماده‌سازی لیست کسب‌وکارها...');
        targetIds = await _fetchAllBusinessIds();
      } else {
        targetIds = _parseBusinessIds(_targetBusinessIdsController.text);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          'خطا در دریافت لیست کسب‌وکارها: ${ErrorExtractor.forContext(e, context)}',
        );
      }
      return;
    }

    if (targetIds.isEmpty) {
      _showSnack('هیچ کسب‌وکاری برای اعمال سیاست مشخص نشد');
      return;
    }

    final config = <String, dynamic>{
      'fee_amount': price,
      'auto_charge_wallet': _singleDocAutoCharge,
      'cascade': _singleDocCascade,
    };
    final desc = _singleDocDescriptionController.text.trim();
    if (desc.isNotEmpty) {
      config['description'] = desc;
    }

    final payload = <String, dynamic>{
      'title': 'هزینه ثبت تکی اسناد',
      'policy_type': 'per_document',
      'priority': 120,
      'is_active': true,
      'config': config,
    };

    setState(() {
      _applyingBulkPolicy = true;
      _bulkProgress = 0;
      _bulkStatus = 'در حال اعمال برای ${targetIds.length} کسب‌وکار';
    });

    int success = 0;
    int failed = 0;

    for (int i = 0; i < targetIds.length; i++) {
      final businessId = targetIds[i];
      try {
        await _service.saveBusinessPolicyAdmin(businessId, payload);
        success++;
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
      setState(() {
        _bulkProgress = (i + 1) / targetIds.length;
        _bulkStatus = 'اعمال ${i + 1} از ${targetIds.length}';
      });
    }

    if (!mounted) return;
    setState(() {
      _applyingBulkPolicy = false;
      _bulkProgress = 0;
      _bulkStatus = 'موفق: $success | ناموفق: $failed';
    });
    _showSnack('اعمال سیاست انجام شد (موفق: $success | ناموفق: $failed)');
  }

  Future<List<int>> _fetchAllBusinessIds() async {
    const pageSize = 200;
    int skip = 0;
    final ids = <int>[];

    while (true) {
      final data = await BusinessApiService.getAllBusinessesAdmin(take: pageSize, skip: skip);
      final items = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
      if (items.isEmpty) break;
      ids.addAll(items.map((e) => (e as Map<String, dynamic>)['id']).whereType<int>());
      skip += items.length;
      if (items.length < pageSize) break;
    }
    return ids;
  }

  List<int> _parseBusinessIds(String input) {
    final ids = <int>{};
    final normalized = input.replaceAll('\n', ',');
    for (final part in normalized.split(RegExp('[,،\\s]+'))) {
      if (part.isEmpty) continue;
      final id = int.tryParse(part.trim());
      if (id != null) {
        ids.add(id);
      }
    }
    return ids.toList();
  }

  String get _walletCurrencyLabel {
    final code = _walletCurrencyCode ?? '-';
    final title = _walletCurrencyTitle;
    if (title != null && title.isNotEmpty) {
      return '$title ($code)';
    }
    return code;
  }

  void _showSnack(String message) {
    SnackBarHelper.show(context, message: message);
  }

  Widget _buildPlansCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'پلن‌های اشتراک نامحدود اسناد',
                  style: theme.textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: () => _showPlanDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('پلن جدید'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingPlans)
              const Center(child: CircularProgressIndicator())
            else if (_plans.isEmpty)
              const Text('پلنی ثبت نشده است')
            else
              Column(
                children: _plans
                    .map(
                      (plan) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(plan['name'] as String? ?? '-'),
                        subtitle: Text(
                          'مدت: ${plan['period_months']} ماه | قیمت: ${plan['price']} ${plan['currency_code'] ?? _walletCurrencyCode ?? ''}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showPlanDialog(initial: plan),
                              tooltip: 'ویرایش',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('حذف پلن'),
                                    content: const Text('آیا از حذف پلن اطمینان دارید؟'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('انصراف'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('حذف'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await _service.deleteSubscriptionPlan(plan['id'] as int);
                                  if (!mounted) return;
                                  _loadInitial();
                                }
                              },
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoliciesCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'سیاست‌های فعال برای کسب‌وکار',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _businessIdController,
                    decoration: InputDecoration(
                      labelText: 'شناسه کسب‌وکار',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _businessIdController.clear();
                          setState(() {
                            _policies = const <Map<String, dynamic>>[];
                            _selectedBusinessId = null;
                          });
                        },
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loadPolicies,
                  icon: const Icon(Icons.search),
                  label: const Text('بارگذاری'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadingPolicies)
              const Center(child: CircularProgressIndicator())
            else if (_selectedBusinessId == null)
              const Text('برای مشاهده سیاست‌ها، شناسه کسب‌وکار را وارد کنید')
            else if (_policies.isEmpty)
              const Text('هیچ سیاستی برای این کسب‌وکار تعریف نشده است')
            else
              Column(
                children: _policies
                    .map(
                      (policy) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(policy['title'] as String? ?? '-'),
                          subtitle: Text('نوع: ${policy['policy_type']} | اولویت: ${policy['priority']}'),
                          leading: Icon(
                            policy['is_active'] == true ? Icons.verified : Icons.pause_circle_outline,
                            color: policy['is_active'] == true ? theme.colorScheme.primary : theme.colorScheme.outline,
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _showPolicyDialog(initial: policy),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () {
                                  final pretty = _service.prettyJson(policy['config'] as Map<String, dynamic>? ?? {});
                                  Clipboard.setData(ClipboardData(text: pretty));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('پیکربندی در کلیپ‌بورد کپی شد')),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('حذف سیاست'),
                                      content: Text('آیا از حذف "${policy['title']}" اطمینان دارید؟'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
                                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await _service.deleteBusinessPolicyAdmin(_selectedBusinessId!, policy['id'] as int);
                                    if (!mounted) return;
                                    _loadPolicies();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

