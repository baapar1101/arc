import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/storage_plan_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import '../../utils/snackbar_helper.dart';

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
        _error = '$e';
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
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                            color: theme.colorScheme.onPrimary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            isEdit ? 'ویرایش پلن' : 'ایجاد پلن جدید',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          color: theme.colorScheme.onPrimary,
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
                                      labelText: 'نام پلن',
                                      prefixIcon: const Icon(Icons.label_outline),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    validator: (v) => v?.isEmpty ?? true ? 'نام الزامی است' : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: codeController,
                                    decoration: InputDecoration(
                                      labelText: 'کد پلن (یکتا)',
                                      prefixIcon: const Icon(Icons.code_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    enabled: !isEdit,
                                    validator: (v) => v?.isEmpty ?? true ? 'کد الزامی است' : null,
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
                                      labelText: 'محدودیت حجم (گیگابایت)',
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
                                      if (v?.isEmpty ?? true) return 'محدودیت حجم الزامی است';
                                      final val = double.tryParse(v!);
                                      if (val == null || val <= 0) return 'مقدار باید بیشتر از صفر باشد';
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selectedPeriod,
                                    decoration: InputDecoration(
                                      labelText: 'دوره',
                                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'monthly', child: Text('ماهانه')),
                                      DropdownMenuItem(value: 'yearly', child: Text('سالانه')),
                                      DropdownMenuItem(value: 'lifetime', child: Text('مادام‌العمر')),
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
                                  labelText: 'تعداد ماه‌ها',
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
                                  if (v?.isEmpty ?? true) return 'تعداد ماه‌ها الزامی است';
                                  final val = int.tryParse(v!);
                                  if (val == null || val <= 0) return 'مقدار باید بیشتر از صفر باشد';
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: 20),
                            DropdownButtonFormField<int>(
                              initialValue: selectedCurrencyId,
                              decoration: InputDecoration(
                                labelText: 'ارز',
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
                              validator: (v) => v == null ? 'ارز الزامی است' : null,
                            ),
                            const SizedBox(height: 20),
                            // Row 3: قیمت‌ها
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: priceController,
                                    decoration: InputDecoration(
                                      labelText: 'قیمت کل پلن',
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
                                      if (v?.isEmpty ?? true) return 'قیمت الزامی است';
                                      final val = double.tryParse(v!);
                                      if (val == null || val < 0) return 'قیمت نامعتبر است';
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: pricePerGbController,
                                    decoration: InputDecoration(
                                      labelText: 'قیمت هر گیگابایت اضافی (اختیاری)',
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
                                labelText: 'مدت مهلت حذف فایل‌ها (روز)',
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
                                if (v?.isEmpty ?? true) return 'مدت مهلت الزامی است';
                                final val = int.tryParse(v!);
                                if (val == null || val < 0) return 'مقدار نامعتبر است';
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: descriptionController,
                              decoration: InputDecoration(
                                labelText: 'توضیحات (اختیاری)',
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
                                      title: const Text('پلن رایگان'),
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
                                      title: const Text('فعال'),
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
                          child: const Text('لغو'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                if (selectedCurrencyId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('لطفاً ارز را انتخاب کنید')),
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
                      content: Text(isEdit ? 'پلن با موفقیت به‌روزرسانی شد' : 'پلن با موفقیت ایجاد شد'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('خطا: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                          },
                          icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline),
                          label: Text(isEdit ? 'ذخیره' : 'ایجاد'),
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
        title: const Text('حذف پلن'),
        content: const Text('آیا از حذف این پلن اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
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
          const SnackBar(
            content: Text('پلن با موفقیت حذف شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'پلن‌های ذخیره‌سازی',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.1),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('تلاش مجدد'),
                        ),
                      ],
                    ),
                  )
                : _plans.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.storage_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'هیچ پلنی یافت نشد',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'برای ایجاد پلن جدید روی دکمه + کلیک کنید',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _plans.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final plan = _plans[index];
                          final isActive = (plan['is_active'] ?? false) == true;
                          final isFree = plan['is_free'] == true;
                          final period = plan['period'] ?? 'monthly';
                          String periodText = '';
                          switch (period) {
                            case 'monthly':
                              periodText = 'ماهانه';
                              break;
                            case 'yearly':
                              periodText = 'سالانه';
                              break;
                            case 'lifetime':
                              periodText = 'مادام‌العمر';
                              break;
                          }
                          if (plan['period_months'] != null) {
                            periodText += ' (${plan['period_months']} ماه)';
                          }

                          return Card(
                            elevation: 2,
                            child: ExpansionTile(
                              leading: Icon(
                                isActive ? Icons.check_circle : Icons.cancel,
                                color: isActive ? Colors.green : Colors.grey,
                              ),
                              title: Text(
                                plan['name'] ?? '-',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isActive ? null : Colors.grey,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('کد: ${plan['code'] ?? '-'}'),
                                  Text('حجم: ${plan['storage_limit_gb']} GB'),
                                  Text('دوره: $periodText'),
                                  Text('قیمت: ${isFree ? 'رایگان' : '${plan['price']} ${plan['currency_code'] ?? ''}'}'),
                                  if (plan['price_per_gb'] != null)
                                    Text('قیمت هر GB اضافی: ${plan['price_per_gb']} ${plan['currency_code'] ?? ''}'),
                                ],
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  IconButton(
                                    tooltip: 'ویرایش',
                                    onPressed: () => _showEditDialog(plan),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'حذف',
                                    onPressed: () => _deletePlan(plan['id']),
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  ),
                                ],
                              ),
                              children: [
                                if (plan['description'] != null)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      'توضیحات: ${plan['description']}',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildInfoChip('مهلت حذف', '${plan['grace_period_days']} روز'),
                                      _buildInfoChip('وضعیت', isActive ? 'فعال' : 'غیرفعال'),
                                      _buildInfoChip('نوع', isFree ? 'رایگان' : 'پولی'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('ایجاد پلن جدید'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
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

