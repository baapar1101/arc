import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/permission_guard.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/year_end_closing_service.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/widgets/invoice/account_combobox_widget.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

class YearEndClosingPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const YearEndClosingPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<YearEndClosingPage> createState() => _YearEndClosingPageState();
}

class _YearEndClosingPageState extends State<YearEndClosingPage> {
  late final YearEndClosingService _service;
  late final BusinessDashboardService _dashboardService;
  CalendarController? _calendarController;
  
  bool _loading = false;
  bool _closing = false;
  Map<String, dynamic>? _previewData;
  String? _error;
  
  int? _currentFiscalYearId;
  final TextEditingController _newFiscalYearTitleController = TextEditingController();
  bool _autoCreateOpeningBalance = true;
  
  // مالیات
  bool _taxModePercentage = true;
  final TextEditingController _taxPercentageController = TextEditingController();
  final TextEditingController _taxAmountController = TextEditingController();
  
  // تقسیم سود
  bool _profitDistributionModePercentage = true;
  final TextEditingController _profitDistributionPercentageController = TextEditingController();
  final TextEditingController _profitDistributionAmountController = TextEditingController();
  Account? _selectedShareholderProfitAccount;
  
  // سود انباشته سنواتی
  final TextEditingController _retainedEarningsFromPreviousYearsController = TextEditingController();
  
  // تنظیمات
  bool _autoIssuePersonBalanceDocument = false;
  
  // تنظیمات سال مالی جدید
  DateTime? _newFiscalYearStartDate;
  DateTime? _newFiscalYearEndDate;
  String _inventoryValuationMethod = 'FIFO';
  
  // سهامداران
  List<Person> _shareholders = [];
  Map<int, double> _shareholderDistributions = {}; // person_id -> profit_amount

  @override
  void initState() {
    super.initState();
    _service = YearEndClosingService(ApiClient());
    _dashboardService = BusinessDashboardService(ApiClient());
    _loadCalendarController();
    _loadCurrentFiscalYear();
  }

  Future<void> _loadCalendarController() async {
    final controller = await CalendarController.load();
    if (mounted) {
      setState(() {
        _calendarController = controller;
      });
    }
  }

  @override
  void dispose() {
    _newFiscalYearTitleController.dispose();
    _taxPercentageController.dispose();
    _taxAmountController.dispose();
    _profitDistributionPercentageController.dispose();
    _profitDistributionAmountController.dispose();
    _retainedEarningsFromPreviousYearsController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentFiscalYear() async {
    try {
      final fiscalYears = await _dashboardService.listFiscalYears(widget.businessId);
      final current = fiscalYears.firstWhere(
        (fy) => fy['is_current'] == true,
        orElse: () => <String, dynamic>{},
      );
      
      if (mounted) {
        final newFiscalYearId = current['id'] as int?;
        setState(() {
          _currentFiscalYearId = newFiscalYearId;
          if (_currentFiscalYearId != null) {
            _loadPreview();
            // پیشنهاد عنوان سال جدید
            final currentTitle = current['title'] as String? ?? '';
            if (currentTitle.isNotEmpty) {
              // استخراج عدد سال از عنوان (مثلاً "سال مالی 1403" -> "1404")
              final match = RegExp(r'(\d+)').firstMatch(currentTitle);
              if (match != null) {
                final year = int.tryParse(match.group(1) ?? '');
                if (year != null) {
                  _newFiscalYearTitleController.text = 'سال مالی ${year + 1}';
                } else {
                  _newFiscalYearTitleController.text = 'سال مالی جدید';
                }
              } else {
                _newFiscalYearTitleController.text = 'سال مالی جدید';
              }
            }
          } else {
            // اگر سال مالی جاری یافت نشد، پیش‌نمایش را پاک کن
            _previewData = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'خطا در دریافت سال مالی جاری: $e';
        });
        SnackBarHelper.show(
          context,
          message: 'خطا در دریافت اطلاعات: $e',
          isError: true,
          action: SnackBarAction(
            label: 'تلاش مجدد',
            onPressed: _loadCurrentFiscalYear,
          ),
        );
      }
    }
  }

  Future<void> _loadShareholders() async {
    try {
      final personService = PersonService();
      final response = await personService.getPersons(
        businessId: widget.businessId,
        filters: {
          'person_types': ['سهامدار'],
        },
        limit: 1000,
      );
      
      final shareholders = personService.parsePersonsList(response);
      
      // بررسی و لاگ کردن share_count برای دیباگ
      for (final shareholder in shareholders) {
        if (shareholder.shareCount == null || shareholder.shareCount == 0) {
          print('Warning: Shareholder ${shareholder.id} (${shareholder.aliasName}) has shareCount: ${shareholder.shareCount}');
        }
      }
      
      if (mounted) {
        setState(() {
          _shareholders = shareholders;
        });
        
        // محاسبه خودکار توزیع سود بر اساس درصد سهام
        _calculateAutoDistribution();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _shareholders = [];
        });
      }
    }
  }
  
  void _calculateAutoDistribution() {
    if (_shareholders.isEmpty) return;
    
    final totalShares = _shareholders.fold<int>(
      0,
      (sum, shareholder) => sum + (shareholder.shareCount ?? 0),
    );
    
    if (totalShares == 0) return;
    
    final netProfit = _previewData?['summary']?['net_profit_loss'] as double? ?? 0.0;
    if (netProfit <= 0) return;
    
    final distributionAmount = _profitDistributionModePercentage
        ? (double.tryParse(_profitDistributionPercentageController.text) ?? 0) / 100 * netProfit
        : (double.tryParse(_profitDistributionAmountController.text) ?? 0);
    
    final distributions = <int, double>{};
    for (final shareholder in _shareholders) {
      if (shareholder.shareCount != null && shareholder.shareCount! > 0) {
        final shareRatio = shareholder.shareCount! / totalShares;
        distributions[shareholder.id!] = distributionAmount * shareRatio;
      }
    }
    
    setState(() {
      _shareholderDistributions = distributions;
    });
  }

  Future<void> _loadPreview() async {
    if (_currentFiscalYearId == null) return;
    
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final preview = await _service.preview(
        businessId: widget.businessId,
        fiscalYearId: _currentFiscalYearId!,
      );
      
      if (mounted) {
        setState(() {
          _previewData = preview;
          _loading = false;
        });
        
        // بارگذاری سهامداران
        await _loadShareholders();
        
        // تنظیم تاریخ‌های پیش‌فرض سال مالی جدید
        final fiscalYear = preview['fiscal_year'] as Map<String, dynamic>?;
        if (fiscalYear != null && _calendarController != null) {
          final endDateStr = fiscalYear['end_date'];
          if (endDateStr != null) {
            final endDate = DateTime.tryParse(endDateStr.toString());
            if (endDate != null) {
              // تاریخ شروع: یک روز بعد از پایان سال مالی فعلی
              final newStartDate = endDate.add(const Duration(days: 1));
              // تاریخ پایان: یک سال بعد از تاریخ شروع
              DateTime newEndDate;
              if (_calendarController!.isJalali) {
                // برای تقویم شمسی
                final jStart = Jalali.fromDateTime(newStartDate);
                final jEnd = Jalali(jStart.year + 1, jStart.month, jStart.day);
                newEndDate = jEnd.toDateTime();
              } else {
                // برای تقویم میلادی
                newEndDate = DateTime(newStartDate.year + 1, newStartDate.month, newStartDate.day);
              }
              
              setState(() {
                _newFiscalYearStartDate = newStartDate;
                _newFiscalYearEndDate = newEndDate;
              });
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'خطا در دریافت پیش‌نمایش: $e';
          _loading = false;
        });
        SnackBarHelper.show(
          context,
          message: 'خطا در دریافت پیش‌نمایش: $e',
          isError: true,
          action: SnackBarAction(
            label: 'تلاش مجدد',
            onPressed: _loadPreview,
          ),
        );
      }
    }
  }

  Future<void> _closeFiscalYear() async {
    if (_currentFiscalYearId == null) return;
    if (_newFiscalYearTitleController.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'لطفاً عنوان سال مالی جدید را وارد کنید');
      return;
    }

    // نمایش اطلاعات پیش از بستن
    final currentFiscalYearTitle = _previewData?['fiscal_year']?['title']?.toString() ?? '';
    final netProfitLoss = _previewData?['summary']?['net_profit_loss'] as double? ?? 0.0;
    final isProfit = netProfitLoss >= 0;
    final profitLossText = isProfit 
        ? 'سود خالص: ${formatWithThousands(netProfitLoss.abs())}'
        : 'زیان خالص: ${formatWithThousands(netProfitLoss.abs())}';

    // تأیید از کاربر
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Expanded(child: Text('تأیید بستن سال مالی')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (currentFiscalYearTitle.isNotEmpty) ...[
                Text(
                  'سال مالی جاری: $currentFiscalYearTitle',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
              ],
              Text(profitLossText, style: TextStyle(
                color: isProfit ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              )),
              const SizedBox(height: 16),
              const Text(
                'آیا از بستن سال مالی اطمینان دارید؟',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'این عمل باعث می‌شود:\n'
                '• حساب‌های درآمد و هزینه بسته شوند\n'
                '• سود/زیان به حساب سود یا زیان انباشته منتقل شود\n'
                '• سال مالی جدید ایجاد شود\n'
                '\n'
                '⚠️ توجه: این عمل غیرقابل بازگشت است.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لغو'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check_circle),
            label: const Text('تأیید و بستن'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _closing = true;
      _error = null;
    });

    try {
      // آماده‌سازی تقسیم سود سهامداران
      List<Map<String, dynamic>>? shareholderDistributions;
      if (_shareholderDistributions.isNotEmpty) {
        shareholderDistributions = _shareholderDistributions.entries
            .map((entry) => {
                  'person_id': entry.key,
                  'profit_amount': entry.value,
                })
            .toList();
      }
      
      final result = await _service.close(
        businessId: widget.businessId,
        fiscalYearId: _currentFiscalYearId!,
        newFiscalYearTitle: _newFiscalYearTitleController.text.trim(),
        autoCreateOpeningBalance: _autoCreateOpeningBalance,
        // مالیات
        taxPercentage: _taxModePercentage
            ? (double.tryParse(_taxPercentageController.text))
            : null,
        taxAmount: !_taxModePercentage
            ? (double.tryParse(_taxAmountController.text))
            : null,
        // تقسیم سود
        profitDistributionPercentage: _profitDistributionModePercentage
            ? (double.tryParse(_profitDistributionPercentageController.text))
            : null,
        profitDistributionAmount: !_profitDistributionModePercentage
            ? (double.tryParse(_profitDistributionAmountController.text))
            : null,
        shareholderProfitAccountId: _selectedShareholderProfitAccount?.id,
        // سود انباشته سنواتی
        retainedEarningsFromPreviousYears:
            double.tryParse(_retainedEarningsFromPreviousYearsController.text),
        // تنظیمات
        autoIssuePersonBalanceDocument: _autoIssuePersonBalanceDocument,
        // تنظیمات سال مالی جدید
        newFiscalYearStartDate: _newFiscalYearStartDate,
        newFiscalYearEndDate: _newFiscalYearEndDate,
        inventoryValuationMethod: _inventoryValuationMethod,
        // تقسیم سود بین سهامداران
        shareholderDistributions: shareholderDistributions,
      );

      if (mounted) {
        // دریافت سال مالی جدید از نتیجه
        final newFiscalYear = result['new_fiscal_year'] as Map<String, dynamic>?;
        final closingDocument = result['closing_document'] as Map<String, dynamic>?;
        
        // نمایش پیام موفقیت با جزئیات
        final documentCode = closingDocument?['code']?.toString() ?? '';
        final newFiscalYearTitle = newFiscalYear?['title']?.toString() ?? '';
        
        // پاک کردن وضعیت
        setState(() {
          _closing = false;
          _error = null;
          _previewData = null; // پاک کردن پیش‌نمایش قبلی
        });
        
        // بارگذاری مجدد اطلاعات سال مالی جاری (که حالا سال مالی جدید است)
        await _loadCurrentFiscalYear();
        
        // نمایش Dialog موفقیت
        if (mounted) {
          final openingBalanceNote = result['opening_balance_note']?.toString() ?? '';
          final openingBalanceCreated = result['opening_balance_created'] as bool? ?? false;
          
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('بستن سال مالی با موفقیت انجام شد')),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'سال مالی با موفقیت بسته شد و تمام عملیات‌های لازم انجام شد.',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (documentCode.isNotEmpty) ...[
                      _buildInfoRow('کد سند بستن', documentCode, Icons.receipt_long),
                      const SizedBox(height: 12),
                    ],
                    if (newFiscalYearTitle.isNotEmpty) ...[
                      _buildInfoRow('سال مالی جدید', newFiscalYearTitle, Icons.calendar_today),
                      const SizedBox(height: 12),
                    ],
                    if (openingBalanceCreated) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'تراز افتتاحیه سال مالی جدید به صورت خودکار ایجاد شد.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (openingBalanceNote.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                openingBalanceNote,
                                style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, 
                            color: Theme.of(context).colorScheme.primary, 
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'می‌توانید از منوی حسابداری به سال مالی جدید دسترسی داشته باشید.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // بازگشت به صفحه قبل
                    if (mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('بازگشت'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'خطا در بستن سال مالی: $e';
          _closing = false;
        });
        
        // نمایش Dialog خطا با جزئیات بیشتر
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 28),
                const SizedBox(width: 8),
                const Expanded(child: Text('خطا در بستن سال مالی')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'متأسفانه در بستن سال مالی خطایی رخ داد.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      e.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.help_outline, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لطفاً موارد زیر را بررسی کنید:\n'
                            '• اتصال به اینترنت\n'
                            '• دسترسی‌های لازم\n'
                            '• وجود سال مالی جاری\n'
                            '• وجود حساب‌های لازم',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('بستن'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // تلاش مجدد
                  _closeFiscalYear();
                },
                child: const Text('تلاش مجدد'),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // بررسی دسترسی
    if (!widget.authStore.hasBusinessPermission('fiscal_years', 'close')) {
      return PermissionGuard.buildAccessDeniedPage();
    }
    
    return Scaffold(
        appBar: AppBar(
          title: const Text('بستن سال مالی'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _previewData == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                        const SizedBox(height: 16),
                        Text(_error ?? 'خطا'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadPreview,
                          child: const Text('تلاش مجدد'),
                        ),
                      ],
                    ),
                  )
                : _currentFiscalYearId == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline, size: 64, color: colorScheme.primary),
                            const SizedBox(height: 16),
                            const Text('سال مالی جاری یافت نشد'),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // اطلاعات سال مالی جاری
                            if (_previewData != null) ...[
                              _buildFiscalYearInfo(_previewData!['fiscal_year']),
                              const SizedBox(height: 24),
                              
                              // خلاصه سود و زیان
                              _buildSummaryCard(_previewData!['summary']),
                              const SizedBox(height: 24),
                              
                              // حساب سود یا زیان انباشته
                              _buildRetainedEarningsCard(_previewData!['retained_earnings']),
                              const SizedBox(height: 24),
                              
                              // لیست حساب‌های درآمد
                              if ((_previewData!['revenue_accounts'] as List?)?.isNotEmpty == true)
                                _buildAccountsList(
                                  'حساب‌های درآمد',
                                  _previewData!['revenue_accounts'],
                                  Colors.green,
                                ),
                              
                              if ((_previewData!['revenue_accounts'] as List?)?.isNotEmpty == true)
                                const SizedBox(height: 16),
                              
                              // لیست حساب‌های هزینه
                              if ((_previewData!['expense_accounts'] as List?)?.isNotEmpty == true)
                                _buildAccountsList(
                                  'حساب‌های هزینه',
                                  _previewData!['expense_accounts'],
                                  Colors.red,
                                ),
                              
                              const SizedBox(height: 24),
                              
                              // هشدار پشتیبان‌گیری
                              Card(
                                color: Colors.orange.shade50,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.backup,
                                        color: Colors.orange.shade700,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'قبل از بستن دوره مالی، سیستم به طور خودکار از دیتابیس شما یک نسخه پشتیبان تهیه می‌کند. در صورتی که ثبتی را فراموش کرده باشید، می‌توانید دیتابیس خود را به قبل از بستن سال مالی برگردانید.',
                                          style: TextStyle(
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            
                            // فرم بستن سال مالی
                            _buildClosingForm(),
                            const SizedBox(height: 24),
                            
                            // دکمه بستن
                            FilledButton.icon(
                              onPressed: _closing ? null : _closeFiscalYear,
                              icon: _closing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_circle),
                              label: Text(_closing ? 'در حال بستن...' : 'بستن سال مالی'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                            
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(_error!, style: TextStyle(color: colorScheme.onErrorContainer))),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
    );
  }

  Widget _buildFiscalYearInfo(Map<String, dynamic> fiscalYear) {
    final isJalali = _calendarController?.isJalali ?? true;
    
    // تاریخ‌ها ممکن است به صورت فرمت شده از API بیایند یا به صورت ISO string
    // ابتدا بررسی می‌کنیم که آیا به صورت فرمت شده آمده‌اند یا نه
    String startDateFormatted = '';
    String endDateFormatted = '';
    
    // بررسی وجود فیلدهای فرمت شده از API
    if (fiscalYear['start_date_formatted'] != null) {
      final startDateFormattedObj = fiscalYear['start_date_formatted'];
      // اگر آبجکت است، از فیلد date_only استفاده می‌کنیم
      if (startDateFormattedObj is Map<String, dynamic>) {
        startDateFormatted = startDateFormattedObj['date_only']?.toString() ?? 
                            startDateFormattedObj['formatted']?.toString() ?? 
                            startDateFormattedObj.toString();
      } else {
        startDateFormatted = startDateFormattedObj.toString();
      }
    } else if (fiscalYear['start_date'] != null) {
      // اگر فرمت شده نبود، خودمان فرمت می‌کنیم
      final startDateStr = fiscalYear['start_date'].toString();
      final startDate = DateTime.tryParse(startDateStr);
      if (startDate != null) {
        startDateFormatted = HesabixDateUtils.formatForDisplay(startDate, isJalali);
      } else {
        startDateFormatted = startDateStr;
      }
    }
    
    if (fiscalYear['end_date_formatted'] != null) {
      final endDateFormattedObj = fiscalYear['end_date_formatted'];
      // اگر آبجکت است، از فیلد date_only استفاده می‌کنیم
      if (endDateFormattedObj is Map<String, dynamic>) {
        endDateFormatted = endDateFormattedObj['date_only']?.toString() ?? 
                          endDateFormattedObj['formatted']?.toString() ?? 
                          endDateFormattedObj.toString();
      } else {
        endDateFormatted = endDateFormattedObj.toString();
      }
    } else if (fiscalYear['end_date'] != null) {
      // اگر فرمت شده نبود، خودمان فرمت می‌کنیم
      final endDateStr = fiscalYear['end_date'].toString();
      final endDate = DateTime.tryParse(endDateStr);
      if (endDate != null) {
        endDateFormatted = HesabixDateUtils.formatForDisplay(endDate, isJalali);
      } else {
        endDateFormatted = endDateStr;
      }
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  fiscalYear['title'] ?? '',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('از $startDateFormatted تا $endDateFormatted'),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final netProfitLoss = summary['net_profit_loss'] as double? ?? 0.0;
    final isProfit = netProfitLoss >= 0;
    
    return Card(
      color: isProfit ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خلاصه سود و زیان',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('جمع درآمدها:'),
                Text(
                  formatWithThousands(summary['total_revenue'] as double? ?? 0.0),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('جمع هزینه‌ها:'),
                Text(
                  formatWithThousands(summary['total_expense'] as double? ?? 0.0),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isProfit ? 'سود خالص:' : 'زیان خالص:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatWithThousands(netProfitLoss.abs()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isProfit ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRetainedEarningsCard(Map<String, dynamic> retainedEarnings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${retainedEarnings['account_name']} (${retainedEarnings['account_code']})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('مانده ابتدای سال:'),
                Text(formatWithThousands(
                  retainedEarnings['opening_balance'] as double? ?? 0.0,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('سود/زیان سال جاری:'),
                Text(
                  formatWithThousands(
                    retainedEarnings['current_year_profit_loss'] as double? ?? 0.0,
                  ),
                  style: TextStyle(
                    color: (retainedEarnings['current_year_profit_loss'] as double? ?? 0.0) >= 0
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'مانده انتهای سال:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatWithThousands(
                    retainedEarnings['closing_balance'] as double? ?? 0.0,
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsList(String title, List<dynamic> accounts, Color color) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final account = accounts[index] as Map<String, dynamic>;
              return ListTile(
                title: Text(account['account_name'] ?? ''),
                subtitle: Text('کد: ${account['account_code'] ?? ''}'),
                trailing: Text(
                  formatWithThousands(
                    account['closing_balance'] as double? ?? 0.0,
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildClosingForm() {
    final netProfit = _previewData?['summary']?['net_profit_loss'] as double? ?? 0.0;
    final taxAmount = _taxModePercentage
        ? (double.tryParse(_taxPercentageController.text) ?? 0) / 100 * netProfit
        : (double.tryParse(_taxAmountController.text) ?? 0);
    final netProfitAfterTax = netProfit - taxAmount;
    
    return Column(
      children: [
        // فرم مالیات
        _buildTaxSection(netProfit, netProfitAfterTax),
        const SizedBox(height: 16),
        
        // فرم تقسیم سود
        _buildProfitDistributionSection(netProfitAfterTax),
        const SizedBox(height: 16),
        
        // لیست سهامداران
        if (_shareholders.isNotEmpty) ...[
          _buildShareholdersSection(),
          const SizedBox(height: 16),
        ],
        
        // تنظیمات ثبت
        _buildAccountingSettingsSection(),
        const SizedBox(height: 16),
        
        // تنظیمات سال مالی جدید
        _buildNewFiscalYearSettingsSection(),
        const SizedBox(height: 16),
        
        // تنظیمات پایه
        _buildBasicSettingsSection(),
      ],
    );
  }
  
  Widget _buildTaxSection(double netProfit, double netProfitAfterTax) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مالیات',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سود خالص قبل از مالیات: ${formatWithThousands(netProfit)} ریال',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: _taxModePercentage,
                  onChanged: (value) {
                    setState(() {
                      _taxModePercentage = value ?? true;
                      if (value == false) {
                        _taxPercentageController.clear();
                      } else {
                        _taxAmountController.clear();
                      }
                    });
                  },
                ),
                const Text('درصد'),
                const SizedBox(width: 24),
                Radio<bool>(
                  value: false,
                  groupValue: _taxModePercentage,
                  onChanged: (value) {
                    setState(() {
                      _taxModePercentage = value ?? false;
                      if (value == true) {
                        _taxAmountController.clear();
                      } else {
                        _taxPercentageController.clear();
                      }
                    });
                  },
                ),
                const Text('مبلغ'),
              ],
            ),
            const SizedBox(height: 12),
            if (_taxModePercentage)
              TextField(
                controller: _taxPercentageController,
                decoration: const InputDecoration(
                  labelText: 'درصد مالیات',
                  hintText: '0',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              )
            else
              TextField(
                controller: _taxAmountController,
                decoration: const InputDecoration(
                  labelText: 'مبلغ مالیات',
                  hintText: '0',
                  border: OutlineInputBorder(),
                  suffixText: 'ریال',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 12),
            Text(
              'سود خالص پس از کسر مالیات: ${formatWithThousands(netProfitAfterTax)} ریال',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProfitDistributionSection(double netProfitAfterTax) {
    final distributionAmount = _profitDistributionModePercentage
        ? (double.tryParse(_profitDistributionPercentageController.text) ?? 0) / 100 * netProfitAfterTax
        : (double.tryParse(_profitDistributionAmountController.text) ?? 0);
    final retainedAmount = netProfitAfterTax - distributionAmount;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تقسیم سود',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سود خالص پس از مالیات: ${formatWithThousands(netProfitAfterTax)} ریال',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: _profitDistributionModePercentage,
                  onChanged: (value) {
                    setState(() {
                      _profitDistributionModePercentage = value ?? true;
                      if (value == false) {
                        _profitDistributionPercentageController.clear();
                      } else {
                        _profitDistributionAmountController.clear();
                      }
                      _calculateAutoDistribution();
                    });
                  },
                ),
                const Text('درصد'),
                const SizedBox(width: 24),
                Radio<bool>(
                  value: false,
                  groupValue: _profitDistributionModePercentage,
                  onChanged: (value) {
                    setState(() {
                      _profitDistributionModePercentage = value ?? false;
                      if (value == true) {
                        _profitDistributionAmountController.clear();
                      } else {
                        _profitDistributionPercentageController.clear();
                      }
                      _calculateAutoDistribution();
                    });
                  },
                ),
                const Text('مبلغ'),
              ],
            ),
            const SizedBox(height: 12),
            if (_profitDistributionModePercentage)
              TextField(
                controller: _profitDistributionPercentageController,
                decoration: const InputDecoration(
                  labelText: 'درصد تقسیم',
                  hintText: '0',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) {
                  setState(() {});
                  _calculateAutoDistribution();
                },
              )
            else
              TextField(
                controller: _profitDistributionAmountController,
                decoration: const InputDecoration(
                  labelText: 'مبلغ تقسیم',
                  hintText: '0',
                  border: OutlineInputBorder(),
                  suffixText: 'ریال',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) {
                  setState(() {});
                  _calculateAutoDistribution();
                },
              ),
            const SizedBox(height: 12),
            Text(
              'سود انباشته: ${formatWithThousands(retainedAmount)} ریال',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildShareholdersSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سهامداران',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...(_shareholders.map((shareholder) {
              final profit = _shareholderDistributions[shareholder.id] ?? 0.0;
              final totalShares = _shareholders.fold<int>(
                0,
                (sum, sh) => sum + (sh.shareCount ?? 0),
              );
              final sharePercentage = totalShares > 0
                  ? ((shareholder.shareCount ?? 0) / totalShares * 100)
                  : 0.0;
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${shareholder.code ?? ''} - ${shareholder.aliasName}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          '${shareholder.shareCount ?? 0} سهم',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (shareholder.shareCount ?? 0) == 0 
                                ? Theme.of(context).colorScheme.error 
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'درصد سهام: ${sharePercentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        Text(
                          'سود: ${formatWithThousands(profit)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList()),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAccountingSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تنظیمات ثبت',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            AccountComboboxWidget(
              businessId: widget.businessId,
              selectedAccount: _selectedShareholderProfitAccount,
              onChanged: (account) {
                setState(() {
                  _selectedShareholderProfitAccount = account;
                });
              },
              label: 'حساب ثبت سود/زیان سهامداران',
              hintText: 'انتخاب حساب',
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('صدور خودکار سند توازن اشخاص'),
              value: _autoIssuePersonBalanceDocument,
              onChanged: (value) {
                setState(() {
                  _autoIssuePersonBalanceDocument = value ?? false;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNewFiscalYearSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات سال مالی جدید',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_calendarController != null) ...[
              Row(
                children: [
                  Expanded(
                    child: DateInputField(
                      value: _newFiscalYearStartDate,
                      labelText: 'تاریخ شروع',
                      firstDate: _previewData?['fiscal_year']?['end_date'] != null
                          ? DateTime.tryParse(_previewData!['fiscal_year']['end_date'].toString())
                          : null,
                      calendarController: _calendarController!,
                      onChanged: (date) {
                        setState(() {
                          _newFiscalYearStartDate = date;
                          // تنظیم خودکار تاریخ پایان (یک سال بعد)
                          if (date != null) {
                            if (_calendarController!.isJalali) {
                              final j = Jalali.fromDateTime(date);
                              final jNext = Jalali(j.year + 1, j.month, j.day);
                              _newFiscalYearEndDate = jNext.toDateTime();
                            } else {
                              _newFiscalYearEndDate = DateTime(date.year + 1, date.month, date.day);
                            }
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DateInputField(
                      value: _newFiscalYearEndDate,
                      labelText: 'تاریخ پایان',
                      firstDate: _newFiscalYearStartDate,
                      calendarController: _calendarController!,
                      onChanged: (date) {
                        setState(() {
                          _newFiscalYearEndDate = date;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _newFiscalYearTitleController,
              decoration: const InputDecoration(
                labelText: 'عنوان سال مالی',
                hintText: 'سال مالی منتهی به 1406/1/1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _inventoryValuationMethod,
              decoration: const InputDecoration(
                labelText: 'روش ارزیابی انبار',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'FIFO', child: Text('FIFO')),
                DropdownMenuItem(value: 'LIFO', child: Text('LIFO')),
                DropdownMenuItem(value: 'WeightedAverage', child: Text('میانگین موزون')),
              ],
              onChanged: (value) {
                setState(() {
                  _inventoryValuationMethod = value ?? 'FIFO';
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              'اگر انواع روش‌های ارزیابی انبار را نمی‌شناسید مقدار پیش‌فرض را تغییر ندهید.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBasicSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تنظیمات پایه',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _retainedEarningsFromPreviousYearsController,
              decoration: const InputDecoration(
                labelText: 'سود یا زیان انباشته (سنواتی)',
                hintText: '0',
                border: OutlineInputBorder(),
                suffixText: 'ریال',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('ایجاد خودکار تراز افتتاحیه سال جدید'),
              value: _autoCreateOpeningBalance,
              onChanged: (value) {
                setState(() {
                  _autoCreateOpeningBalance = value ?? true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

