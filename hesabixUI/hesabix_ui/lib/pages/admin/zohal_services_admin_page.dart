import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../services/zohal_service.dart';
import '../../services/currency_service.dart';
import '../../utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class ZohalServicesAdminPage extends StatefulWidget {
  const ZohalServicesAdminPage({super.key});

  @override
  State<ZohalServicesAdminPage> createState() => _ZohalServicesAdminPageState();
}

class _ZohalServicesAdminPageState extends State<ZohalServicesAdminPage> {
  late final ZohalService _zohalService;
  late final CurrencyService _currencyService;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _services = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _currencies = const <Map<String, dynamic>>[];
  String? _selectedCategory;
  bool? _onlyActive;

  final List<String> _categories = [
    'همه',
    'بانکی',
    'احراز هویت',
    'احراز هویت ویدیویی',
    'خدماتی',
    'شرکت',
    'استعلام اعتبارسنجی',
  ];

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _zohalService = ZohalService(api);
    _currencyService = CurrencyService(api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = await _zohalService.listServices(
        category: _selectedCategory == 'همه' ? null : _selectedCategory,
        onlyActive: _onlyActive,
      );
      final currencies = await _currencyService.listCurrencies();
      debugPrint('[ZohalServicesAdminPage] Loaded ${services.length} services');
      setState(() {
        _services = services;
        _currencies = currencies;
        _loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('[ZohalServicesAdminPage] Error loading services: $e');
      debugPrint('[ZohalServicesAdminPage] StackTrace: $stackTrace');
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _toggleService(int serviceId, bool currentStatus) async {
    try {
      await _zohalService.toggleService(serviceId, !currentStatus);
      if (mounted) {
        SnackBarHelper.show(context, message: adminTx(context, 'وضعیت سرویس تغییر کرد', 'Service status updated'));
        _load();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _showPriceDialog(Map<String, dynamic> service) async {
    final formKey = GlobalKey<FormState>();
    final priceController = TextEditingController(
      text: (service['base_price'] ?? 0).toString(),
    );
    int? selectedCurrencyId = service['currency_id'] as int?;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: Text(adminTx(context, 'قیمت ${service['service_name']}', 'Price for ${service['service_name']}'), style: const TextStyle(fontSize: 16)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: priceController,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'قیمت', 'Price'),
                      prefixIcon: const Icon(Icons.attach_money),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
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
                      labelText: adminTx(context, 'ارز', 'Currency'),
                      prefixIcon: const Icon(Icons.currency_exchange),
                      isDense: true,
                    ),
                    items: _currencies
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'] as int?,
                              child: Text('${c['title']} (${c['code']})'),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedCurrencyId = v),
                    validator: (v) => v == null ? adminTx(context, 'ارز الزامی است', 'Currency is required') : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(adminTx(context, 'انصراف', 'Cancel')),
              ),
              FilledButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  try {
                    await _zohalService.updateServicePrice(
                      serviceId: service['id'] as int,
                      basePrice: double.parse(priceController.text),
                      currencyId: selectedCurrencyId!,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      SnackBarHelper.show(context, message: adminTx(context, 'قیمت ذخیره شد', 'Price saved'));
                      _load();
                    }
                  } catch (e) {
                    if (mounted) {
                      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                    }
                  }
                },
                child: Text(adminTx(context, 'ذخیره', 'Save')),
              ),
            ],
          );
        },
      ),
    );
  }

  String _categoryLabel(String cat) {
    return switch (cat) {
      'همه' => adminTx(context, 'همه', 'All'),
      'بانکی' => adminTx(context, 'بانکی', 'Banking'),
      'احراز هویت' => adminTx(context, 'احراز هویت', 'Identity'),
      'احراز هویت ویدیویی' => adminTx(context, 'احراز هویت ویدیویی', 'Video identity'),
      'خدماتی' => adminTx(context, 'خدماتی', 'Services'),
      'شرکت' => adminTx(context, 'شرکت', 'Company'),
      'استعلام اعتبارسنجی' => adminTx(context, 'استعلام اعتبارسنجی', 'Credit inquiry'),
      _ => cat,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminCompactScaffold(
      title: adminTx(context, 'سرویس‌های زحل', 'Zohal services'),
      subtitle: adminTx(context, 'کاتالوگ استعلام‌های زحل', 'Zohal inquiry catalog'),
      actions: [
        IconButton(
          icon: const Icon(Icons.bar_chart, size: 20),
          onPressed: () => context.go('/user/profile/system-settings/zohal-statistics'),
          tooltip: adminTx(context, 'آمار', 'Statistics'),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _load,
          tooltip: adminTx(context, 'بارگذاری مجدد', 'Reload'),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // فیلترها
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        border: Border(
                          bottom: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedCategory,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'دسته', 'Category'),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: _categories
                                  .map((cat) => DropdownMenuItem<String>(
                                        value: cat == 'همه' ? null : cat,
                                        child: Text(_categoryLabel(cat)),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                setState(() => _selectedCategory = v);
                                _load();
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<bool?>(
                              value: _onlyActive,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'وضعیت', 'Status'),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                DropdownMenuItem<bool?>(value: null, child: Text(adminTx(context, 'همه', 'All'))),
                                DropdownMenuItem<bool?>(value: true, child: Text(adminTx(context, 'فعال', 'Active'))),
                                DropdownMenuItem<bool?>(value: false, child: Text(adminTx(context, 'غیرفعال', 'Inactive'))),
                              ],
                              onChanged: (v) {
                                setState(() => _onlyActive = v);
                                _load();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    // لیست سرویس‌ها
                    Expanded(
                      child: _services.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inbox_outlined, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                                  const SizedBox(height: 16),
                                  Text(
                                    adminTx(context, 'سرویسی نیست', 'No services'),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _services.length,
                              itemBuilder: (context, index) {
                                final service = _services[index];
                                final isActive = service['is_active'] as bool? ?? false;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isActive
                                          ? theme.colorScheme.primaryContainer
                                          : theme.colorScheme.errorContainer,
                                      child: Icon(
                                        isActive ? Icons.check_circle : Icons.cancel,
                                        color: isActive
                                            ? theme.colorScheme.onPrimaryContainer
                                            : theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                    title: Text(
                                      service['service_name'] ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isActive ? null : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${_categoryLabel('${service['service_category'] ?? ''}')} · ${service['base_price'] ?? 0} ${service['currency_code'] ?? ''}'),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          onPressed: () => _showPriceDialog(service),
                                          tooltip: adminTx(context, 'قیمت', 'Price'),
                                        ),
                                        Switch(
                                          value: isActive,
                                          onChanged: (v) => _toggleService(service['id'] as int, isActive),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

