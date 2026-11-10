import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/marketplace_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'admin_compact_scaffold.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'package:hesabix_ui/widgets/marketplace/plugin_marketplace_utils.dart';

class MarketplacePluginsAdminPage extends StatefulWidget {
  const MarketplacePluginsAdminPage({super.key});

  @override
  State<MarketplacePluginsAdminPage> createState() => _MarketplacePluginsAdminPageState();
}

class _MarketplacePluginsAdminPageState extends State<MarketplacePluginsAdminPage> {
  late final MarketplaceService _marketplaceService;
  late final CurrencyService _currencyService;
  bool _loading = true;
  bool _syncing = false;
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
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _syncDefaultPluginsFromSeed() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final res = await _marketplaceService.syncDefaultPlugins();
      if (!mounted) return;
      final createdP = res['plugins_created'] ?? 0;
      final updatedP = res['plugins_updated'] ?? 0;
      final createdPlans = res['plans_created'] ?? 0;
      final reactivated = res['plans_reactivated'] ?? 0;
      SnackBarHelper.show(
        context,
        message:
            adminTx(context, 'همگام‌سازی انجام شد. افزونه جدید: $createdP، به‌روزشده: $updatedP، ', 'Sync finished. New plugins: $createdP, updated: $updatedP, ')
            adminTx(context, 'پلن جدید: $createdPlans، پلن فعال‌شده: $reactivated', 'new plans: $createdPlans, reactivated: $reactivated'),
        backgroundColor: SemanticColorResolver.positive(context),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: adminTx(context, 'خطا در همگام‌سازی: ${ErrorExtractor.forContext(e, context)}', 'Sync failed: ${ErrorExtractor.forContext(e, context)}'),
        backgroundColor: SemanticColorResolver.negative(context),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<Widget> _appBarSyncActions() {
    return [
      if (_syncing)
        const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      else
        IconButton(
          tooltip: adminTx(context, 'به‌روزرسانی لیست افزونه‌های پیش‌فرض (نصب قدیمی / محیط جدید)', 'Refresh the default plugin list'),
          icon: const Icon(Icons.cloud_download_outlined),
          onPressed: _syncDefaultPluginsFromSeed,
        ),
    ];
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
    bool isActive = initialData == null || !initialData.containsKey('is_active')
        ? true
        : marketplaceJsonBool(initialData['is_active']);
    bool listedInMarketplace =
        initialData == null || !initialData.containsKey('listed_in_marketplace')
            ? true
            : marketplaceJsonBool(initialData['listed_in_marketplace']);
    bool enabledForAllBusinesses =
        marketplaceJsonBool(initialData?['enabled_for_all_businesses']);
    bool trialAllowed = marketplaceJsonBool(initialData?['trial_allowed']);

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
                              isEdit ? adminTx(context, 'ویرایش افزونه', 'Edit plugin') : adminTx(context, 'ایجاد افزونه جدید', 'New plugin'),
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
                                labelText: adminTx(context, 'کد افزونه *', 'Plugin code *'),
                                prefixIcon: const Icon(Icons.code_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              enabled: !isEdit,
                              validator: (v) => v?.isEmpty ?? true ? adminTx(context, 'کد الزامی است', 'Code is required') : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: nameController,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'نام افزونه *', 'Plugin name *'),
                                prefixIcon: const Icon(Icons.label_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              validator: (v) => v?.isEmpty ?? true ? adminTx(context, 'نام الزامی است', 'Name is required') : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: descriptionController,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'توضیحات', 'Description'),
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
                                labelText: adminTx(context, 'دسته‌بندی', 'Category'),
                                prefixIcon: const Icon(Icons.category_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: iconUrlController,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'آدرس آیکون', 'Icon URL'),
                                prefixIcon: const Icon(Icons.image_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: trialDaysController,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'تعداد روزهای trial (مثلاً 7)', 'Trial days (for example 7)'),
                                prefixIcon: const Icon(Icons.free_breakfast_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                helperText: adminTx(context, 'برای غیرفعال کردن trial، این فیلد را خالی بگذارید', 'Leave empty to disable the trial'),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: false),
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              title: Text(adminTx(context, 'فعال در سیستم', 'Enabled in the system')),
                              subtitle: Text(adminTx(context, 'اگر خاموش باشد افزونه برای هیچ کسب‌وکاری کار نمی‌کند', 'When off, the plugin works for no business')),
                              value: isActive,
                              onChanged: (v) => setDialogState(() => isActive = v ?? true),
                            ),
                            CheckboxListTile(
                              title: Text(adminTx(context, 'نمایش در بازار افزونه‌ها', 'Show in the marketplace')),
                              subtitle: Text(adminTx(context, 'در کاتالوگ قابل خرید کسب‌وکارها دیده شود', 'Visible in the catalog businesses can buy')),
                              value: listedInMarketplace,
                              onChanged: (v) => setDialogState(() => listedInMarketplace = v ?? true),
                            ),
                            CheckboxListTile(
                              title: Text(adminTx(context, 'فعال برای همه کسب‌وکارها', 'Enabled for every business')),
                              subtitle: Text(adminTx(context, 'بدون خرید، برای همه کسب‌وکارهای فعلی و بعدی فعال می‌ماند', 'Stays on for current and future businesses without a purchase')),
                              value: enabledForAllBusinesses,
                              onChanged: (v) => setDialogState(() => enabledForAllBusinesses = v ?? false),
                            ),
                            CheckboxListTile(
                              title: Text(adminTx(context, 'مجاز به trial', 'Trial allowed')),
                              subtitle: Text(adminTx(context, 'اجازه استفاده از دوره تست رایگان', 'Allow the free trial')),
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
                            child: Text(adminTx(context, 'لغو', 'Cancel')),
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
                                  'listed_in_marketplace': listedInMarketplace,
                                  'enabled_for_all_businesses': enabledForAllBusinesses,
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
                                  message: isEdit ? adminTx(context, 'افزونه با موفقیت به‌روزرسانی شد', 'Plugin saved') : adminTx(context, 'افزونه با موفقیت ایجاد شد', 'Plugin created'),
                                  backgroundColor: SemanticColorResolver.positive(context),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                SnackBarHelper.show(
                                  context,
                                  message: adminTx(context, 'خطا: ${ErrorExtractor.forContext(e, context)}', '${ErrorExtractor.forContext(e, context)}'),
                                  backgroundColor: SemanticColorResolver.negative(context),
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
                              isEdit ? adminTx(context, 'ویرایش پلن', 'Edit plan') : adminTx(context, 'ایجاد پلن جدید', 'New plan'),
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
                                labelText: adminTx(context, 'دوره *', 'Period *'),
                                prefixIcon: const Icon(Icons.calendar_today_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              items: [
                                DropdownMenuItem(value: 'monthly', child: Text(adminTx(context, 'ماهانه', 'Monthly'))),
                                DropdownMenuItem(value: 'yearly', child: Text(adminTx(context, 'سالانه', 'Yearly'))),
                                DropdownMenuItem(value: 'lifetime', child: Text(adminTx(context, 'مادام‌العمر', 'Lifetime'))),
                              ],
                              onChanged: (v) => setDialogState(() => selectedPeriod = v ?? 'monthly'),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: priceController,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'قیمت *', 'Price *'),
                                prefixIcon: const Icon(Icons.attach_money_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                              validator: (v) {
                                if (v?.isEmpty ?? true) return adminTx(context, 'قیمت الزامی است', 'Price is required');
                                final val = double.tryParse(v!);
                                if (val == null || val < 0) return adminTx(context, 'قیمت نامعتبر است', 'Invalid price');
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                              value: selectedCurrencyId,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'ارز *', 'Currency *'),
                                prefixIcon: const Icon(Icons.currency_exchange_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              items: _currencies.map((c) => DropdownMenuItem<int>(
                                value: c['id'] as int?,
                                child: Text('${c['title']} (${c['code']})'),
                              )).toList(),
                              onChanged: (v) => setDialogState(() => selectedCurrencyId = v),
                              validator: (v) => v == null ? adminTx(context, 'ارز الزامی است', 'Currency is required') : null,
                            ),
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              title: Text(adminTx(context, 'فعال', 'Active')),
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
                            child: Text(adminTx(context, 'لغو', 'Cancel')),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              if (selectedCurrencyId == null) {
                                SnackBarHelper.show(context, message: adminTx(context, 'لطفاً ارز را انتخاب کنید', 'Select a currency'), backgroundColor: SemanticColorResolver.negative(context));
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
                                  message: isEdit ? adminTx(context, 'پلن با موفقیت به‌روزرسانی شد', 'Plan saved') : adminTx(context, 'پلن با موفقیت ایجاد شد', 'Plan created'),
                                  backgroundColor: SemanticColorResolver.positive(context),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                SnackBarHelper.show(
                                  context,
                                  message: adminTx(context, 'خطا: ${ErrorExtractor.forContext(e, context)}', '${ErrorExtractor.forContext(e, context)}'),
                                  backgroundColor: SemanticColorResolver.negative(context),
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
        title: Text(adminTx(context, 'تایید حذف', 'Confirm delete')),
        content: Text(adminTx(context, 'آیا از حذف این افزونه اطمینان دارید؟', 'Delete this plugin?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(adminTx(context, 'لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(adminTx(context, 'حذف', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _marketplaceService.deletePlugin(pluginId);
      _load();
      SnackBarHelper.show(context, message: adminTx(context, 'افزونه با موفقیت حذف شد', 'Plugin deleted'), backgroundColor: SemanticColorResolver.positive(context));
    } catch (e) {
      SnackBarHelper.show(context, message: adminTx(context, 'خطا: ${ErrorExtractor.forContext(e, context)}', '${ErrorExtractor.forContext(e, context)}'), backgroundColor: SemanticColorResolver.negative(context));
    }
  }

  Future<void> _deletePlan(int planId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(adminTx(context, 'تایید حذف', 'Confirm delete')),
        content: Text(adminTx(context, 'آیا از حذف این پلن اطمینان دارید؟', 'Delete this plan?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(adminTx(context, 'لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(adminTx(context, 'حذف', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _marketplaceService.deletePluginPlan(planId);
      _load();
      SnackBarHelper.show(context, message: adminTx(context, 'پلن حذف شد', 'Plan deleted'), backgroundColor: SemanticColorResolver.positive(context));
    } catch (e) {
      SnackBarHelper.show(context, message: adminTx(context, 'خطا: ${ErrorExtractor.forContext(e, context)}', '${ErrorExtractor.forContext(e, context)}'), backgroundColor: SemanticColorResolver.negative(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return AdminCompactScaffold(
        title: adminTx(context, 'افزونه‌های بازار', 'Marketplace plugins'),
        subtitle: adminTx(context, 'کاتالوگ و پلن افزونه‌ها', 'Plugin catalog and plans'),
        actions: _appBarSyncActions(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return AdminCompactScaffold(
        title: adminTx(context, 'افزونه‌های بازار', 'Marketplace plugins'),
        subtitle: adminTx(context, 'کاتالوگ و پلن افزونه‌ها', 'Plugin catalog and plans'),
        actions: _appBarSyncActions(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${adminTx(context, 'خطا', 'Error')}: $_error', style: TextStyle(color: SemanticColorResolver.negative(context))),
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

    return AdminCompactScaffold(
      title: adminTx(context, 'افزونه‌های بازار', 'Marketplace plugins'),
      subtitle: adminTx(context, 'کاتالوگ و پلن افزونه‌ها', 'Plugin catalog and plans'),
      actions: _appBarSyncActions(),
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
              subtitle: Text(
                [
                  plugin['code'] ?? '-',
                  if (plugin['is_active'] != true) adminTx(context, 'غیرفعال در سیستم', 'Disabled'),
                  if (plugin.containsKey('listed_in_marketplace') &&
                      !marketplaceJsonBool(plugin['listed_in_marketplace']))
                    adminTx(context, 'مخفی از بازار', 'Hidden from marketplace'),
                  if (marketplaceJsonBool(plugin['enabled_for_all_businesses'])) adminTx(context, 'سراسری', 'Global'),
                ].join(' • '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit),
                    onPressed: () => _showEditPluginDialog(plugin),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: SemanticColorResolver.negative(context)),
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
                  title: Text(adminTx(context, 'پلن‌ها', 'Plans')),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showCreatePlanDialog(plugin['id']),
                  ),
                ),
                ...plans.map((plan) {
                  final period = plan['period'] ?? '-';
                  final periodLabel = period == 'monthly'
                      ? adminTx(context, 'ماهانه', 'Monthly')
                      : period == 'yearly'
                          ? adminTx(context, 'سالانه', 'Yearly')
                          : adminTx(context, 'مادام‌العمر', 'Lifetime');
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
                    subtitle: Text(adminTx(context, 'وضعیت: ${plan['is_active'] == true ? 'فعال' : 'غیرفعال'}', 'Status: ${plan['is_active'] == true ? 'Active' : 'Inactive'}')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () => _showEditPlanDialog(plugin['id'], plan),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: SemanticColorResolver.negative(context)),
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
        label: Text(adminTx(context, 'افزونه جدید', 'New plugin')),
      ),
    );
  }
}

