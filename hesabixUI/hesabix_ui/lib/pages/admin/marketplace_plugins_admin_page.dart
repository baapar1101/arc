import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/marketplace_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;

class MarketplacePluginsAdminPage extends StatefulWidget {
  const MarketplacePluginsAdminPage({super.key});

  @override
  State<MarketplacePluginsAdminPage> createState() => _MarketplacePluginsAdminPageState();
}

class _MarketplacePluginsAdminPageState extends State<MarketplacePluginsAdminPage> {
  late final MarketplaceService _marketplaceService;
  late final CurrencyService _currencyService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plugins = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _currencies = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _marketplaceService = MarketplaceService(apiClient: api);
    _currencyService = CurrencyService(api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plugins = await _marketplaceService.listAllPlugins();
      final currencies = await _currencyService.listCurrencies();
      setState(() {
        _plugins = plugins;
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

  Future<void> _showCreatePluginDialog() async {
    await _showPluginFormDialog();
  }

  Future<void> _showEditPluginDialog(Map<String, dynamic> plugin) async {
    await _showPluginFormDialog(initialData: plugin);
  }

  Future<void> _showPluginFormDialog({Map<String, dynamic>? initialData}) async {
    final isEdit = initialData != null;
    final formKey = GlobalKey<FormState>();
    
    final codeController = TextEditingController(text: initialData?['code'] ?? '');
    final nameController = TextEditingController(text: initialData?['name'] ?? '');
    final descriptionController = TextEditingController(text: initialData?['description'] ?? '');
    final categoryController = TextEditingController(text: initialData?['category'] ?? '');
    final iconUrlController = TextEditingController(text: initialData?['icon_url'] ?? '');
    final trialDaysController = TextEditingController(text: initialData?['trial_days']?.toString() ?? '');
    bool isActive = initialData?['is_active'] ?? true;
    bool trialAllowed = initialData?['trial_allowed'] ?? false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.extension, color: theme.colorScheme.onPrimary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isEdit ? 'ویرایش افزونه' : 'ایجاد افزونه جدید',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    // Body
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: codeController,
                              decoration: InputDecoration(
                                labelText: 'کد افزونه *',
                                prefixIcon: const Icon(Icons.code_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              enabled: !isEdit,
                              validator: (v) => v?.isEmpty ?? true ? 'کد الزامی است' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: nameController,
                              decoration: InputDecoration(
                                labelText: 'نام افزونه *',
                                prefixIcon: const Icon(Icons.label_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              validator: (v) => v?.isEmpty ?? true ? 'نام الزامی است' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: descriptionController,
                              decoration: InputDecoration(
                                labelText: 'توضیحات',
                                prefixIcon: const Icon(Icons.description_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: categoryController,
                              decoration: InputDecoration(
                                labelText: 'دسته‌بندی',
                                prefixIcon: const Icon(Icons.category_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: iconUrlController,
                              decoration: InputDecoration(
                                labelText: 'آدرس آیکون',
                                prefixIcon: const Icon(Icons.image_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: trialDaysController,
                              decoration: InputDecoration(
                                labelText: 'تعداد روزهای trial (مثلاً 7)',
                                prefixIcon: const Icon(Icons.free_breakfast_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                helperText: 'برای غیرفعال کردن trial، این فیلد را خالی بگذارید',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: false),
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              title: const Text('فعال'),
                              value: isActive,
                              onChanged: (v) => setDialogState(() => isActive = v ?? true),
                            ),
                            CheckboxListTile(
                              title: const Text('مجاز به trial'),
                              subtitle: const Text('اجازه استفاده از دوره تست رایگان'),
                              value: trialAllowed,
                              onChanged: (v) => setDialogState(() => trialAllowed = v ?? false),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Footer
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
                            child: const Text('لغو'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              
                              try {
                                final trialDaysValue = trialDaysController.text.trim().isEmpty
                                    ? null
                                    : int.tryParse(trialDaysController.text.trim());
                                
                                final data = <String, dynamic>{
                                  'code': codeController.text.trim(),
                                  'name': nameController.text.trim(),
                                  'description': descriptionController.text.trim().isEmpty 
                                      ? null 
                                      : descriptionController.text.trim(),
                                  'category': categoryController.text.trim().isEmpty 
                                      ? null 
                                      : categoryController.text.trim(),
                                  'icon_url': iconUrlController.text.trim().isEmpty 
                                      ? null 
                                      : iconUrlController.text.trim(),
                                  'is_active': isActive,
                                  'trial_allowed': trialAllowed && trialDaysValue != null && trialDaysValue > 0,
                                  'trial_days': trialDaysValue,
                                };

                                if (isEdit) {
                                  await _marketplaceService.updatePlugin(initialData!['id'], data);
                                } else {
                                  await _marketplaceService.createPlugin(data);
                                }

                                if (!context.mounted) return;
                                Navigator.pop(context);
                                _load();
                                SnackBarHelper.show(
                                  context,
                                  message: isEdit ? 'افزونه با موفقیت به‌روزرسانی شد' : 'افزونه با موفقیت ایجاد شد',
                                  backgroundColor: Colors.green,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                SnackBarHelper.show(
                                  context,
                                  message: 'خطا: $e',
                                  backgroundColor: Colors.red,
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
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCreatePlanDialog(int pluginId) async {
    await _showPlanFormDialog(pluginId: pluginId);
  }

  Future<void> _showEditPlanDialog(int pluginId, Map<String, dynamic> plan) async {
    await _showPlanFormDialog(pluginId: pluginId, initialData: plan);
  }

  Future<void> _showPlanFormDialog({
    required int pluginId,
    Map<String, dynamic>? initialData,
  }) async {
    final isEdit = initialData != null;
    final formKey = GlobalKey<FormState>();
    
    final priceController = TextEditingController(text: initialData?['price']?.toString() ?? '0');
    String selectedPeriod = initialData?['period'] ?? 'monthly';
    int? selectedCurrencyId = initialData?['currency_id'];
    bool isActive = initialData?['is_active'] ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.attach_money, color: theme.colorScheme.onPrimary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isEdit ? 'ویرایش پلن' : 'ایجاد پلن جدید',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              value: selectedPeriod,
                              decoration: InputDecoration(
                                labelText: 'دوره *',
                                prefixIcon: const Icon(Icons.calendar_today_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'monthly', child: Text('ماهانه')),
                                DropdownMenuItem(value: 'yearly', child: Text('سالانه')),
                                DropdownMenuItem(value: 'lifetime', child: Text('مادام‌العمر')),
                              ],
                              onChanged: (v) => setDialogState(() => selectedPeriod = v ?? 'monthly'),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: priceController,
                              decoration: InputDecoration(
                                labelText: 'قیمت *',
                                prefixIcon: const Icon(Icons.attach_money_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                              validator: (v) {
                                if (v?.isEmpty ?? true) return 'قیمت الزامی است';
                                final val = double.tryParse(v!);
                                if (val == null || val < 0) return 'قیمت نامعتبر است';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                              value: selectedCurrencyId,
                              decoration: InputDecoration(
                                labelText: 'ارز *',
                                prefixIcon: const Icon(Icons.currency_exchange_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              items: _currencies.map((c) => DropdownMenuItem<int>(
                                value: c['id'] as int?,
                                child: Text('${c['title']} (${c['code']})'),
                              )).toList(),
                              onChanged: (v) => setDialogState(() => selectedCurrencyId = v),
                              validator: (v) => v == null ? 'ارز الزامی است' : null,
                            ),
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              title: const Text('فعال'),
                              value: isActive,
                              onChanged: (v) => setDialogState(() => isActive = v ?? true),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                            child: const Text('لغو'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              if (selectedCurrencyId == null) {
                                SnackBarHelper.show(context, message: 'لطفاً ارز را انتخاب کنید', backgroundColor: Colors.red);
                                return;
                              }
                              
                              try {
                                final data = <String, dynamic>{
                                  'period': selectedPeriod,
                                  'price': double.parse(priceController.text),
                                  'currency_id': selectedCurrencyId,
                                  'is_active': isActive,
                                };

                                if (isEdit) {
                                  await _marketplaceService.updatePluginPlan(initialData!['id'], data);
                                } else {
                                  await _marketplaceService.createPluginPlan(pluginId, data);
                                }

                                if (!context.mounted) return;
                                Navigator.pop(context);
                                _load();
                                SnackBarHelper.show(
                                  context,
                                  message: isEdit ? 'پلن با موفقیت به‌روزرسانی شد' : 'پلن با موفقیت ایجاد شد',
                                  backgroundColor: Colors.green,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                SnackBarHelper.show(
                                  context,
                                  message: 'خطا: $e',
                                  backgroundColor: Colors.red,
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
            ),
          );
        },
      ),
    );
  }

  Future<void> _deletePlugin(int pluginId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تایید حذف'),
        content: const Text('آیا از حذف این افزونه اطمینان دارید؟'),
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
    );

    if (confirmed != true) return;

    try {
      await _marketplaceService.deletePlugin(pluginId);
      _load();
      SnackBarHelper.show(context, message: 'افزونه با موفقیت حذف شد', backgroundColor: Colors.green);
    } catch (e) {
      SnackBarHelper.show(context, message: 'خطا: $e', backgroundColor: Colors.red);
    }
  }

  Future<void> _deletePlan(int planId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تایید حذف'),
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
    );

    if (confirmed != true) return;

    try {
      await _marketplaceService.deletePluginPlan(planId);
      _load();
      SnackBarHelper.show(context, message: 'پلن با موفقیت حذف شد', backgroundColor: Colors.green);
    } catch (e) {
      SnackBarHelper.show(context, message: 'خطا: $e', backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('مدیریت افزونه‌های بازار')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('مدیریت افزونه‌های بازار')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('خطا: $_error', style: const TextStyle(color: Colors.red)),
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
        title: const Text('مدیریت افزونه‌های بازار'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _plugins.length,
        itemBuilder: (context, index) {
          final plugin = _plugins[index];
          final plans = (plugin['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ExpansionTile(
              leading: Icon(Icons.extension, color: theme.colorScheme.primary),
              title: Text(plugin['name'] ?? '-'),
              subtitle: Text(plugin['code'] ?? '-'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditPluginDialog(plugin),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deletePlugin(plugin['id']),
                  ),
                ],
              ),
              children: [
                if (plugin['description'] != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(plugin['description']),
                  ),
                ListTile(
                  title: const Text('پلن‌ها'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showCreatePlanDialog(plugin['id']),
                  ),
                ),
                ...plans.map((plan) {
                  final period = plan['period'] ?? '-';
                  final periodLabel = period == 'monthly'
                      ? 'ماهانه'
                      : period == 'yearly'
                          ? 'سالانه'
                          : 'مادام‌العمر';
                  final price = (plan['price'] ?? 0).toDouble();
                  // پیدا کردن ارز
                  String currencyInfo = '';
                  if (plan['currency_id'] != null) {
                    final currencyId = (plan['currency_id'] as num?)?.toInt();
                    if (currencyId != null) {
                      final currency = _currencies.firstWhere(
                        (c) => (c['id'] as num?)?.toInt() == currencyId,
                        orElse: () => <String, dynamic>{},
                      );
                      if (currency.isNotEmpty) {
                        currencyInfo = ' - ${currency['symbol'] ?? currency['code'] ?? currency['title'] ?? ''}';
                      }
                    }
                  }
                  return ListTile(
                    title: Text('$periodLabel - ${formatWithThousands(price, decimalPlaces: 0)}$currencyInfo'),
                    subtitle: Text('وضعیت: ${plan['is_active'] == true ? 'فعال' : 'غیرفعال'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showEditPlanDialog(plugin['id'], plan),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deletePlan(plan['id']),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreatePluginDialog,
        icon: const Icon(Icons.add),
        label: const Text('افزونه جدید'),
      ),
    );
  }
}

