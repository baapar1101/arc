import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../services/system_settings_service.dart';
import '../../services/document_monetization_service.dart';
import '../../services/business_api_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';

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
        _error = adminTx(context, 'شناسه کسب‌وکار را وارد کنید', 'Enter a business id');
      });
      return;
    }
    final id = int.tryParse(raw);
    if (id == null) {
      setState(() {
        _error = adminTx(context, 'شناسه کسب‌وکار نامعتبر است', 'Invalid business id');
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
          title: Text(initial == null ? adminTx(context, 'پلن جدید', 'New plan') : adminTx(context, 'ویرایش پلن', 'Edit plan')),
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
                      decoration: InputDecoration(labelText: adminTx(context, 'نام پلن', 'Plan name')),
                      validator: (v) => v == null || v.isEmpty ? adminTx(context, 'نام الزامی است', 'Name is required') : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: codeCtrl,
                      decoration: InputDecoration(labelText: adminTx(context, 'کد پلن', 'Plan code')),
                      enabled: initial == null,
                      validator: (v) => v == null || v.isEmpty ? adminTx(context, 'کد الزامی است', 'Code is required') : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: periodCtrl,
                      decoration: InputDecoration(labelText: adminTx(context, 'مدت (ماه)', 'Term (months)')),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.isEmpty) return adminTx(context, 'مدت الزامی است', 'Term is required');
                        final val = int.tryParse(v);
                        if (val == null || val <= 0) return adminTx(context, 'مدت نامعتبر است', 'Invalid term');
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priceCtrl,
                      decoration: InputDecoration(labelText: adminTx(context, 'قیمت ($_walletCurrencyLabel)', 'Price ($_walletCurrencyLabel)')),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => v == null || v.isEmpty ? adminTx(context, 'قیمت الزامی است', 'Price is required') : null,
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: adminTx(context, 'ارز پایه', 'Base currency'),
                        prefixIcon: Icon(Icons.currency_exchange),
                      ),
                      child: Text(_walletCurrencyLabel),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: Text(adminTx(context, 'فعال', 'Active')),
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
              child: Text(adminTx(context, 'انصراف', 'Cancel')),
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
              child: Text(adminTx(context, 'ذخیره', 'Save')),
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
          title: Text(initial == null ? adminTx(context, 'سیاست جدید', 'New policy') : adminTx(context, 'ویرایش سیاست', 'Edit policy')),
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
                      decoration: InputDecoration(labelText: adminTx(context, 'عنوان', 'Title')),
                      validator: (v) => v == null || v.isEmpty ? adminTx(context, 'عنوان الزامی است', 'Title is required') : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: policyType,
                      decoration: InputDecoration(labelText: adminTx(context, 'نوع سیاست', 'Policy type')),
                      items: [
                        DropdownMenuItem(value: 'free', child: Text(adminTx(context, 'رایگان', 'Free'))),
                        DropdownMenuItem(value: 'subscription', child: Text(adminTx(context, 'اشتراک', 'Subscription'))),
                        DropdownMenuItem(value: 'per_document', child: Text(adminTx(context, 'به‌ازای هر سند', 'Per document'))),
                        DropdownMenuItem(value: 'volume', child: Text(adminTx(context, 'حجمی/تناوبی', 'Volume'))),
                        DropdownMenuItem(value: 'hybrid', child: Text(adminTx(context, 'ترکیبی', 'Hybrid'))),
                      ],
                      onChanged: (v) => setInnerState(() => policyType = v ?? policyType),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priorityCtrl,
                      decoration: InputDecoration(labelText: adminTx(context, 'اولویت', 'Priority')),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => v == null || v.isEmpty ? adminTx(context, 'اولویت الزامی است', 'Priority is required') : null,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: Text(adminTx(context, 'فعال', 'Active')),
                      value: isActive,
                      onChanged: (v) => setInnerState(() => isActive = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: configCtrl,
                      decoration: InputDecoration(
                        labelText: adminTx(context, 'پیکربندی (JSON)', 'Configuration (JSON)'),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 8,
                      validator: (v) {
                        if (v == null || v.isEmpty) return adminTx(context, 'پیکربندی الزامی است', 'Configuration is required');
                        try {
                          jsonDecode(v);
                          return null;
                        } catch (_) {
                          return adminTx(context, 'فرمت JSON نامعتبر است', 'Invalid JSON');
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
              child: Text(adminTx(context, 'انصراف', 'Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (_selectedBusinessId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(adminTx(context, 'ابتدا کسب‌وکار را انتخاب کنید', 'Select a business first'))));
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
              child: Text(adminTx(context, 'ذخیره', 'Save')),
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
    return AdminCompactScaffold(
      title: adminTx(context, 'درآمدزایی اسناد', 'Document monetization'),
      subtitle: adminTx(context, 'سناریو و سیاست هزینهٔ سند', 'Document fee scenario and policies'),
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
              label: Text(adminTx(context, 'سیاست جدید', 'New policy')),
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
                        adminTx(context, 'سیاست‌های پیش‌فرض کسب‌وکارهای جدید', 'Default policies for new businesses'),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adminTx(context, 'این سیاست‌ها به صورت خودکار برای هر کسب‌وکار جدید اعمال می‌شوند. اولویت‌ها به ترتیب از کم به زیاد بررسی می‌شوند.', 'These policies are applied automatically to every new business. Lower priority numbers are checked first.'),
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: adminTx(context, 'سیاست‌ها به ترتیب اولویت بررسی می‌شوند. عدد کمتر = اولویت بالاتر', 'Policies are checked by priority. A lower number wins.'),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadingDefaultPolicies)
              const Center(child: CircularProgressIndicator())
            else if (_defaultPolicies.isEmpty)
              Text(adminTx(context, 'هیچ سیاست پیش‌فرضی تعریف نشده است', 'No default policies yet'))
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
                  label: Text(adminTx(context, 'ذخیره تغییرات', 'Save changes')),
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
        typeLabel = adminTx(context, 'رایگان', 'Free');
        typeIcon = Icons.check_circle_outline;
        break;
      case 'subscription':
        typeLabel = adminTx(context, 'پکیج نامحدود', 'Unlimited package');
        typeIcon = Icons.all_inclusive;
        break;
      case 'volume':
        typeLabel = adminTx(context, 'حجمی', 'Volume');
        typeIcon = Icons.analytics;
        break;
      case 'per_document':
        typeLabel = adminTx(context, 'تک سند', 'Single document');
        typeIcon = Icons.receipt;
        break;
      case 'hybrid':
        typeLabel = adminTx(context, 'ترکیبی', 'Hybrid');
        typeIcon = Icons.merge_type;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(typeIcon),
        title: Text(title),
        subtitle: Text(adminTx(context, 'نوع: $typeLabel | اولویت: $priority', 'Type: $typeLabel | Priority: $priority')),
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
                        decoration: InputDecoration(
                          labelText: adminTx(context, 'اولویت', 'Priority'),
                          helperText: adminTx(context, 'عدد کمتر = اولویت بالاتر', 'Lower number = higher priority'),
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
                        decoration: InputDecoration(labelText: adminTx(context, 'عنوان', 'Title')),
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
                          adminTx(context, 'تنظیمات:', 'Settings:'),
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
          title: Text(adminTx(context, 'ویرایش تنظیمات: ${policy['title']}', 'Edit settings: ${policy['title']}')),
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
              child: Text(adminTx(context, 'بستن', 'Close')),
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
              decoration: InputDecoration(labelText: adminTx(context, 'هزینه هر سند', 'Fee per document')),
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
              title: Text(adminTx(context, 'کسر خودکار از کیف‌پول', 'Charge the wallet automatically')),
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
              title: Text(adminTx(context, 'اجازه ادامه سیاست‌های بعدی (cascade)', 'Continue to later policies (cascade)')),
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
              decoration: InputDecoration(labelText: adminTx(context, 'توضیح (اختیاری)', 'Description (optional)')),
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
              decoration: InputDecoration(labelText: adminTx(context, 'دوره', 'Cycle')),
              initialValue: controllers['cycle']!.text,
              items: [
                DropdownMenuItem(value: 'weekly', child: Text(adminTx(context, 'هفتگی', 'Weekly'))),
                DropdownMenuItem(value: 'monthly', child: Text(adminTx(context, 'ماهانه', 'Monthly'))),
                DropdownMenuItem(value: 'yearly', child: Text(adminTx(context, 'سالانه', 'Yearly'))),
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
              decoration: InputDecoration(labelText: adminTx(context, 'مبلغ هر پله', 'Amount per tier')),
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
              decoration: InputDecoration(labelText: adminTx(context, 'قیمت هر پله', 'Price per tier')),
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
              decoration: InputDecoration(labelText: adminTx(context, 'آستانه رایگان', 'Free threshold')),
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
              title: Text(adminTx(context, 'اجازه ادامه سیاست‌های بعدی (cascade)', 'Continue to later policies (cascade)')),
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
              title: Text(adminTx(context, 'اجازه ادامه سیاست‌های بعدی (cascade)', 'Continue to later policies (cascade)')),
              value: controllers['cascade']!.text == 'true',
              onChanged: (value) {
                controllers['cascade']!.text = value.toString();
                onUpdate({'cascade': value});
              },
            ),
          ] else ...[
            Text(adminTx(context, 'این نوع سیاست تنظیمات خاصی ندارد', 'This policy type has no extra settings')),
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
        SnackBar(content: Text(adminTx(context, 'سیاست‌های پیش‌فرض با موفقیت ذخیره شدند', 'Default policies saved'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = adminTx(context, 'خطا در ذخیره: ${ErrorExtractor.forContext(e, context)}', 'Save failed: ${ErrorExtractor.forContext(e, context)}');
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
                        adminTx(context, 'اعمال سیاست به کسب‌وکارهای موجود', 'Apply a policy to existing businesses'),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adminTx(context, 'اعمال سیاست‌های مختلف به صورت انبوه برای کسب‌وکارهای موجود', 'Apply policies in bulk to existing businesses'),
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: adminTx(context, 'می‌توانید سیاست‌های مختلف را به صورت انبوه برای کسب‌وکارهای موجود اعمال کنید', 'Apply different policies in bulk to businesses that already exist'),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: adminTx(context, 'نوع سیاست', 'Policy type'),
                prefixIcon: Icon(Icons.policy),
              ),
              initialValue: _selectedBulkPolicyType,
              items: [
                DropdownMenuItem(value: 'free', child: Text(adminTx(context, 'رایگان', 'Free'))),
                DropdownMenuItem(value: 'subscription', child: Text(adminTx(context, 'پکیج نامحدود', 'Unlimited package'))),
                DropdownMenuItem(value: 'volume', child: Text(adminTx(context, 'حجمی', 'Volume'))),
                DropdownMenuItem(value: 'per_document', child: Text(adminTx(context, 'تک سند', 'Single document'))),
                DropdownMenuItem(value: 'hybrid', child: Text(adminTx(context, 'ترکیبی', 'Hybrid'))),
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
                decoration: InputDecoration(
                  labelText: adminTx(context, 'عنوان سیاست', 'Policy title'),
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bulkPolicyPriorityController,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'اولویت', 'Priority'),
                  helperText: adminTx(context, 'عدد کمتر = اولویت بالاتر', 'Lower number = higher priority'),
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
                      title: Text(adminTx(context, 'همه کسب‌وکارها', 'All businesses')),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      value: false,
                      // ignore: deprecated_member_use
                      groupValue: _bulkPolicyApplyToAll,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setState(() => _bulkPolicyApplyToAll = v ?? false),
                      title: Text(adminTx(context, 'لیست شناسه‌ها', 'Id list')),
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
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'شناسه کسب‌وکارها (با ویرگول یا خط جدید جدا کنید)', 'Business ids (comma or new line)'),
                      prefixIcon: Icon(Icons.list_alt_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _applyingBulkPolicyToExisting ? null : _applyBulkPolicyToExisting,
                icon: const Icon(Icons.playlist_add_check),
                label: Text(adminTx(context, 'اعمال سیاست', 'Apply policy')),
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
              title: Text(adminTx(context, 'اجازه ادامه سیاست‌های بعدی (cascade)', 'Continue to later policies (cascade)')),
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
                labelText: adminTx(context, 'هزینه هر سند ($_walletCurrencyLabel)', 'Fee per document ($_walletCurrencyLabel)'),
                prefixIcon: const Icon(Icons.price_change_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(adminTx(context, 'کسر خودکار از کیف‌پول', 'Charge the wallet automatically')),
              value: _bulkPolicyAutoCharge,
              onChanged: (value) => setState(() => _bulkPolicyAutoCharge = value),
            ),
            SwitchListTile(
              title: Text(adminTx(context, 'اجازه ادامه سیاست‌های بعدی (cascade)', 'Continue to later policies (cascade)')),
              value: _bulkPolicyCascade,
              onChanged: (value) => setState(() => _bulkPolicyCascade = value),
            ),
            TextField(
              controller: _bulkPerDocDescriptionController,
              decoration: InputDecoration(
                labelText: adminTx(context, 'توضیح (اختیاری)', 'Description (optional)'),
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
          ],
        );
      case 'volume':
        return Column(
          children: [
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: adminTx(context, 'دوره', 'Cycle'),
                prefixIcon: Icon(Icons.calendar_today),
              ),
              initialValue: _bulkVolumeCycle,
              items: [
                DropdownMenuItem(value: 'weekly', child: Text(adminTx(context, 'هفتگی', 'Weekly'))),
                DropdownMenuItem(value: 'monthly', child: Text(adminTx(context, 'ماهانه', 'Monthly'))),
                DropdownMenuItem(value: 'yearly', child: Text(adminTx(context, 'سالانه', 'Yearly'))),
              ],
              onChanged: (value) => setState(() => _bulkVolumeCycle = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bulkVolumeTierAmountController,
              decoration: InputDecoration(
                labelText: adminTx(context, 'مبلغ هر پله ($_walletCurrencyLabel)', 'Amount per tier ($_walletCurrencyLabel)'),
                prefixIcon: const Icon(Icons.analytics),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bulkVolumePricePerTierController,
              decoration: InputDecoration(
                labelText: adminTx(context, 'قیمت هر پله ($_walletCurrencyLabel)', 'Price per tier ($_walletCurrencyLabel)'),
                prefixIcon: const Icon(Icons.attach_money),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bulkVolumeFreeThresholdController,
              decoration: InputDecoration(
                labelText: adminTx(context, 'آستانه رایگان ($_walletCurrencyLabel)', 'Free threshold ($_walletCurrencyLabel)'),
                prefixIcon: const Icon(Icons.free_breakfast),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(adminTx(context, 'اجازه ادامه سیاست‌های بعدی (cascade)', 'Continue to later policies (cascade)')),
              value: _bulkPolicyCascade,
              onChanged: (value) => setState(() => _bulkPolicyCascade = value),
            ),
          ],
        );
      case 'hybrid':
        return Column(
          children: [
            SwitchListTile(
              title: Text(adminTx(context, 'اجازه ادامه سیاست‌های بعدی (cascade)', 'Continue to later policies (cascade)')),
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
      _showSnack(adminTx(context, 'نوع سیاست را انتخاب کنید', 'Select a policy type'));
      return;
    }

    final title = _bulkPolicyTitleController.text.trim();
    if (title.isEmpty) {
      _showSnack(adminTx(context, 'عنوان سیاست را وارد کنید', 'Enter a policy title'));
      return;
    }

    final priority = int.tryParse(_bulkPolicyPriorityController.text.trim());
    if (priority == null || priority < 0) {
      _showSnack(adminTx(context, 'اولویت معتبر وارد کنید', 'Enter a valid priority'));
      return;
    }

    // ساخت config بر اساس نوع سیاست
    Map<String, dynamic> config = {};
    if (_selectedBulkPolicyType == 'per_document') {
      final fee = double.tryParse(_bulkPerDocFeeController.text.replaceAll(',', '').trim());
      if (fee == null || fee <= 0) {
        _showSnack(adminTx(context, 'مبلغ معتبر وارد کنید', 'Enter a valid amount'));
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
        _showSnack(adminTx(context, 'مقادیر معتبر وارد کنید', 'Enter valid values'));
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
        _showSnack(adminTx(context, 'در حال آماده‌سازی لیست کسب‌وکارها...', 'Preparing the business list...'));
        targetIds = await _fetchAllBusinessIds();
      } else {
        targetIds = _parseBusinessIds(_bulkPolicyBusinessIdsController.text);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          adminTx(context, 'خطا در دریافت لیست کسب‌وکارها: ${ErrorExtractor.forContext(e, context)}', 'Could not load businesses: ${ErrorExtractor.forContext(e, context)}'),
        );
      }
      return;
    }

    if (targetIds.isEmpty) {
      _showSnack(adminTx(context, 'هیچ کسب‌وکاری برای اعمال سیاست مشخص نشد', 'No business was selected'));
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
      _bulkPolicyStatus = adminTx(context, 'در حال اعمال برای ${targetIds.length} کسب‌وکار', 'Applying to ${targetIds.length} businesses');
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
        _bulkPolicyStatus = adminTx(context, 'اعمال ${i + 1} از ${targetIds.length} (موفق: $success | ناموفق: $failed)', 'Applying ${i + 1} of ${targetIds.length} (ok: $success | failed: $failed)');
      });
    }

    if (!mounted) return;
    setState(() {
      _applyingBulkPolicyToExisting = false;
      _bulkPolicyProgress = 0;
      _bulkPolicyStatus = adminTx(context, 'موفق: $success | ناموفق: $failed', 'Ok: $success | Failed: $failed');
    });
    _showSnack(adminTx(context, 'اعمال سیاست انجام شد (موفق: $success | ناموفق: $failed)', 'Policy applied (ok: $success | failed: $failed)'));
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
                        adminTx(context, 'هزینه ثبت تکی اسناد', 'Per-document registration fee'),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adminTx(context, 'تعیین نرخ پایه برای ثبت هر سند حسابداری و اعمال آن بر روی همه یا بخشی از کسب‌وکارها', 'Set the base fee for each accounting document and apply it to all or some businesses'),
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: adminTx(context, 'با این قابلیت می‌توانید سیاست per_document را به صورت انبوه برای کسب‌وکارها ثبت کنید.', 'This registers a per-document policy in bulk.'),
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
                      labelText: adminTx(context, 'هزینه هر سند ($_walletCurrencyLabel)', 'Fee per document ($_walletCurrencyLabel)'),
                      prefixIcon: Icon(Icons.price_change_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'ارز پایه', 'Base currency'),
                      prefixIcon: Icon(Icons.currency_exchange),
                    ),
                    child: Text(_walletCurrencyLabel),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _singleDocDescriptionController,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'توضیح سیاست (اختیاری)', 'Policy description (optional)'),
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
                  label: Text(adminTx(context, 'کسر خودکار از کیف‌پول', 'Charge the wallet automatically')),
                  selected: _singleDocAutoCharge,
                  onSelected: (v) => setState(() => _singleDocAutoCharge = v),
                ),
                FilterChip(
                  label: Text(adminTx(context, 'اجازهٔ ادامه سیاست‌های بعدی (cascade)', 'Continue to later policies (cascade)')),
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
                    title: Text(adminTx(context, 'همهٔ کسب‌وکارها', 'All businesses')),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    value: false,
                    // ignore: deprecated_member_use
                    groupValue: _applyToAllBusinesses,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _applyToAllBusinesses = v ?? false),
                    title: Text(adminTx(context, 'شناسه‌های دلخواه', 'Selected ids')),
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
                  decoration: InputDecoration(
                    labelText: adminTx(context, 'شناسه کسب‌وکارها (با ویرگول یا خط جدید جدا کنید)', 'Business ids (comma or new line)'),
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
                    label: Text(adminTx(context, 'اعمال سیاست', 'Apply policy')),
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
      _showSnack(adminTx(context, 'مبلغ معتبر وارد کنید', 'Enter a valid amount'));
      return;
    }
    List<int> targetIds = <int>[];
    try {
      if (_applyToAllBusinesses) {
        _showSnack(adminTx(context, 'در حال آماده‌سازی لیست کسب‌وکارها...', 'Preparing the business list...'));
        targetIds = await _fetchAllBusinessIds();
      } else {
        targetIds = _parseBusinessIds(_targetBusinessIdsController.text);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          adminTx(context, 'خطا در دریافت لیست کسب‌وکارها: ${ErrorExtractor.forContext(e, context)}', 'Could not load businesses: ${ErrorExtractor.forContext(e, context)}'),
        );
      }
      return;
    }

    if (targetIds.isEmpty) {
      _showSnack(adminTx(context, 'هیچ کسب‌وکاری برای اعمال سیاست مشخص نشد', 'No business was selected'));
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
      'title': adminTx(context, 'هزینه ثبت تکی اسناد', 'Per-document registration fee'),
      'policy_type': 'per_document',
      'priority': 120,
      'is_active': true,
      'config': config,
    };

    setState(() {
      _applyingBulkPolicy = true;
      _bulkProgress = 0;
      _bulkStatus = adminTx(context, 'در حال اعمال برای ${targetIds.length} کسب‌وکار', 'Applying to ${targetIds.length} businesses');
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
        _bulkStatus = adminTx(context, 'اعمال ${i + 1} از ${targetIds.length}', 'Applying ${i + 1} of ${targetIds.length}');
      });
    }

    if (!mounted) return;
    setState(() {
      _applyingBulkPolicy = false;
      _bulkProgress = 0;
      _bulkStatus = adminTx(context, 'موفق: $success | ناموفق: $failed', 'Ok: $success | Failed: $failed');
    });
    _showSnack(adminTx(context, 'اعمال سیاست انجام شد (موفق: $success | ناموفق: $failed)', 'Policy applied (ok: $success | failed: $failed)'));
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
                  adminTx(context, 'پلن‌های اشتراک نامحدود اسناد', 'Unlimited document plans'),
                  style: theme.textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: () => _showPlanDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(adminTx(context, 'پلن جدید', 'New plan')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingPlans)
              const Center(child: CircularProgressIndicator())
            else if (_plans.isEmpty)
              Text(adminTx(context, 'پلنی ثبت نشده است', 'No plans yet'))
            else
              Column(
                children: _plans
                    .map(
                      (plan) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(plan['name'] as String? ?? '-'),
                        subtitle: Text(
                          adminTx(context, 'مدت: ${plan['period_months']} ماه | قیمت: ${plan['price']} ${plan['currency_code'] ?? _walletCurrencyCode ?? ''}', 'Term: ${plan['period_months']} mo | Price: ${plan['price']} ${plan['currency_code'] ?? _walletCurrencyCode ?? ''}'),
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showPlanDialog(initial: plan),
                              tooltip: adminTx(context, 'ویرایش', 'Edit'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(adminTx(context, 'حذف پلن', 'Delete plan')),
                                    content: Text(adminTx(context, 'آیا از حذف پلن اطمینان دارید؟', 'Delete this plan?')),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: Text(adminTx(context, 'انصراف', 'Cancel')),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: Text(adminTx(context, 'حذف', 'Delete')),
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
                              tooltip: adminTx(context, 'حذف', 'Delete'),
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
              adminTx(context, 'سیاست‌های فعال برای کسب‌وکار', 'Active policies for a business'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _businessIdController,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'شناسه کسب‌وکار', 'Business id'),
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
                  label: Text(adminTx(context, 'بارگذاری', 'Load')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadingPolicies)
              const Center(child: CircularProgressIndicator())
            else if (_selectedBusinessId == null)
              Text(adminTx(context, 'برای مشاهده سیاست‌ها، شناسه کسب‌وکار را وارد کنید', 'Enter a business id to see its policies'))
            else if (_policies.isEmpty)
              Text(adminTx(context, 'هیچ سیاستی برای این کسب‌وکار تعریف نشده است', 'This business has no policies'))
            else
              Column(
                children: _policies
                    .map(
                      (policy) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(policy['title'] as String? ?? '-'),
                          subtitle: Text(adminTx(context, 'نوع: ${policy['policy_type']} | اولویت: ${policy['priority']}', 'Type: ${policy['policy_type']} | Priority: ${policy['priority']}')),
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
                                    SnackBar(content: Text(adminTx(context, 'پیکربندی در کلیپ‌بورد کپی شد', 'Configuration copied'))),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(adminTx(context, 'حذف سیاست', 'Delete policy')),
                                      content: Text(adminTx(context, 'آیا از حذف "${policy['title']}" اطمینان دارید؟', 'Delete "${policy['title']}"?')),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(adminTx(context, 'انصراف', 'Cancel'))),
                                        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(adminTx(context, 'حذف', 'Delete'))),
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

