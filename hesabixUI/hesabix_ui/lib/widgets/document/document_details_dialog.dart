import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/services/document_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/services/warehouse_service.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/report_template_service.dart';
import 'package:hesabix_ui/services/receipt_payment_service.dart';
import 'package:hesabix_ui/models/receipt_payment_document.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/widgets/attached_files/attached_files_widget.dart';

/// دیالوگ نمایش جزئیات کامل سند حسابداری
class DocumentDetailsDialog extends StatefulWidget {
  final int documentId;
  final CalendarController calendarController;

  const DocumentDetailsDialog({
    super.key,
    required this.documentId,
    required this.calendarController,
  });

  @override
  State<DocumentDetailsDialog> createState() => _DocumentDetailsDialogState();
}

class _DocumentDetailsDialogState extends State<DocumentDetailsDialog> {
  late DocumentService _service;
  DocumentModel? _document;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isGeneratingPdf = false;
  final _warehouseService = WarehouseService();
  List<dynamic> _relatedWhDocs = const [];
  final ReportTemplateService _templateService = ReportTemplateService(ApiClient());
  List<Map<String, dynamic>> _invoiceTemplates = const [];
  bool _loadingInvoiceTemplates = false;
  int? _selectedInvoiceTemplateId;
  
  // تراکنش‌های پرداخت
  final _receiptPaymentService = ReceiptPaymentService(ApiClient());
  List<ReceiptPaymentDocument> _paymentDocuments = [];
  bool _loadingPayments = false;
  
  // سرویس ذخیره‌سازی
  late final BusinessStorageService _storageService;
  bool _uploadingFile = false;
  final AttachedFilesWidgetKey _attachedFilesKey = AttachedFilesWidgetKey();

  @override
  void initState() {
    super.initState();
    _service = DocumentService(ApiClient());
    _storageService = BusinessStorageService(ApiClient());
    _loadDocument();
  }
  
  Future<void> _attachFile() async {
    if (_document == null) return;
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = result.files.first;
      if (file.bytes == null) return;
      
      setState(() => _uploadingFile = true);
      
      try {
        await _storageService.uploadFile(
          businessId: _document!.businessId,
          fileBytes: file.bytes!,
          filename: file.name,
          moduleContext: 'accounting',
          contextId: _document!.id.toString(),
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فایل با موفقیت الصاق شد'),
              backgroundColor: Colors.green,
            ),
          );
          // رفرش لیست فایل‌ها
          _attachedFilesKey.refresh();
        }
      } on DioException catch (e) {
        if (mounted) {
          await _handleUploadError(e);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در آپلود فایل: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _uploadingFile = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _uploadingFile = false);
      }
    }
  }
  
  Future<void> _handleUploadError(DioException e) async {
    final response = e.response;
    if (response != null && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      final error = data['error'];
      
      if (error is Map && error['code'] == 'STORAGE_LIMIT_EXCEEDED') {
        // نمایش دیالوگ با جزئیات خطا
        await _showStorageLimitDialog(Map<String, dynamic>.from(error));
        return;
      }
    }
    
    // خطای عمومی
    String errorMessage = 'خطا در آپلود فایل';
    if (response?.data is Map) {
      final data = response!.data as Map<String, dynamic>;
      if (data.containsKey('message')) {
        errorMessage = data['message'] as String;
      } else if (data.containsKey('error') && data['error'] is Map) {
        final errorMap = data['error'] as Map;
        if (errorMap.containsKey('message')) {
          errorMessage = errorMap['message'] as String;
        }
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  Future<void> _showStorageLimitDialog(Map<String, dynamic> error) async {
    final totalLimit = (error['total_limit_gb'] as num?)?.toDouble() ?? 0.0;
    final currentUsage = (error['current_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final available = (error['available_gb'] as num?)?.toDouble() ?? 0.0;
    final overUsage = (error['over_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final required = (error['required_gb'] as num?)?.toDouble() ?? 0.0;
    
    final theme = Theme.of(context);
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'محدودیت ذخیره‌سازی',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error['message'] as String? ?? 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStorageInfoRow('محدودیت کل:', '${totalLimit.toStringAsFixed(3)} GB', theme),
                    _buildStorageInfoRow('استفاده شده:', '${currentUsage.toStringAsFixed(3)} GB', theme),
                    _buildStorageInfoRow('موجود:', '${available.toStringAsFixed(3)} GB', theme),
                    const Divider(height: 24),
                    _buildStorageInfoRow('حجم مورد نیاز:', '${required.toStringAsFixed(3)} GB', theme, isHighlight: true),
                    _buildStorageInfoRow('حجم اضافی:', '${overUsage.toStringAsFixed(3)} GB', theme, isHighlight: true, isError: true),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'برای آپلود این فایل، لطفاً پلن ذخیره‌سازی خود را ارتقا دهید یا فایل کوچکتری انتخاب کنید.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('متوجه شدم'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.go('/business/${_document!.businessId}/storage-files');
            },
            icon: const Icon(Icons.storage_outlined),
            label: const Text('مدیریت ذخیره‌سازی'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStorageInfoRow(String label, String value, ThemeData theme, {bool isHighlight = false, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              color: isError 
                  ? Colors.red 
                  : isHighlight 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf() async {
    if (_document == null) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final api = ApiClient();
      final doc = _document!;
      String path;
      // اگر فاکتور است، از endpoint اختصاصی فاکتور استفاده کنیم تا قالب invoices/detail اعمال شود
      if (doc.documentType.startsWith('invoice')) {
        path = '/invoices/business/${doc.businessId}/${doc.id}/pdf';
      } else {
        // سایر اسناد: endpoint عمومی با قالب documents/detail
        path = '/documents/${doc.id}/pdf';
      }
      final query = <String, dynamic>{};
      if (doc.documentType.startsWith('invoice') && _selectedInvoiceTemplateId != null) {
        query['template_id'] = _selectedInvoiceTemplateId;
      }
      final bytes = await api.downloadPdf(path, query: query.isNotEmpty ? query : null);
      await _savePdfFile(bytes, doc.code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).pdfSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context).pdfError}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _savePdfFile(List<int> bytes, String filename) async {
    try {
      final name = filename.endsWith('.pdf') ? filename : '$filename.pdf';
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', name)
        ..click();
      html.Url.revokeObjectUrl(url);
      // ignore: avoid_print
    } catch (e) {
      // ignore: avoid_print
    }
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final doc = await _service.getDocument(widget.documentId);
      if (mounted) {
        setState(() {
          _document = doc;
          _isLoading = false;
        });
      }
      // اگر سند از نوع فاکتور باشد، قالب‌های چاپ فاکتور را بارگذاری کن
      try {
        if (doc.documentType.startsWith('invoice')) {
          await _loadInvoiceTemplates(doc.businessId);
        }
      } catch (_) {
        // خطای بارگذاری قالب‌ها نباید نمایش سند را متوقف کند
      }
      // load related warehouse docs
      try {
        final data = await _warehouseService.search(
          businessId: doc.businessId,
          limit: 50,
          filters: {
            'source_type': 'invoice',
            'source_document_id': widget.documentId,
          },
        );
        if (mounted) {
          setState(() {
            _relatedWhDocs = List<dynamic>.from(data['items'] ?? const []);
          });
        }
      } catch (_) {}
      
      // بارگذاری تراکنش‌های پرداخت برای فاکتورها
      if (doc.documentType.startsWith('invoice')) {
        await _loadPaymentDocuments(doc);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadInvoiceTemplates(int businessId) async {
    setState(() {
      _loadingInvoiceTemplates = true;
    });
    try {
      final items = await _templateService.listTemplates(
        businessId: businessId,
        moduleKey: 'invoices',
        subtype: 'detail',
        status: 'published',
      );
      if (!mounted) return;
      setState(() {
        _invoiceTemplates = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _invoiceTemplates = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingInvoiceTemplates = false;
        });
      }
    }
  }

  Future<void> _loadPaymentDocuments(DocumentModel doc) async {
    if (doc.extraInfo == null) return;
    
    final links = doc.extraInfo!['links'] as Map<String, dynamic>?;
    if (links == null) return;
    
    final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
    if (receiptPaymentIds == null || receiptPaymentIds.isEmpty) return;
    
    setState(() {
      _loadingPayments = true;
    });
    
    try {
      final List<ReceiptPaymentDocument> documents = [];
      for (final id in receiptPaymentIds) {
        try {
          final doc = await _receiptPaymentService.getById(id as int);
          if (doc != null) {
            documents.add(doc);
          }
        } catch (e) {
          // اگر خطا رخ داد، ادامه بده
        }
      }
      
      if (mounted) {
        setState(() {
          _paymentDocuments = documents;
          _loadingPayments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPayments = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))
              : _errorMessage != null
                  ? SizedBox(height: 240, child: Center(child: Text(_errorMessage!)))
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // هدر
                          _buildHeader(theme),

                          // محتوای اصلی
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _errorMessage != null
                                    ? _buildError()
                                    : _buildContent(theme),
                          ),

                          // فوتر
                          _buildFooter(),
                          const SizedBox(height: 16),
                          if (_relatedWhDocs.isNotEmpty) ...[
                            Text('حواله‌های مرتبط', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Card(
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _relatedWhDocs.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final it = _relatedWhDocs[index] as Map<String, dynamic>;
                                  return ListTile(
                                    dense: true,
                                    title: Text('${it['code'] ?? '-'} • ${it['doc_type'] ?? ''} • ${it['status'] ?? ''}'),
                                    subtitle: Text(it['document_date'] ?? ''),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.publish),
                                      onPressed: (it['status'] == 'draft') ? () async {
                                        try {
                                          await _warehouseService.postDoc(
                                            businessId: _document!.businessId,
                                            docId: it['id'],
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('حواله پست شد')),
                                          );
                                          _loadDocument();
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('خطا در پست حواله: $e')),
                                          );
                                        }
                                      } : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  /// ساخت هدر دیالوگ
  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description,
            size: 28,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'جزئیات سند ${_document?.code ?? ''}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                if (_document != null)
                  Text(
                    _document!.getDocumentTypeName(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }

  /// ساخت پیام خطا
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'خطا در بارگذاری سند',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'خطای نامشخص',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadDocument,
            icon: const Icon(Icons.refresh),
            label: const Text('تلاش مجدد'),
          ),
        ],
      ),
    );
  }

  /// ساخت محتوای اصلی
  Widget _buildContent(ThemeData theme) {
    if (_document == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // اطلاعات هدر سند
          _buildDocumentHeader(theme),

          const SizedBox(height: 24),

          // جدول سطرهای سند
          _buildLinesTable(theme),

          const SizedBox(height: 16),

          // جمع کل
          _buildTotals(theme),

          // تراکنش‌های پرداخت (فقط برای فاکتورها)
          if (_document != null && _document!.documentType.startsWith('invoice')) ...[
            const SizedBox(height: 24),
            _buildPaymentTransactions(theme),
          ],
          
          // فایل‌های الصاق شده
          const SizedBox(height: 24),
          _buildAttachedFiles(theme),
        ],
      ),
    );
  }
  
  /// ساخت بخش فایل‌های الصاق شده
  Widget _buildAttachedFiles(ThemeData theme) {
    if (_document == null) return const SizedBox.shrink();
    
    return AttachedFilesWidget(
      refreshKey: _attachedFilesKey,
      businessId: _document!.businessId,
      moduleContext: 'accounting',
      contextId: _document!.id.toString(),
      title: 'فایل‌های الصاق شده',
      autoLoad: true,
      allowDelete: false, // در دیالوگ مشاهده، حذف مجاز نیست
      onFilesLoaded: (files) {
        // می‌توانید عملیات اضافی انجام دهید
      },
    );
  }

  /// ساخت اطلاعات هدر سند
  Widget _buildDocumentHeader(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات سند',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            _buildInfoRow('شماره سند:', _document!.code),
            _buildInfoRow('نوع سند:', _document!.getDocumentTypeName()),
            _buildInfoRow('تاریخ سند:', _document!.documentDateRaw ?? '-'),
            _buildInfoRow('سال مالی:', _document!.fiscalYearTitle ?? '-'),
            _buildInfoRow('ارز:', _document!.currencyCode ?? '-'),
            _buildInfoRow('وضعیت:', _document!.statusText),
            _buildInfoRow('ایجادکننده:', _document!.createdByName ?? '-'),
            if (_document!.description != null && _document!.description!.isNotEmpty)
              _buildInfoRow('توضیحات:', _document!.description!),
          ],
        ),
      ),
    );
  }

  /// ساخت یک ردیف اطلاعات
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// ساخت جدول سطرهای سند
  Widget _buildLinesTable(ThemeData theme) {
    final lines = _document!.lines ?? [];

    if (lines.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'هیچ سطری برای این سند ثبت نشده است',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'سطرهای سند',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child:             DataTable(
              headingRowColor: WidgetStateProperty.all(
                theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              ),
              columns: const [
                DataColumn(label: Text('ردیف', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('حساب', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('طرف‌حساب', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('بدهکار', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('بستانکار', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('توضیحات', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: lines.asMap().entries.map((entry) {
                final index = entry.key;
                final line = entry.value;
                return DataRow(
                  cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          line.fullAccountName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 150,
                        child: Text(
                          line.counterpartyName ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        line.debit > 0 ? formatWithThousands(line.debit.toInt()) : '-',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.red,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    DataCell(
                      Text(
                        line.credit > 0 ? formatWithThousands(line.credit.toInt()) : '-',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.green,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          line.description ?? '-',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// ساخت بخش جمع کل
  Widget _buildTotals(ThemeData theme) {
    return Card(
      elevation: 2,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildTotalItem(
              'جمع بدهکار',
              formatWithThousands(_document!.totalDebit.toInt()),
              Colors.red,
            ),
            Container(
              width: 2,
              height: 40,
              color: theme.dividerColor,
            ),
            _buildTotalItem(
              'جمع بستانکار',
              formatWithThousands(_document!.totalCredit.toInt()),
              Colors.green,
            ),
            Container(
              width: 2,
              height: 40,
              color: theme.dividerColor,
            ),
            _buildTotalItem(
              'تعداد سطرها',
              '${_document!.linesCount}',
              theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  /// ساخت یک آیتم از جمع کل
  Widget _buildTotalItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
            fontFamily: 'monospace',
          ),
          textDirection: TextDirection.ltr,
        ),
      ],
    );
  }

  /// ساخت بخش تراکنش‌های پرداخت
  Widget _buildPaymentTransactions(ThemeData theme) {
    if (_loadingPayments) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'در حال بارگذاری تراکنش‌های پرداخت...',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_paymentDocuments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.payment,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'تراکنش‌های پرداخت',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: _paymentDocuments.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final paymentDoc = _paymentDocuments[index];
              return _buildPaymentCard(theme, paymentDoc);
            },
          ),
        ],
      ),
    );
  }

  /// ساخت کارت یک تراکنش پرداخت
  Widget _buildPaymentCard(ThemeData theme, ReceiptPaymentDocument doc) {
    final isReceipt = doc.documentType == 'receipt';
    final totalAmount = doc.totalAmount;
    
    // جمع‌آوری اطلاعات تراکنش‌ها از account_lines
    final transactionMethods = <String>[];
    for (final line in doc.accountLines) {
      if (line.transactionType != null) {
        String methodName;
        switch (line.transactionType) {
          case 'bank':
            methodName = 'بانک';
            if (line.extraInfo?['bank_name'] != null) {
              methodName += ' (${line.extraInfo!['bank_name']})';
            }
            break;
          case 'cash_register':
            methodName = 'صندوق';
            if (line.extraInfo?['cash_register_name'] != null) {
              methodName += ' (${line.extraInfo!['cash_register_name']})';
            }
            break;
          case 'petty_cash':
            methodName = 'تنخواهگردان';
            if (line.extraInfo?['petty_cash_name'] != null) {
              methodName += ' (${line.extraInfo!['petty_cash_name']})';
            }
            break;
          case 'check':
            methodName = 'چک';
            if (line.extraInfo?['check_number'] != null) {
              methodName += ' (${line.extraInfo!['check_number']})';
            }
            break;
          case 'person':
            methodName = 'شخص';
            break;
          case 'account':
            methodName = line.accountName;
            break;
          default:
            methodName = line.transactionType ?? 'نامشخص';
        }
        if (!transactionMethods.contains(methodName)) {
          transactionMethods.add(methodName);
        }
      }
    }

    return Card(
      elevation: 1,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () {
          // می‌توانید دیالوگ مشاهده جزئیات سند دریافت/پرداخت را باز کنید
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isReceipt ? Icons.arrow_downward : Icons.arrow_upward,
                    color: isReceipt ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      doc.code,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isReceipt 
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isReceipt ? 'دریافت' : 'پرداخت',
                      style: TextStyle(
                        color: isReceipt ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildPaymentInfoRow(
                      'تاریخ:',
                      HesabixDateUtils.formatForDisplay(
                        doc.documentDate,
                        widget.calendarController.isJalali == true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _buildPaymentInfoRow(
                      'مبلغ:',
                      formatWithThousands(totalAmount.toInt()),
                      isAmount: true,
                    ),
                  ),
                ],
              ),
              if (transactionMethods.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildPaymentInfoRow(
                  'روش پرداخت:',
                  transactionMethods.join('، '),
                ),
              ],
              if (doc.description != null && doc.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildPaymentInfoRow(
                  'توضیحات:',
                  doc.description!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// ساخت یک ردیف اطلاعات در کارت پرداخت
  Widget _buildPaymentInfoRow(String label, String value, {bool isAmount = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: isAmount ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
              fontFamily: isAmount ? 'monospace' : null,
            ),
            textDirection: isAmount ? TextDirection.ltr : null,
          ),
        ),
      ],
    );
  }

  /// ساخت فوتر دیالوگ
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // دکمه الصاق فایل
          OutlinedButton.icon(
            onPressed: _uploadingFile ? null : _attachFile,
            icon: _uploadingFile
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: Text(_uploadingFile ? 'در حال آپلود...' : 'الصاق فایل'),
          ),
          const SizedBox(width: 12),
          // دکمه چاپ PDF
          OutlinedButton.icon(
            onPressed: _isGeneratingPdf ? null : _generatePdf,
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            label: Text(_isGeneratingPdf ? AppLocalizations.of(context).generating : AppLocalizations.of(context).printPdf),
          ),
          const SizedBox(width: 12),
          if (_document != null &&
              _document!.documentType.startsWith('invoice') &&
              !_loadingInvoiceTemplates &&
              _invoiceTemplates.isNotEmpty) ...[
            DropdownButton<int?>(
              value: _selectedInvoiceTemplateId,
              hint: Text(AppLocalizations.of(context).printTemplatePublished),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(AppLocalizations.of(context).noCustomTemplate),
                ),
                ..._invoiceTemplates.map((tpl) {
                  final id = (tpl['id'] as num).toInt();
                  final name = (tpl['name'] ?? 'Template').toString();
                  final isDefault = tpl['is_default'] == true;
                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Row(
                      children: [
                        if (isDefault) const Icon(Icons.star, size: 16),
                        if (isDefault) const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedInvoiceTemplateId = value;
                });
              },
            ),
            const SizedBox(width: 12),
          ],
          // دکمه بستن
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }
}

