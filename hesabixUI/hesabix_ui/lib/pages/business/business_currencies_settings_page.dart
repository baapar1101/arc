import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';
import 'dart:ui' as ui;

class BusinessCurrenciesSettingsPage extends StatefulWidget {
  final int businessId;

  const BusinessCurrenciesSettingsPage({super.key, required this.businessId});

  @override
  State<BusinessCurrenciesSettingsPage> createState() => _BusinessCurrenciesSettingsPageState();
}

class _BusinessCurrenciesSettingsPageState extends State<BusinessCurrenciesSettingsPage> {
  late final ApiClient _apiClient;
  late final CurrencyService _currencyService;

  // مدیریت ارزها
  List<Map<String, dynamic>> _businessCurrencies = [];
  List<Map<String, dynamic>> _allCurrencies = [];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _defaultCurrency;
  
  // برای انتخاب ارز پیش‌فرض
  int? _selectedDefaultCurrencyId;
  bool _savingDefaultCurrency = false;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _currencyService = CurrencyService(_apiClient);
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // بارگذاری ارزهای کسب‌وکار
      final businessCurrencies = await _currencyService.listBusinessCurrencies(
        businessId: widget.businessId,
      );
      
      // بارگذاری تمام ارزهای موجود
      final allCurrencies = await _currencyService.listCurrencies();
      
      // جدا کردن ارز پیش‌فرض و ارزهای جانبی
      Map<String, dynamic>? defaultCurrency;
      List<Map<String, dynamic>> secondaryCurrencies = [];
      
      for (final currency in businessCurrencies) {
        if (currency['is_default'] == true) {
          defaultCurrency = currency;
        } else {
          secondaryCurrencies.add(currency);
        }
      }
      
      setState(() {
        _defaultCurrency = defaultCurrency;
        _businessCurrencies = secondaryCurrencies;
        _allCurrencies = allCurrencies;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در بارگذاری ارزها: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  Future<void> _addCurrency(int currencyId) async {
    try {
      await _currencyService.addBusinessCurrency(
        businessId: widget.businessId,
        currencyId: currencyId,
      );
      
      // بارگذاری مجدد لیست ارزها
      await _loadCurrencies();
      
      if (mounted) {
        SnackBarHelper.show(context, message: 'ارز با موفقیت اضافه شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    }
  }

  Future<void> _removeCurrency(int currencyId, String currencyTitle) async {
    // بررسی استفاده در اسناد
    try {
      final usage = await _currencyService.checkCurrencyUsage(
        businessId: widget.businessId,
        currencyId: currencyId,
      );
      
      if (usage['is_used'] == true) {
        final count = usage['document_count'] as int;
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('امکان حذف وجود ندارد'),
              content: Text(
                'این ارز در $count سند حسابداری استفاده شده و قابل حذف نیست.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('متوجه شدم'),
                ),
              ],
            ),
          );
        }
        return;
      }
      
      // نمایش Dialog تأیید
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأیید حذف ارز'),
          content: Text('آیا از حذف ارز "$currencyTitle" اطمینان دارید؟'),
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
      
      if (confirmed != true) return;
      
      // حذف ارز
      await _currencyService.removeBusinessCurrency(
        businessId: widget.businessId,
        currencyId: currencyId,
      );
      
      // بارگذاری مجدد لیست ارزها
      await _loadCurrencies();
      
      if (mounted) {
        SnackBarHelper.show(context, message: 'ارز با موفقیت حذف شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    }
  }

  Future<void> _showAddCurrencyDialog() async {
    // فیلتر کردن ارزهای قبلاً اضافه شده
    final addedCurrencyIds = {
      if (_defaultCurrency != null) _defaultCurrency!['id'] as int,
      ..._businessCurrencies.map((c) => c['id'] as int),
    };
    
    final availableCurrencies = _allCurrencies
        .where((c) => !addedCurrencyIds.contains(c['id'] as int))
        .toList();
    
    if (availableCurrencies.isEmpty) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'همه ارزهای موجود قبلاً اضافه شده‌اند');
      }
      return;
    }
    
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddCurrencyDialog(
        availableCurrencies: availableCurrencies,
      ),
    );
    
    if (selected != null) {
      await _addCurrency(selected['id'] as int);
    }
  }

  Future<void> _setDefaultCurrency(int currencyId) async {
    setState(() {
      _savingDefaultCurrency = true;
    });
    
    try {
      // استفاده از API برای تنظیم ارز پیش‌فرض
      await _apiClient.put<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}',
        data: {'default_currency_id': currencyId},
      );
      
      // بارگذاری مجدد لیست ارزها
      await _loadCurrencies();
      
      if (mounted) {
        SnackBarHelper.show(context, message: 'ارز پیش‌فرض با موفقیت تنظیم شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingDefaultCurrency = false;
          _selectedDefaultCurrencyId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.settingsSideCurrenciesTitle),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.settingsSideCurrenciesTitle),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadCurrencies,
                child: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settingsSideCurrenciesTitle),
        leading: businessSubpageBackLeading(context, widget.businessId),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ارز پیش‌فرض
            if (_defaultCurrency != null) ...[
              Card(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.star, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_defaultCurrency!['title']} (${_defaultCurrency!['code']})',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ارز پیش‌فرض',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: 'این ارز در زمان ایجاد کسب‌وکار انتخاب شده و قابل تغییر نیست',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('ارز پیش‌فرض'),
                              content: const Text(
                                'این ارز در زمان ایجاد کسب‌وکار انتخاب شده و قابل تغییر نیست.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('متوجه شدم'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              // بخش انتخاب ارز پیش‌فرض (اگر ارز پیش‌فرض وجود نداشته باشد)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'کسب‌وکار شما ارز پیش‌فرض تنظیم نکرده است',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'لطفاً یک ارز پیش‌فرض انتخاب کنید تا بتوانید سند حسابداری ثبت کنید.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: _selectedDefaultCurrencyId,
                        decoration: InputDecoration(
                          labelText: 'ارز پیش‌فرض *',
                          border: const OutlineInputBorder(),
                          helperText: 'این ارز به صورت پیش‌فرض در تمام اسناد حسابداری استفاده می‌شود',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _allCurrencies.map((currency) {
                          return DropdownMenuItem<int>(
                            value: currency['id'] as int,
                            child: Text('${currency['title']} (${currency['code']})'),
                          );
                        }).toList(),
                        onChanged: _savingDefaultCurrency
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedDefaultCurrencyId = value;
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _savingDefaultCurrency || _selectedDefaultCurrencyId == null
                              ? null
                              : () => _setDefaultCurrency(_selectedDefaultCurrencyId!),
                          icon: _savingDefaultCurrency
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check),
                          label: Text(_savingDefaultCurrency ? 'در حال ذخیره...' : 'تنظیم ارز پیش‌فرض'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ارزهای جانبی
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.currency_exchange, color: cs.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'ارزهای جانبی',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_businessCurrencies.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'هیچ ارز جانبی اضافه نشده است',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      ..._businessCurrencies.map((currency) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${currency['title']} (${currency['code']})',
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: cs.error,
                                tooltip: 'حذف ارز',
                                onPressed: () => _removeCurrency(
                                  currency['id'] as int,
                                  currency['title'] ?? currency['code'] ?? '',
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _showAddCurrencyDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('اضافه کردن ارز'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCurrencyDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableCurrencies;

  const _AddCurrencyDialog({
    required this.availableCurrencies,
  });

  @override
  State<_AddCurrencyDialog> createState() => _AddCurrencyDialogState();
}

class _AddCurrencyDialogState extends State<_AddCurrencyDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredCurrencies = [];

  @override
  void initState() {
    super.initState();
    _filteredCurrencies = widget.availableCurrencies;
    _searchController.addListener(_filterCurrencies);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCurrencies() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredCurrencies = widget.availableCurrencies;
      } else {
        _filteredCurrencies = widget.availableCurrencies.where((currency) {
          final title = (currency['title'] ?? '').toString().toLowerCase();
          final name = (currency['name'] ?? '').toString().toLowerCase();
          final code = (currency['code'] ?? '').toString().toLowerCase();
          final symbol = (currency['symbol'] ?? '').toString().toLowerCase();
          return title.contains(query) ||
              name.contains(query) ||
              code.contains(query) ||
              symbol.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 600,
          maxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.currency_exchange,
                      color: cs.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'انتخاب ارز جدید',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.availableCurrencies.length} ارز موجود',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'بستن',
                  ),
                ],
              ),
            ),

            // Search bar — فیلد جست‌وجو خارج از ValueListenableBuilder تا با تغییر suffix فوکوس قطع نشود
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'جستجو بر اساس نام، کد یا نماد ارز...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      ),
                      autofocus: true,
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _searchController,
                    builder: (context, _) {
                      final hasText = _searchController.text.isNotEmpty;
                      return IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: hasText ? null : Colors.transparent,
                        ),
                        tooltip: 'پاک کردن',
                        onPressed: hasText ? () => _searchController.clear() : null,
                      );
                    },
                  ),
                ],
              ),
            ),

            // Currency list
            Flexible(
              child: _filteredCurrencies.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'نتیجه‌ای یافت نشد',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'لطفاً عبارت جستجوی دیگری را امتحان کنید',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredCurrencies.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final currency = _filteredCurrencies[index];
                        final title = currency['title'] ?? currency['name'] ?? '';
                        final code = currency['code'] ?? '';
                        final symbol = currency['symbol'] ?? '';

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, currency),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  // Currency symbol badge
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: cs.primary.withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        symbol,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: cs.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Currency info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: cs.surfaceContainerHighest
                                                    .withValues(alpha: 0.5),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                code,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  fontWeight: FontWeight.w500,
                                                  fontFeatures: [
                                                    ui.FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              symbol,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Arrow icon
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('انصراف'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

