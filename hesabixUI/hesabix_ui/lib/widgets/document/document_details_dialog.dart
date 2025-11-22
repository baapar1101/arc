import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/services/document_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/services/warehouse_service.dart';
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
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import 'package:hesabix_ui/widgets/warehouse/warehouse_document_details_dialog.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

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

class _DocumentDetailsDialogState extends State<DocumentDetailsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DocumentService _service;
  DocumentModel? _document;
  Map<String, dynamic>? _rawDocumentData; // داده‌های خام برای دسترسی به product_lines و account_lines
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
    // تعداد تب‌ها: اطلاعات، محصولات (فقط برای فاکتور)، حساب‌ها، فایل‌ها
    _tabController = TabController(length: 4, vsync: this);
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
    
    SnackBarHelper.showError(context, message: errorMessage);
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
      SnackBarHelper.showSuccess(context, message: 'فایل PDF با موفقیت ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در تولید PDF: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _savePdfFile(List<int> bytes, String filename) async {
    if (kIsWeb) {
      final name = filename.endsWith('.pdf') ? filename : '$filename.pdf';
      await web_utils.saveBytesAsFileWeb(
        bytes,
        name,
        mimeType: 'application/pdf',
      );
    } else {
      throw UnsupportedError('دانلود فایل فقط در نسخه وب پشتیبانی می‌شود');
    }
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final doc = await _service.getDocument(widget.documentId);
      // دریافت داده‌های خام برای دسترسی به product_lines و account_lines
      final api = ApiClient();
      Map<String, dynamic>? rawData;
      
      // برای فاکتورها از endpoint مخصوص فاکتور استفاده کن که product_lines را برمی‌گرداند
      if (doc.documentType.startsWith('invoice')) {
        try {
          final invoiceResponse = await api.get('/invoices/business/${doc.businessId}/${widget.documentId}');
          if (invoiceResponse.data['success'] == true) {
            final item = invoiceResponse.data['data']?['item'] as Map<String, dynamic>?;
            if (item != null) {
              rawData = item;
            }
          }
        } catch (e) {
          // اگر خطا رخ داد، از endpoint عمومی استفاده کن
          final rawResponse = await api.get('/documents/${widget.documentId}');
          if (rawResponse.data['success'] == true) {
            rawData = rawResponse.data['data'] as Map<String, dynamic>?;
          }
        }
      } else {
        // برای سایر اسناد از endpoint عمومی استفاده کن
        final rawResponse = await api.get('/documents/${widget.documentId}');
        if (rawResponse.data['success'] == true) {
          rawData = rawResponse.data['data'] as Map<String, dynamic>?;
        }
      }
      if (mounted) {
        setState(() {
          _document = doc;
          _rawDocumentData = rawData;
          _isLoading = false;
        });
        // تنظیم مجدد TabController بر اساس نوع سند
        final isInvoice = doc.documentType.startsWith('invoice');
        final tabCount = isInvoice ? 4 : 3; // اگر فاکتور است 4 تب، وگرنه 3 تب
        if (_tabController.length != tabCount) {
          _tabController.dispose();
          _tabController = TabController(length: tabCount, vsync: this);
        }
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 820),
        child: Column(
          children: [
            _buildHeader(theme),
            Material(
              color: theme.colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  const Tab(icon: Icon(Icons.info_outline), text: 'اطلاعات سند'),
                  if (_document != null && _document!.documentType.startsWith('invoice'))
                    const Tab(icon: Icon(Icons.shopping_cart), text: 'محصولات'),
                  const Tab(icon: Icon(Icons.account_balance), text: 'حساب‌ها'),
                  const Tab(icon: Icon(Icons.attach_file), text: 'فایل‌ها'),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _buildError()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildInfoTab(theme),
                            if (_document != null && _document!.documentType.startsWith('invoice'))
                              _buildProductsTab(theme)
                            else
                              _buildAccountsTab(theme),
                            if (_document != null && _document!.documentType.startsWith('invoice'))
                              _buildAccountsTab(theme)
                            else
                              _buildAttachmentsTab(theme),
                            _buildAttachmentsTab(theme),
                          ],
                        ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// ساخت هدر دیالوگ
  Widget _buildHeader(ThemeData theme) {
    final formatter = NumberFormat('#,##0');
    final isInvoice = _document?.documentType.startsWith('invoice') ?? false;
    final balance = (_document?.totalCredit ?? 0) - (_document?.totalDebit ?? 0);
    final balanceColor = balance > 0
        ? Colors.green
        : balance < 0
            ? Colors.red
            : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Text(
              (_document?.code ?? '?').isNotEmpty ? (_document?.code ?? '?')[0] : '?',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _document?.code ?? 'در حال بارگذاری...',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (_document != null)
                      _buildHeaderChip(
                        _document!.getDocumentTypeName(),
                        theme,
                      ),
                    if (_document?.documentDateRaw != null)
                      _buildHeaderChip(
                        'تاریخ: ${_document!.documentDateRaw}',
                        theme,
                        icon: Icons.calendar_today,
                      ),
                    if (isInvoice && _document != null)
                      _buildHeaderChip(
                        'مبلغ: ${formatter.format((_document!.extraInfo?['totals']?['net'] as num?)?.toDouble() ?? 0)}',
                        theme,
                        icon: Icons.attach_money,
                        iconColor: balanceColor,
                      ),
                    if (_document?.statusText != null)
                      _buildHeaderChip(
                        'وضعیت: ${_document!.statusText}',
                        theme,
                        icon: Icons.circle,
                        iconColor: balanceColor,
                      ),
                    if (_isLoading)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 6),
                          Text('در حال بروزرسانی...'),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(String text, ThemeData theme, {IconData? icon, Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor ?? theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: theme.textTheme.bodySmall,
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

  /// ساخت تب اطلاعات
  Widget _buildInfoTab(ThemeData theme) {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadDocument, child: const Text('تلاش مجدد')),
          ],
        ),
      );
    }

    final document = _document;
    if (document == null) {
      return const Center(child: Text('اطلاعاتی برای نمایش وجود ندارد.'));
    }

    final isInvoice = document.documentType.startsWith('invoice');
    final totals = document.extraInfo?['totals'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isInvoice && totals != null) ...[
            _buildFinancialSummaryCard(theme, totals),
            const SizedBox(height: 24),
          ],
          _buildSectionHeader('مشخصات پایه'),
          _buildInfoGrid([
            _InfoRow('شماره سند', document.code),
            _InfoRow('نوع سند', document.getDocumentTypeName()),
            _InfoRow('تاریخ سند', document.documentDateRaw ?? '-'),
            _InfoRow('سال مالی', document.fiscalYearTitle ?? '-'),
            _InfoRow('ارز', document.currencyCode ?? '-'),
            _InfoRow('وضعیت', document.statusText),
            _InfoRow('ایجادکننده', document.createdByName ?? '-'),
            if (document.description != null && document.description!.isNotEmpty)
              _InfoRow('توضیحات', document.description!),
          ]),
          if (isInvoice) ...[
            const SizedBox(height: 24),
            _buildCounterpartyInfoCard(theme, document),
          ],
          if (isInvoice) ...[
            const SizedBox(height: 24),
            _buildPaymentTransactions(theme),
          ],
          if (_relatedWhDocs.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('حواله‌های مرتبط'),
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
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => WarehouseDocumentDetailsDialog(
                          businessId: document.businessId,
                          documentId: it['id'] as int,
                        ),
                      ).then((_) => _loadDocument());
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (it['status'] == 'draft')
                          IconButton(
                            icon: const Icon(Icons.publish),
                            onPressed: () async {
                              try {
                                await _warehouseService.postDoc(
                                  businessId: document.businessId,
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
                            },
                            tooltip: 'پست',
                          ),
                        IconButton(
                          icon: const Icon(Icons.visibility),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => WarehouseDocumentDetailsDialog(
                                businessId: document.businessId,
                                documentId: it['id'] as int,
                              ),
                            ).then((_) => _loadDocument());
                          },
                          tooltip: 'جزئیات',
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    );
  }

  /// استخراج اطلاعات طرف حساب از سند
  Map<String, String?> _extractCounterpartyInfo(DocumentModel document) {
    // ابتدا از extraInfo بررسی کن
    final extraInfo = document.extraInfo;
    String? personName;
    String? personCode;
    String? personMobile;
    String? personEmail;
    int? personId;

    if (extraInfo != null) {
      personId = extraInfo['person_id'] as int?;
      personName = extraInfo['person_name'] as String?;
      personCode = extraInfo['person_code'] as String?;
      personMobile = extraInfo['person_mobile'] as String?;
      personEmail = extraInfo['person_email'] as String?;
    }

    // اگر از extraInfo پیدا نشد، از خطوط سند بررسی کن
    if (personName == null && document.lines != null) {
      for (final line in document.lines!) {
        if (line.personName != null && line.personName!.isNotEmpty) {
          personName = line.personName;
          personId = line.personId;
          break;
        }
      }
    }

    // اگر از خطوط سند هم پیدا نشد، از _rawDocumentData بررسی کن
    if (personName == null && _rawDocumentData != null) {
      final accountLines = _rawDocumentData!['account_lines'] as List<dynamic>?;
      if (accountLines != null) {
        for (final line in accountLines) {
          if (line is Map<String, dynamic>) {
            final pName = line['person_name'] as String?;
            if (pName != null && pName.isNotEmpty) {
              personName = pName;
              personId = line['person_id'] as int?;
              break;
            }
          }
        }
      }
    }

    // اگر هنوز پیدا نشد، از _rawDocumentData مستقیم بررسی کن
    if (personName == null && _rawDocumentData != null) {
      personName = _rawDocumentData!['person_name'] as String?;
      personId = _rawDocumentData!['person_id'] as int?;
      personCode = _rawDocumentData!['person_code'] as String?;
      personMobile = _rawDocumentData!['person_mobile'] as String?;
      personEmail = _rawDocumentData!['person_email'] as String?;
    }

    return {
      'name': personName,
      'code': personCode,
      'mobile': personMobile,
      'email': personEmail,
      'id': personId?.toString(),
    };
  }

  /// ساخت کارت اطلاعات طرف حساب
  Widget _buildCounterpartyInfoCard(ThemeData theme, DocumentModel document) {
    final counterpartyInfo = _extractCounterpartyInfo(document);
    final personName = counterpartyInfo['name'];
    
    // اگر اطلاعات طرف حساب وجود نداشت، چیزی نمایش نده
    if (personName == null || personName.isEmpty) {
      return const SizedBox.shrink();
    }

    // تعیین نوع طرف حساب بر اساس نوع فاکتور
    final isSales = document.documentType.contains('sales');
    final counterpartyType = isSales ? 'مشتری' : 'فروشنده';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'اطلاعات $counterpartyType',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoGrid([
              _InfoRow('نام', personName),
              if (counterpartyInfo['code'] != null && counterpartyInfo['code']!.isNotEmpty)
                _InfoRow('کد', counterpartyInfo['code']!),
              if (counterpartyInfo['mobile'] != null && counterpartyInfo['mobile']!.isNotEmpty)
                _InfoRow('موبایل', counterpartyInfo['mobile']!),
              if (counterpartyInfo['email'] != null && counterpartyInfo['email']!.isNotEmpty)
                _InfoRow('ایمیل', counterpartyInfo['email']!),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoGrid(List<_InfoRow> rows) {
    final visibleRows = rows.where((row) => row.value != null && row.value!.trim().isNotEmpty && row.value != '-').toList();
    if (visibleRows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: visibleRows.map((row) => _InfoTile(row: row)).toList(),
    );
  }

  Widget _buildFinancialSummaryCard(ThemeData theme, Map<String, dynamic> totals) {
    final formatter = NumberFormat('#,##0');
    final gross = (totals['gross'] as num?)?.toDouble() ?? 0.0;
    final discount = (totals['discount'] as num?)?.toDouble() ?? 0.0;
    final tax = (totals['tax'] as num?)?.toDouble() ?? 0.0;
    final net = (totals['net'] as num?)?.toDouble() ?? 0.0;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خلاصه مالی فاکتور',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSummaryStat(
                  theme,
                  label: 'جمع کل',
                  value: gross,
                  color: theme.colorScheme.primary,
                  icon: Icons.receipt_long,
                  formatter: formatter,
                ),
                _buildSummaryStat(
                  theme,
                  label: 'تخفیف',
                  value: discount,
                  color: Colors.orange,
                  icon: Icons.discount,
                  formatter: formatter,
                ),
                _buildSummaryStat(
                  theme,
                  label: 'مالیات',
                  value: tax,
                  color: Colors.blue,
                  icon: Icons.account_balance,
                  formatter: formatter,
                ),
                _buildSummaryStat(
                  theme,
                  label: 'خالص',
                  value: net,
                  color: Colors.green[700],
                  icon: Icons.account_balance_wallet,
                  formatter: formatter,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(
    ThemeData theme, {
    required String label,
    required double value,
    required Color? color,
    required IconData icon,
    required NumberFormat formatter,
  }) {
    final display = formatter.format(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? theme.colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(
                display,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color ?? theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ساخت تب محصولات
  Widget _buildProductsTab(ThemeData theme) {
    if (_document == null || _rawDocumentData == null) {
      return const Center(child: Text('اطلاعاتی برای نمایش وجود ندارد.'));
    }

    final productLines = _rawDocumentData?['product_lines'] as List<dynamic>?;
    
    if (productLines == null || productLines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'هیچ محصولی در این فاکتور ثبت نشده است',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductLinesTable(theme),
        ],
      ),
    );
  }

  /// ساخت تب حساب‌ها
  Widget _buildAccountsTab(ThemeData theme) {
    if (_document == null) {
      return const Center(child: Text('اطلاعاتی برای نمایش وجود ندارد.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLinesTable(theme),
          const SizedBox(height: 16),
          _buildTotals(theme),
        ],
      ),
    );
  }

  /// ساخت تب فایل‌ها
  Widget _buildAttachmentsTab(ThemeData theme) {
    if (_document == null) {
      return const Center(child: Text('برای الصاق فایل نیاز به شناسه معتبر سند است.'));
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AttachedFilesWidget(
              refreshKey: _attachedFilesKey,
              businessId: _document!.businessId,
              moduleContext: 'accounting',
              contextId: _document!.id.toString(),
              title: 'فایل‌های الصاق شده',
              autoLoad: true,
              allowDelete: false,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _uploadingFile ? null : _attachFile,
            icon: _uploadingFile
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: Text(_uploadingFile ? 'در حال آپلود...' : 'افزودن فایل'),
          ),
        ],
      ),
    );
  }
  


  /// ساخت جدول سطرهای محصول (فقط برای فاکتورها)
  Widget _buildProductLinesTable(ThemeData theme) {
    final productLines = _rawDocumentData?['product_lines'] as List<dynamic>?;
    
    if (productLines == null || productLines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'سطرهای محصول',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              ),
              columns: const [
                DataColumn(label: Text('ردیف', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('محصول', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('تعداد', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('واحد', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('قیمت واحد', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('تخفیف', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('مالیات', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('جمع', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('توضیحات', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: productLines.asMap().entries.map((entry) {
                final index = entry.key;
                final line = entry.value as Map<String, dynamic>;
                final extraInfo = line['extra_info'] as Map<String, dynamic>?;
                final quantity = (line['quantity'] as num?)?.toDouble() ?? 0.0;
                final unitPrice = (extraInfo?['unit_price'] as num?)?.toDouble() ?? 0.0;
                final discount = (extraInfo?['line_discount'] as num?)?.toDouble() ?? 0.0;
                final tax = (extraInfo?['tax_amount'] as num?)?.toDouble() ?? 0.0;
                final lineTotal = (extraInfo?['line_total'] as num?)?.toDouble() ?? 0.0;
                final unit = extraInfo?['unit'] as String? ?? '-';
                
                return DataRow(
                  cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          line['product_name'] as String? ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatWithThousands(quantity.toInt()),
                        textDirection: ui.TextDirection.ltr,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    DataCell(Text(unit)),
                    DataCell(
                      Text(
                        formatWithThousands(unitPrice.toInt()),
                        textDirection: ui.TextDirection.ltr,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    DataCell(
                      Text(
                        discount > 0 ? formatWithThousands(discount.toInt()) : '-',
                        textDirection: ui.TextDirection.ltr,
                        style: const TextStyle(fontFamily: 'monospace', color: Colors.orange),
                      ),
                    ),
                    DataCell(
                      Text(
                        tax > 0 ? formatWithThousands(tax.toInt()) : '-',
                        textDirection: ui.TextDirection.ltr,
                        style: const TextStyle(fontFamily: 'monospace', color: Colors.blue),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatWithThousands(lineTotal.toInt()),
                        textDirection: ui.TextDirection.ltr,
                        style: const TextStyle(fontFamily: 'monospace', color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          line['description'] as String? ?? '-',
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

  /// ساخت جدول سطرهای سند
  Widget _buildLinesTable(ThemeData theme) {
    // استفاده از account_lines از داده‌های خام اگر lines خالی است
    List<dynamic> lines = _document!.lines ?? [];
    if (lines.isEmpty && _rawDocumentData != null) {
      final accountLines = _rawDocumentData!['account_lines'] as List<dynamic>?;
      if (accountLines != null) {
        lines = accountLines;
      }
    }

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
                
                // پشتیبانی از هر دو نوع DocumentLineModel و Map
                String accountName;
                String? counterpartyName;
                double debit;
                double credit;
                String? description;
                
                if (line is DocumentLineModel) {
                  accountName = line.fullAccountName;
                  counterpartyName = line.counterpartyName;
                  debit = line.debit;
                  credit = line.credit;
                  description = line.description;
                } else if (line is Map<String, dynamic>) {
                  accountName = '${line['account_code'] ?? ''} - ${line['account_name'] ?? '-'}';
                  counterpartyName = line['person_name'] as String?;
                  debit = (line['debit'] as num?)?.toDouble() ?? 0.0;
                  credit = (line['credit'] as num?)?.toDouble() ?? 0.0;
                  description = line['description'] as String?;
                } else {
                  accountName = '-';
                  counterpartyName = null;
                  debit = 0.0;
                  credit = 0.0;
                  description = null;
                }
                
                return DataRow(
                  cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          accountName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 150,
                        child: Text(
                          counterpartyName ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        debit > 0 ? formatWithThousands(debit.toInt()) : '-',
                        textDirection: ui.TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.red,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        credit > 0 ? formatWithThousands(credit.toInt()) : '-',
                        textDirection: ui.TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.green,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          description ?? '-',
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
    final isInvoice = _document?.documentType.startsWith('invoice') ?? false;
    final totals = _document?.extraInfo?['totals'] as Map<String, dynamic>?;
    
    if (isInvoice && totals != null) {
      // برای فاکتورها: نمایش خلاصه مالی کامل
      final gross = (totals['gross'] as num?)?.toDouble() ?? 0.0;
      final discount = (totals['discount'] as num?)?.toDouble() ?? 0.0;
      final tax = (totals['tax'] as num?)?.toDouble() ?? 0.0;
      final net = (totals['net'] as num?)?.toDouble() ?? 0.0;
      
      return Card(
        elevation: 2,
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // خلاصه مالی فاکتور
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTotalItem('جمع کل (قبل از تخفیف)', formatWithThousands(gross.toInt()), theme.colorScheme.primary),
                  Container(width: 2, height: 40, color: theme.dividerColor),
                  _buildTotalItem('تخفیف', formatWithThousands(discount.toInt()), Colors.orange),
                  Container(width: 2, height: 40, color: theme.dividerColor),
                  _buildTotalItem('مالیات', formatWithThousands(tax.toInt()), Colors.blue),
                  Container(width: 2, height: 40, color: theme.dividerColor),
                  _buildTotalItem('خالص', formatWithThousands(net.toInt()), Colors.green),
                ],
              ),
              const Divider(height: 24),
              // جمع بدهکار و بستانکار
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTotalItem('جمع بدهکار', formatWithThousands(_document!.totalDebit.toInt()), Colors.red),
                  Container(width: 2, height: 40, color: theme.dividerColor),
                  _buildTotalItem('جمع بستانکار', formatWithThousands(_document!.totalCredit.toInt()), Colors.green),
                  Container(width: 2, height: 40, color: theme.dividerColor),
                  _buildTotalItem('تعداد سطرها', '${_document!.linesCount}', theme.colorScheme.secondary),
                ],
              ),
            ],
          ),
        ),
      );
    }
    
    // برای سایر اسناد: نمایش ساده
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
          textDirection: ui.TextDirection.ltr,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
            fontFamily: 'monospace',
          ),
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
            textDirection: isAmount ? ui.TextDirection.ltr : null,
            style: TextStyle(
              fontWeight: isAmount ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
              fontFamily: isAmount ? 'monospace' : null,
            ),
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

class _InfoRow {
  final String label;
  final String? value;

  const _InfoRow(this.label, this.value);
}

class _InfoTile extends StatelessWidget {
  final _InfoRow row;

  const _InfoTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = (row.value == null || row.value!.trim().isEmpty) ? '-' : row.value!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(row.label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(
            displayValue,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

