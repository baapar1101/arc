import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../services/zohal_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../widgets/zohal/identity_inquiry_dialog.dart';

class ZohalInquiriesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ZohalInquiriesPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<ZohalInquiriesPage> createState() => _ZohalInquiriesPageState();
}

class _ZohalInquiriesPageState extends State<ZohalInquiriesPage> {
  late final ZohalService _zohalService;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _services = const <Map<String, dynamic>>[];
  double? _walletBalance;
  String? _walletCurrency;
  bool _lowBalanceWarning = false;
  double? _lowBalanceThreshold;

  String? _selectedCategory;
  Map<String, dynamic>? _selectedService;
  Map<String, dynamic>? _lastResult;
  bool _submitting = false;

  final Map<String, TextEditingController> _fieldControllers = {};

  @override
  void initState() {
    super.initState();
    _zohalService = ZohalService(ApiClient());
    _load();
  }

  @override
  void dispose() {
    for (var controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _zohalService.listServicesForBusiness(
        businessId: widget.businessId,
        category: _selectedCategory,
      );
      setState(() {
        _services = (data['services'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _walletBalance = (data['wallet_balance'] as num?)?.toDouble();
        _walletCurrency = data['wallet_currency']?.toString();
        _lowBalanceWarning = data['low_balance_warning'] as bool? ?? false;
        _lowBalanceThreshold = (data['low_balance_threshold'] as num?)?.toDouble();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _selectService(Map<String, dynamic> service) async {
    final serviceCode = service['service_code']?.toString() ?? '';
    
    // برای استعلام اطلاعات هویتی، دیالوگ شخصی‌سازی شده را نمایش می‌دهیم
    if (_isIdentityInquiry(serviceCode)) {
      await _showIdentityInquiryDialog();
      return;
    }

    setState(() {
      _selectedService = service;
      _lastResult = null;
    });

    // ایجاد کنترلرهای فیلدها بر اساس request_schema
    final requestSchema = service['request_schema'] as Map<String, dynamic>?;
    final properties = requestSchema?['properties'] as Map<String, dynamic>? ?? {};

    for (var key in properties.keys) {
      if (!_fieldControllers.containsKey(key)) {
        _fieldControllers[key] = TextEditingController();
      }
    }
  }

  /// بررسی اینکه آیا سرویس، استعلام اطلاعات هویتی است یا نه
  bool _isIdentityInquiry(String serviceCode) {
    final normalized = serviceCode.toLowerCase().replaceAll('/', '_').replaceAll('-', '_');
    return normalized.contains('identity') || 
           normalized.contains('national_identity') ||
           normalized.contains('national_code') ||
           serviceCode.contains('national_identity_inquiry');
  }

  /// نمایش دیالوگ استعلام اطلاعات هویتی
  Future<void> _showIdentityInquiryDialog() async {
    final result = await IdentityInquiryDialog.show(
      context,
      businessId: widget.businessId,
    );

    if (result != null) {
      // به‌روزرسانی موجودی کیف پول
      await _load();
      
      // نمایش نتیجه در صفحه (اختیاری)
      setState(() {
        _lastResult = result;
      });
    }
  }

  Future<void> _submitInquiry() async {
    if (_selectedService == null) return;

    final serviceCode = _selectedService!['service_code'] as String?;
    if (serviceCode == null) return;

    // جمع‌آوری داده‌های فرم
    final requestData = <String, dynamic>{};
    for (var entry in _fieldControllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) {
        requestData[entry.key] = value;
      }
    }

    setState(() => _submitting = true);
    try {
      final result = await _zohalService.executeInquiry(
        businessId: widget.businessId,
        serviceCode: serviceCode,
        requestData: requestData,
      );

      setState(() {
        _lastResult = result;
        _submitting = false;
      });

      // به‌روزرسانی موجودی
      _load();

      if (mounted) {
        if (result['success'] == true) {
          SnackBarHelper.show(context, message: 'استعلام با موفقیت انجام شد');
        } else {
          SnackBarHelper.showError(context, message: 'استعلام ناموفق بود');
        }
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در اجرای استعلام: $e');
      }
    }
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final theme = Theme.of(context);
    final isActive = service['is_active'] as bool? ?? false;
    final basePrice = (service['base_price'] as num?)?.toDouble() ?? 0.0;
    final currencyCode = service['currency_code']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isActive ? () => _selectService(service) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.search,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['service_name'] ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      service['service_category'] ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.attach_money, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${formatWithThousands(basePrice)} $currencyCode',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isActive)
                Chip(
                  label: const Text('غیرفعال'),
                  backgroundColor: theme.colorScheme.errorContainer,
                  labelStyle: TextStyle(color: theme.colorScheme.onErrorContainer),
                )
              else
                const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInquiryForm() {
    if (_selectedService == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final formKey = GlobalKey<FormState>();
    final requestSchema = _selectedService!['request_schema'] as Map<String, dynamic>?;
    final properties = requestSchema?['properties'] as Map<String, dynamic>? ?? {};
    final requiredFields = requestSchema?['required'] as List? ?? [];

    // اگر properties خالی است، از description استفاده می‌کنیم
    if (properties.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedService!['service_name'] ?? '',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _selectedService = null;
                      _lastResult = null;
                    }),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'برای این سرویس فیلدهای ورودی از API مستندات دریافت نشده است. لطفاً با پشتیبانی تماس بگیرید.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedService!['service_name'] ?? '',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _selectedService = null;
                      _lastResult = null;
                    }),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              ...properties.entries.map((entry) {
                final fieldName = entry.key;
                final fieldSchema = entry.value as Map<String, dynamic>;
                final isRequired = requiredFields.contains(fieldName);
                final fieldType = fieldSchema['type']?.toString() ?? 'string';
                final example = fieldSchema['example']?.toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: _fieldControllers[fieldName] ?? TextEditingController(),
                    decoration: InputDecoration(
                      labelText: fieldName,
                      hintText: example,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.input),
                    ),
                    keyboardType: fieldType == 'number' ? TextInputType.number : TextInputType.text,
                    validator: (value) {
                      if (isRequired && (value == null || value.trim().isEmpty)) {
                        return 'این فیلد الزامی است';
                      }
                      return null;
                    },
                  ),
                );
              }),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _submitting
                    ? null
                    : () {
                        if (formKey.currentState?.validate() ?? false) {
                          _submitInquiry();
                        }
                      },
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'در حال ارسال...' : 'ارسال درخواست'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    if (_lastResult == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final success = _lastResult!['success'] as bool? ?? false;
    final result = _lastResult!['result'] as Map<String, dynamic>?;
    final amountCharged = (_lastResult!['amount_charged'] as num?)?.toDouble() ?? 0.0;
    final remainingBalance = (_lastResult!['remaining_balance'] as num?)?.toDouble() ?? 0.0;

    return Card(
      margin: const EdgeInsets.all(16),
      color: success
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error,
                  color: success
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  success ? 'استعلام موفق' : 'استعلام ناموفق',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: success
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (success) ...[
              if (result != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.toString(),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('هزینه:', style: theme.textTheme.bodyMedium),
                  Text(
                    '${formatWithThousands(amountCharged)} ${_walletCurrency ?? ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('موجودی باقیمانده:', style: theme.textTheme.bodyMedium),
                  Text(
                    '${formatWithThousands(remainingBalance)} ${_walletCurrency ?? ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                result?['response_body']?['message']?.toString() ?? 'خطا در استعلام',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('استعلامات'),
        actions: [
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
                    // نمایش موجودی کیف پول
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
                          Icon(
                            Icons.account_balance_wallet,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'موجودی کیف پول: ',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '${formatWithThousands(_walletBalance ?? 0)} ${_walletCurrency ?? ''}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          if (_lowBalanceWarning) ...[
                            const SizedBox(width: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning_amber,
                                    size: 16,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'موجودی کم',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // فیلتر دسته‌بندی
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'دسته‌بندی',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('همه')),
                          const DropdownMenuItem<String>(value: 'بانکی', child: Text('بانکی')),
                          const DropdownMenuItem<String>(value: 'احراز هویت', child: Text('احراز هویت')),
                          const DropdownMenuItem<String>(value: 'خدماتی', child: Text('خدماتی')),
                          const DropdownMenuItem<String>(value: 'شرکت', child: Text('شرکت')),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedCategory = v);
                          _load();
                        },
                      ),
                    ),
                    // محتوای اصلی
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // فرم استعلام
                            if (_selectedService != null) _buildInquiryForm(),
                            // نتیجه
                            if (_lastResult != null) _buildResult(),
                            // لیست سرویس‌ها
                            if (_selectedService == null)
                              ..._services.map((service) => _buildServiceCard(service)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

