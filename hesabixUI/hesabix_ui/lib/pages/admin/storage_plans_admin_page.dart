import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/storage_plan_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class StoragePlansAdminPage extends StatefulWidget {
  const StoragePlansAdminPage({super.key});

  @override
  State<StoragePlansAdminPage> createState() => _StoragePlansAdminPageState();
}

class _StoragePlansAdminPageState extends State<StoragePlansAdminPage> {
  late final StoragePlanService _planService;
  late final CurrencyService _currencyService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _currencies = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _planService = StoragePlanService(api);
    _currencyService = CurrencyService(api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _planService.listPlans();
      final currencies = await _currencyService.listCurrencies();
      setState(() {
        _plans = plans;
        _currencies = currencies;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _showCreateDialog() async {
    await _showPlanFormDialog();
  }

  Future<void> _showEditDialog(Map<String, dynamic> plan) async {
    await _showPlanFormDialog(initialData: plan);
  }

  Future<void> _showPlanFormDialog({Map<String, dynamic>? initialData}) async {
    final isEdit = initialData != null;
    final formKey = GlobalKey<FormState>();
    
    final nameController = TextEditingController(text: initialData?['name'] ?? '');
    final codeController = TextEditingController(text: initialData?['code'] ?? '');
    final storageLimitController = TextEditingController(text: initialData?['storage_limit_gb']?.toString() ?? '');
    final periodMonthsController = TextEditingController(text: initialData?['period_months']?.toString() ?? '');
    final priceController = TextEditingController(text: initialData?['price']?.toString() ?? '0');
    final pricePerGbController = TextEditingController(text: initialData?['price_per_gb']?.toString() ?? '');
    final descriptionController = TextEditingController(text: initialData?['description'] ?? '');
    final gracePeriodController = TextEditingController(text: initialData?['grace_period_days']?.toString() ?? '30');
    
    String? selectedPeriod = initialData?['period'] ?? 'monthly';
    int? selectedCurrencyId = initialData?['currency_id'];
    bool isFree = initialData?['is_free'] ?? false;
    bool isActive = initialData?['is_active'] ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final screenWidth = MediaQuery.of(context).size.width;
          final isDesktop = screenWidth > 768;
          
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              width: screenWidth * (isDesktop ? 0.7 : 0.95),
              constraints: const BoxConstraints(
                maxWidth: 900,
                maxHeight: 800,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isEdit
                                ? adminTx(context, 'ویرایش پلن', 'Edit plan')
                                : adminTx(context, 'پلن جدید', 'New plan'),
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                  // Form Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Row 1: نام و کد
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: nameController,
                                    decoration: InputDecoration(
                                      labelText: adminTx(context, 'نام پلن', 'Plan name'),
                                      prefixIcon: const Icon(Icons.label_outline),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    validator: (v) => v?.isEmpty ?? true ? adminTx(context, 'نام الزامی است', 'Name is required') : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: codeController,
                                    decoration: InputDecoration(
                                      labelText: adminTx(context, 'کد یکتا', 'Unique code'),
                                      prefixIcon: const Icon(Icons.code_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    enabled: !isEdit,
                                    validator: (v) => v?.isEmpty ?? true ? adminTx(context, 'کد الزامی است', 'Code is required') : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Row 2: حجم و دوره
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: storageLimitController,
                                    decoration: InputDecoration(
                                      labelText: adminTx(context, 'سقف حجم (گیگابایت)', 'Storage limit (GB)'),
                                      prefixIcon: const Icon(Icons.storage_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))],
                                    validator: (v) {
                                      if (v?.isEmpty ?? true) return adminTx(context, 'سقف حجم الزامی است', 'Storage limit is required');
                                      final val = double.tryParse(v!);
                                      if (val == null || val <= 0) return adminTx(context, 'مقدار باید بیشتر از صفر باشد', 'Value must be greater than zero');
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selectedPeriod,
                                    decoration: InputDecoration(
                                      labelText: adminTx(context, 'دوره', 'Period'),
                                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    items: [
                                      DropdownMenuItem(value: 'monthly', child: Text(adminTx(context, 'ماهانه', 'Monthly'))),
                                      DropdownMenuItem(value: 'yearly', child: Text(adminTx(context, 'سالانه', 'Yearly'))),
                                      DropdownMenuItem(value: 'lifetime', child: Text(adminTx(context, 'مادام‌العمر', 'Lifetime'))),
                                    ],
                                    onChanged: (v) {
                                      setDialogState(() => selectedPeriod = v);
                                      if (v == 'lifetime') {
                                        periodMonthsController.clear();
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (selectedPeriod != 'lifetime') ...[
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: periodMonthsController,
                                decoration: InputDecoration(
                                  labelText: adminTx(context, 'تعداد ماه', 'Months'),
                                  prefixIcon: const Icon(Icons.numbers_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: theme.colorScheme.surfaceContainerHighest,
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                validator: (v) {
                                  if (selectedPeriod == 'lifetime') return null;
                                  if (v?.isEmpty ?? true) return adminTx(context, 'تعداد ماه الزامی است', 'Month count is required');
                                  final val = int.tryParse(v!);
                                  if (val == null || val <= 0) return adminTx(context, 'مقدار باید بیشتر از صفر باشد', 'Value must be greater than zero');
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: 20),
                            DropdownButtonFormField<int>(
                              initialValue: selectedCurrencyId,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'ارز', 'Currency'),
                                prefixIcon: const Icon(Icons.currency_exchange_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest,
                              ),
                              items: _currencies.map((c) => DropdownMenuItem<int>(
                                value: c['id'] as int?,
                                child: Text('${c['title']} (${c['code']})'),
                              )).toList(),
                              onChanged: (v) => setDialogState(() => selectedCurrencyId = v),
                              validator: (v) => v == null ? adminTx(context, 'ارز الزامی است', 'Currency is required') : null,
                            ),
                            const SizedBox(height: 20),
                            // Row 3: قیمت‌ها
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: priceController,
                                    decoration: InputDecoration(
                                      labelText: adminTx(context, 'قیمت کل', 'Total price'),
                                      prefixIcon: const Icon(Icons.attach_money_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                                    enabled: !isFree,
                                    validator: (v) {
                                      if (isFree) return null;
                                      if (v?.isEmpty ?? true) return adminTx(context, 'قیمت الزامی است', 'Price is required');
                                      final val = double.tryParse(v!);
                                      if (val == null || val < 0) return adminTx(context, 'قیمت نامعتبر است', 'Invalid price');
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: pricePerGbController,
                                    decoration: InputDecoration(
                                      labelText: adminTx(context, 'قیمت هر گیگابایت اضافه', 'Price per extra GB'),
                                      prefixIcon: const Icon(Icons.price_check_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: gracePeriodController,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'مهلت حذف فایل (روز)', 'File deletion grace (days)'),
                                prefixIcon: const Icon(Icons.timer_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              validator: (v) {
                                if (v?.isEmpty ?? true) return adminTx(context, 'مهلت الزامی است', 'Grace period is required');
                                final val = int.tryParse(v!);
                                if (val == null || val < 0) return adminTx(context, 'مقدار نامعتبر است', 'Invalid value');
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: descriptionController,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'توضیح', 'Description'),
                                prefixIcon: const Icon(Icons.description_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest,
                              ),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 24),
                            // Checkboxes
                            Row(
                              children: [
                                Expanded(
                                  child: Card(
                                    elevation: 0,
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isFree 
                                            ? theme.colorScheme.primary 
                                            : theme.colorScheme.outline.withValues(alpha: 0.2),
                                        width: isFree ? 2 : 1,
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      title: Text(adminTx(context, 'رایگان', 'Free'), style: const TextStyle(fontSize: 13)),
                                      value: isFree,
                                      onChanged: (v) {
                                        setDialogState(() {
                                          isFree = v ?? false;
                                          if (isFree) priceController.text = '0';
                                        });
                                      },
                                      controlAffinity: ListTileControlAffinity.leading,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Card(
                                    elevation: 0,
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isActive 
                                            ? theme.colorScheme.primary 
                                            : theme.colorScheme.outline.withValues(alpha: 0.2),
                                        width: isActive ? 2 : 1,
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      title: Text(adminTx(context, 'فعال', 'Active'), style: const TextStyle(fontSize: 13)),
                                      value: isActive,
                                      onChanged: (v) => setDialogState(() => isActive = v ?? true),
                                      controlAffinity: ListTileControlAffinity.leading,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Footer Actions
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: Text(adminTx(context, 'انصراف', 'Cancel')),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                if (selectedCurrencyId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(adminTx(context, 'ارز را انتخاب کنید', 'Select a currency'))),
                  );
                  return;
                }

                try {
                  final data = <String, dynamic>{
                    'name': nameController.text.trim(),
                    'code': codeController.text.trim(),
                    'storage_limit_gb': double.parse(storageLimitController.text),
                    'period': selectedPeriod,
                    'period_months': selectedPeriod == 'lifetime' ? null : int.parse(periodMonthsController.text),
                    'price': double.parse(priceController.text),
                    'price_per_gb': pricePerGbController.text.isEmpty ? null : double.parse(pricePerGbController.text),
                    'is_free': isFree,
                    'is_active': isActive,
                    'currency_id': selectedCurrencyId,
                    'grace_period_days': int.parse(gracePeriodController.text),
                    'description': descriptionController.text.trim(),
                  };

                  if (isEdit) {
                    await _planService.updatePlan(initialData['id'], data);
                  } else {
                    await _planService.createPlan(data);
                  }

                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _load();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit
                          ? adminTx(context, 'پلن ذخیره شد', 'Plan saved')
                          : adminTx(context, 'پلن ایجاد شد', 'Plan created')),
                      backgroundColor: SemanticColorResolver.positive(context),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ErrorExtractor.forContext(e, context)),
                      backgroundColor: SemanticColorResolver.negative(context),
                    ),
                  );
                }
                          },
                          icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline, size: 18),
                          label: Text(isEdit ? adminTx(context, 'ذخیره', 'Save') : adminTx(context, 'ایجاد', 'Create')),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
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
    );
  }

  Future<void> _deletePlan(int planId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(adminTx(context, 'حذف پلن', 'Delete plan'), style: const TextStyle(fontSize: 16)),
        content: Text(adminTx(context, 'این پلن حذف شود؟', 'Delete this plan?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(adminTx(context, 'انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: SemanticColorResolver.negative(context)),
            child: Text(adminTx(context, 'حذف', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _planService.deletePlan(planId);
      if (mounted) {
        _load();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(adminTx(context, 'پلن حذف شد', 'Plan deleted')),
            backgroundColor: SemanticColorResolver.positive(context),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorExtractor.forContext(e, context)),
            backgroundColor: SemanticColorResolver.negative(context),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminCompactScaffold(
      title: adminTx(context, 'پلن‌های ذخیره‌سازی', 'Storage plans'),
      subtitle: adminTx(context, 'بسته‌های فضای فایل', 'File storage packages'),
      actions: [
        IconButton(
          tooltip: adminTx(context, 'پلن جدید', 'New plan'),
          onPressed: _showCreateDialog,
          icon: const Icon(Icons.add, size: 20),
        ),
        IconButton(
          tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
                        ),
                      ],
                    ),
                  )
                : _plans.isEmpty
                    ? Center(
                        child: Text(
                          adminTx(context, 'پلنی ثبت نشده است', 'No plans yet'),
                          style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: context.settingsHub.pagePadding,
                        itemCount: _plans.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final plan = _plans[index];
                          final isActive = (plan['is_active'] ?? false) == true;
                          final isFree = plan['is_free'] == true;
                          final period = plan['period'] ?? 'monthly';
                          final periodText = switch (period) {
                            'yearly' => adminTx(context, 'سالانه', 'Yearly'),
                            'lifetime' => adminTx(context, 'مادام‌العمر', 'Lifetime'),
                            _ => adminTx(context, 'ماهانه', 'Monthly'),
                          };
                          final months = plan['period_months'];
                          final periodLine = months == null
                              ? periodText
                              : '$periodText ($months ${adminTx(context, 'ماه', 'mo')})';
                          final price = isFree
                              ? adminTx(context, 'رایگان', 'Free')
                              : '${plan['price']} ${plan['currency_code'] ?? ''}';

                          return Card(
                            elevation: 0,
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                              leading: Icon(
                                isActive ? Icons.check_circle : Icons.cancel,
                                size: 18,
                                color: isActive ? SemanticColorResolver.positive(context) : theme.colorScheme.outline,
                              ),
                              title: Text(
                                plan['name'] ?? '-',
                                style: context.settingsHub.cardTitleStyle(
                                  theme.textTheme,
                                  color: isActive ? theme.colorScheme.onSurface : theme.colorScheme.outline,
                                ),
                              ),
                              subtitle: Text(
                                '${plan['code'] ?? '-'} · ${plan['storage_limit_gb']} GB · $periodLine · $price',
                                style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                              ),
                              trailing: Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    tooltip: adminTx(context, 'ویرایش', 'Edit'),
                                    onPressed: () => _showEditDialog(plan),
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                  ),
                                  IconButton(
                                    tooltip: adminTx(context, 'حذف', 'Delete'),
                                    onPressed: () => _deletePlan(plan['id']),
                                    icon: Icon(Icons.delete_outline, size: 18, color: SemanticColorResolver.negative(context)),
                                  ),
                                ],
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (plan['price_per_gb'] != null)
                                        Text(
                                          '${adminTx(context, 'هر گیگابایت اضافه', 'Extra GB')}: ${plan['price_per_gb']} ${plan['currency_code'] ?? ''}',
                                          style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                                        ),
                                      if (plan['description'] != null)
                                        Text('${plan['description']}', style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant)),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          _buildInfoChip(adminTx(context, 'مهلت حذف', 'Grace'), '${plan['grace_period_days']} ${adminTx(context, 'روز', 'days')}'),
                                          _buildInfoChip(adminTx(context, 'وضعیت', 'Status'), isActive ? adminTx(context, 'فعال', 'Active') : adminTx(context, 'غیرفعال', 'Inactive')),
                                          _buildInfoChip(adminTx(context, 'نوع', 'Type'), isFree ? adminTx(context, 'رایگان', 'Free') : adminTx(context, 'پولی', 'Paid')),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Chip(
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

