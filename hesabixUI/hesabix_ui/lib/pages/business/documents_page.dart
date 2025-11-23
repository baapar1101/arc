import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/services/document_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/widgets/document/document_details_dialog.dart';
import 'package:hesabix_ui/widgets/document/document_form_dialog.dart';

/// صفحه لیست اسناد حسابداری (عمومی و اتوماتیک)
class DocumentsPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const DocumentsPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  late DocumentService _service;
  String? _selectedDocumentType;
  DateTime? _fromDate;
  DateTime? _toDate;
  final GlobalKey _tableKey = GlobalKey();
  int _selectedCount = 0;

  // انواع اسناد
  final Map<String, String> _documentTypes = {
    'all': 'همه',
    'manual': 'سند دستی',
    'expense': 'هزینه',
    'income': 'درآمد',
    'receipt': 'دریافت',
    'payment': 'پرداخت',
    'transfer': 'انتقال',
    'invoice': 'فاکتور',
  };

  @override
  void initState() {
    super.initState();
    _service = DocumentService(widget.apiClient);
  }

  /// تازه‌سازی داده‌های جدول
  void _refreshData() {
    final state = _tableKey.currentState;
    if (state != null) {
      try {
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
            // فیلترها
            _buildFilters(t),

            // جدول داده‌ها
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<DocumentModel>(
                  key: _tableKey,
                  config: _buildTableConfig(t),
                  fromJson: (json) => DocumentModel.fromJson(json),
                  calendarController: widget.calendarController,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ساخت فیلترها
  Widget _buildFilters(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // فیلتر نوع سند
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedDocumentType,
              decoration: const InputDecoration(
                labelText: 'نوع سند',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
              items: _documentTypes.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key == 'all' ? null : entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDocumentType = value;
                });
                _refreshData();
              },
            ),
          ),
          const SizedBox(width: 8),

          // فیلتر از تاریخ
          Expanded(
            child: DateInputField(
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

          // فیلتر تا تاریخ
          Expanded(
            child: DateInputField(
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

          // دکمه پاک کردن فیلترها
          IconButton(
            onPressed: () {
              setState(() {
                _selectedDocumentType = null;
                _fromDate = null;
                _toDate = null;
              });
              _refreshData();
            },
            icon: const Icon(Icons.clear),
            tooltip: 'پاک کردن فیلتر',
          ),
          const Spacer(),

          // دکمه افزودن سند جدید
          ElevatedButton.icon(
            onPressed: _createNewDocument,
            icon: const Icon(Icons.add),
            label: const Text('سند جدید'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// ایجاد سند جدید
  Future<void> _createNewDocument() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DocumentFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        authStore: widget.authStore,
        apiClient: widget.apiClient,
        fiscalYearId: null, // TODO: از context یا state بگیریم
        currencyId: 1, // TODO: از تنظیمات بگیریم
      ),
    );

    if (result == true) {
      _refreshData();
    }
  }

  /// ساخت تنظیمات جدول
  DataTableConfig<DocumentModel> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<DocumentModel>(
      endpoint: '/businesses/${widget.businessId}/documents',
      title: 'اسناد حسابداری',
      excelEndpoint: '/businesses/${widget.businessId}/documents/export/excel',
      customHeaderActions: [
        if (_selectedCount > 0)
          Tooltip(
            message: 'حذف انتخاب‌شده‌ها',
            child: FilledButton.icon(
              onPressed: _handleBulkDelete,
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
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toUtc().toIso8601String(),
      },
      additionalParams: {
        if (_selectedDocumentType != null)
          'document_type': _selectedDocumentType!,
        if (_fromDate != null)
          'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null)
          'to_date': _toDate!.toUtc().toIso8601String(),
      },
      columns: [
        // شماره سند
        TextColumn(
          'code',
          'شماره سند',
          width: ColumnWidth.medium,
          formatter: (item) => item.code,
        ),

        // نوع سند
        CustomColumn(
          'document_type',
          'نوع',
          width: ColumnWidth.medium,
          builder: (item, index) {
            final doc = item as DocumentModel;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getDocumentTypeColor(doc.documentType).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getDocumentTypeColor(doc.documentType),
                  width: 1,
                ),
              ),
              child: Text(
                doc.getDocumentTypeName(),
                style: TextStyle(
                  color: _getDocumentTypeColor(doc.documentType),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),

        // تاریخ سند
        TextColumn(
          'document_date',
          'تاریخ',
          width: ColumnWidth.medium,
          formatter: (item) => item.documentDateRaw ?? '-',
        ),

        // سال مالی
        TextColumn(
          'fiscal_year_title',
          'سال مالی',
          width: ColumnWidth.medium,
          formatter: (item) => item.fiscalYearTitle ?? '-',
        ),

        // بدهکار
        NumberColumn(
          'total_debit',
          'بدهکار',
          width: ColumnWidth.large,
          formatter: (item) => formatWithThousands(item.totalDebit.toInt()),
          suffix: ' ریال',
        ),

        // بستانکار
        NumberColumn(
          'total_credit',
          'بستانکار',
          width: ColumnWidth.large,
          formatter: (item) => formatWithThousands(item.totalCredit.toInt()),
          suffix: ' ریال',
        ),

        // وضعیت
        CustomColumn(
          'is_proforma',
          'وضعیت',
          width: ColumnWidth.small,
          builder: (item, index) {
            final doc = item as DocumentModel;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: doc.isProforma
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                doc.statusText,
                style: TextStyle(
                  color: doc.isProforma ? Colors.orange : Colors.green,
                  fontSize: 11,
                ),
              ),
            );
          },
        ),

        // توضیحات
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (item) => item.description ?? '-',
        ),

        // عملیات
        ActionColumn(
          'actions',
          'عملیات',
          width: ColumnWidth.medium,
          actions: [
            // مشاهده - برای همه اسناد
            DataTableAction(
              icon: Icons.visibility,
              label: 'مشاهده',
              onTap: (item) => _showDocumentDetails(item as DocumentModel),
            ),
            // ویرایش - فقط برای manual
            DataTableAction(
              icon: Icons.edit,
              label: 'ویرایش',
              onTap: (item) => _editDocument(item as DocumentModel),
              enabled: true,
            ),
            // حذف - فقط برای manual
            DataTableAction(
              icon: Icons.delete,
              label: 'حذف',
              onTap: (item) => _deleteDocument(item as DocumentModel),
              isDestructive: true,
            ),
          ],
        ),
      ],
      searchFields: ['code', 'description'],
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
      pdfEndpoint: '/businesses/${widget.businessId}/documents/export/pdf',
      showPdfExport: true,
      businessId: widget.businessId,
      reportModuleKey: 'documents',
      reportSubtype: 'list',
      defaultPageSize: 50,
      pageSizeOptions: [20, 50, 100, 200],
      onRowSelectionChanged: (rows) {
        setState(() {
          _selectedCount = rows.length;
        });
      },
      onRowTap: (item) => _showDocumentDetails(item as DocumentModel),
    );
  }

  /// رنگ بر اساس نوع سند
  Color _getDocumentTypeColor(String type) {
    switch (type) {
      case 'manual':
        return Colors.blue;
      case 'expense':
        return Colors.red;
      case 'income':
        return Colors.green;
      case 'receipt':
        return Colors.teal;
      case 'payment':
        return Colors.orange;
      case 'transfer':
        return Colors.purple;
      case 'invoice':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  /// نمایش جزئیات سند
  Future<void> _showDocumentDetails(DocumentModel doc) async {
    await showDialog(
      context: context,
      builder: (context) => DocumentDetailsDialog(
        documentId: doc.id,
        calendarController: widget.calendarController,
      ),
    );
  }

  /// ویرایش سند
  Future<void> _editDocument(DocumentModel doc) async {
    if (!doc.isEditable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فقط اسناد دستی قابل ویرایش هستند'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // بارگذاری جزئیات کامل سند (با سطرها)
    try {
      final fullDocument = await _service.getDocument(doc.id);
      
      if (!mounted) return;
      
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => DocumentFormDialog(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          authStore: widget.authStore,
          apiClient: widget.apiClient,
          document: fullDocument, // حالت ویرایش
          fiscalYearId: fullDocument.fiscalYearId,
          currencyId: fullDocument.currencyId,
        ),
      );

      if (result == true) {
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در بارگذاری سند: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// حذف سند
  Future<void> _deleteDocument(DocumentModel doc) async {
    if (!doc.isDeletable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فقط اسناد دستی قابل حذف هستند'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('آیا از حذف سند ${doc.code} اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteDocument(doc.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('سند با موفقیت حذف شد')),
          );
          _refreshData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در حذف سند: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// حذف گروهی اسناد
  Future<void> _handleBulkDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید حذف گروهی'),
        content: Text(
            'آیا از حذف $_selectedCount سند انتخاب شده اطمینان دارید؟\n\nتوجه: فقط اسناد دستی حذف خواهند شد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // دریافت آیتم‌های انتخاب شده از جدول
        final state = _tableKey.currentState;
        if (state != null) {
          final selectedRows =
              (state as dynamic).getSelectedRows() as List<DocumentModel>;
          final documentIds = selectedRows.map((doc) => doc.id).toList();

          if (documentIds.isNotEmpty) {
            final result = await _service.bulkDeleteDocuments(documentIds);

            if (mounted) {
              final deletedCount = result['deleted_count'] as int;
              final skipped = result['skipped_auto_documents'] as List;

              String message = '$deletedCount سند با موفقیت حذف شد';
              if (skipped.isNotEmpty) {
                message += '\n${skipped.length} سند اتوماتیک نادیده گرفته شد';
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
              _refreshData();
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در حذف گروهی: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
