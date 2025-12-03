import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/receipt_payment_document.dart';
import 'package:hesabix_ui/services/receipt_payment_list_service.dart';
import 'package:hesabix_ui/services/invoice_service.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/receipt_payment_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
// removed duplicate import
import 'package:hesabix_ui/widgets/invoice/invoice_transactions_widget.dart';
import 'package:hesabix_ui/widgets/invoice/check_combobox_widget.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/models/invoice_type_model.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
// removed duplicate import
import 'package:hesabix_ui/models/business_dashboard_models.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import '../../utils/snackbar_helper.dart';

/// صفحه لیست اسناد دریافت و پرداخت با ویجت جدول
class ReceiptsPaymentsListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const ReceiptsPaymentsListPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<ReceiptsPaymentsListPage> createState() => _ReceiptsPaymentsListPageState();
}

class _ReceiptsPaymentsListPageState extends State<ReceiptsPaymentsListPage> {
  late ReceiptPaymentListService _service;
  String? _selectedDocumentType;
  DateTime? _fromDate;
  DateTime? _toDate;
  // کلید کنترل جدول برای دسترسی به selection و refresh
  final GlobalKey _tableKey = GlobalKey();
  int _selectedCount = 0; // تعداد سطرهای انتخاب‌شده

  @override
  void initState() {
    super.initState();
    _service = ReceiptPaymentListService(widget.apiClient);
  }

  /// تازه‌سازی داده‌های جدول
  void _refreshData() {
    if (!mounted) return;
    
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        // استفاده از متد عمومی refresh در ویجت جدول
        // نوت: دسترسی دینامیک چون State کلاس خصوصی است
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
        return;
      } catch (e) {
        // در صورت خطا، با setState تلاش می‌کنیم
        debugPrint('خطا در refresh جدول: $e');
      }
    }
    
    // Fallback: استفاده از setState برای به‌روزرسانی
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // هدر صفحه
            _buildHeader(t),
            
            // فیلترها
            _buildFilters(t),
            
            // جدول داده‌ها
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<ReceiptPaymentDocument>(
                  key: _tableKey,
                  config: _buildTableConfig(t),
                  fromJson: (json) => ReceiptPaymentDocument.fromJson(json),
                  calendarController: widget.calendarController,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ساخت هدر صفحه
  Widget _buildHeader(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.receiptsAndPayments,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت اسناد دریافت و پرداخت',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _onAddNew,
            icon: const Icon(Icons.add),
            label: Text(t.add),
          ),
        ],
      ),
    );
  }

  /// ساخت بخش فیلترها
  Widget _buildFilters(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // فیلتر نوع سند
          Expanded(
            flex: 2,
            child: SegmentedButton<String?>(
              segments: [
                ButtonSegment<String?>(
                  value: null,
                  label: Text('همه'),
                  icon: const Icon(Icons.all_inclusive),
                ),
                ButtonSegment<String?>(
                  value: 'receipt',
                  label: Text(t.receipts),
                  icon: const Icon(Icons.download_done_outlined),
                ),
                ButtonSegment<String?>(
                  value: 'payment',
                  label: Text(t.payments),
                  icon: const Icon(Icons.upload_outlined),
                ),
              ],
              selected: {_selectedDocumentType},
              onSelectionChanged: (set) {
                setState(() {
                  _selectedDocumentType = set.first;
                });
                // refresh data when filter changes
                _refreshData();
              },
            ),
          ),
          
          const SizedBox(width: 16),
          
          // فیلتر تاریخ
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: DateInputField(
                    value: _fromDate,
                    calendarController: widget.calendarController,
                    onChanged: (date) {
                      setState(() => _fromDate = date);
                      _refreshData();
                    },
                    labelText: 'از تاریخ',
                    hintText: 'انتخاب تاریخ شروع',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DateInputField(
                    value: _toDate,
                    calendarController: widget.calendarController,
                    onChanged: (date) {
                      setState(() => _toDate = date);
                      _refreshData();
                    },
                    labelText: 'تا تاریخ',
                    hintText: 'انتخاب تاریخ پایان',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _fromDate = null;
                      _toDate = null;
                    });
                    _refreshData();
                  },
                  icon: const Icon(Icons.clear),
                  tooltip: 'پاک کردن فیلتر تاریخ',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ساخت تنظیمات جدول
  DataTableConfig<ReceiptPaymentDocument> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<ReceiptPaymentDocument>(
      endpoint: '/businesses/${widget.businessId}/receipts-payments',
      title: t.receiptsAndPayments,
      excelEndpoint: '/businesses/${widget.businessId}/receipts-payments/export/excel',
      pdfEndpoint: '/businesses/${widget.businessId}/receipts-payments/export/pdf',
      businessId: widget.businessId,
      reportModuleKey: 'receipts_payments',
      reportSubtype: 'list',
      // دکمه حذف گروهی در هدر جدول
      customHeaderActions: [
        Tooltip(
          message: 'حذف انتخاب‌شده‌ها',
          child: FilledButton.icon(
            onPressed: _selectedCount > 0 ? _onBulkDelete : null,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.delete_forever),
            label: Text('حذف ($_selectedCount)'),
          ),
        ),
      ],
      getExportParams: () => {
        'business_id': widget.businessId,
        // همیشه document_type را ارسال کن، حتی اگر null باشد
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toUtc().toIso8601String(),
      },
      columns: [
        // کد سند
        TextColumn(
          'code',
          'کد سند',
          width: ColumnWidth.medium,
          formatter: (item) => item.code,
        ),
        
        // نوع سند
        TextColumn(
          'document_type',
          'نوع',
          width: ColumnWidth.small,
          formatter: (item) => item.documentTypeName,
        ),
        
        // تاریخ سند
        DateColumn(
          'document_date',
          'تاریخ سند',
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.documentDate, widget.calendarController.isJalali),
        ),
        
        // مبلغ کل
        NumberColumn(
          'total_amount',
          'مبلغ کل',
          width: ColumnWidth.large,
          formatter: (item) => formatWithThousands(item.totalAmount),
          suffix: ' ریال',
        ),
        
        // نام اشخاص
        TextColumn(
          'person_names',
          'اشخاص',
          width: ColumnWidth.medium,
          formatter: (item) => item.personNames ?? 'نامشخص',
        ),
        
        // توضیحات
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (item) => item.description ?? '',
        ),
        
        // تعداد حساب‌ها
        NumberColumn(
          'account_lines_count',
          'حساب‌ها',
          width: ColumnWidth.small,
          formatter: (item) => item.accountLinesCount.toString(),
        ),
        
        // ایجادکننده
        TextColumn(
          'created_by_name',
          'ایجادکننده',
          width: ColumnWidth.medium,
          formatter: (item) => item.createdByName ?? 'نامشخص',
        ),
        
        // تاریخ ثبت
        DateColumn(
          'registered_at',
          'تاریخ ثبت',
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.registeredAt, widget.calendarController.isJalali),
        ),
        
        // عملیات
        ActionColumn(
          'actions',
          'عملیات',
          width: ColumnWidth.medium,
          actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: 'مشاهده',
              onTap: (item) => _onView(item),
            ),
            DataTableAction(
              icon: Icons.edit,
              label: 'ویرایش',
              onTap: (item) => _onEdit(item),
            ),
            DataTableAction(
              icon: Icons.delete,
              label: 'حذف',
              onTap: (item) => _onDelete(item),
              isDestructive: true,
            ),
          ],
        ),
      ],
      searchFields: ['code', 'created_by_name'],
      filterFields: ['document_type'],
      dateRangeField: 'document_date',
      showSearch: true,
      showFilters: true,
      showPagination: true,
      showColumnSearch: true,
      showRefreshButton: true,
      showClearFiltersButton: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      showExportButtons: true,
      showExcelExport: true,
      showPdfExport: true,
      defaultPageSize: 20,
      pageSizeOptions: [10, 20, 50, 100],
      onRowSelectionChanged: (rows) {
        setState(() {
          _selectedCount = rows.length;
        });
      },
      additionalParams: {
        // همیشه document_type را ارسال کن، حتی اگر null باشد
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toUtc().toIso8601String(),
      },
      onRowTap: (item) => _onView(item),
      onRowDoubleTap: (item) => _onEdit(item),
      emptyStateMessage: 'هیچ سند دریافت یا پرداختی یافت نشد',
      loadingMessage: 'در حال بارگذاری اسناد...',
      errorMessage: 'خطا در بارگذاری اسناد',
    );
  }

  /// افزودن سند جدید
  void _onAddNew() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => BulkSettlementDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        isReceipt: true, // پیش‌فرض دریافت
        businessInfo: widget.authStore.currentBusiness,
        apiClient: widget.apiClient,
        authStore: widget.authStore,
      ),
    );
    
    // اگر سند با موفقیت ثبت شد، جدول را تازه‌سازی کن
    if (result == true) {
      _refreshData();
    }
  }

  /// مشاهده جزئیات سند
  void _onView(ReceiptPaymentDocument document) async {
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سند یافت نشد')),
        );
        return;
      }

      // نمایش دیالوگ مشاهده جزئیات
      if (!context.mounted) return;
      final ctx = context;
      await showDialog(
        context: ctx,
        builder: (_) => ReceiptPaymentViewDialog(
          document: fullDoc,
          calendarController: widget.calendarController,
          businessId: widget.businessId,
          apiClient: widget.apiClient,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در بارگذاری جزئیات: $e')),
      );
    }
  }

  /// ویرایش سند
  void _onEdit(ReceiptPaymentDocument document) async {
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سند یافت نشد')),
        );
        return;
      }

      if (!context.mounted) return;
      final ctx = context;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (_) => BulkSettlementDialog(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          isReceipt: fullDoc.isReceipt,
          businessInfo: widget.authStore.currentBusiness,
          apiClient: widget.apiClient,
          initialDocument: fullDoc,
          authStore: widget.authStore,
        ),
      );

      if (result == true) {
        _refreshData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در آماده‌سازی ویرایش: $e')),
      );
    }
  }

  /// حذف سند
  void _onDelete(ReceiptPaymentDocument document) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('حذف سند ${document.code} غیرقابل بازگشت است. آیا ادامه می‌دهید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performDelete(document);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  /// انجام عملیات حذف
  Future<void> _performDelete(ReceiptPaymentDocument document) async {
    if (!mounted) return;
    
    // نمایش لودینگ هنگام حذف
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await _service.delete(document.id);
      if (!mounted) return;
      
      // بستن لودینگ
      Navigator.pop(context);
      
      if (success) {
        // پاک‌سازی شمارنده انتخاب
        setState(() {
          _selectedCount = 0;
        });
        
        // تازه‌سازی داده‌ها بعد از بستن دیالوگ
        Future.microtask(() {
          if (mounted) {
            _refreshData();
          }
        });
        
        // نمایش پیام موفقیت
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('سند ${document.code} با موفقیت حذف شد'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('خطا در حذف سند');
      }
    } catch (e) {
      if (!mounted) return;
      
      // بستن لودینگ در صورت بروز خطا
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      String message = 'خطا در حذف سند';
      int? statusCode;
      if (e is DioException) {
        statusCode = e.response?.statusCode;
        final data = e.response?.data;
        try {
          final detail = (data is Map<String, dynamic>) ? data['detail'] : null;
          if (detail is Map<String, dynamic>) {
            final err = detail['error'];
            if (err is Map<String, dynamic>) {
              final m = err['message'];
              if (m is String && m.trim().isNotEmpty) {
                message = m;
              }
            }
          }
        } catch (_) {
          // ignore parse errors
        }

        if (statusCode == 404) {
          message = 'سند یافت نشد یا قبلاً حذف شده است';
          // تازه‌سازی داده‌ها در صورت 404
          Future.microtask(() {
            if (mounted) {
              _refreshData();
            }
          });
        } else if (statusCode == 403) {
          message = 'دسترسی لازم برای حذف این سند را ندارید';
        } else if (statusCode == 409) {
          // پیام از سرور استخراج شده است (مثلاً سند قفل/دارای وابستگی)
          if (message == 'خطا در حذف سند') {
            message = 'حذف این سند امکان‌پذیر نیست';
          }
        }
      } else {
        message = e.toString();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// حذف گروهی اسناد انتخاب‌شده
  Future<void> _onBulkDelete() async {
    if (!mounted) return;
    
    // استخراج آیتم‌های انتخاب‌شده از جدول
    final state = _tableKey.currentState;
    if (state == null) return;

    List<dynamic> selectedItems = const [];
    try {
      // ignore: avoid_dynamic_calls
      selectedItems = (state as dynamic).getSelectedItems();
    } catch (_) {}

    if (selectedItems.isEmpty) return;

    // نگاشت به مدل و شناسه‌ها
    final docs = selectedItems.cast<ReceiptPaymentDocument>();
    final ids = docs.map((d) => d.id).toList();
    final codes = docs.map((d) => d.code).toList();

    // تایید کاربر
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('تأیید حذف گروهی'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تعداد اسناد انتخاب‌شده: ${ids.length}'),
              const SizedBox(height: 8),
              Text('این عملیات غیرقابل بازگشت است. ادامه می‌دهید؟'),
              if (codes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('نمونه کدها: ${codes.take(5).join(', ')}${codes.length > 5 ? ' ...' : ''}'),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // نمایش لودینگ
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _service.deleteMultiple(ids);
      if (!mounted) return;
      
      // بستن لودینگ
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      // پاک‌سازی شمارنده انتخاب
      setState(() {
        _selectedCount = 0;
      });
      
      // تازه‌سازی داده‌ها بعد از بستن دیالوگ
      Future.microtask(() {
        if (mounted) {
          _refreshData();
        }
      });
      
      // نمایش پیام موفقیت
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ids.length} سند با موفقیت حذف شد'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      // بستن لودینگ در صورت بروز خطا
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      String message = 'خطا در حذف اسناد';
      if (e is DioException) {
        message = e.message ?? message;
      } else {
        message = e.toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class BulkSettlementDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final bool isReceipt;
  final BusinessWithPermission? businessInfo;
  final ApiClient apiClient;
  final ReceiptPaymentDocument? initialDocument;
  final AuthStore? authStore;
  const BulkSettlementDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.isReceipt,
    this.businessInfo,
    required this.apiClient,
    this.initialDocument,
    this.authStore,
  });

  @override
  State<BulkSettlementDialog> createState() => _BulkSettlementDialogState();
}

class _BulkSettlementDialogState extends State<BulkSettlementDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _docDate;
  late bool _isReceipt;
  int? _selectedCurrencyId;
  final TextEditingController _descriptionController = TextEditingController();
  final List<_PersonLine> _personLines = <_PersonLine>[];
  final List<InvoiceTransaction> _centerTransactions = <InvoiceTransaction>[];
  // استراتژی پیش‌فرض انتخاب قسط جاری برای این کسب‌وکار
  late String _defaultInstallmentSelectionStrategy; // 'first_remaining' | 'nearest_due' | 'prefer_partial'

  @override
  void initState() {
    super.initState();
    // بارگذاری استراتژی پیش‌فرض از localStorage
    final key = 'installment_strategy_${widget.businessId}';
    final storedStrategy = web_utils.getLocalStorageValue(key);
    _defaultInstallmentSelectionStrategy =
        (storedStrategy == 'nearest_due' || storedStrategy == 'prefer_partial')
            ? storedStrategy!
            : 'first_remaining';
    final initial = widget.initialDocument;
    if (initial != null) {
      // حالت ویرایش: پرکردن اولیه از سند
      _isReceipt = initial.isReceipt;
      _docDate = initial.documentDate;
      _selectedCurrencyId = initial.currencyId;
      _descriptionController.text = initial.description ?? '';
      // تبدیل خطوط اشخاص
      _personLines.clear();
      for (final pl in initial.personLines) {
        final extraInfo = pl.extraInfo;
        _personLines.add(
          _PersonLine(
            personId: pl.personId?.toString(),
            personName: pl.personName,
            amount: pl.amount,
            description: pl.description,
            linkToInvoice: extraInfo?['link_to_invoice'] == true,
            invoiceId: extraInfo?['invoice_id'] is int 
                ? extraInfo!['invoice_id'] as int 
                : extraInfo?['invoice_id'] is num
                    ? (extraInfo!['invoice_id'] as num).toInt()
                    : null,
            invoiceCode: extraInfo?['invoice_code']?.toString(),
          ),
        );
      }
      // لود کردن اطلاعات اقساط از extra_info.settlements
      if (initial.extraInfo != null && initial.extraInfo!['settlements'] != null) {
        final settlements = initial.extraInfo!['settlements'] as List<dynamic>?;
        if (settlements != null && settlements.isNotEmpty) {
          for (final st in settlements) {
            final personId = st['person_id'] as int?;
            final invoiceId = st['invoice_id'] as int?;
            final allocations = st['allocations'] as List<dynamic>?;
            if (personId != null && invoiceId != null && allocations != null && allocations.isNotEmpty) {
              // پیدا کردن personLine مربوطه
              final personLineIndex = _personLines.indexWhere((pl) => pl.personId == personId.toString());
              if (personLineIndex >= 0) {
                // تبدیل allocations به Map<int, double>
                final allocMap = <int, double>{};
                for (final al in allocations) {
                  final seq = (al['seq'] as num?)?.toInt();
                  final amount = (al['amount'] as num?)?.toDouble();
                  if (seq != null && amount != null && amount > 0) {
                    allocMap[seq] = amount;
                  }
                }
                if (allocMap.isNotEmpty) {
                  // پیدا کردن قسط جاری (اولین قسط با تخصیص)
                  int? currentSeq;
                  if (allocMap.isNotEmpty) {
                    currentSeq = allocMap.keys.first;
                  }
                  // فعال کردن اقساط و تنظیم اطلاعات
                  _personLines[personLineIndex] = _personLines[personLineIndex].copyWith(
                    installmentsEnabled: true,
                    installmentInvoiceId: invoiceId,
                    installmentAllocations: allocMap,
                    installmentCurrentSeq: currentSeq,
                    installmentSelectionStrategy: _defaultInstallmentSelectionStrategy,
                  );
                  // لود کردن برنامه اقساط برای نمایش (بعد از initState)
                  final lineToLoad = _personLines[personLineIndex];
                  Future.microtask(() async {
                    if (mounted) {
                      await _loadInstallmentPlanForLine(lineToLoad);
                    }
                  });
                }
              }
            }
          }
        }
      }
      // تبدیل خطوط حساب‌ها (حذف خطوط کارمزد)
      _centerTransactions.clear();
      for (final al in initial.accountLines) {
        final isCommission = (al.extraInfo != null && (al.extraInfo!['is_commission_line'] == true));
        if (isCommission) continue;
        final t = TransactionType.fromValue(al.transactionType ?? '') ?? TransactionType.person;
        _centerTransactions.add(
          InvoiceTransaction(
            id: al.id.toString(),
            type: t,
            bankId: al.extraInfo?['bank_id']?.toString(),
            bankName: al.extraInfo?['bank_name']?.toString(),
            cashRegisterId: al.extraInfo?['cash_register_id']?.toString(),
            cashRegisterName: al.extraInfo?['cash_register_name']?.toString(),
            pettyCashId: al.extraInfo?['petty_cash_id']?.toString(),
            pettyCashName: al.extraInfo?['petty_cash_name']?.toString(),
            checkId: al.extraInfo?['check_id']?.toString(),
            checkNumber: al.extraInfo?['check_number']?.toString(),
            personId: al.extraInfo?['person_id']?.toString(),
            personName: al.extraInfo?['person_name']?.toString(),
            accountId: al.accountId.toString(),
            accountName: al.accountName,
            transactionDate: al.transactionDate ?? _docDate,
            amount: al.amount,
            commission: al.commission,
            description: al.description,
          ),
        );
      }
    } else {
      // حالت ایجاد
      _docDate = DateTime.now();
      _isReceipt = widget.isReceipt;
      _selectedCurrencyId = widget.businessInfo?.defaultCurrency?.id;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final sumPersons = _personLines.fold<double>(0, (p, e) => p + e.amount);
    final sumCenters = _centerTransactions.fold<double>(0, (p, e) => p + (e.amount.toDouble()));
    final diff = (_isReceipt ? sumCenters - sumPersons : sumPersons - sumCenters).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.receiptsAndPayments,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (widget.initialDocument == null)
                      SegmentedButton<bool>(
                      segments: [
                        ButtonSegment<bool>(value: true, label: Text(t.receipts)),
                        ButtonSegment<bool>(value: false, label: Text(t.payments)),
                      ],
                      selected: {_isReceipt},
                      onSelectionChanged: (s) => setState(() => _isReceipt = s.first),
                      ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: DateInputField(
                        value: _docDate,
                        calendarController: widget.calendarController,
                        onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                        labelText: 'تاریخ سند',
                        hintText: 'انتخاب تاریخ',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: CurrencyPickerWidget(
                        businessId: widget.businessId,
                        selectedCurrencyId: _selectedCurrencyId,
                        onChanged: (currencyId) => setState(() => _selectedCurrencyId = currencyId),
                        label: 'ارز',
                        hintText: 'انتخاب ارز',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات کلی سند',
                    hintText: 'توضیحات اختیاری...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _PersonsPanel(
                        businessId: widget.businessId,
                        lines: _personLines,
                        onChanged: (ls) {
                          debugPrint('⚫ [BulkSettlementDialog] onChanged - old lines count: ${_personLines.length}, new lines count: ${ls.length}');
                          for (int i = 0; i < ls.length && i < _personLines.length; i++) {
                            if (_personLines[i].amount != ls[i].amount) {
                              debugPrint('⚫ [BulkSettlementDialog] line $i amount changed: ${_personLines[i].amount} -> ${ls[i].amount}');
                            }
                          }
                          setState(() {
                            _personLines.clear();
                            _personLines.addAll(ls);
                          });
                          debugPrint('⚫ [BulkSettlementDialog] after setState - _personLines[0].amount: ${_personLines.isNotEmpty ? _personLines[0].amount : "N/A"}');
                        },
                        calendarController: widget.calendarController,
                        apiClient: widget.apiClient,
                        selectedCurrencyId: _selectedCurrencyId,
                        isReceipt: _isReceipt,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: InvoiceTransactionsWidget(
                          transactions: _centerTransactions,
                          onChanged: (txs) => setState(() {
                            _centerTransactions.clear();
                            _centerTransactions.addAll(txs);
                          }),
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          invoiceType: InvoiceType.sales,
                          checkPickerMode: _isReceipt ? CheckPickerMode.receipt : CheckPickerMode.payment,
                          authStore: widget.authStore,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // سکشن اقساط حذف شد؛ اقساط در هر ردیف شخص مدیریت می‌شود
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _TotalChip(label: t.people, value: sumPersons),
                          _TotalChip(label: t.accounts, value: sumCenters),
                          _TotalChip(label: 'اختلاف', value: diff, isError: diff != 0),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: diff == 0 && _personLines.isNotEmpty && _centerTransactions.isNotEmpty
                          ? _onSave
                          : null,
                      icon: const Icon(Icons.save),
                      label: Text(t.save),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (!mounted) return;
    
    // بررسی اعتبارسنجی: اگر سویچ اقساط روشن است، باید فاکتور انتخاب شده باشد
    for (final line in _personLines) {
      if (line.installmentsEnabled == true && line.installmentInvoiceId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('برای ${line.personName ?? 'شخص انتخاب شده'} سویچ اقساط روشن است اما فاکتوری انتخاب نشده است. لطفاً فاکتور را انتخاب کنید یا سویچ اقساط را خاموش کنید.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
    }
    
    // نمایش loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final service = ReceiptPaymentService(widget.apiClient);
      
      // تبدیل personLines به فرمت مورد نیاز API
      final personLinesData = _personLines.map((line) {
        final personLine = <String, dynamic>{
          'person_id': int.parse(line.personId!),
          'person_name': line.personName,
          'amount': line.amount,
          if (line.description != null && line.description!.isNotEmpty)
            'description': line.description,
        };
        
        // اضافه کردن اطلاعات فاکتور در extra_info
        if (line.linkToInvoice && line.invoiceId != null) {
          personLine['extra_info'] = {
            'invoice_id': line.invoiceId,
            'invoice_code': line.invoiceCode,
            'link_to_invoice': true,
          };
        }
        
        return personLine;
      }).toList();
      
      // تبدیل centerTransactions به فرمت مورد نیاز API
      final accountLinesData = _centerTransactions.map((tx) => {
        'account_id': tx.accountId,
        'amount': tx.amount.toDouble(),
        'transaction_type': tx.type.value,
        'transaction_date': tx.transactionDate.toIso8601String(),
        if (tx.commission != null && tx.commission! > 0)
          'commission': tx.commission!.toDouble(),
        if (tx.description != null && tx.description!.isNotEmpty)
          'description': tx.description,
        // اطلاعات اضافی بر اساس نوع تراکنش
        if (tx.type == TransactionType.bank) ...{
          'bank_id': tx.bankId,
          'bank_name': tx.bankName,
        },
        if (tx.type == TransactionType.cashRegister) ...{
          'cash_register_id': tx.cashRegisterId,
          'cash_register_name': tx.cashRegisterName,
        },
        if (tx.type == TransactionType.pettyCash) ...{
          'petty_cash_id': tx.pettyCashId,
          'petty_cash_name': tx.pettyCashName,
        },
        if (tx.type == TransactionType.check) ...{
          'check_id': tx.checkId,
          'check_number': tx.checkNumber,
        },
        if (tx.type == TransactionType.person) ...{
          'person_id': tx.personId,
          'person_name': tx.personName,
        },
      }).toList();
      
      // ساخت extra_info (تخصیص اقساط بر اساس ردیف‌های شخص)
      Map<String, dynamic>? extraInfo;
      final settlementsPayload = <Map<String, dynamic>>[];
      for (final line in _personLines) {
        if (!(line.installmentsEnabled == true)) continue;
        if (line.installmentInvoiceId == null || (line.installmentAllocations?.isEmpty ?? true)) continue;
        final pidStr = line.personId;
        if (pidStr == null) continue;
        // سقف جمع: مجموع تخصیص‌های همین ردیف ≤ مبلغ ردیف
        final allocSum = line.installmentAllocations!.values.fold<double>(0, (p, e) => p + (e > 0 ? e : 0));
        if (allocSum > (line.amount + 0.0001)) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('جمع تخصیص اقساط برای ${line.personName ?? ''} از مبلغ خط همان شخص بیشتر است'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        final allocations = line.installmentAllocations!.entries
            .where((e) => (e.value) > 0)
            .map((e) => {'seq': e.key, 'amount': e.value})
            .toList();
        if (allocations.isEmpty) continue;
        settlementsPayload.add({
          'invoice_id': line.installmentInvoiceId,
          'person_id': int.tryParse(pidStr),
                'allocations': allocations,
        });
              }
      if (settlementsPayload.isNotEmpty) {
        extraInfo = {'settlements': settlementsPayload};
      }
      // اگر initialDocument وجود دارد، حالت ویرایش
      if (widget.initialDocument != null) {
        await service.updateReceiptPayment(
          documentId: widget.initialDocument!.id,
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          personLines: personLinesData,
          accountLines: accountLinesData,
          extraInfo: extraInfo,
        );
      } else {
        // ایجاد سند جدید
        await service.createReceiptPayment(
          businessId: widget.businessId,
          documentType: _isReceipt ? 'receipt' : 'payment',
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          personLines: personLinesData,
          accountLines: accountLinesData,
          extraInfo: extraInfo,
        );
      }
      
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // بستن dialog اصلی با موفقیت
      Navigator.pop(context, true);
      
      // نمایش پیام موفقیت
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialDocument != null
              ? 'سند با موفقیت ویرایش شد'
              : (_isReceipt ? 'سند دریافت با موفقیت ثبت شد' : 'سند پرداخت با موفقیت ثبت شد'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // نمایش خطا
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadInstallmentPlanForLine(_PersonLine line) async {
    if (line.installmentInvoiceId == null) return;
    try {
      final svc = InvoiceService(apiClient: widget.apiClient);
      final data = await svc.getInstallmentPlan(
        businessId: widget.businessId,
        invoiceId: line.installmentInvoiceId!,
      );
      // بررسی هم‌ارزی ارز سند دریافت با ارز فاکتور اقساطی
      final planCurrencyId = (data['currency_id'] as num?)?.toInt();
      if (_selectedCurrencyId != null && planCurrencyId != null && _selectedCurrencyId != planCurrencyId) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ارز فاکتور اقساط با ارز سند دریافت متفاوت است. لطفاً ارزی همسان انتخاب کنید.'),
            backgroundColor: Colors.orange,
          ),
        );
        final idx = _personLines.indexOf(line);
        if (idx >= 0) {
          final updated = _personLines[idx].copyWith(
            installmentSchedule: const <Map<String, dynamic>>[],
            installmentAllocations: <int, double>{},
            installmentCurrentSeq: null,
        );
        setState(() {
            _personLines[idx] = updated;
        });
        }
        return;
      }
      final plan = (data['plan'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final schedule = (plan['schedule'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      final invoiceCode = (data['invoice_code'] as String?) ?? '';
      // اگر allocations موجود است (حالت ویرایش)، از آن استفاده کن، در غیر این صورت قسط جاری را انتخاب کن
      final existingAllocations = line.installmentAllocations;
      final strategy = line.installmentSelectionStrategy ?? 'first_remaining';
      int? currentSeq;
      double currentRemaining = 0;
      if (strategy == 'nearest_due') {
        DateTime? bestDue;
        for (final it in schedule) {
          final seq = (it['seq'] as num?)?.toInt() ?? 0;
          final total = (it['total'] as num?)?.toDouble() ?? 0;
          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
          final remaining = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
          if (remaining <= 0) continue;
          final dueStr = (it['due_date'] as String?) ?? '';
          DateTime? due;
          try { if (dueStr.isNotEmpty) due = DateTime.parse(dueStr); } catch (_) {}
          if (due != null && (bestDue == null || due.isBefore(bestDue))) {
            bestDue = due;
            currentSeq = seq;
            currentRemaining = remaining;
          }
        }
      } else if (strategy == 'prefer_partial') {
        for (final it in schedule) {
          final seq = (it['seq'] as num?)?.toInt() ?? 0;
          final total = (it['total'] as num?)?.toDouble() ?? 0;
          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
          final remaining = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
          if (paid > 0 && remaining > 0) { currentSeq = seq; currentRemaining = remaining; break; }
        }
        if (currentSeq == null) {
          for (final it in schedule) {
            final seq = (it['seq'] as num?)?.toInt() ?? 0;
            final total = (it['total'] as num?)?.toDouble() ?? 0;
            final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
            final remaining = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
            if (remaining > 0) { currentSeq = seq; currentRemaining = remaining; break; }
          }
        }
      } else {
        for (final it in schedule) {
          final seq = (it['seq'] as num?)?.toInt() ?? 0;
          final total = (it['total'] as num?)?.toDouble() ?? 0;
          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
          final remaining = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
          if (seq > 0 && remaining > 0) { currentSeq = seq; currentRemaining = remaining; break; }
        }
      }
      final idx = _personLines.indexOf(line);
      if (idx >= 0) {
        // اگر allocations موجود است (حالت ویرایش)، از آن استفاده کن
        final finalAllocs = existingAllocations?.isNotEmpty == true 
            ? existingAllocations! 
            : (currentSeq != null ? <int, double>{currentSeq: currentRemaining} : <int, double>{});
        // اگر allocations موجود است، currentSeq را از آن بگیر
        final finalCurrentSeq = existingAllocations?.isNotEmpty == true 
            ? existingAllocations!.keys.first 
            : currentSeq;
        var newDesc = _personLines[idx].description;
        if (finalCurrentSeq != null && invoiceCode.isNotEmpty) {
          // توضیح خودکار: قسط N فاکتور CODE
          newDesc = 'قسط $finalCurrentSeq فاکتور $invoiceCode'.trim();
        }
        final updated = _personLines[idx].copyWith(
          installmentSchedule: schedule,
          installmentAllocations: finalAllocs,
          installmentCurrentSeq: finalCurrentSeq,
          installmentInvoiceCode: invoiceCode.isNotEmpty ? invoiceCode : _personLines[idx].installmentInvoiceCode,
          amount: existingAllocations?.isNotEmpty == true 
              ? _personLines[idx].amount  // در حالت ویرایش، مبلغ را تغییر نده
              : (currentSeq != null ? currentRemaining : _personLines[idx].amount),
          description: newDesc,
        );
      setState(() {
          _personLines[idx] = updated;
      });
      }
    } catch (e) {
      if (!mounted) return;
      String message = 'خطا در دریافت اقساط';
      if (e is DioException) {
        final status = e.response?.statusCode;
        if (status == 404) {
          message = 'برای این فاکتور طرح اقساط ثبت نشده است';
          // پاک‌سازی انتخاب اقساط تا UI در حالت ناسازگار نماند
          final idx = _personLines.indexOf(line);
          if (idx >= 0) {
            final updated = _personLines[idx].copyWith(
              installmentSchedule: const <Map<String, dynamic>>[],
              installmentAllocations: <int, double>{},
              installmentCurrentSeq: null,
            );
          setState(() {
              _personLines[idx] = updated;
          });
          }
        } else {
          // تلاش برای استخراج پیام سرور
          final data = e.response?.data;
          final serverMsg = (data is Map && data['error'] is Map && (data['error']['message'] is String))
              ? (data['error']['message'] as String)
              : null;
          if (serverMsg != null && serverMsg.trim().isNotEmpty) {
            message = serverMsg;
          }
        }
      } else {
        message = e.toString();
      }
      SnackBarHelper.show(context, message: message);
    }
  }

  Future<void> _pickInvoiceForLine(_PersonLine line) async {
    final svc = InvoiceService(apiClient: widget.apiClient);
    final TextEditingController searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    bool loading = false;
    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> doSearch() async {
          loading = true;
          (ctx as Element).markNeedsBuild();
          try {
            final bodyFilters = <String, dynamic>{};
            final pid = int.tryParse(line.personId ?? '');
            if (pid != null) bodyFilters['person_id'] = pid;
            if (_selectedCurrencyId != null) {
              bodyFilters['currency_id'] = _selectedCurrencyId;
            }
            final data = await svc.searchInvoices(
              businessId: widget.businessId,
              page: 1,
              limit: 20,
              search: searchCtrl.text.trim().isEmpty ? null : searchCtrl.text.trim(),
              filters: bodyFilters.isEmpty ? null : bodyFilters,
            );
            final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
            // فقط فاکتورهای اقساطی را نمایش بده
            results = items.where((it) {
              final isInstallment = it['is_installment_sale'] == true;
              return isInstallment;
            }).toList();
          } catch (e) {
            results = <Map<String, dynamic>>[];
          } finally {
            loading = false;
            (ctx).markNeedsBuild();
          }
        }

        return AlertDialog(
          title: const Text('انتخاب فاکتور'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'جستجو (کد/شرح/...)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => doSearch(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: doSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('جستجو'),
                    ),
                    const SizedBox(width: 8),
                    if (line.personName != null)
                      Chip(label: Text('مشتری: ${line.personName!}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading) const LinearProgressIndicator(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (c, i) {
                      final it = results[i];
                      final code = (it['code']?.toString() ?? '-');
                      final desc = (it['description']?.toString() ?? '').trim();
                      final person = (it['counterparty']?.toString() ?? '').trim();
                      final docDate = (it['document_date']?.toString() ?? '').split('T').first;
                      final total = (it['total_amount'] is num) ? (it['total_amount'] as num).toDouble() : null;
                      final currency = (it['currency_code']?.toString() ?? '').trim();
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                        leading: const Icon(Icons.receipt_long),
                          title: Row(
                            children: [
                              Text(code, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (currency.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Chip(label: Text(currency), visualDensity: VisualDensity.compact),
                              ],
                            ],
                          ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                              children: [
                                  if (person.isNotEmpty) Text('طرف حساب: $person'),
                                if (docDate.isNotEmpty) Text('تاریخ: $docDate'),
                                  if (total != null) Text('مبلغ کل: ${formatWithThousands(total)}'),
                              ],
                            ),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(ctx, it);
                        },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
          ],
        );
      },
    ).then((picked) async {
      if (picked is Map<String, dynamic>) {
        final id = picked['id'] as int?;
        final code = (picked['code']?.toString() ?? '').trim();
        if (id != null) {
          final idx = _personLines.indexOf(line);
          if (idx >= 0) {
          setState(() {
              _personLines[idx] = _personLines[idx].copyWith(
                installmentInvoiceId: id,
                installmentInvoiceCode: code.isNotEmpty ? code : _personLines[idx].installmentInvoiceCode,
              );
          });
            // استفاده از line به‌روز شده
            await _loadInstallmentPlanForLine(_personLines[idx]);
          }
        }
      }
    });
  }
}

class _PersonsPanel extends StatefulWidget {
  final int businessId;
  final List<_PersonLine> lines;
  final ValueChanged<List<_PersonLine>> onChanged;
  final CalendarController calendarController;
  final ApiClient apiClient;
  final int? selectedCurrencyId;
  final bool isReceipt;
  const _PersonsPanel({
    required this.businessId,
    required this.lines,
    required this.onChanged,
    required this.calendarController,
    required this.apiClient,
    required this.selectedCurrencyId,
    required this.isReceipt,
  });

  @override
  State<_PersonsPanel> createState() => _PersonsPanelState();
}

class _PersonsPanelState extends State<_PersonsPanel> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.people, style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                onPressed: () {
                  final newLines = List<_PersonLine>.from(widget.lines);
                  newLines.add(_PersonLine.empty());
                  widget.onChanged(newLines);
                },
                icon: const Icon(Icons.add),
                tooltip: t.add,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.lines.isEmpty
                ? Center(child: Text(t.noDataFound))
                : ListView.separated(
                    itemCount: widget.lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final line = widget.lines[i];
                      return _PersonLineTile(
                        businessId: widget.businessId,
                        line: line,
                        onChanged: (l) {
                          debugPrint('🔴 [PersonsPanel] onChanged called - index: $i, old amount: ${line.amount}, new amount: ${l.amount}');
                          final newLines = List<_PersonLine>.from(widget.lines);
                          newLines[i] = l;
                          debugPrint('🔴 [PersonsPanel] calling widget.onChanged with ${newLines.length} lines');
                          widget.onChanged(newLines);
                        },
                        onDelete: () {
                          final newLines = List<_PersonLine>.from(widget.lines);
                          newLines.removeAt(i);
                          widget.onChanged(newLines);
                        },
                        apiClient: (context.findAncestorStateOfType<_BulkSettlementDialogState>())!.widget.apiClient,
                        calendarController: (context.findAncestorStateOfType<_BulkSettlementDialogState>())!.widget.calendarController,
                        selectedCurrencyId: (context.findAncestorStateOfType<_BulkSettlementDialogState>())!._selectedCurrencyId,
                        isReceipt: widget.isReceipt,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PersonLineTile extends StatefulWidget {
  final int businessId;
  final _PersonLine line;
  final ValueChanged<_PersonLine> onChanged;
  final VoidCallback onDelete;
  final ApiClient apiClient;
  final CalendarController calendarController;
  final int? selectedCurrencyId;
  final bool isReceipt;
  const _PersonLineTile({
    required this.businessId,
    required this.line,
    required this.onChanged,
    required this.onDelete,
    required this.apiClient,
    required this.calendarController,
    required this.selectedCurrencyId,
    required this.isReceipt,
  });

  @override
  State<_PersonLineTile> createState() => _PersonLineTileState();
}

class _PersonLineTileState extends State<_PersonLineTile> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  bool _showInstallmentSchedule = false; // برای نمایش/مخفی کردن لیست اقساط
  List<Map<String, dynamic>> _invoices = [];
  bool _loadingInvoices = false;

  @override
  void initState() {
    super.initState();
    final formatted = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
    _amountController.text = formatted;
    _descController.text = widget.line.description ?? '';
    // اگر قسط جاری انتخاب شده باشد، لیست را مخفی کن
    _showInstallmentSchedule = widget.line.installmentCurrentSeq == null;
    if (widget.line.linkToInvoice && widget.line.personId != null) {
      _loadInvoices();
    }
    debugPrint('🔵 [PersonLineTile] initState - amount: ${widget.line.amount}, formatted: "$formatted", controller.text: "${_amountController.text}"');
  }

  @override
  void didUpdateWidget(covariant _PersonLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // اگر شخص تغییر کرد و لینک فاکتور فعال است، فاکتورها را دوباره لود کن
    if (widget.line.linkToInvoice && 
        widget.line.personId != null && 
        widget.line.personId != oldWidget.line.personId) {
      _loadInvoices();
    }
    if (oldWidget.line.amount != widget.line.amount) {
      final oldAmount = oldWidget.line.amount;
      final newAmount = widget.line.amount;
      final oldControllerText = _amountController.text;
      final formatted = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
      final currentControllerText = _amountController.text;
      final parsedCurrent = parseFormattedDouble(currentControllerText);
      
      debugPrint('🟡 [PersonLineTile] didUpdateWidget - amount changed: $oldAmount -> $newAmount');
      debugPrint('🟡 [PersonLineTile] didUpdateWidget - oldControllerText: "$oldControllerText", formatted: "$formatted"');
      debugPrint('🟡 [PersonLineTile] didUpdateWidget - parsedCurrent: $parsedCurrent, newAmount: $newAmount');
      debugPrint('🟡 [PersonLineTile] didUpdateWidget - selection: ${_amountController.selection}');
      
      // فقط اگر مقدار کنترلر با مقدار جدید متفاوت است، آن را به‌روزرسانی کن
      // این از پاک شدن مقدار هنگام تایپ جلوگیری می‌کند
      if (parsedCurrent != newAmount) {
        _amountController.text = formatted;
        debugPrint('🟡 [PersonLineTile] didUpdateWidget - controller updated to: "$formatted"');
      } else {
        debugPrint('🟡 [PersonLineTile] didUpdateWidget - controller NOT updated (parsedCurrent == newAmount: ${parsedCurrent == newAmount})');
      }
    }
    if (oldWidget.line.description != widget.line.description) {
      _descController.text = widget.line.description ?? '';
    }
    // اگر قسط جاری انتخاب شده باشد، لیست را مخفی کن
    if (widget.line.installmentCurrentSeq != null && oldWidget.line.installmentCurrentSeq == null) {
      _showInstallmentSchedule = false;
    }
  }

  /// محاسبه مانده فاکتور بر اساس تراکنش‌های مرتبط
  Future<double> _calculateInvoiceRemaining(Map<String, dynamic> invoice) async {
    try {
      final invoiceId = (invoice['id'] as num?)?.toInt();
      if (invoiceId == null) return 0;
      
      // دریافت مبلغ کل فاکتور
      final totalAmount = _getInvoiceTotal(invoice);
      
      // دریافت لیست اسناد دریافت/پرداخت مرتبط
      final receiptPaymentService = ReceiptPaymentService(widget.apiClient);
      double totalPaid = 0;
      
      // 1. بررسی از طریق links.receipt_payment_document_ids
      final extraInfo = invoice['extra_info'] as Map<String, dynamic>?;
      if (extraInfo != null) {
        final links = extraInfo['links'] as Map<String, dynamic>?;
        if (links != null) {
          final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
          if (receiptPaymentIds != null && receiptPaymentIds.isNotEmpty) {
            for (final id in receiptPaymentIds) {
              try {
                final docId = id is int ? id : int.tryParse(id.toString());
                if (docId == null) continue;
                
                final doc = await receiptPaymentService.getById(docId);
                if (doc == null) continue;
                
                // مجموع account_lines (بدون کارمزد)
                for (final accountLine in doc.accountLines) {
                  final isCommission = accountLine.extraInfo?['is_commission_line'] == true;
                  if (!isCommission) {
                    totalPaid += accountLine.amount;
                  }
                }
              } catch (e) {
                // ادامه در صورت خطا
              }
            }
          }
        }
      }
      
      // 2. بررسی از طریق جستجو در اسناد دریافت/پرداخت که invoice_id دارند
      try {
        final receiptPaymentList = await receiptPaymentService.listReceiptsPayments(
          businessId: widget.businessId,
          skip: 0,
          take: 1000,
        );
        
        final items = (receiptPaymentList['items'] as List<dynamic>?) ?? [];
        final Set<int> processedDocIds = {};
        
        // محاسبه receipt_payment_document_ids برای جلوگیری از تکرار
        if (extraInfo != null) {
          final links = extraInfo['links'] as Map<String, dynamic>?;
          if (links != null) {
            final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
            if (receiptPaymentIds != null) {
              for (final id in receiptPaymentIds) {
                final docId = id is int ? id : int.tryParse(id.toString());
                if (docId != null) {
                  processedDocIds.add(docId);
                }
              }
            }
          }
        }
        
        for (final item in items) {
          try {
            final docId = (item['id'] as num?)?.toInt();
            if (docId == null || processedDocIds.contains(docId)) continue;
            
            // بررسی person_lines برای invoice_id
            final personLines = item['person_lines'] as List<dynamic>?;
            if (personLines == null) continue;
            
            bool hasInvoiceLink = false;
            for (final pl in personLines) {
              final plExtraInfo = pl['extra_info'] as Map<String, dynamic>?;
              if (plExtraInfo != null) {
                final plInvoiceId = plExtraInfo['invoice_id'];
                if (plInvoiceId is int && plInvoiceId == invoiceId) {
                  hasInvoiceLink = true;
                  break;
                } else if (plInvoiceId is num && plInvoiceId.toInt() == invoiceId) {
                  hasInvoiceLink = true;
                  break;
                }
              }
            }
            
            if (!hasInvoiceLink) continue;
            
            // دریافت جزئیات کامل سند
            final doc = await receiptPaymentService.getById(docId);
            if (doc == null) continue;
            
            processedDocIds.add(docId);
            
            // مجموع account_lines (بدون کارمزد)
            for (final accountLine in doc.accountLines) {
              final isCommission = accountLine.extraInfo?['is_commission_line'] == true;
              if (!isCommission) {
                totalPaid += accountLine.amount;
              }
            }
          } catch (e) {
            // ادامه در صورت خطا
          }
        }
      } catch (e) {
        // در صورت خطا در جستجو، فقط از links استفاده می‌کنیم
      }
      
      return totalAmount - totalPaid;
    } catch (e) {
      return 0;
    }
  }

  /// استخراج مبلغ کل فاکتور
  double _getInvoiceTotal(Map<String, dynamic> invoice) {
    try {
      // اول از total_amount
      if (invoice['total_amount'] != null) {
        final total = invoice['total_amount'];
        if (total is num) return total.toDouble();
        if (total is String) return double.tryParse(total) ?? 0;
      }
      
      // سپس از extra_info.totals.net
      final extraInfo = invoice['extra_info'] as Map<String, dynamic>?;
      if (extraInfo != null) {
        final totals = extraInfo['totals'] as Map<String, dynamic>?;
        if (totals != null && totals['net'] != null) {
          final net = totals['net'];
          if (net is num) return net.toDouble();
          if (net is String) return double.tryParse(net) ?? 0;
        }
      }
      
      // در نهایت از total
      if (invoice['total'] != null) {
        final total = invoice['total'];
        if (total is num) return total.toDouble();
        if (total is String) return double.tryParse(total) ?? 0;
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _loadInvoices() async {
    if (widget.line.personId == null) return;
    
    setState(() {
      _loadingInvoices = true;
    });

    try {
      final invoiceService = InvoiceService(apiClient: widget.apiClient);
      
      // تعیین نوع فاکتورهای مناسب
      final List<String> invoiceTypes;
      if (widget.isReceipt) {
        // برای دریافت: فاکتورهای فروش و برگشت از خرید
        invoiceTypes = ['invoice_sales', 'invoice_purchase_return'];
      } else {
        // برای پرداخت: فاکتورهای خرید و برگشت از فروش
        invoiceTypes = ['invoice_purchase', 'invoice_sales_return'];
      }

      final filters = <String, dynamic>{
        'document_type': invoiceTypes,
        'person_id': int.tryParse(widget.line.personId!) ?? 0,
        'is_proforma': false, // فقط فاکتورهای قطعی
      };
      
      // اضافه کردن فیلتر ارز اگر انتخاب شده باشد
      if (widget.selectedCurrencyId != null) {
        filters['currency_id'] = widget.selectedCurrencyId;
      }

      final result = await invoiceService.searchInvoices(
        businessId: widget.businessId,
        page: 1,
        limit: 100,
        filters: filters,
      );

      if (mounted) {
        final items = (result['items'] as List<dynamic>?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ?? [];
        
        // محاسبه مانده برای هر فاکتور و فیلتر کردن فاکتورهای تسویه شده
        final List<Map<String, dynamic>> validInvoices = [];
        for (final invoice in items) {
          final remaining = await _calculateInvoiceRemaining(invoice);
          // فقط فاکتورهایی که مانده > 0 دارند (تسویه نشده‌اند)
          if (remaining > 0.01) { // tolerance برای خطای ممیز شناور
            validInvoices.add({
              ...invoice,
              '_remaining': remaining,
            });
          }
        }
        
        setState(() {
          _invoices = validInvoices;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _invoices = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingInvoices = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: PersonComboboxWidget(
                    businessId: widget.businessId,
                    selectedPerson: widget.line.personId != null 
                        ? Person(
                            id: int.tryParse(widget.line.personId!),
                            businessId: widget.businessId,
                            aliasName: widget.line.personName ?? '',
                            personTypes: const [],
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          )
                        : null,
                    onChanged: (opt) {
                      widget.onChanged(widget.line.copyWith(
                        personId: opt?.id?.toString(), 
                        personName: opt?.displayName,
                        // اگر شخص تغییر کرد و لینک فاکتور فعال است، فاکتورها را reset کن
                        invoiceId: opt == null ? null : widget.line.invoiceId,
                        invoiceCode: opt == null ? null : widget.line.invoiceCode,
                      ));
                      // اگر شخص انتخاب شد و لینک فاکتور فعال است، فاکتورها را لود کن
                      if (opt != null && widget.line.linkToInvoice) {
                        Future.microtask(() => _loadInvoices());
                      }
                    },
                    label: t.people,
                    hintText: t.search,
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: t.amount,
                      hintText: '1,000,000',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      EnglishDigitsFormatter(),
                      ThousandsSeparatorInputFormatter(allowDecimal: false),
                    ],
                    validator: (v) {
                      final val = parseFormattedDouble(v);
                      debugPrint('🟢 [PersonLineTile] validator - input: "$v", parsed: $val');
                      if (val == null || val <= 0) return t.mustBePositiveNumber;
                      return null;
                    },
                    onChanged: (v) {
                      final controllerTextBefore = _amountController.text;
                      final parsed = parseFormattedDouble(v);
                      final val = parsed ?? 0;
                      debugPrint('🟠 [PersonLineTile] onChanged - input: "$v", controller.text before: "$controllerTextBefore", parsed: $parsed, final val: $val, old line.amount: ${widget.line.amount}');
                      widget.onChanged(widget.line.copyWith(amount: val));
                      debugPrint('🟣 [PersonLineTile] onChanged - after widget.onChanged, controller.text: "${_amountController.text}"');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: t.description,
              ),
              onChanged: (v) => widget.onChanged(widget.line.copyWith(description: v.trim().isEmpty ? null : v.trim())),
            ),
            const SizedBox(height: 8),
            // سوئیچ لینک به فاکتور (فقط برای اسناد غیراقساطی)
            SwitchListTile(
              title: const Text('لینک به فاکتور'),
              subtitle: Text(widget.isReceipt 
                  ? 'این دریافت را به فاکتور فروش مرتبط کن (قابل استفاده نیست اگر اقساط فعال باشد)'
                  : 'این پرداخت را به فاکتور خرید مرتبط کن'),
              value: widget.line.linkToInvoice,
              onChanged: (widget.line.personId != null && !widget.line.installmentsEnabled)
                  ? (value) {
                      if (value && widget.line.installmentsEnabled) {
                        // نباید همزمان فعال شود
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('نمی‌توان همزمان لینک به فاکتور و اقساط را فعال کرد. لطفاً ابتدا اقساط را غیرفعال کنید.'),
                            backgroundColor: Colors.orange,
                            duration: Duration(seconds: 3),
                          ),
                        );
                        return;
                      }
                      widget.onChanged(widget.line.copyWith(
                        linkToInvoice: value,
                        invoiceId: value ? null : null,
                        invoiceCode: value ? null : null,
                      ));
                      if (value) {
                        _loadInvoices();
                      }
                    }
                  : null,
            ),
            // Dropdown انتخاب فاکتور (فقط اگر سوئیچ فعال باشد)
            if (widget.line.linkToInvoice && widget.line.personId != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: widget.line.invoiceId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'فاکتور',
                  hintText: _loadingInvoices ? 'در حال بارگذاری...' : 'انتخاب فاکتور',
                  border: const OutlineInputBorder(),
                ),
                items: _loadingInvoices
                    ? [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      ]
                    : _invoices.map((invoice) {
                        final id = (invoice['id'] as num?)?.toInt();
                        final code = invoice['code']?.toString() ?? '';
                        final total = _getInvoiceTotal(invoice);
                        final remaining = (invoice['_remaining'] as num?)?.toDouble() ?? (total - 0);
                        final dateStr = invoice['document_date']?.toString();
                        final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
                        final dateDisplay = date != null ? HesabixDateUtils.formatForDisplay(date, true) : '';
                        
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                code,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                dateDisplay.isNotEmpty 
                                    ? 'تاریخ: $dateDisplay'
                                    : '',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'مبلغ کل: ${formatWithThousands(total)}',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'مانده: ${formatWithThousands(remaining)}',
                                style: TextStyle(
                                  color: remaining > 0 
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                selectedItemBuilder: (context) {
                  // نمایش کد فاکتور انتخاب شده در dropdown
                  if (widget.line.invoiceId == null) {
                    return [
                      const Text(
                        'انتخاب فاکتور',
                        overflow: TextOverflow.ellipsis,
                      )
                    ];
                  }
                  final selectedInvoice = _invoices.firstWhere(
                    (inv) => (inv['id'] as num?)?.toInt() == widget.line.invoiceId,
                    orElse: () => <String, dynamic>{},
                  );
                  final code = selectedInvoice['code']?.toString() ?? '';
                  return [
                    Text(
                      code.isNotEmpty ? code : 'انتخاب فاکتور',
                      overflow: TextOverflow.ellipsis,
                    )
                  ];
                },
                onChanged: (invoiceId) {
                  final invoice = _invoices.firstWhere(
                    (inv) => (inv['id'] as num?)?.toInt() == invoiceId,
                    orElse: () => <String, dynamic>{},
                  );
                  widget.onChanged(widget.line.copyWith(
                    invoiceId: invoiceId,
                    invoiceCode: invoice['code']?.toString(),
                  ));
                },
              ),
            ],
            // بخش اقساط فقط برای اسناد دریافت نمایش داده می‌شود
            if (widget.isReceipt) ...[
              const SizedBox(height: 8),
              // سطر اول: سویچ اقساط و انتخاب فاکتور
              Row(
                children: [
                  Switch(
                    value: widget.line.installmentsEnabled,
                    onChanged: (enabled) {
                      if (enabled && widget.line.linkToInvoice) {
                        // نباید همزمان فعال شود
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('نمی‌توان همزمان اقساط و لینک به فاکتور را فعال کرد. لطفاً ابتدا لینک به فاکتور را غیرفعال کنید.'),
                            backgroundColor: Colors.orange,
                            duration: Duration(seconds: 3),
                          ),
                        );
                        return;
                      }
                      final ancestor = context.findAncestorStateOfType<_BulkSettlementDialogState>();
                      final defaultStrategy = ancestor?._defaultInstallmentSelectionStrategy ?? 'first_remaining';
                      var updated = widget.line.copyWith(
                        installmentsEnabled: enabled,
                        installmentSelectionStrategy: enabled
                            ? (widget.line.installmentSelectionStrategy ?? defaultStrategy)
                            : widget.line.installmentSelectionStrategy,
                      );
                      if (!enabled) {
                        updated = updated.copyWith(
                          installmentInvoiceId: null,
                          installmentSchedule: const <Map<String, dynamic>>[],
                          installmentAllocations: <int, double>{},
                          installmentCurrentSeq: null,
                          installmentSelectionStrategy: null,
                        );
                      }
                      widget.onChanged(updated);
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text('اقساط'),
                  const Spacer(),
                if (widget.line.installmentsEnabled) ...[
                  FilledButton(
                    onPressed: (widget.line.personId == null)
                        ? null
                        : () async {
                            await (context.findAncestorStateOfType<_BulkSettlementDialogState>())!
                                ._pickInvoiceForLine(widget.line);
                            setState(() {});
                          },
                    child: Text(widget.line.installmentInvoiceId == null ? 'انتخاب فاکتور' : 'تغییر فاکتور'),
                  ),
                  if (widget.line.installmentInvoiceCode != null && widget.line.installmentInvoiceCode!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('فاکتور: ${widget.line.installmentInvoiceCode}'),
                      avatar: const Icon(Icons.receipt_long, size: 18),
                    ),
                  ],
                ],
              ],
            ),
            // سطر دوم: استراتژی و دکمه اعمال
            if (widget.line.installmentsEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  // استراتژی انتخاب قسط جاری
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: widget.line.installmentSelectionStrategy
                          ?? (context.findAncestorStateOfType<_BulkSettlementDialogState>()?._defaultInstallmentSelectionStrategy ?? 'first_remaining'),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'روش انتخاب قسط جاری',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'first_remaining', child: Text('اولین قسط با مانده')),
                        DropdownMenuItem(value: 'nearest_due', child: Text('نزدیک‌ترین سررسید با مانده')),
                        DropdownMenuItem(value: 'prefer_partial', child: Text('اول قسط‌های نیمه‌پرداخت')),
                      ],
                      onChanged: (v) {
                        widget.onChanged(widget.line.copyWith(installmentSelectionStrategy: v));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'تنظیم استراتژی پیش‌فرض اقساط برای این کسب‌وکار',
                    child: IconButton(
                      onPressed: () async {
                        final ancestor = context.findAncestorStateOfType<_BulkSettlementDialogState>();
                        if (ancestor == null) return;
                        final current = ancestor._defaultInstallmentSelectionStrategy;
                        String temp = current;
                        await showDialog(
                          context: context,
                          builder: (ctx) {
                            return AlertDialog(
                              title: const Text('تنظیم استراتژی پیش‌فرض اقساط'),
                              content: StatefulBuilder(
                                builder: (ctx, setSt) {
                                  return SizedBox(
                                    width: 360,
                                    child: DropdownButtonFormField<String>(
                                      value: temp,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'استراتژی پیش‌فرض',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'first_remaining', child: Text('اولین قسط با مانده')),
                                        DropdownMenuItem(value: 'nearest_due', child: Text('نزدیک‌ترین سررسید با مانده')),
                                        DropdownMenuItem(value: 'prefer_partial', child: Text('اول قسط‌های نیمه‌پرداخت')),
                                      ],
                                      onChanged: (v) => setSt(() => temp = v ?? 'first_remaining'),
                                    ),
                                  );
                                },
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
                                FilledButton(
                                  onPressed: () {
                                    try {
                                      final key = 'installment_strategy_${ancestor.widget.businessId}';
                                      web_utils.setLocalStorageValue(key, temp);
                                      ancestor.setState(() {
                                        ancestor._defaultInstallmentSelectionStrategy = temp;
                                      });
                                    } catch (_) {}
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('ذخیره'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      icon: const Icon(Icons.settings_suggest_outlined),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: (widget.line.installmentInvoiceId == null) ? null : () async {
                      // اعمال مجدد استراتژی روی برنامه موجود
                      final schedule = widget.line.installmentSchedule ?? const <Map<String, dynamic>>[];
                      if (schedule.isEmpty) return;
                      final strategy = widget.line.installmentSelectionStrategy ?? 'first_remaining';
                      int? selSeq;
                      double selRemain = 0;
                      if (strategy == 'nearest_due') {
                        DateTime? bestDue;
                        for (final it in schedule) {
                          final total = (it['total'] as num?)?.toDouble() ?? 0;
                          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
                          final remain = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
                          if (remain <= 0) continue;
                          final dueStr = (it['due_date'] as String?) ?? '';
                          DateTime? due;
                          try { if (dueStr.isNotEmpty) due = DateTime.parse(dueStr); } catch (_) {}
                          final seq = (it['seq'] as num?)?.toInt() ?? 0;
                          if (due != null && (bestDue == null || due.isBefore(bestDue))) {
                            bestDue = due;
                            selSeq = seq;
                            selRemain = remain;
                          }
                        }
                      } else if (strategy == 'prefer_partial') {
                        // ابتدا partial: paid>0 && remaining>0
                        for (final it in schedule) {
                          final total = (it['total'] as num?)?.toDouble() ?? 0;
                          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
                          final remain = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
                          final seq = (it['seq'] as num?)?.toInt() ?? 0;
                          if (paid > 0 && remain > 0) {
                            selSeq = seq; selRemain = remain; break;
                          }
                        }
                        // اگر نبود، اولین با مانده
                        if (selSeq == null) {
                          for (final it in schedule) {
                            final total = (it['total'] as num?)?.toDouble() ?? 0;
                            final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
                            final remain = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
                            final seq = (it['seq'] as num?)?.toInt() ?? 0;
                            if (remain > 0) { selSeq = seq; selRemain = remain; break; }
                          }
                        }
                      } else {
                        // first_remaining
                        for (final it in schedule) {
                          final total = (it['total'] as num?)?.toDouble() ?? 0;
                          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
                          final remain = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
                          final seq = (it['seq'] as num?)?.toInt() ?? 0;
                          if (remain > 0) { selSeq = seq; selRemain = remain; break; }
                        }
                      }
                      if (selSeq != null && selRemain > 0) {
                        final newAllocs = <int, double>{selSeq: selRemain};
                        final newDesc = 'قسط $selSeq فاکتور ${widget.line.installmentInvoiceCode ?? ''}'.trim();
                        widget.onChanged(widget.line.copyWith(
                          installmentAllocations: newAllocs,
                          installmentCurrentSeq: selSeq,
                          amount: selRemain,
                          description: newDesc,
                        ));
                        setState(() {});
                      }
                    },
                    child: const Text('اعمال استراتژی'),
                  ),
                ],
              ),
            ],
            if (widget.line.installmentsEnabled && (widget.line.installmentSchedule?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              // دکمه نمایش/مخفی کردن لیست اقساط
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showInstallmentSchedule = !_showInstallmentSchedule;
                      });
                    },
                    icon: Icon(_showInstallmentSchedule ? Icons.expand_less : Icons.expand_more),
                    label: Text(_showInstallmentSchedule ? 'مخفی کردن لیست اقساط' : 'نمایش لیست اقساط'),
                  ),
                  if (widget.line.installmentCurrentSeq != null) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('قسط جاری: ${widget.line.installmentCurrentSeq}'),
                      avatar: const Icon(Icons.check_circle, size: 18),
                    ),
                  ],
                ],
              ),
              if (_showInstallmentSchedule) ...[
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Expanded(child: Text('قسط')),
                    Expanded(child: Text('سررسید')),
                    Expanded(child: Text('باقیمانده')),
                    SizedBox(width: 120, child: Text('مبلغ تخصیص', textAlign: TextAlign.end)),
                  ],
                ),
                const Divider(),
                ...(widget.line.installmentSchedule ?? const <Map<String, dynamic>>[]).map((it) {
                  final seq = (it['seq'] as num?)?.toInt() ?? 0;
                  final dueStr = (it['due_date'] as String?);
                  DateTime? dueDate;
                  String dueDisplay = '-';
                  if (dueStr != null && dueStr.isNotEmpty && dueStr != '-') {
                    try {
                      dueDate = DateTime.parse(dueStr);
                      dueDisplay = HesabixDateUtils.formatForDisplay(dueDate, widget.calendarController.isJalali);
                    } catch (_) {
                      dueDisplay = dueStr;
                    }
                  }
                  final remaining = (it['remaining'] as num?)?.toDouble() ??
                      (((it['total'] as num?)?.toDouble() ?? 0) - ((it['paid_amount'] as num?)?.toDouble() ?? 0));
                  final current = widget.line.installmentAllocations?[seq] ?? 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text('#$seq')),
                        Expanded(child: Text(dueDisplay)),
                        Expanded(child: Text(formatWithThousands(remaining))),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            textAlign: TextAlign.end,
                            initialValue: current > 0 ? formatWithThousands(current) : '',
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) {
                              final val = double.tryParse(v.replaceAll(',', '')) ?? 0;
                              final newMap = Map<int, double>.from(widget.line.installmentAllocations ?? <int, double>{});
                              if (val <= 0) {
                                newMap.remove(seq);
                              } else {
                                newMap[seq] = val;
                              }
                              widget.onChanged(widget.line.copyWith(installmentAllocations: newMap));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // دکمه انتخاب به عنوان قسط جاری: مبلغ و توضیح ردیف را خودکار تنظیم می‌کند
                        FilledButton.tonal(
                          onPressed: remaining <= 0
                              ? null
                              : () {
                                  final newAllocs = <int, double>{seq: remaining};
                                  final newDesc = 'قسط $seq فاکتور ${widget.line.installmentInvoiceCode ?? ''}'.trim();
                                  widget.onChanged(widget.line.copyWith(
                                    installmentAllocations: newAllocs,
                                    installmentCurrentSeq: seq,
                                    amount: remaining,
                                    description: newDesc,
                                  ));
                                  setState(() {
                                    _showInstallmentSchedule = false; // مخفی کردن لیست بعد از انتخاب
                                  });
                                },
                          child: const Text('انتخاب به عنوان جاری'),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
            ],
          ],
        ),
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final double value;
  final bool isError;
  const _TotalChip({required this.label, required this.value, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label: ${formatWithThousands(value)}'),
      backgroundColor: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: isError ? scheme.onErrorContainer : scheme.onSurfaceVariant),
    );
  }
}

class _PersonLine {
  final String? personId;
  final String? personName;
  final double amount;
  final String? description;
  final bool installmentsEnabled;
  final int? installmentInvoiceId;
  final List<Map<String, dynamic>>? installmentSchedule;
  final Map<int, double>? installmentAllocations;
  final String? installmentInvoiceCode;
  final int? installmentCurrentSeq;
  final String? installmentSelectionStrategy; // 'first_remaining' | 'nearest_due' | 'prefer_partial'
  final bool linkToInvoice;
  final int? invoiceId;
  final String? invoiceCode;

  const _PersonLine({
    this.personId,
    this.personName,
    required this.amount,
    this.description,
    this.installmentsEnabled = false,
    this.installmentInvoiceId,
    this.installmentSchedule,
    this.installmentAllocations,
    this.installmentInvoiceCode,
    this.installmentCurrentSeq,
    this.installmentSelectionStrategy,
    this.linkToInvoice = false,
    this.invoiceId,
    this.invoiceCode,
  });

  factory _PersonLine.empty() => const _PersonLine(
        amount: 0,
        installmentsEnabled: false,
      );

  _PersonLine copyWith({
    String? personId,
    String? personName,
    double? amount,
    String? description,
    bool? installmentsEnabled,
    int? installmentInvoiceId,
    List<Map<String, dynamic>>? installmentSchedule,
    Map<int, double>? installmentAllocations,
    String? installmentInvoiceCode,
    int? installmentCurrentSeq,
    String? installmentSelectionStrategy,
    bool? linkToInvoice,
    int? invoiceId,
    String? invoiceCode,
  }) {
    final newAmount = amount ?? this.amount;
    if (amount != null && amount != this.amount) {
      debugPrint('🟤 [PersonLine.copyWith] amount changed: ${this.amount} -> $newAmount');
    }
    return _PersonLine(
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      amount: newAmount,
      description: description ?? this.description,
      installmentsEnabled: installmentsEnabled ?? this.installmentsEnabled,
      installmentInvoiceId: installmentInvoiceId ?? this.installmentInvoiceId,
      installmentSchedule: installmentSchedule ?? this.installmentSchedule,
      installmentAllocations: installmentAllocations ?? this.installmentAllocations,
      installmentInvoiceCode: installmentInvoiceCode ?? this.installmentInvoiceCode,
      installmentCurrentSeq: installmentCurrentSeq ?? this.installmentCurrentSeq,
      installmentSelectionStrategy: installmentSelectionStrategy ?? this.installmentSelectionStrategy,
      linkToInvoice: linkToInvoice ?? this.linkToInvoice,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceCode: invoiceCode ?? this.invoiceCode,
    );
  }
}

/// دیالوگ مشاهده جزئیات سند دریافت/پرداخت
class ReceiptPaymentViewDialog extends StatefulWidget {
  final ReceiptPaymentDocument document;
  final CalendarController calendarController;
  final int businessId;
  final ApiClient apiClient;

  const ReceiptPaymentViewDialog({
    super.key,
    required this.document,
    required this.calendarController,
    required this.businessId,
    required this.apiClient,
  });

  @override
  State<ReceiptPaymentViewDialog> createState() => _ReceiptPaymentViewDialogState();
}

class _ReceiptPaymentViewDialogState extends State<ReceiptPaymentViewDialog> {
  bool _isGeneratingPdf = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final doc = widget.document;
    
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // هدر دیالوگ
            _buildHeader(t, doc),
            
            // محتوای اصلی
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اطلاعات کلی سند
                    _buildDocumentInfo(t, doc),
                    
                    const SizedBox(height: 24),
                    
                    // خطوط اشخاص
                    _buildPersonLines(t, doc),
                    
                    const SizedBox(height: 24),
                    
                    // خطوط حساب‌ها
                    _buildAccountLines(t, doc),
                  ],
                ),
              ),
            ),
            
            // دکمه‌های پایین
            _buildFooter(t),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'جزئیات سند ${doc.documentTypeName}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'کد سند: ${doc.code}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: 'بستن',
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentInfo(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات کلی سند',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildInfoRow('نوع سند', doc.documentTypeName),
            _buildInfoRow('تاریخ سند', HesabixDateUtils.formatForDisplay(doc.documentDate, widget.calendarController.isJalali)),
            _buildInfoRow('تاریخ ثبت', HesabixDateUtils.formatForDisplay(doc.registeredAt, widget.calendarController.isJalali)),
            _buildInfoRow('ارز', doc.currencyCode ?? 'نامشخص'),
            _buildInfoRow('ایجادکننده', doc.createdByName ?? 'نامشخص'),
            _buildInfoRow('مبلغ کل', formatWithThousands(doc.totalAmount) + ' ریال'),
            if (doc.description != null && doc.description!.isNotEmpty)
              _buildInfoRow('توضیحات', doc.description!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonLines(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطوط اشخاص (${doc.personLinesCount})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (doc.personLines.isEmpty)
              const Text('هیچ خط شخصی یافت نشد')
            else
              ...doc.personLines.map((line) => _buildPersonLineItem(line)),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonLineItem(PersonLine line) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.personName ?? 'نامشخص',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (line.description != null && line.description!.isNotEmpty)
                  Text(
                    line.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            formatWithThousands(line.amount) + ' ریال',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountLines(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطوط حساب‌ها (${doc.accountLinesCount})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (doc.accountLines.isEmpty)
              const Text('هیچ خط حسابی یافت نشد')
            else
              ...doc.accountLines.map((line) => _buildAccountLineItem(line)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountLineItem(AccountLine line) {
    final isCommission = line.extraInfo?['is_commission_line'] == true;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isCommission 
            ? Theme.of(context).colorScheme.error 
            : Theme.of(context).colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isCommission 
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1)
          : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.accountName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'کد: ${line.accountCode}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (line.transactionType != null)
                      Text(
                        'نوع: ${_getTransactionTypeName(line.transactionType!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Text(
                formatWithThousands(line.amount) + ' ریال',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (line.description != null && line.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              line.description!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (isCommission) ...[
            const SizedBox(height: 4),
            Text(
              'کارمزد',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getTransactionTypeName(String type) {
    switch (type) {
      case 'bank':
        return 'بانک';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواهگردان';
      case 'check':
        return 'چک';
      case 'person':
        return 'شخص';
      default:
        return type;
    }
  }

  Widget _buildFooter(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isGeneratingPdf ? null : _generatePdf,
            icon: _isGeneratingPdf 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf),
            label: Text(_isGeneratingPdf ? AppLocalizations.of(context).generating : AppLocalizations.of(context).exportToPdf),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      // ایجاد PDF از سند
      final pdfBytes = await widget.apiClient.downloadPdf(
        '/receipts-payments/${widget.document.id}/pdf',
      );

      // ذخیره فایل
      await _savePdfFile(pdfBytes, widget.document.code);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).pdfSuccess),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).pdfError}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  Future<void> _savePdfFile(List<int> bytes, String filename) async {
    if (kIsWeb) {
      await web_utils.saveBytesAsFileWeb(
        bytes,
        filename.endsWith('.pdf') ? filename : '$filename.pdf',
        mimeType: 'application/pdf',
      );
    } else {
      throw UnsupportedError('PDF download is only supported on web.');
    }
  }
}

