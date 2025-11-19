import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/expense_income_document.dart';
import 'package:hesabix_ui/services/expense_income_list_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/widgets/expense_income/expense_income_form_dialog.dart';
import 'package:hesabix_ui/widgets/expense_income/expense_income_details_dialog.dart';

/// صفحه لیست اسناد هزینه و درآمد با ویجت جدول
class ExpenseIncomeListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const ExpenseIncomeListPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<ExpenseIncomeListPage> createState() => _ExpenseIncomeListPageState();
}

class _ExpenseIncomeListPageState extends State<ExpenseIncomeListPage> {
  late ExpenseIncomeListService _service;
  String? _selectedDocumentType;
  DateTime? _fromDate;
  DateTime? _toDate;
  // کلید کنترل جدول برای دسترسی به selection و refresh
  final GlobalKey _tableKey = GlobalKey();
  int _selectedCount = 0; // تعداد سطرهای انتخاب‌شده

  @override
  void initState() {
    super.initState();
    _service = ExpenseIncomeListService(widget.apiClient);
  }

  /// تازه‌سازی داده‌های جدول
  void _refreshData() {
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        // استفاده از متد عمومی refresh در ویجت جدول
        // نوت: دسترسی دینامیک چون State کلاس خصوصی است
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
        return;
      } catch (_) {}
    }
    if (mounted) setState(() {});
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
                child: DataTableWidget<ExpenseIncomeDocument>(
                  key: _tableKey,
                  config: _buildTableConfig(t),
                  fromJson: (json) => ExpenseIncomeDocument.fromJson(json),
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
                  'هزینه و درآمد',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت اسناد هزینه و درآمد',
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
                  value: 'expense',
                  label: Text('هزینه‌ها'),
                  icon: const Icon(Icons.trending_down),
                ),
                ButtonSegment<String?>(
                  value: 'income',
                  label: Text('درآمدها'),
                  icon: const Icon(Icons.trending_up),
                ),
              ],
              selected: _selectedDocumentType != null ? {_selectedDocumentType} : <String?>{},
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
  DataTableConfig<ExpenseIncomeDocument> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<ExpenseIncomeDocument>(
      endpoint: '/businesses/${widget.businessId}/expense-income',
      title: 'هزینه و درآمد',
      excelEndpoint: '/businesses/${widget.businessId}/expense-income/export/excel',
      pdfEndpoint: '/businesses/${widget.businessId}/expense-income/export/pdf',
      businessId: widget.businessId,
      reportModuleKey: 'expense_income',
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
        
        // نام حساب‌ها
        TextColumn(
          'item_accounts',
          'حساب‌ها',
          width: ColumnWidth.medium,
          formatter: (item) => item.itemAccountNames ?? 'نامشخص',
        ),
        
        // اطلاعات طرف‌حساب
        TextColumn(
          'counterparty_info',
          'طرف‌حساب',
          width: ColumnWidth.medium,
          formatter: (item) => item.counterpartyInfo ?? 'نامشخص',
        ),
        
        // توضیحات
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (item) => item.description ?? '',
        ),
        
        // تعداد خطوط
        NumberColumn(
          'lines_count',
          'خطوط',
          width: ColumnWidth.small,
          formatter: (item) => (item.itemLinesCount + item.counterpartyLinesCount).toString(),
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
      emptyStateMessage: 'هیچ سند هزینه یا درآمدی یافت نشد',
      loadingMessage: 'در حال بارگذاری اسناد...',
      errorMessage: 'خطا در بارگذاری اسناد',
    );
  }

  /// افزودن سند جدید
  void _onAddNew() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ExpenseIncomeFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        isIncome: false, // پیش‌فرض هزینه
        businessInfo: widget.authStore.currentBusiness,
        apiClient: widget.apiClient,
      ),
    );
    
    // اگر سند با موفقیت ثبت شد، جدول را تازه‌سازی کن
    if (result == true) {
      _refreshData();
    }
  }

  /// مشاهده جزئیات سند
  void _onView(ExpenseIncomeDocument document) async {
    if (!context.mounted) return;
    final ctx = context;
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('سند یافت نشد')),
        );
        return;
      }

      // نمایش دیالوگ مشاهده جزئیات
      if (!ctx.mounted) return;
      await showDialog(
        context: ctx,
        builder: (_) => ExpenseIncomeDetailsDialog(
          document: fullDoc,
          calendarController: widget.calendarController,
          businessId: widget.businessId,
          apiClient: widget.apiClient,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('خطا در بارگذاری جزئیات: $e')),
      );
    }
  }

  /// ویرایش سند
  void _onEdit(ExpenseIncomeDocument document) async {
    if (!context.mounted) return;
    final ctx = context;
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('سند یافت نشد')),
        );
        return;
      }
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (_) => ExpenseIncomeFormDialog(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          isIncome: fullDoc.isIncome,
          businessInfo: widget.authStore.currentBusiness,
          apiClient: widget.apiClient,
          initialDocument: fullDoc,
        ),
      );

      if (result == true) {
        _refreshData();
      }
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('خطا در آماده‌سازی ویرایش: $e')),
      );
    }
  }

  /// حذف سند
  void _onDelete(ExpenseIncomeDocument document) {
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
  Future<void> _performDelete(ExpenseIncomeDocument document) async {
    try {
      // نمایش لودینگ هنگام حذف
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final success = await _service.delete(document.id);
      if (success) {
        if (mounted) {
          Navigator.pop(context); // بستن لودینگ
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('سند ${document.code} با موفقیت حذف شد'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _selectedCount = 0; // پاک‌سازی شمارنده انتخاب پس از حذف
          });
          _refreshData();
        }
      } else {
        if (mounted) Navigator.pop(context);
        throw Exception('خطا در حذف سند');
      }
    } catch (e) {
      if (mounted) {
        // بستن لودینگ در صورت بروز خطا
        Navigator.pop(context);

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
            _refreshData();
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
  }

  /// حذف گروهی اسناد انتخاب‌شده
  Future<void> _onBulkDelete() async {
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
    final docs = selectedItems.cast<ExpenseIncomeDocument>();
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

    // نمایش لودینگ
    if (!context.mounted) return;
    final ctx = context;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _service.deleteMultiple(ids);
      if (!ctx.mounted) return;
      Navigator.pop(ctx); // بستن لودینگ
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('${ids.length} سند با موفقیت حذف شد'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _selectedCount = 0; // پاک‌سازی شمارنده انتخاب پس از حذف گروهی
      });
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // بستن لودینگ
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