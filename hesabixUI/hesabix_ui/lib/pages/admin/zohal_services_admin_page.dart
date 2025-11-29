import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/zohal_service.dart';
import '../../services/currency_service.dart';
import '../../utils/snackbar_helper.dart';

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
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleService(int serviceId, bool currentStatus) async {
    try {
      await _zohalService.toggleService(serviceId, !currentStatus);
      if (mounted) {
        SnackBarHelper.show(context, message: 'وضعیت سرویس تغییر کرد');
        _load();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: $e');
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
            title: Text('تغییر قیمت: ${service['service_name']}'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'قیمت (تومان)',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
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
                    decoration: const InputDecoration(
                      labelText: 'ارز',
                      prefixIcon: Icon(Icons.currency_exchange),
                    ),
                    items: _currencies
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'] as int?,
                              child: Text('${c['title']} (${c['code']})'),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedCurrencyId = v),
                    validator: (v) => v == null ? 'ارز الزامی است' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('لغو'),
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
                      SnackBarHelper.show(context, message: 'قیمت به‌روزرسانی شد');
                      _load();
                    }
                  } catch (e) {
                    if (mounted) {
                      SnackBarHelper.showError(context, message: 'خطا: $e');
                    }
                  }
                },
                child: const Text('ذخیره'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت سرویس‌های زحل'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => context.go('/user/profile/system-settings/zohal-statistics'),
            tooltip: 'آمار و گزارش‌ها',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'بارگذاری مجدد',
          ),
        ],
      ),
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
                        label: const Text('تلاش مجدد'),
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
                              decoration: const InputDecoration(
                                labelText: 'دسته‌بندی',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: _categories
                                  .map((cat) => DropdownMenuItem<String>(
                                        value: cat == 'همه' ? null : cat,
                                        child: Text(cat),
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
                              decoration: const InputDecoration(
                                labelText: 'وضعیت',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem<bool?>(value: null, child: Text('همه')),
                                DropdownMenuItem<bool?>(value: true, child: Text('فعال')),
                                DropdownMenuItem<bool?>(value: false, child: Text('غیرفعال')),
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
                                    'سرویسی یافت نشد',
                                    style: theme.textTheme.titleMedium?.copyWith(
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
                                        Text('دسته‌بندی: ${service['service_category'] ?? ''}'),
                                        Text(
                                          'قیمت: ${service['base_price'] ?? 0} ${service['currency_code'] ?? ''}',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          onPressed: () => _showPriceDialog(service),
                                          tooltip: 'تغییر قیمت',
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

