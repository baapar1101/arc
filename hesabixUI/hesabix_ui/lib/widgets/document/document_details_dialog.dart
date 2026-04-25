import 'dart:math' show min;
import 'dart:ui' as ui;
import 'dart:ui' show FontFeature;
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
import 'package:hesabix_ui/services/person_service.dart';
import '../../main.dart' show navigatorKey;
import 'package:hesabix_ui/widgets/attached_files/attached_files_widget.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import 'package:hesabix_ui/widgets/warehouse/warehouse_document_details_dialog.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/invoice/bank_account_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/cash_register_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/petty_cash_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/check_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/account_tree_combobox_widget.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/models/account_tree_node.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart'
    show EnglishDigitsFormatter, ThousandsSeparatorInputFormatter, parseJsonDoubleOrNull;
import 'package:flutter/services.dart';
import 'package:hesabix_ui/services/invoice_service.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/widgets/invoice/invoice_print_options_bottom_sheet.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:hesabix_ui/utils/invoice_transaction_preferences.dart';
import 'package:hesabix_ui/models/invoice_transaction.dart' show TransactionType;
import 'package:share_plus/share_plus.dart';

int? _parseInstallmentSeq(dynamic v) {
  if (v == null) return null;
  if (v is bool) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim().replaceAll(',', ''));
  return null;
}

double? _parseInstallmentAmount(dynamic v) {
  if (v == null) return null;
  if (v is bool) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

double _scheduleMoney(dynamic v, [double fallback = 0.0]) {
  return _parseInstallmentAmount(v) ?? fallback;
}

int _scheduleSeq(dynamic v, [int fallback = 0]) {
  return _parseInstallmentSeq(v) ?? fallback;
}

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
  String? _invoicePrintPaperSize;
  String _invoicePrintOrientation = 'landscape';
  bool _invoicePrintShowStamp = true;
  bool _invoicePrintShowShareQr = false;
  /// اگر در تنظیمات چاپ کسب‌وکار برای این نوع سند فعال باشد، سوییچ QR در چاپ نمایش داده می‌شود
  bool _businessPrintAllowsShareQr = false;
  int? _invoicePrintTemplateId;
  Map<String, dynamic>? _invoicePublicShareLink;
  bool _loadingInvoiceShareLink = false;
  bool _revokingInvoiceShareLink = false;
  /// مقدار `hours` برای ایجاد لینک: 168، 336، 720 یا null = پیش‌فرض سرور
  int? _invoiceShareExpiryChoiceHours = 168;
  final TextEditingController _invoiceShareMaxViewsController = TextEditingController();
  
  // تراکنش‌های پرداخت
  final _receiptPaymentService = ReceiptPaymentService(ApiClient());
  List<ReceiptPaymentDocument> _paymentDocuments = [];
  bool _loadingPayments = false;
  
  // سرویس ذخیره‌سازی
  late final BusinessStorageService _storageService;
  bool _uploadingFile = false;
  final AttachedFilesWidgetKey _attachedFilesKey = AttachedFilesWidgetKey();

  final InvoiceService _invoiceService = InvoiceService();
  final PersonService _personService = PersonService();
  /// در صورت موفقیت، جزئیات کامل طرف حساب از API اشخاص (مکمل فیلدهای ناقص سند).
  Person? _counterpartyPerson;
  /// فقط وقتی روی فاکتور `extra_info.installment_plan` وجود دارد.
  bool _showInstallmentsTab = false;
  Map<String, dynamic>? _installmentPlanPayload;
  bool _loadingInstallmentPlan = false;
  String? _installmentPlanError;

  @override
  void initState() {
    super.initState();
    _service = DocumentService(ApiClient());
    _storageService = BusinessStorageService(ApiClient());
    // قبل از بارگذاری سند فقط سه تب پایه نمایش داده می‌شود (هم‌خوان با TabBar حالت loading)
    _tabController = TabController(length: 3, vsync: this);
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
          SnackBarHelper.showSuccess(context, message: 'فایل با موفقیت الصاق شد');
          // رفرش لیست فایل‌ها
          _attachedFilesKey.refresh();
        }
      } on DioException catch (e) {
        if (mounted) {
          await _handleUploadError(e);
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: 'خطا در آپلود فایل: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      } finally {
        if (mounted) {
          setState(() => _uploadingFile = false);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
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

  Future<void> _loadInvoicePrintStampDefault(DocumentModel doc) async {
    try {
      final data = await BusinessApiService.getPrintSettings(doc.businessId);
      final defaultSettings = (data['default'] as Map?)?.cast<String, dynamic>();
      final perType = (data['per_type'] as Map?)?.cast<String, dynamic>();
      Map<String, dynamic>? target = perType?[doc.documentType];
      target ??= defaultSettings;
      if (target == null || !mounted) return;
      final ss = target['show_stamp'];
      if (ss is bool) {
        setState(() => _invoicePrintShowStamp = ss);
      }
      final sqr = target['show_share_qr'];
      if (sqr is bool) {
        setState(() {
          _businessPrintAllowsShareQr = sqr;
          _invoicePrintShowShareQr = sqr;
        });
      } else {
        setState(() {
          _businessPrintAllowsShareQr = false;
          _invoicePrintShowShareQr = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadInvoiceShareLinkInfo(DocumentModel doc) async {
    if (!doc.documentType.startsWith('invoice')) return;
    setState(() => _loadingInvoiceShareLink = true);
    try {
      final link = await _invoiceService.getInvoiceShareLink(
        businessId: doc.businessId,
        invoiceId: doc.id,
      );
      if (!mounted) return;
      setState(() {
        _invoicePublicShareLink = link;
        _loadingInvoiceShareLink = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingInvoiceShareLink = false);
      }
    }
  }

  Future<void> _copyInvoicePublicLink() async {
    final u = _invoicePublicShareLink?['short_url']?.toString();
    if (u == null || u.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: u));
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: 'لینک کپی شد');
  }

  Future<void> _createOrRefreshInvoicePublicLink() async {
    final d = _document;
    if (d == null) return;
    try {
      int? maxV;
      final mv = _invoiceShareMaxViewsController.text.trim();
      if (mv.isNotEmpty) {
        maxV = int.tryParse(mv.replaceAll(',', ''));
      }
      final created = await _invoiceService.createInvoiceShareLink(
        businessId: d.businessId,
        invoiceId: d.id,
        expiresInHours: _invoiceShareExpiryChoiceHours,
        maxViewCount: maxV,
      );
      if (!mounted) return;
      setState(() => _invoicePublicShareLink = created);
      SnackBarHelper.showSuccess(context, message: 'لینک نمایش عمومی فاکتور ایجاد شد');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message: 'خطا در ایجاد لینک: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    }
  }

  Future<void> _revokeInvoicePublicShareLink() async {
    final d = _document;
    if (d == null) return;
    setState(() => _revokingInvoiceShareLink = true);
    try {
      await _invoiceService.revokeInvoiceShareLink(
        businessId: d.businessId,
        invoiceId: d.id,
      );
      if (!mounted) return;
      setState(() {
        _invoicePublicShareLink = null;
        _revokingInvoiceShareLink = false;
      });
      SnackBarHelper.showSuccess(context, message: 'لینک لغو شد');
      await _loadInvoiceShareLinkInfo(d);
    } catch (e) {
      if (mounted) {
        setState(() => _revokingInvoiceShareLink = false);
        SnackBarHelper.showError(
        context,
        message: 'خطا در لغو لینک: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    }
  }

  Future<void> _copyAndShareInvoicePublicLink() async {
    final u = _invoicePublicShareLink?['short_url']?.toString();
    if (u == null || u.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: u));
    await Share.share(u);
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: 'لینک کپی و آمادهٔ اشتراک‌گذاری است');
  }

  Future<void> _onInvoicePrintPdfTapped() async {
    if (_document == null) return;
    final result = await showInvoicePrintOptionsBottomSheet(
      context: context,
      templates: _invoiceTemplates,
      loadingTemplates: _loadingInvoiceTemplates,
      initialPaperSize: _invoicePrintPaperSize,
      initialOrientation: _invoicePrintOrientation,
      initialShowStamp: _invoicePrintShowStamp,
      allowShareQrOption: _businessPrintAllowsShareQr,
      initialShowShareQr: _invoicePrintShowShareQr,
      initialTemplateId: _invoicePrintTemplateId,
    );
    if (result == null || !mounted) return;
    setState(() {
      _invoicePrintPaperSize = result.paperSize;
      _invoicePrintOrientation = result.orientation;
      _invoicePrintShowStamp = result.showStamp;
      _invoicePrintShowShareQr = result.showShareQr;
      _invoicePrintTemplateId = result.templateId;
    });
    await _generatePdf(invoicePrint: result);
  }

  Future<void> _generatePdf({InvoicePrintOptionsResult? invoicePrint}) async {
    if (_document == null) return;
    final doc = _document!;
    final isInvoice = doc.documentType.startsWith('invoice');
    if (isInvoice && invoicePrint == null) {
      return;
    }
    setState(() => _isGeneratingPdf = true);
    try {
      final api = ApiClient();
      String path;
      // اگر فاکتور است، از endpoint اختصاصی فاکتور استفاده کنیم تا قالب invoices/detail اعمال شود
      if (isInvoice) {
        path = '/invoices/business/${doc.businessId}/${doc.id}/pdf';
      } else {
        // سایر اسناد: endpoint عمومی با قالب documents/detail
        path = '/documents/${doc.id}/pdf';
      }
      final query = <String, dynamic>{};
      if (isInvoice) {
        final p = invoicePrint!;
        final ps = p.paperSize;
        if (ps != null && ps.isNotEmpty) {
          query['paper_size'] = ps;
        }
        if (p.orientation.isNotEmpty) {
          query['orientation'] = p.orientation;
        }
        query['show_stamp'] = p.showStamp ? 'true' : 'false';
        query['show_share_qr'] = p.showShareQr ? 'true' : 'false';
        if (p.templateId != null) {
          query['template_id'] = p.templateId;
        }
      }
      final bytes = await api.downloadPdf(path, query: query.isNotEmpty ? query : null);
      await _savePdfFile(bytes, doc.code);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'فایل PDF با موفقیت ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در تولید PDF: ${ErrorExtractor.forContext(e, context)}',
      );
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
      _counterpartyPerson = null;
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
      final isInvoice = doc.documentType.startsWith('invoice');
      Map<String, dynamic>? mergedExtra;
      if (rawData != null && rawData['extra_info'] is Map<String, dynamic>) {
        mergedExtra = rawData['extra_info'] as Map<String, dynamic>;
      } else {
        mergedExtra = doc.extraInfo;
      }
      final hasInstallmentPlan =
          isInvoice && mergedExtra != null && mergedExtra['installment_plan'] is Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _document = doc;
          _rawDocumentData = rawData;
          _isLoading = false;
          _showInstallmentsTab = hasInstallmentPlan;
          if (hasInstallmentPlan) {
            _loadingInstallmentPlan = true;
            _installmentPlanPayload = null;
            _installmentPlanError = null;
          } else {
            _loadingInstallmentPlan = false;
            _installmentPlanPayload = null;
            _installmentPlanError = null;
          }
        });
        final tabCount = isInvoice ? (hasInstallmentPlan ? 7 : 6) : 3;
        if (_tabController.length != tabCount) {
          _tabController.dispose();
          _tabController = TabController(length: tabCount, vsync: this);
        }
      }
      if (hasInstallmentPlan && mounted) {
        await _loadInstallmentPlan(doc);
      }
      // اگر سند از نوع فاکتور باشد، قالب‌های چاپ فاکتور را بارگذاری کن
      try {
        if (doc.documentType.startsWith('invoice')) {
          await _loadInvoiceTemplates(doc.businessId);
          await _loadInvoicePrintStampDefault(doc);
          await _loadInvoiceShareLinkInfo(doc);
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
        await _loadCounterpartyPersonDetails(doc);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorExtractor.forContext(e, context);
          _isLoading = false;
          _showInstallmentsTab = false;
          _loadingInstallmentPlan = false;
          _installmentPlanPayload = null;
          _installmentPlanError = null;
        });
      }
    }
  }

  Future<void> _loadInstallmentPlan(DocumentModel doc) async {
    try {
      final data = await _invoiceService.getInstallmentPlan(
        businessId: doc.businessId,
        invoiceId: doc.id,
      );
      if (!mounted) return;
      setState(() {
        _installmentPlanPayload = data;
        _loadingInstallmentPlan = false;
        _installmentPlanError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInstallmentPlan = false;
        _installmentPlanError = ErrorExtractor.forContext(e, context);
      });
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
    _invoiceShareMaxViewsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context)!;
    final isMobile = ResponsiveHelper.isMobile(context);
    final tabCompact = MediaQuery.sizeOf(context).width < 720;

    return Dialog(
      insetPadding: ResponsiveHelper.getDialogPadding(context),
      clipBehavior: Clip.antiAlias,
      shape: isMobile
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mq = MediaQuery.sizeOf(context);
          final boxConstraints = isMobile
              ? BoxConstraints(
                  maxWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : mq.width,
                  maxHeight: constraints.maxHeight.isFinite ? constraints.maxHeight : mq.height,
                )
              : const BoxConstraints(maxWidth: 1100, maxHeight: 820);
          return ConstrainedBox(
            constraints: boxConstraints,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(theme, dense: isMobile),
                Material(
                  color: theme.colorScheme.surface,
                  child: _buildDocumentTabBar(theme, t, compact: tabCompact),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? _buildError()
                          : TabBarView(
                              controller: _tabController,
                              children: _document != null && _document!.documentType.startsWith('invoice')
                                  ? [
                                      _buildInfoTab(context, theme),
                                      _buildProductsTab(context, theme),
                                      _buildAccountsTab(context, theme),
                                      _buildTransactionsTab(context, theme),
                                      if (_showInstallmentsTab) _buildInstallmentsTab(theme, t),
                                      _buildInvoiceShareTab(context, theme),
                                      _buildAttachmentsTab(context, theme),
                                    ]
                                  : [
                                      _buildInfoTab(context, theme),
                                      _buildAccountsTab(context, theme),
                                      _buildAttachmentsTab(context, theme),
                                    ],
                            ),
                ),
                _buildFooter(dense: isMobile),
              ],
            ),
          );
        },
      ),
    );
  }

  Tab _detailTab({required bool compact, required IconData icon, required String label}) {
    if (compact) {
      return Tab(
        height: 44,
        child: Tooltip(
          message: label,
          child: Icon(icon, size: 22),
        ),
      );
    }
    return Tab(icon: Icon(icon), text: label);
  }

  Widget _buildDocumentTabBar(ThemeData theme, AppLocalizations t, {required bool compact}) {
    final tabs = <Tab>[
      _detailTab(compact: compact, icon: Icons.info_outline, label: 'اطلاعات سند'),
      if (_document != null && _document!.documentType.startsWith('invoice'))
        _detailTab(compact: compact, icon: Icons.shopping_cart, label: 'کالاها'),
      _detailTab(compact: compact, icon: Icons.account_balance, label: 'حساب‌ها'),
      if (_document != null && _document!.documentType.startsWith('invoice'))
        _detailTab(compact: compact, icon: Icons.payment, label: 'تراکنش‌ها'),
      if (_document != null &&
          _document!.documentType.startsWith('invoice') &&
          _showInstallmentsTab)
        _detailTab(
          compact: compact,
          icon: Icons.calendar_view_month,
          label: t.documentDetailsInstallmentsTab,
        ),
      if (_document != null && _document!.documentType.startsWith('invoice'))
        _detailTab(compact: compact, icon: Icons.share, label: 'اشتراک‌گذاری'),
      _detailTab(compact: compact, icon: Icons.attach_file, label: 'فایل‌ها'),
    ];
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelPadding: compact ? const EdgeInsets.symmetric(horizontal: 6) : null,
      tabs: tabs,
    );
  }

  /// فاصلهٔ اطراف محتوای تب‌ها (در موبایل کم‌تر برای استفادهٔ بهتر از عرض/ارتفاع)
  EdgeInsets _documentDetailsTabPadding(BuildContext context) {
    return EdgeInsets.all(ResponsiveHelper.isMobile(context) ? 8 : 20);
  }

  double _documentDetailsSectionGap(BuildContext context) {
    return ResponsiveHelper.isMobile(context) ? 12 : 24;
  }

  double _documentDetailsCardInnerPadding(BuildContext context) {
    return ResponsiveHelper.isMobile(context) ? 12 : 20;
  }

  /// ساخت هدر دیالوگ
  Widget _buildHeader(ThemeData theme, {bool dense = false}) {
    final formatter = NumberFormat('#,##0');
    final isInvoice = _document?.documentType.startsWith('invoice') ?? false;
    final balance = (_document?.totalCredit ?? 0) - (_document?.totalDebit ?? 0);
    final balanceColor = balance > 0
        ? Colors.green
        : balance < 0
            ? Colors.red
            : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 24, vertical: dense ? 8 : 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: dense ? 20 : 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Text(
              (_document?.code ?? '?').isNotEmpty ? (_document?.code ?? '?')[0] : '?',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: dense ? 14 : null,
              ),
            ),
          ),
          SizedBox(width: dense ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _document?.code ?? 'در حال بارگذاری...',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: dense ? 18 : null,
                  ),
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
                    if (_document?.documentDateDisplay != null)
                      _buildHeaderChip(
                        'تاریخ: ${_document!.documentDateDisplay}',
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

  Widget _invoiceShareStatChip(ThemeData theme, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceShareTab(BuildContext context, ThemeData theme) {
    final canEditInvoices = ApiClient.getAuthStore()?.canWriteSection('invoices') ?? false;
    final cardPad = _documentDetailsCardInnerPadding(context);
    final isJalali = widget.calendarController.isJalali;
    if (_loadingInvoiceShareLink) {
      return const Center(child: CircularProgressIndicator());
    }

    final link = _invoicePublicShareLink;
    final active = link != null && link['is_active'] == true;
    final url = link?['short_url']?.toString();
    final status = link?['status']?.toString() ?? '—';
    final fmt = NumberFormat('#,##0', 'fa_IR');
    final viewCount = fmt.format((link?['view_count'] as num?)?.toInt() ?? 0);

    String expiryText = '—';
    final expRaw = link?['expires_at']?.toString();
    if (expRaw != null && expRaw.isNotEmpty) {
      try {
        final dt = DateTime.tryParse(expRaw);
        if (dt != null) {
          expiryText = HesabixDateUtils.formatDateTime(dt, isJalali);
        }
      } catch (_) {
        expiryText = expRaw;
      }
    } else {
      expiryText = 'بدون محدودیت';
    }

    String lastViewText = '—';
    final lv = link?['last_view_at']?.toString();
    if (lv != null && lv.isNotEmpty) {
      try {
        final dt = DateTime.tryParse(lv);
        if (dt != null) {
          lastViewText = HesabixDateUtils.formatDateTime(dt, isJalali);
        }
      } catch (_) {
        lastViewText = lv;
      }
    }

    Color statusColor;
    switch (status) {
      case 'فعال':
        statusColor = Colors.green[700] ?? theme.colorScheme.primary;
        break;
      case 'منقضی':
        statusColor = theme.colorScheme.error;
        break;
      default:
        statusColor = theme.colorScheme.secondary;
    }

    final expiryOptions = <Map<String, dynamic>>[
      {'label': '۷ روز', 'value': 168},
      {'label': '۱۴ روز', 'value': 336},
      {'label': '۳۰ روز', 'value': 720},
      {'label': 'پیش‌فرض سامانه', 'value': null},
    ];

    return SingleChildScrollView(
      padding: _documentDetailsTabPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (link != null && active && url != null && url.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(cardPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('لینک فعال', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            url,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'کپی',
                          onPressed: _copyInvoicePublicLink,
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _invoiceShareStatChip(theme, 'وضعیت', status, statusColor),
                        _invoiceShareStatChip(theme, 'انقضا', expiryText, theme.colorScheme.onSurface),
                        _invoiceShareStatChip(theme, 'بازدید', viewCount, theme.colorScheme.primary),
                        _invoiceShareStatChip(theme, 'آخرین بازدید', lastViewText, theme.colorScheme.onSurface),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _copyAndShareInvoicePublicLink,
                          icon: const Icon(Icons.share),
                          label: const Text('کپی و اشتراک'),
                        ),
                        OutlinedButton.icon(
                          onPressed: canEditInvoices && !_revokingInvoiceShareLink ? _revokeInvoicePublicShareLink : null,
                          icon: _revokingInvoiceShareLink
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.link_off),
                          label: Text(_revokingInvoiceShareLink ? 'در حال لغو…' : 'لغو لینک'),
                        ),
                        TextButton.icon(
                          onPressed: _loadingInvoiceShareLink ? null : () => _document != null ? _loadInvoiceShareLinkInfo(_document!) : null,
                          icon: const Icon(Icons.refresh),
                          label: const Text('بروزرسانی وضعیت'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else if (link != null && !active) ...[
            Card(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: EdgeInsets.all(cardPad),
                child: Text(
                  'لینک قبلی منقضی یا غیرفعال است. می‌توانید لینک جدید بسازید.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: EdgeInsets.all(cardPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ایجاد لینک جدید', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'با این لینک، بدون ورود به حساب، نسخهٔ ثبت‌شدهٔ این فاکتور قابل مشاهده است. در صورت وجود لینک فعال، ابتدا لغو و لینک تازه ایجاد می‌شود.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: _invoiceShareExpiryChoiceHours,
                    decoration: const InputDecoration(
                      labelText: 'مدت اعتبار',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: expiryOptions
                        .map(
                          (e) => DropdownMenuItem<int?>(
                            value: e['value'] as int?,
                            child: Text(e['label'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: canEditInvoices
                        ? (v) => setState(() => _invoiceShareExpiryChoiceHours = v)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _invoiceShareMaxViewsController,
                    decoration: const InputDecoration(
                      labelText: 'حداکثر بازدید (اختیاری)',
                      hintText: 'خالی = نامحدود',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    enabled: canEditInvoices,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: canEditInvoices ? _createOrRefreshInvoicePublicLink : null,
                    icon: const Icon(Icons.add_link),
                    label: Text(link == null ? 'ایجاد لینک' : 'ایجاد لینک جدید'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'آدرس کوتاه مشابه کارت حساب اشخاص است: دامنهٔ شما /i/کد — پس از باز کردن، به صفحهٔ عمومی فاکتور هدایت می‌شوید.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// ساخت تب اطلاعات
  Widget _buildInfoTab(BuildContext context, ThemeData theme) {
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
    final t = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: _documentDetailsTabPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isInvoice && totals != null) ...[
            _buildFinancialSummaryCard(theme, totals),
            SizedBox(height: _documentDetailsSectionGap(context)),
          ],
          // نمایش سود (فقط برای فاکتورهای فروش و تولید)
          if (isInvoice && (document.documentType == 'invoice_sales' || 
              document.documentType == 'invoice_sales_return' || 
              document.documentType == 'invoice_production')) ...[
            _buildProfitSection(theme),
            SizedBox(height: _documentDetailsSectionGap(context)),
          ],
          _buildSectionHeader('مشخصات پایه'),
          _buildInfoGrid([
            _InfoRow('شماره سند', document.code),
            _InfoRow('نوع سند', document.getDocumentTypeName()),
            _InfoRow('تاریخ سند', document.documentDateDisplay ?? '-'),
            _InfoRow('سال مالی', document.fiscalYearTitle ?? '-'),
            _InfoRow('ارز', document.currencyCode ?? '-'),
            _InfoRow('وضعیت', document.statusText),
            _InfoRow('ایجادکننده', document.createdByName ?? '-'),
            if (document.description != null && document.description!.isNotEmpty)
              _InfoRow('توضیحات', document.description!),
          ]),
          if (isInvoice) ...[
            SizedBox(height: _documentDetailsSectionGap(context)),
            _buildCounterpartyInfoCard(theme, document),
          ],
          if (_relatedWhDocs.isNotEmpty) ..._buildRelatedWarehouseDocumentsSection(context, theme, t, document),
        ],
      ),
    );
  }

  /// تاریخ حواله در API به‌صورت میلادی است؛ نمایش مطابق تقویم انتخاب‌شدهٔ کاربر.
  String _formatRelatedWarehouseDocumentDate(dynamic raw) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty) return '-';
    try {
      final d = DateTime.parse(s.split('T').first);
      return HesabixDateUtils.formatForDisplay(d, widget.calendarController.isJalali == true);
    } catch (_) {
      return s;
    }
  }

  /// ترتیب نمایش گروه‌ها در لیست حواله‌های مرتبط (ورود، خروج، …).
  int _warehouseDocTypeSortOrder(String? type) {
    if (type == null || type.isEmpty) return 100;
    const order = ['receipt', 'issue', 'transfer', 'adjustment', 'production_in', 'production_out'];
    final i = order.indexOf(type);
    return i >= 0 ? i : 99;
  }

  String _warehouseDocTypeLabel(String? type, AppLocalizations t) {
    switch (type) {
      case 'receipt':
        return t.docTypeReceipt;
      case 'issue':
        return t.docTypeIssue;
      case 'transfer':
        return t.docTypeTransfer;
      case 'adjustment':
        return t.docTypeAdjustment;
      case 'production_in':
        return t.docTypeProductionIn;
      case 'production_out':
        return t.docTypeProductionOut;
      default:
        return type?.isNotEmpty == true ? type! : '-';
    }
  }

  String _warehouseDocStatusLabel(String? status, AppLocalizations t) {
    switch (status) {
      case 'draft':
        return t.statusDraft;
      case 'posted':
        return t.statusPosted;
      case 'cancelled':
        return t.statusCancelled;
      default:
        return status?.isNotEmpty == true ? status! : '-';
    }
  }

  Color _warehouseDocStatusColor(String? status) {
    switch (status) {
      case 'draft':
        return Colors.orange;
      case 'posted':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _warehouseDocTypeIcon(String? type) {
    switch (type) {
      case 'receipt':
        return Icons.move_to_inbox;
      case 'issue':
        return Icons.outbox;
      case 'transfer':
        return Icons.swap_horiz;
      case 'adjustment':
        return Icons.tune;
      case 'production_in':
      case 'production_out':
        return Icons.precision_manufacturing_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  void _openRelatedWarehouseDocument(BuildContext context, DocumentModel document, int docId) {
    showDialog<void>(
      context: context,
      builder: (_) => WarehouseDocumentDetailsDialog(
        businessId: document.businessId,
        documentId: docId,
      ),
    ).then((_) => _loadDocument());
  }

  List<Widget> _buildRelatedWarehouseDocumentsSection(
    BuildContext context,
    ThemeData theme,
    AppLocalizations t,
    DocumentModel document,
  ) {
    final sorted = List<Map<String, dynamic>>.from(
      _relatedWhDocs.map((e) => Map<String, dynamic>.from(e as Map)),
    );
    sorted.sort((a, b) {
      final ta = a['doc_type'] as String?;
      final tb = b['doc_type'] as String?;
      final c = _warehouseDocTypeSortOrder(ta).compareTo(_warehouseDocTypeSortOrder(tb));
      if (c != 0) return c;
      final da = a['document_date']?.toString() ?? '';
      final db = b['document_date']?.toString() ?? '';
      return da.compareTo(db);
    });
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final it in sorted) {
      final key = (it['doc_type'] as String?) ?? '';
      groups.putIfAbsent(key, () => []).add(it);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => _warehouseDocTypeSortOrder(a.isEmpty ? null : a).compareTo(_warehouseDocTypeSortOrder(b.isEmpty ? null : b)));

    final children = <Widget>[];
    for (var gi = 0; gi < keys.length; gi++) {
      final key = keys[gi];
      final items = groups[key]!;
      final typeForLabel = key.isEmpty ? null : key;
      if (gi > 0) {
        children.add(Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.5)));
      }
      children.add(
        Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(_warehouseDocTypeIcon(typeForLabel), size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _warehouseDocTypeLabel(typeForLabel, t),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${items.length}',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < items.length; i++) {
        if (i > 0) {
          children.add(const Divider(height: 1));
        }
        final it = items[i];
        final status = it['status'] as String?;
        final statusLabel = _warehouseDocStatusLabel(status, t);
        final statusColor = _warehouseDocStatusColor(status);
        final code = it['code']?.toString() ?? '-';
        final docId = it['id'] as int;
        children.add(
          InkWell(
            onTap: () => _openRelatedWarehouseDocument(context, document, docId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(code, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${t.warehouseDocumentDate}: ${_formatRelatedWarehouseDocumentDate(it['document_date'])}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                    child: Chip(
                      label: Text(
                        statusLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Color.alphaBlend(statusColor.withValues(alpha: 0.14), theme.colorScheme.surface),
                      side: BorderSide(color: statusColor.withValues(alpha: 0.35)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (status == 'draft')
                    IconButton(
                      icon: const Icon(Icons.publish),
                      onPressed: () async {
                        try {
                          await _warehouseService.postDoc(
                            businessId: document.businessId,
                            docId: it['id'],
                          );
                          if (!context.mounted) return;
                          SnackBarHelper.show(context, message: t.warehouseDocumentPostSuccess);
                          _loadDocument();
                        } catch (e) {
                          if (!context.mounted) return;
                          SnackBarHelper.show(
                            context,
                            message: t.warehouseDocumentPostFailed(ErrorExtractor.forContext(e, context)),
                          );
                        }
                      },
                      tooltip: t.postWarehouseDocument,
                    ),
                  IconButton(
                    icon: const Icon(Icons.visibility),
                    onPressed: () => _openRelatedWarehouseDocument(context, document, docId),
                    tooltip: t.viewWarehouseDocument,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return [
      const SizedBox(height: 24),
      _buildSectionHeader(t.relatedWarehouseDocuments),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ];
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

  int? _personIdFromDynamic(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  /// شناسهٔ شخص طرف حساب برای لینک کاردکس و بارگذاری جزئیات.
  int? _resolvedCounterpartyPersonId(DocumentModel document) {
    final extra = document.extraInfo;
    if (extra != null) {
      final id = _personIdFromDynamic(extra['person_id']);
      if (id != null) return id;
    }
    final raw = _rawDocumentData;
    if (raw != null) {
      final id = _personIdFromDynamic(raw['person_id']);
      if (id != null) return id;
      final ei = raw['extra_info'];
      if (ei is Map<String, dynamic>) {
        final id2 = _personIdFromDynamic(ei['person_id']);
        if (id2 != null) return id2;
      }
    }
    if (document.lines != null) {
      for (final line in document.lines!) {
        final id = _personIdFromDynamic(line.personId);
        if (id != null) return id;
      }
    }
    final s = _extractCounterpartyInfo(document)['id'];
    if (s != null && s.isNotEmpty) return int.tryParse(s);
    return null;
  }

  Future<void> _loadCounterpartyPersonDetails(DocumentModel doc) async {
    final personId = _resolvedCounterpartyPersonId(doc);
    if (personId == null || personId <= 0) return;
    try {
      final p = await _personService.getPerson(personId);
      if (!mounted) return;
      setState(() => _counterpartyPerson = p);
    } catch (_) {
      /* نمایش با فیلدهای جاسازی‌شده در سند */
    }
  }

  void _openPersonKardex(DocumentModel document) {
    final id = _counterpartyPerson?.id ?? _resolvedCounterpartyPersonId(document);
    if (id == null) return;
    final bid = document.businessId;
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      ctx.go('/business/$bid/reports/kardex', extra: <String, dynamic>{
        'person_ids': [id],
      });
    });
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
    String? personNationalId;
    String? personCompanyName;
    String? personAliasName;
    String? personPhone;
    String? personAddress;
    String? personProvince;
    String? personCity;
    String? personPostalCode;
    String? personEconomicId;
    String? personRegistrationNumber;
    String? personGroupName;

    Map<String, dynamic>? rawExtra(Map<String, dynamic>? root) {
      final ei = root?['extra_info'];
      return ei is Map<String, dynamic> ? ei : null;
    }

    String? pickStr(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    void mergeExtra(Map<String, dynamic>? m) {
      if (m == null) return;
      personNationalId ??= pickStr(m['national_id']) ?? pickStr(m['person_national_id']);
      personCompanyName ??= pickStr(m['company_name']) ?? pickStr(m['person_company_name']);
      personAliasName ??= pickStr(m['alias_name']) ?? pickStr(m['person_alias_name']);
      personPhone ??= pickStr(m['phone']) ?? pickStr(m['person_phone']);
      personAddress ??= pickStr(m['address']) ?? pickStr(m['person_address']);
      personProvince ??= pickStr(m['province']);
      personCity ??= pickStr(m['city']);
      personPostalCode ??= pickStr(m['postal_code']);
      personEconomicId ??= pickStr(m['economic_id']);
      personRegistrationNumber ??= pickStr(m['registration_number']);
      personGroupName ??= pickStr(m['person_group_name']);
    }

    if (extraInfo != null) {
      personId = _personIdFromDynamic(extraInfo['person_id']);
      personName = extraInfo['person_name'] as String?;
      personCode = extraInfo['person_code']?.toString();
      personMobile = extraInfo['person_mobile'] as String?;
      personEmail = extraInfo['person_email'] as String?;
      mergeExtra(extraInfo);
    }

    // اگر از extraInfo پیدا نشد، از خطوط سند بررسی کن
    if (personName == null && document.lines != null) {
      for (final line in document.lines!) {
        if (line.personName != null && line.personName!.isNotEmpty) {
          personName = line.personName;
          personId = _personIdFromDynamic(line.personId);
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
              personId = _personIdFromDynamic(line['person_id']);
              break;
            }
          }
        }
      }
    }

    // اگر هنوز پیدا نشد، از _rawDocumentData مستقیم بررسی کن
    if (personName == null && _rawDocumentData != null) {
      personName = _rawDocumentData!['person_name'] as String?;
      personId = _personIdFromDynamic(_rawDocumentData!['person_id']);
      personCode = _rawDocumentData!['person_code']?.toString();
      personMobile = _rawDocumentData!['person_mobile'] as String?;
      personEmail = _rawDocumentData!['person_email'] as String?;
    }

    if (_rawDocumentData != null) {
      mergeExtra(rawExtra(_rawDocumentData));
    }

    return {
      'name': personName,
      'code': personCode,
      'mobile': personMobile,
      'email': personEmail,
      'id': personId?.toString(),
      'national_id': personNationalId,
      'company_name': personCompanyName,
      'alias_name': personAliasName,
      'phone': personPhone,
      'address': personAddress,
      'province': personProvince,
      'city': personCity,
      'postal_code': personPostalCode,
      'economic_id': personEconomicId,
      'registration_number': personRegistrationNumber,
      'person_group_name': personGroupName,
    };
  }

  List<_InfoRow> _counterpartyDetailRows(Map<String, String?> extracted, Person? loaded) {
    final rows = <_InfoRow>[];
    final p = loaded;
    if (p != null) {
      rows.add(_InfoRow('نام', p.displayName));
      if (p.aliasName.trim().isNotEmpty) {
        rows.add(_InfoRow('نام مستعار', p.aliasName));
      }
      if (p.code != null) {
        rows.add(_InfoRow('کد', '${p.code}'));
      }
      if (p.personGroupName != null && p.personGroupName!.trim().isNotEmpty) {
        rows.add(_InfoRow('گروه اشخاص', p.personGroupName!));
      }
      if (p.personTypes.isNotEmpty) {
        rows.add(_InfoRow('نوع', p.personTypes.map((e) => e.persianName).join('، ')));
      }
      if (p.companyName != null && p.companyName!.trim().isNotEmpty) {
        rows.add(_InfoRow('شرکت', p.companyName!));
      }
      if (p.nationalId != null && p.nationalId!.trim().isNotEmpty) {
        rows.add(_InfoRow('کد ملی / شناسه ملی', p.nationalId!));
      }
      if (p.economicId != null && p.economicId!.trim().isNotEmpty) {
        rows.add(_InfoRow('شماره اقتصادی', p.economicId!));
      }
      if (p.registrationNumber != null && p.registrationNumber!.trim().isNotEmpty) {
        rows.add(_InfoRow('شماره ثبت', p.registrationNumber!));
      }
      if (p.phone != null && p.phone!.trim().isNotEmpty) {
        rows.add(_InfoRow('تلفن', p.phone!));
      }
      if (p.mobile != null && p.mobile!.trim().isNotEmpty) {
        rows.add(_InfoRow('موبایل', p.mobile!));
      }
      if (p.fax != null && p.fax!.trim().isNotEmpty) {
        rows.add(_InfoRow('فکس', p.fax!));
      }
      if (p.email != null && p.email!.trim().isNotEmpty) {
        rows.add(_InfoRow('ایمیل', p.email!));
      }
      final addrParts = <String>[];
      if (p.province != null && p.province!.trim().isNotEmpty) addrParts.add(p.province!);
      if (p.city != null && p.city!.trim().isNotEmpty) addrParts.add(p.city!);
      if (p.address != null && p.address!.trim().isNotEmpty) addrParts.add(p.address!);
      if (p.postalCode != null && p.postalCode!.trim().isNotEmpty) {
        addrParts.add('کدپستی: ${p.postalCode}');
      }
      if (addrParts.isNotEmpty) {
        rows.add(_InfoRow('آدرس', addrParts.join('، ')));
      }
      if (p.balance != null) {
        rows.add(_InfoRow(
          'مانده حساب',
          formatWithThousands(p.balance!, decimalPlaces: (p.balance! % 1 == 0) ? 0 : 2),
        ));
      }
      if (p.status != null && p.status!.trim().isNotEmpty) {
        rows.add(_InfoRow('وضعیت مالی', p.status!));
      }
      return rows;
    }

    final name = extracted['name'];
    if (name != null && name.isNotEmpty) rows.add(_InfoRow('نام', name));
    void add(String label, String? k) {
      final v = extracted[k];
      if (v != null && v.trim().isNotEmpty) rows.add(_InfoRow(label, v));
    }

    add('نام مستعار', 'alias_name');
    add('کد', 'code');
    add('گروه اشخاص', 'person_group_name');
    add('شرکت', 'company_name');
    add('کد ملی / شناسه ملی', 'national_id');
    add('شماره اقتصادی', 'economic_id');
    add('شماره ثبت', 'registration_number');
    add('تلفن', 'phone');
    add('موبایل', 'mobile');
    add('ایمیل', 'email');
    final addrParts = <String>[];
    final prov = extracted['province'];
    final city = extracted['city'];
    final addr = extracted['address'];
    final pc = extracted['postal_code'];
    if (prov != null && prov.trim().isNotEmpty) addrParts.add(prov);
    if (city != null && city.trim().isNotEmpty) addrParts.add(city);
    if (addr != null && addr.trim().isNotEmpty) addrParts.add(addr);
    if (pc != null && pc.trim().isNotEmpty) addrParts.add('کدپستی: $pc');
    if (addrParts.isNotEmpty) rows.add(_InfoRow('آدرس', addrParts.join('، ')));
    return rows;
  }

  /// ساخت کارت اطلاعات طرف حساب
  Widget _buildCounterpartyInfoCard(ThemeData theme, DocumentModel document) {
    final counterpartyInfo = _extractCounterpartyInfo(document);
    final personIdNav = _counterpartyPerson?.id ?? _resolvedCounterpartyPersonId(document);
    final hasName = counterpartyInfo['name'] != null && counterpartyInfo['name']!.trim().isNotEmpty;
    if (!hasName && personIdNav == null) {
      return const SizedBox.shrink();
    }

    // تعیین نوع طرف حساب بر اساس نوع فاکتور
    final isSales = document.documentType.contains('sales');
    final counterpartyType = isSales ? 'مشتری' : 'فروشنده';
    final detailRows = _counterpartyDetailRows(counterpartyInfo, _counterpartyPerson);

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
                Expanded(
                  child: Text(
                    'اطلاعات $counterpartyType',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (personIdNav != null)
                  FilledButton.tonalIcon(
                    onPressed: () => _openPersonKardex(document),
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text('کارت حساب'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoGrid(detailRows),
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

  Widget _buildProfitSection(ThemeData theme) {
    if (_rawDocumentData == null) {
      return const SizedBox.shrink();
    }
    
    // استفاده از total_profit (که می‌تواند gross یا net باشد) یا fallback به gross_profit
    final totalProfit = _rawDocumentData!['total_profit'] as num?;
    final totalProfitPercent = _rawDocumentData!['gross_profit_percent'] as num?;
    final grossProfit = _rawDocumentData!['gross_profit'] as num?;
    final grossProfitPercent = _rawDocumentData!['gross_profit_percent'] as num?;
    final netProfit = _rawDocumentData!['net_profit'] as num?;
    final netProfitPercent = _rawDocumentData!['net_profit_percent'] as num?;
    final totalOverhead = _rawDocumentData!['total_overhead'] as num?;
    
    // اگر سود محاسبه نشده باشد، چیزی نمایش نده
    final profit = totalProfit ?? grossProfit;
    if (profit == null) {
      return const SizedBox.shrink();
    }
    
    final profitValue = profit.toDouble();
    final profitPercentValue = (totalProfitPercent ?? grossProfitPercent)?.toDouble() ?? 0.0;
    final isPositive = profitValue >= 0;
    
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
                  isPositive ? Icons.trending_up : Icons.trending_down,
                  color: isPositive ? Colors.green : Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'سود فاکتور',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isPositive ? Colors.green.shade200 : Colors.red.shade200,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سود ${totalProfit != null && netProfit != null ? 'کل' : grossProfit != null ? 'ناخالص' : 'خالص'}:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (totalOverhead != null && totalOverhead.toDouble() > 0)
                        Text(
                          'هزینه سربار:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatWithThousands(profitValue),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                      if (profitPercentValue != 0)
                        Text(
                          '${profitPercentValue.toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontSize: 14,
                            color: isPositive ? Colors.green.shade600 : Colors.red.shade600,
                          ),
                        ),
                      if (totalOverhead != null && totalOverhead.toDouble() > 0)
                        Text(
                          formatWithThousands(totalOverhead.toDouble()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // نمایش سود ناخالص و خالص (اگر هر دو موجود باشند)
            if (grossProfit != null && netProfit != null && grossProfit != netProfit) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'سود ناخالص',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatWithThousands(grossProfit.toDouble()),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          if (grossProfitPercent != null && grossProfitPercent.toDouble() != 0)
                            Text(
                              '${grossProfitPercent.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'سود خالص',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatWithThousands(netProfit.toDouble()),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade700,
                            ),
                          ),
                          if (netProfitPercent != null && netProfitPercent.toDouble() != 0)
                            Text(
                              '${netProfitPercent.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.purple.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
  Widget _buildProductsTab(BuildContext context, ThemeData theme) {
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
              'هیچ کالایی در این فاکتور ثبت نشده است',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return _buildProductLinesTable(context, theme);
  }

  /// ساخت تب حساب‌ها
  Widget _buildAccountsTab(BuildContext context, ThemeData theme) {
    if (_document == null) {
      return const Center(child: Text('اطلاعاتی برای نمایش وجود ندارد.'));
    }

    return SingleChildScrollView(
      padding: _documentDetailsTabPadding(context),
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

  /// ساخت تب تراکنش‌ها
  Widget _buildTransactionsTab(BuildContext context, ThemeData theme) {
    if (_document == null) {
      return const Center(child: Text('اطلاعاتی برای نمایش وجود ندارد.'));
    }

    // بررسی اینکه آیا می‌توان تراکنش اضافه کرد
    final canAddTransaction = _canAddTransaction();

    return SingleChildScrollView(
      padding: _documentDetailsTabPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // هدر با دکمه افزودن
          Row(
            children: [
              Expanded(
                child: Text(
                  'تراکنش‌های دریافت/پرداخت',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (canAddTransaction)
                ElevatedButton.icon(
                  onPressed: _addTransaction,
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن تراکنش'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          // نمایش خلاصه مالی
          if (_canShowBalanceSummary())
            _buildBalanceSummaryCard(theme),
          
          const SizedBox(height: 16),
          
          // لیست تراکنش‌ها
          if (_loadingPayments)
            _buildPaymentTransactions(theme)
          else if (_paymentDocuments.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'هیچ تراکنش پرداختی ثبت نشده است',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (canAddTransaction) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _addTransaction,
                      icon: const Icon(Icons.add),
                      label: const Text('افزودن اولین تراکنش'),
                    ),
                  ],
                ],
              ),
            )
          else
            _buildPaymentTransactions(theme),
        ],
      ),
    );
  }

  Widget _buildInstallmentsTab(ThemeData theme, AppLocalizations t) {
    if (_loadingInstallmentPlan) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_installmentPlanError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            _installmentPlanError!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      );
    }
    final payload = _installmentPlanPayload;
    if (payload == null) {
      return Center(child: Text(t.installmentsFetchError));
    }
    final planRaw = payload['plan'];
    if (planRaw is! Map<String, dynamic>) {
      return Center(child: Text(t.documentDetailsInstallmentsEmptySchedule));
    }
    final plan = planRaw;
    final scheduleRaw = plan['schedule'];
    final List<dynamic> rows = scheduleRaw is List<dynamic> ? scheduleRaw : const <dynamic>[];
    final currencySuffix = (_document?.currencySymbol ?? _document?.currencyCode ?? '').trim();

    String suffixAmount(String s) {
      if (currencySuffix.isEmpty) return s;
      return '$s $currencySuffix';
    }

    String fmtNum(dynamic v) {
      if (v == null) return '-';
      if (v is bool) return '-';
      final n = v is num ? v.toDouble() : parseJsonDoubleOrNull(v);
      if (n == null) return '-';
      return formatWithThousands(n, decimalPlaces: (n % 1 == 0) ? 0 : 2);
    }

    double? planDouble(Map<String, dynamic> p, String k) {
      return _parseInstallmentAmount(p[k]);
    }

    String fmtDue(dynamic v) {
      if (v == null) return '-';
      if (v is Map<String, dynamic>) {
        final dateOnly = v['date_only'] ?? v['formatted'] ?? v['date_time'];
        if (dateOnly != null) return dateOnly.toString();
        return '-';
      }
      final s = v.toString();
      if (s.isEmpty) return '-';
      try {
        final d = DateTime.parse(s.split('T').first);
        return HesabixDateUtils.formatForDisplay(d, widget.calendarController.isJalali == true);
      } catch (_) {
        return s;
      }
    }

    Color statusColor(String? status) {
      switch (status) {
        case 'paid':
          return theme.colorScheme.primary;
        case 'partial':
          return theme.colorScheme.tertiary;
        case 'overdue':
          return theme.colorScheme.error;
        default:
          return theme.colorScheme.outline;
      }
    }

    IconData statusIcon(String? status) {
      switch (status) {
        case 'paid':
          return Icons.check_circle_outline_rounded;
        case 'partial':
          return Icons.pie_chart_outline_rounded;
        case 'overdue':
          return Icons.warning_amber_rounded;
        default:
          return Icons.schedule_rounded;
      }
    }

    String statusLabel(String? status) {
      switch (status) {
        case 'paid':
          return t.installmentsStatusPaid;
        case 'partial':
          return t.installmentsStatusPartial;
        case 'overdue':
          return t.installmentsStatusOverdue;
        case 'pending':
        default:
          return t.installmentsStatusPending;
      }
    }

    double rowRemaining(Map<String, dynamic> r) {
      final rem = r['remaining'];
      if (rem is num) return rem.toDouble().clamp(0, 1e18);
      final remParsed = _parseInstallmentAmount(rem);
      if (remParsed != null) return remParsed.clamp(0, 1e18);
      final total = _scheduleMoney(r['total']);
      final paid = _scheduleMoney(r['paid_amount']);
      return (total - paid).clamp(0, 1e18);
    }

    double paidSum = 0;
    for (final r in rows) {
      if (r is Map<String, dynamic>) {
        final pd = _parseInstallmentAmount(r['paid_amount']);
        if (pd != null) paidSum += pd;
      }
    }

    final principalT = planDouble(plan, 'principal_total');
    final interestT = planDouble(plan, 'interest_total');
    final remainingT = planDouble(plan, 'remaining_total');
    final down = planDouble(plan, 'down_payment');
    final numInst = plan['num_installments'];

    int firstUnpaidIndex = -1;
    for (var i = 0; i < rows.length; i++) {
      final raw = rows[i];
      if (raw is! Map<String, dynamic>) continue;
      final rr = raw;
      final st = rr['status']?.toString();
      if (st == 'paid') continue;
      if (rowRemaining(rr) > 0.009) {
        firstUnpaidIndex = i;
        break;
      }
    }

    final narrowLayout =
        ResponsiveHelper.isMobile(context) || MediaQuery.sizeOf(context).width < 560;
    final stackDueAndStatus = MediaQuery.sizeOf(context).width < 480;

    Widget summaryTile(String title, String value, double width) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            bottom: narrowLayout ? 6 : 10,
            end: narrowLayout ? 6 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }

    Widget kvLine(String k, String v) {
      if (narrowLayout) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  k,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  v,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(
                k,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    Widget paymentsTableOrCards(List<dynamic> pays) {
      if (narrowLayout) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final raw in pays)
              if (raw is Map) ...[
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: theme.dividerColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t.documentDetailsInstallmentDocCodeColumn,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          () {
                            final pm = Map<String, dynamic>.from(raw);
                            final codeRaw = pm['document_code'];
                            if (codeRaw is String && codeRaw.trim().isNotEmpty) {
                              return codeRaw.trim();
                            }
                            return pm['document_id']?.toString() ?? '-';
                          }(),
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.documentDetailsInstallmentPaymentDateColumn,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmtDue(Map<String, dynamic>.from(raw)['document_date']),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.installmentsTablePaid,
                                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                              ),
                            ),
                            Text(
                              fmtNum(Map<String, dynamic>.from(raw)['amount']),
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
          ],
        );
      }
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
              ),
              children: [
                _tableHeaderCell(theme, t.documentDetailsInstallmentDocCodeColumn),
                _tableHeaderCell(theme, t.documentDetailsInstallmentPaymentDateColumn),
                _tableHeaderCell(theme, t.installmentsTablePaid, alignEnd: true),
              ],
            ),
            ...() {
              final paymentRows = <TableRow>[];
              for (final raw in pays) {
                if (raw is! Map) continue;
                final pm = Map<String, dynamic>.from(raw);
                final codeRaw = pm['document_code'];
                final code = (codeRaw is String && codeRaw.trim().isNotEmpty)
                    ? codeRaw.trim()
                    : (pm['document_id']?.toString() ?? '-');
                paymentRows.add(
                  TableRow(
                    children: [
                      _tableDataCell(
                        theme,
                        Text(code, style: theme.textTheme.bodySmall),
                      ),
                      _tableDataCell(
                        theme,
                        Text(fmtDue(pm['document_date']), style: theme.textTheme.bodySmall),
                      ),
                      _tableDataCell(
                        theme,
                        Text(
                          fmtNum(pm['amount']),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        alignEnd: true,
                      ),
                    ],
                  ),
                );
              }
              return paymentRows;
            }(),
          ],
        ),
      );
    }

    final canReceiveForInstallment =
        _canAddTransaction() && _determineTransactionType() == 'receipt';

    return Padding(
      padding: EdgeInsets.fromLTRB(narrowLayout ? 8 : 12, 8, narrowLayout ? 8 : 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                narrowLayout ? 12 : 16,
                narrowLayout ? 12 : 14,
                narrowLayout ? 12 : 16,
                narrowLayout ? 12 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.installmentsDetailTitle,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (_document?.code != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${t.installmentsTableInvoice}: ${_document!.code}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                  if (currencySuffix.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      t.documentDetailsInstallmentsAmountsNote(currencySuffix),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                  const Divider(height: 20),
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      const spacing = 10.0;
                      final cols = narrowLayout
                          ? (w >= 400 ? 2 : 1)
                          : (w >= 900 ? 4 : (w >= 620 ? 3 : 2));
                      final tileW = (w - spacing * (cols - 1)).clamp(0, double.infinity) / cols;
                      final tiles = <Widget>[
                        if (numInst != null) summaryTile(t.installmentsCount, numInst.toString(), tileW),
                        if (down != null && down > 0) summaryTile(t.downPayment, fmtNum(down), tileW),
                        if (principalT != null) summaryTile(t.installmentsSummaryPrincipal, fmtNum(principalT), tileW),
                        if (interestT != null) summaryTile(t.installmentsSummaryInterest, fmtNum(interestT), tileW),
                        summaryTile(t.installmentsSummaryPaid, fmtNum(paidSum), tileW),
                        if (remainingT != null) summaryTile(t.installmentsSummaryRemaining, fmtNum(remainingT), tileW),
                      ];
                      return Wrap(
                        spacing: spacing,
                        runSpacing: 10,
                        children: tiles,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(t.documentDetailsInstallmentsEmptySchedule))
                : Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final raw = rows[index];
                        final r = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
                        final st = r['status']?.toString();
                        final seq = _scheduleSeq(r['seq']);
                        final remaining = rowRemaining(r);
                        final pays = (r['payments'] as List?) ?? const <dynamic>[];
                        final paidAmt = _scheduleMoney(r['paid_amount']);
                        final installmentPaidEvidence =
                            paidAmt > 0.009 || st == 'partial' || st == 'paid';
                        final overdue = st == 'overdue';
                        final showReceive = canReceiveForInstallment &&
                            st != 'paid' &&
                            remaining > 0.009;

                        return Card(
                          elevation: 0,
                          color: overdue
                              ? theme.colorScheme.errorContainer.withValues(alpha: 0.22)
                              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: overdue
                                  ? theme.colorScheme.error.withValues(alpha: 0.35)
                                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                            ),
                          ),
                          child: ExpansionTile(
                            key: PageStorageKey('inst_row_$seq'),
                            initiallyExpanded: index == firstUnpaidIndex,
                            tilePadding: EdgeInsets.symmetric(
                              horizontal: narrowLayout ? 8 : 12,
                              vertical: 4,
                            ),
                            childrenPadding: EdgeInsets.fromLTRB(
                              narrowLayout ? 12 : 16,
                              0,
                              narrowLayout ? 12 : 16,
                              14,
                            ),
                            leading: CircleAvatar(
                              radius: narrowLayout ? 16 : 18,
                              backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
                              child: Text(
                                '$seq',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontSize: narrowLayout ? 13 : null,
                                ),
                              ),
                            ),
                            title: Builder(
                              builder: (context) {
                                Widget statusChip() {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor(st).withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(statusIcon(st), size: 16, color: statusColor(st)),
                                        const SizedBox(width: 4),
                                        Text(
                                          statusLabel(st),
                                          style: theme.textTheme.labelMedium?.copyWith(
                                            color: statusColor(st),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final dueText = Text(
                                  '${t.installmentsTableDueDate}: ${fmtDue(r['due_date'])}',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: narrowLayout ? 15 : null,
                                  ),
                                );
                                if (stackDueAndStatus) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      dueText,
                                      const SizedBox(height: 8),
                                      statusChip(),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: dueText),
                                    const SizedBox(width: 8),
                                    statusChip(),
                                  ],
                                );
                              },
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  kvLine(t.installmentsTablePrincipal, fmtNum(r['principal'])),
                                  kvLine(t.installmentsTableInterest, fmtNum(r['interest'])),
                                  kvLine(t.installmentsTableTotal, fmtNum(r['total'])),
                                  kvLine(t.installmentsTablePaid, fmtNum(r['paid_amount'])),
                                  kvLine(t.installmentsTableRemaining, fmtNum(remaining)),
                                ],
                              ),
                            ),
                            children: [
                              if (showReceive)
                                narrowLayout
                                    ? SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: () {
                                            _openReceiptDialogForInstallment(
                                              seq: seq,
                                              remainingAmount: remaining,
                                            );
                                          },
                                          icon: const Icon(Icons.add_card_rounded, size: 20),
                                          label: Text(t.documentDetailsInstallmentReceive),
                                        ),
                                      )
                                    : Align(
                                        alignment: AlignmentDirectional.centerStart,
                                        child: FilledButton.icon(
                                          onPressed: () {
                                            _openReceiptDialogForInstallment(
                                              seq: seq,
                                              remainingAmount: remaining,
                                            );
                                          },
                                          icon: const Icon(Icons.add_card_rounded, size: 20),
                                          label: Text(t.documentDetailsInstallmentReceive),
                                        ),
                                      ),
                              if (showReceive) const SizedBox(height: 12),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  t.installmentsPaymentsColumn,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (pays.isEmpty && installmentPaidEvidence)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline_rounded, color: theme.colorScheme.outline, size: 28),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          t.installmentsPaymentsDetailMissing,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (pays.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(Icons.payments_outlined, color: theme.colorScheme.outline, size: 28),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          t.installmentsNoPaymentsYet,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                paymentsTableOrCards(pays),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(ThemeData theme, String text, {bool alignEnd = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _tableDataCell(ThemeData theme, Widget child, {bool alignEnd = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: alignEnd ? Align(alignment: AlignmentDirectional.centerEnd, child: child) : child,
    );
  }

  /// ساخت تب فایل‌ها
  Widget _buildAttachmentsTab(BuildContext context, ThemeData theme) {
    if (_document == null) {
      return const Center(child: Text('برای الصاق فایل نیاز به شناسه معتبر سند است.'));
    }

    return Padding(
      padding: _documentDetailsTabPadding(context),
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
  


  DataColumn _productLineColumnLabel(String label) {
    return DataColumn(
      label: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// ساخت جدول سطرهای محصول (فقط برای فاکتورها)
  Widget _buildProductLinesTable(BuildContext context, ThemeData theme) {
    final productLines = _rawDocumentData?['product_lines'] as List<dynamic>?;
    final isMobile = ResponsiveHelper.isMobile(context);
    final outerPad = _documentDetailsTabPadding(context);
    final titlePad = EdgeInsets.symmetric(
      horizontal: isMobile ? 8 : 16,
      vertical: isMobile ? 8 : 16,
    );
    final tableHMargin = isMobile ? 8.0 : 16.0;
    final tableColSpacing = isMobile ? 12.0 : 24.0;
    
    if (productLines == null || productLines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: outerPad,
      child: Card(
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: titlePad,
              child: Text(
                'لیست کالاها',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            // اسکرول عمودی + افقی: متن کامل نام/توضیح بدون برش؛ در صورت عرض زیاد، اسکرول افقی
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      horizontalMargin: tableHMargin,
                      columnSpacing: tableColSpacing,
                      headingRowColor: WidgetStateProperty.all(
                        theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      ),
                      dataRowMinHeight: 48,
                      dataRowMaxHeight: 200,
                      columns: [
                        _productLineColumnLabel('ردیف'),
                        _productLineColumnLabel('نام کالا'),
                        _productLineColumnLabel('تعداد'),
                        _productLineColumnLabel('واحد'),
                        _productLineColumnLabel('فی'),
                        _productLineColumnLabel('تخفیف'),
                        _productLineColumnLabel('مالیات'),
                        _productLineColumnLabel('قیمت'),
                        if (_rawDocumentData?['line_profits'] != null) _productLineColumnLabel('سود'),
                        _productLineColumnLabel('توضیحات'),
                      ],
                    rows: productLines.asMap().entries.map((entry) {
                      final index = entry.key;
                      final line = entry.value as Map<String, dynamic>;
                      final productName = line['product_name'] as String? ?? '-';
                      final extraInfo = line['extra_info'] as Map<String, dynamic>?;
                      final quantity = (line['quantity'] as num?)?.toDouble() ?? 0.0;
                      final unitPrice = (extraInfo?['unit_price'] as num?)?.toDouble() ?? 0.0;
                      final discount = (extraInfo?['line_discount'] as num?)?.toDouble() ?? 0.0;
                      final tax = (extraInfo?['tax_amount'] as num?)?.toDouble() ?? 0.0;
                      final lineTotal = (extraInfo?['line_total'] as num?)?.toDouble() ?? 0.0;
                      final unit = extraInfo?['unit'] as String? ?? '-';
                      final lineDesc = (line['description'] as String? ?? '-').trim();
                      final descText = lineDesc.isEmpty ? '-' : lineDesc;
                      
                      // دریافت سود این ردیف از line_profits
                      Map<String, dynamic>? lineProfitData;
                      if (_rawDocumentData?['line_profits'] != null) {
                        final lineProfits = _rawDocumentData!['line_profits'] as List<dynamic>;
                        final lineId = line['id'] as int?;
                        if (lineId != null) {
                          lineProfitData = lineProfits.firstWhere(
                            (lp) => (lp as Map<String, dynamic>)['line_id'] == lineId,
                            orElse: () => null,
                          ) as Map<String, dynamic>?;
                        }
                      }
                      
                      // استایل پایه برای اعداد - استفاده از theme و tabular figures
                      final baseNumberStyle = theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ) ?? const TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
                      
                      return DataRow(
                        cells: [
                          DataCell(
                            Center(
                              child: Text(
                                '${index + 1}',
                                textAlign: TextAlign.center,
                                textDirection: ui.TextDirection.ltr,
                                style: baseNumberStyle,
                              ),
                            ),
                          ),
                          DataCell(
                            Center(
                              child: Tooltip(
                                message: productName,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minWidth: 100),
                                  child: Text(
                                    productName,
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        DataCell(
                          Center(
                            child: Text(
                              formatWithThousands(quantity, decimalPlaces: quantity % 1 == 0 ? 0 : 2),
                              textAlign: TextAlign.center,
                              textDirection: ui.TextDirection.ltr,
                              style: baseNumberStyle,
                            ),
                          ),
                        ),
                        DataCell(
                          Center(
                            child: Text(unit, textAlign: TextAlign.center),
                          ),
                        ),
                        DataCell(
                          Center(
                            child: Text(
                              formatWithThousands(unitPrice, decimalPlaces: unitPrice % 1 == 0 ? 0 : 2),
                              textAlign: TextAlign.center,
                              textDirection: ui.TextDirection.ltr,
                              style: baseNumberStyle,
                            ),
                          ),
                        ),
                        DataCell(
                          Center(
                            child: Text(
                              discount > 0 ? formatWithThousands(discount, decimalPlaces: discount % 1 == 0 ? 0 : 2) : '-',
                              textAlign: TextAlign.center,
                              textDirection: ui.TextDirection.ltr,
                              style: baseNumberStyle.copyWith(color: Colors.orange),
                            ),
                          ),
                        ),
                        DataCell(
                          Center(
                            child: Text(
                              tax > 0 ? formatWithThousands(tax, decimalPlaces: tax % 1 == 0 ? 0 : 2) : '-',
                              textAlign: TextAlign.center,
                              textDirection: ui.TextDirection.ltr,
                              style: baseNumberStyle.copyWith(color: Colors.blue),
                            ),
                          ),
                        ),
                        DataCell(
                          Center(
                            child: Text(
                              formatWithThousands(lineTotal, decimalPlaces: lineTotal % 1 == 0 ? 0 : 2),
                              textAlign: TextAlign.center,
                              textDirection: ui.TextDirection.ltr,
                              style: baseNumberStyle.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (_rawDocumentData?['line_profits'] != null)
                          DataCell(
                            Center(
                              child: Builder(
                                builder: (context) {
                                  if (lineProfitData == null) {
                                    return const Text('-', textAlign: TextAlign.center);
                                  }
                                  final profit = (lineProfitData['profit'] ?? lineProfitData['gross_profit']) as num?;
                                  final profitPercent = (lineProfitData['profit_percent'] ?? lineProfitData['gross_profit_percent']) as num?;
                                  if (profit == null) {
                                    return const Text('-', textAlign: TextAlign.center);
                                  }
                                  final profitValue = profit.toDouble();
                                  final profitPercentValue = profitPercent?.toDouble() ?? 0.0;
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        formatWithThousands(profitValue),
                                        textAlign: TextAlign.center,
                                        textDirection: ui.TextDirection.ltr,
                                        style: baseNumberStyle.copyWith(
                                          color: profitValue >= 0 ? Colors.green : Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (profitPercentValue != 0)
                                        Text(
                                          '${profitPercentValue.toStringAsFixed(1)}%',
                                          textAlign: TextAlign.center,
                                          textDirection: ui.TextDirection.ltr,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: profitValue >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          DataCell(
                            Center(
                              child: Tooltip(
                                message: descText,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minWidth: 100),
                                  child: Text(
                                    descText,
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: Colors.red,
                        ) ?? const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: Colors.red,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        credit > 0 ? formatWithThousands(credit.toInt()) : '-',
                        textDirection: ui.TextDirection.ltr,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: Colors.green,
                        ) ?? const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
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
    final theme = Theme.of(context);
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
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ) ?? TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
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
                const Spacer(),
                Text(
                  '${_paymentDocuments.length} تراکنش',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
                const SizedBox(width: 8),
                // دکمه ویرایش
                IconButton(
                  onPressed: () => _editTransaction(doc),
                  icon: const Icon(Icons.edit),
                  tooltip: 'ویرایش',
                  iconSize: 20,
                ),
                // دکمه حذف
                IconButton(
                  onPressed: () => _deleteTransaction(doc),
                  icon: const Icon(Icons.delete),
                  tooltip: 'حذف',
                  iconSize: 20,
                  color: theme.colorScheme.error,
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
    );
  }

  /// ساخت یک ردیف اطلاعات در کارت پرداخت
  Widget _buildPaymentInfoRow(String label, String value, {bool isAmount = false}) {
    final theme = Theme.of(context);
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
            style: isAmount
                ? (theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ) ?? const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ))
                : TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 12,
                  ),
          ),
        ),
      ],
    );
  }

  // ==================== متدهای کمکی تراکنش‌ها ====================
  
  /// تعیین نوع تراکنش بر اساس نوع فاکتور
  String _determineTransactionType() {
    final docType = _document?.documentType ?? '';
    if (docType == 'invoice_sales') return 'receipt';
    if (docType == 'invoice_sales_return') return 'payment';
    if (docType == 'invoice_purchase') return 'payment';
    if (docType == 'invoice_purchase_return') return 'receipt';
    return 'receipt'; // fallback
  }

  /// محاسبه مانده قابل پرداخت
  num _calculateRemainingBalance() {
    final invoiceTotal = (_document?.extraInfo?['totals']?['net'] as num?)?.toDouble() ?? 0;
    final currentTotal = _paymentDocuments.fold<num>(0, (sum, doc) => sum + doc.totalAmount);
    return invoiceTotal - currentTotal;
  }

  /// محاسبه مجموع تراکنش‌های موجود
  num _calculateTotalPaid() {
    return _paymentDocuments.fold<num>(0, (sum, doc) => sum + doc.totalAmount);
  }

  /// بررسی اینکه آیا می‌توان تراکنش اضافه کرد
  bool _canAddTransaction() {
    if (_document == null) return false;
    // فقط برای فاکتورهای قطعی
    if (_document!.isProforma) return false;
    // فقط برای فاکتورهای دارای شخص
    final personId = _document!.extraInfo?['person_id'] as int?;
    if (personId == null) return false;
    // بررسی اینکه نوع فاکتور مجاز است
    final docType = _document!.documentType;
    if (!docType.startsWith('invoice')) return false;
    if (docType == 'invoice_production' || 
        docType == 'invoice_waste' || 
        docType == 'invoice_direct_consumption') {
      return false;
    }
    return true;
  }

  /// بررسی اینکه آیا باید خلاصه مالی نمایش داده شود
  bool _canShowBalanceSummary() {
    if (_document == null) return false;
    final invoiceTotal = (_document!.extraInfo?['totals']?['net'] as num?)?.toDouble() ?? 0;
    return invoiceTotal > 0;
  }

  /// اعتبارسنجی مبلغ تراکنش
  bool _validateTransactionAmount(num amount) {
    final invoiceTotal = (_document?.extraInfo?['totals']?['net'] as num?)?.toDouble() ?? 0;
    final currentTotal = _calculateTotalPaid();
    final maxAllowed = invoiceTotal * 1.1; // 10% tolerance
    return (currentTotal + amount) <= maxAllowed;
  }

  /// ساخت کارت خلاصه مالی
  Widget _buildBalanceSummaryCard(ThemeData theme) {
    final invoiceTotal = (_document?.extraInfo?['totals']?['net'] as num?)?.toDouble() ?? 0;
    final totalPaid = _calculateTotalPaid();
    final remaining = _calculateRemainingBalance();
    final paidPercentage = invoiceTotal > 0 ? (totalPaid / invoiceTotal) * 100 : 0;
    final remainingPercentage = invoiceTotal > 0 ? (remaining / invoiceTotal) * 100 : 0;
    
    final remainingColor = remaining > 0 
        ? theme.colorScheme.error 
        : remaining < 0 
            ? theme.colorScheme.tertiary 
            : theme.colorScheme.primary;

    return Card(
      elevation: 2,
      color: remaining > 0 
          ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
          : remaining < 0
              ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3)
              : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  remaining > 0 
                      ? Icons.warning_amber_rounded
                      : remaining < 0
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                  color: remainingColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'خلاصه مالی',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildBalanceRow(
                    theme,
                    'مبلغ کل فاکتور:',
                    formatWithThousands(invoiceTotal.toInt()),
                    theme.colorScheme.onSurface,
                  ),
                ),
                Expanded(
                  child: _buildBalanceRow(
                    theme,
                    'مجموع تراکنش‌ها:',
                    formatWithThousands(totalPaid.toInt()),
                    theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildBalanceRow(
                    theme,
                    'مانده فاکتور:',
                    formatWithThousands(remaining.toInt()),
                    remainingColor,
                    isBold: true,
                  ),
                ),
                Expanded(
                  child: _buildBalanceRow(
                    theme,
                    'درصد پرداخت شده:',
                    '${paidPercentage.toStringAsFixed(1)}%',
                    theme.colorScheme.onSurface,
                    showCurrency: false,
                  ),
                ),
              ],
            ),
            if (remaining > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.error,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'فاکتور هنوز تسویه نشده است. مانده باقی‌مانده: ${formatWithThousands(remaining.toInt())} ریال',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ساخت یک ردیف در کارت خلاصه مالی
  Widget _buildBalanceRow(
    ThemeData theme,
    String label,
    String value,
    Color valueColor, {
    bool isBold = false,
    bool showCurrency = true,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textDirection: ui.TextDirection.ltr,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: valueColor,
              fontSize: isBold ? 16 : null,
            ),
            textAlign: TextAlign.left,
          ),
        ),
      ],
    );
  }

  /// ایجاد سند دریافت/پرداخت از خروجی دیالوگ تراکنش و به‌روزرسانی لینک فاکتور
  Future<Map<String, dynamic>> _createReceiptPaymentFromFormData(
    Map<String, dynamic> data,
    String documentType,
  ) async {
    final created = await _receiptPaymentService.createReceiptPayment(
      businessId: _document!.businessId,
      documentType: documentType,
      documentDate: data['document_date'] as DateTime,
      currencyId: _document!.currencyId,
      personLines: data['person_lines'] as List<Map<String, dynamic>>,
      accountLines: data['account_lines'] as List<Map<String, dynamic>>,
      description: data['description'] as String?,
      extraInfo: data['extra_info'] as Map<String, dynamic>?,
    );

    final currentLinks = _document!.extraInfo?['links'] as Map<String, dynamic>? ?? {};
    final currentIds = List<int>.from(currentLinks['receipt_payment_document_ids'] as List<dynamic>? ?? []);
    currentIds.add(created['id'] as int);
    await _updateInvoiceLinks(currentIds);

    if (mounted) {
      SnackBarHelper.showSuccess(context, message: 'تراکنش با موفقیت اضافه شد');
    }
    return created;
  }

  /// افزودن تراکنش جدید
  Future<void> _addTransaction() async {
    if (!_canAddTransaction()) return;
    
    final transactionType = _determineTransactionType();
    final personId = _document!.extraInfo?['person_id'] as int?;
    final personName = _document!.extraInfo?['person_name'] as String?;
    
    if (personId == null) {
      SnackBarHelper.showError(context, message: 'فاکتور باید دارای شخص باشد');
      return;
    }

    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ReceiptPaymentTransactionDialog(
        document: _document!,
        transactionType: transactionType,
        personId: personId,
        personName: personName,
        calendarController: widget.calendarController,
        existingDocuments: _paymentDocuments,
        onSave: (data) async {
          try {
            return await _createReceiptPaymentFromFormData(data, transactionType);
          } catch (e) {
            if (mounted) {
              SnackBarHelper.showError(
                context,
                message: 'خطا در افزودن تراکنش: ${ErrorExtractor.forContext(e, context)}',
              );
            }
            rethrow;
          }
        },
      ),
    );
  }

  /// باز کردن دیالوگ دریافت با تخصیص از پیش برای یک قسط (از تب اقساط)
  Future<void> _openReceiptDialogForInstallment({
    required int seq,
    required double remainingAmount,
  }) async {
    if (!_canAddTransaction()) return;
    final t = AppLocalizations.of(context)!;
    final transactionType = _determineTransactionType();
    if (transactionType != 'receipt') {
      SnackBarHelper.showError(context, message: t.documentDetailsInstallmentReceiptTypeOnly);
      return;
    }
    final personId = _document!.extraInfo?['person_id'] as int?;
    final personName = _document!.extraInfo?['person_name'] as String?;
    if (personId == null) {
      SnackBarHelper.showError(context, message: 'فاکتور باید دارای شخص باشد');
      return;
    }
    final code = _document!.code;
    final desc = 'قسط $seq فاکتور $code';

    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ReceiptPaymentTransactionDialog(
        document: _document!,
        transactionType: transactionType,
        personId: personId,
        personName: personName,
        calendarController: widget.calendarController,
        existingDocuments: _paymentDocuments,
        initialInstallmentSeq: seq,
        initialInstallmentAllocationAmount: remainingAmount,
        initialDescription: desc,
        onSave: (data) async {
          try {
            return await _createReceiptPaymentFromFormData(data, transactionType);
          } catch (e) {
            if (mounted) {
              SnackBarHelper.showError(
                context,
                message: 'خطا در افزودن تراکنش: ${ErrorExtractor.forContext(e, context)}',
              );
            }
            rethrow;
          }
        },
      ),
    );
  }

  /// ویرایش تراکنش موجود
  Future<void> _editTransaction(ReceiptPaymentDocument doc) async {
    if (!_canAddTransaction()) return;
    
    final transactionType = doc.documentType;
    final personId = doc.personLines.isNotEmpty ? doc.personLines.first.personId : null;
    final personName = doc.personLines.isNotEmpty ? doc.personLines.first.personName : null;
    
    // باز کردن دیالوگ ویرایش تراکنش
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ReceiptPaymentTransactionDialog(
        document: _document!,
        transactionType: transactionType,
        personId: personId,
        personName: personName,
        calendarController: widget.calendarController,
        existingDocuments: _paymentDocuments,
        existingDocument: doc,
        onSave: (data) async {
          // به‌روزرسانی سند دریافت/پرداخت
          try {
            final updated = await _receiptPaymentService.updateReceiptPayment(
              documentId: doc.id,
              documentDate: data['document_date'] as DateTime,
              currencyId: _document!.currencyId,
              personLines: data['person_lines'] as List<Map<String, dynamic>>,
              accountLines: data['account_lines'] as List<Map<String, dynamic>>,
              description: data['description'] as String?,
              extraInfo: data['extra_info'] as Map<String, dynamic>?,
            );
            
            // رفرش لیست تراکنش‌ها
            // دریافت document به‌روزرسانی شده از سرور
            if (mounted) {
              await _loadDocument();
            }
            
            if (mounted) {
              SnackBarHelper.showSuccess(context, message: 'تراکنش با موفقیت به‌روزرسانی شد');
            }
            
            return updated;
          } catch (e) {
            if (mounted) {
              SnackBarHelper.showError(
                context,
                message: 'خطا در به‌روزرسانی تراکنش: ${ErrorExtractor.forContext(e, context)}',
              );
            }
            rethrow;
          }
        },
      ),
    );
  }

  /// حذف تراکنش
  Future<void> _deleteTransaction(ReceiptPaymentDocument doc) async {
    // تایید حذف
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف تراکنش'),
        content: Text('آیا از حذف تراکنش ${doc.code} اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // حذف سند دریافت/پرداخت
      await _receiptPaymentService.deleteReceiptPayment(doc.id);
      
      // به‌روزرسانی لینک‌های فاکتور
      final currentLinks = _document!.extraInfo?['links'] as Map<String, dynamic>? ?? {};
      final currentIds = List<int>.from(currentLinks['receipt_payment_document_ids'] as List<dynamic>? ?? []);
      currentIds.remove(doc.id);
      currentLinks['receipt_payment_document_ids'] = currentIds;
      
      await _updateInvoiceLinks(currentIds);
      // توجه: _updateInvoiceLinks خودش _loadDocument را فراخوانی می‌کند که _loadPaymentDocuments را هم فراخوانی می‌کند
      
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'تراکنش با موفقیت حذف شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در حذف تراکنش: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  /// به‌روزرسانی لینک‌های فاکتور
  Future<void> _updateInvoiceLinks(List<int> receiptPaymentIds) async {
    if (_document == null) return;
    
    try {
      final api = ApiClient();
      
      // دریافت invoice به‌روزرسانی شده از سرور برای اطمینان از به‌روز بودن extra_info و product_lines
      Map<String, dynamic>? latestExtraInfo;
      Map<String, dynamic>? invoiceItem;
      
      try {
        final invoiceResponse = await api.get('/invoices/business/${_document!.businessId}/${_document!.id}');
        if (invoiceResponse.data['success'] == true) {
          invoiceItem = invoiceResponse.data['data']?['item'] as Map<String, dynamic>?;
          if (invoiceItem != null && invoiceItem['extra_info'] != null) {
            latestExtraInfo = Map<String, dynamic>.from(invoiceItem['extra_info'] as Map<String, dynamic>);
          }
        }
      } catch (e) {
        // اگر خطا رخ داد، از _rawDocumentData استفاده کن
        invoiceItem = _rawDocumentData;
      }
      
      // استفاده از extra_info به‌روزرسانی شده یا فعلی document
      final currentExtraInfo = Map<String, dynamic>.from(latestExtraInfo ?? _document!.extraInfo ?? {});
      final currentLinks = Map<String, dynamic>.from(currentExtraInfo['links'] ?? {});
      currentLinks['receipt_payment_document_ids'] = receiptPaymentIds;
      currentExtraInfo['links'] = currentLinks;
      
      // دریافت product_lines از invoiceItem (که از API یا _rawDocumentData دریافت کردیم)
      List<Map<String, dynamic>> lines = [];
      if (invoiceItem != null) {
        final productLines = invoiceItem['product_lines'] as List<dynamic>?;
        if (productLines != null && productLines.isNotEmpty) {
          lines = productLines.map((line) {
            return {
              'product_id': line['product_id'],
              'quantity': line['quantity'],
              'description': line['description'],
              'extra_info': line['extra_info'] ?? {},
            };
          }).toList();
        }
      }
      
      // اگر هنوز lines خالی است، یک بار دیگر از API دریافت کن
      if (lines.isEmpty) {
        try {
          final invoiceResponse = await api.get('/invoices/business/${_document!.businessId}/${_document!.id}');
          if (invoiceResponse.data['success'] == true) {
            final item = invoiceResponse.data['data']?['item'] as Map<String, dynamic>?;
            if (item != null) {
              final productLines = item['product_lines'] as List<dynamic>?;
              if (productLines != null && productLines.isNotEmpty) {
                lines = productLines.map((line) {
                  return {
                    'product_id': line['product_id'],
                    'quantity': line['quantity'],
                    'description': line['description'],
                    'extra_info': line['extra_info'] ?? {},
                  };
                }).toList();
              }
            }
          }
        } catch (e) {
          // اگر خطا رخ داد، خطا را throw کن
          throw Exception(
            'خطا در دریافت اطلاعات فاکتور: ${ErrorExtractor.userMessage(e)}',
          );
        }
      }
      
      if (lines.isEmpty) {
        throw Exception('خطا: فاکتور باید حداقل یک ردیف داشته باشد');
      }
      
      await api.put(
        '/invoices/business/${_document!.businessId}/${_document!.id}',
        data: {
          'extra_info': currentExtraInfo,
          'lines': lines,
        },
      );
      
      // دریافت document به‌روزرسانی شده از سرور
      if (mounted) {
        await _loadDocument();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در به‌روزرسانی لینک‌های فاکتور: ${ErrorExtractor.forContext(e, context)}',
        );
      }
      rethrow;
    }
  }

  /// ساخت فوتر دیالوگ
  Widget _buildFooter({bool dense = false}) {
    final t = AppLocalizations.of(context)!;
    final showEdit = _document != null &&
        _document!.documentType.startsWith('invoice') &&
        (ApiClient.getAuthStore()?.canWriteSection('invoices') ?? false);

    Widget pdfButton() => OutlinedButton.icon(
          onPressed: _isGeneratingPdf
              ? null
              : () {
                  final d = _document;
                  if (d != null && d.documentType.startsWith('invoice')) {
                    _onInvoicePrintPdfTapped();
                  } else {
                    _generatePdf();
                  }
                },
          icon: _isGeneratingPdf
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf),
          label: Text(_isGeneratingPdf ? t.generating : t.printPdf),
        );

    Widget editButton() => OutlinedButton.icon(
          onPressed: () {
            final doc = _document!;
            final router = GoRouter.of(context);
            Navigator.of(context).pop();
            router.pushNamed(
              'business_edit_invoice',
              pathParameters: {
                'business_id': doc.businessId.toString(),
                'invoice_id': doc.id.toString(),
              },
            );
          },
          icon: const Icon(Icons.edit_outlined),
          label: Text('${t.edit} ${t.invoice}'),
        );

    Widget closeButton() => ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('بستن'),
        );

    final rowChildren = <Widget>[
      pdfButton(),
      if (showEdit) editButton(),
      closeButton(),
    ];

    return Container(
      padding: EdgeInsets.all(dense ? 8 : 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: dense
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    pdfButton(),
                    if (showEdit) editButton(),
                    closeButton(),
                  ],
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < rowChildren.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  rowChildren[i],
                ],
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

/// دیالوگ افزودن/ویرایش تراکنش دریافت/پرداخت
class _ReceiptPaymentTransactionDialog extends StatefulWidget {
  final DocumentModel document;
  final String transactionType; // 'receipt' or 'payment'
  final int? personId;
  final String? personName;
  final CalendarController calendarController;
  final List<ReceiptPaymentDocument> existingDocuments;
  final ReceiptPaymentDocument? existingDocument;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data) onSave;
  /// در حالت تراکنش جدید: پیش‌تخصیص به این شماره قسط
  final int? initialInstallmentSeq;
  /// مبلغ پیش‌فرض تخصیص (معمولاً ماندهٔ همان قسط)
  final double? initialInstallmentAllocationAmount;
  /// توضیح پیش‌فرض (مثلاً «قسط N فاکتور CODE»)
  final String? initialDescription;

  _ReceiptPaymentTransactionDialog({
    required this.document,
    required this.transactionType,
    this.personId,
    this.personName,
    required this.calendarController,
    required this.existingDocuments,
    this.existingDocument,
    required this.onSave,
    this.initialInstallmentSeq,
    this.initialInstallmentAllocationAmount,
    this.initialDescription,
  });

  @override
  State<_ReceiptPaymentTransactionDialog> createState() => _ReceiptPaymentTransactionDialogState();
}

class _ReceiptPaymentTransactionDialogState extends State<_ReceiptPaymentTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _commissionController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  DateTime _transactionDate = DateTime.now();
  String? _selectedTransactionMethod; // 'bank', 'cash_register', 'petty_cash', 'check', 'person', 'account'
  String? _selectedBankId;
  String? _selectedCashRegisterId;
  String? _selectedPettyCashId;
  String? _selectedCheckId;
  String? _selectedCheckNumber;
  AccountTreeNode? _selectedAccount;
  
  // اقساط
  Map<int, double> _installmentAllocations = {}; // seq -> amount
  
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    
    // اگر در حال ویرایش هستیم، مقادیر را از سند موجود پر کنیم
    if (widget.existingDocument != null) {
      final doc = widget.existingDocument!;
      _transactionDate = doc.documentDate;
      _amountController.text = formatWithThousands(doc.totalAmount, decimalPlaces: 0);
      _descriptionController.text = doc.description ?? '';
      
      // تعیین روش پرداخت از account_lines
      if (doc.accountLines.isNotEmpty) {
        final firstLine = doc.accountLines.first;
        _selectedTransactionMethod = firstLine.transactionType;
        if (_selectedTransactionMethod == 'bank') {
          _selectedBankId = firstLine.extraInfo?['bank_id']?.toString();
        } else if (_selectedTransactionMethod == 'cash_register') {
          _selectedCashRegisterId = firstLine.extraInfo?['cash_register_id']?.toString();
        } else if (_selectedTransactionMethod == 'petty_cash') {
          _selectedPettyCashId = firstLine.extraInfo?['petty_cash_id']?.toString();
        } else if (_selectedTransactionMethod == 'check') {
          _selectedCheckId = firstLine.extraInfo?['check_id']?.toString();
          _selectedCheckNumber = firstLine.extraInfo?['check_number']?.toString();
        } else if (_selectedTransactionMethod == 'account') {
          // باید account را از account_id پیدا کنیم
        }
      }
      
      // بارگذاری اقساط از extra_info
      if (doc.extraInfo != null) {
        final settlements = doc.extraInfo!['settlements'] as List<dynamic>?;
        if (settlements != null && settlements.isNotEmpty) {
          final settlement = settlements.first as Map<String, dynamic>;
          final allocations = settlement['allocations'] as List<dynamic>?;
          if (allocations != null) {
            for (final alloc in allocations) {
              if (alloc is! Map) continue;
              final am = Map<String, dynamic>.from(alloc);
              final seq = _parseInstallmentSeq(am['seq']);
              final amount = _parseInstallmentAmount(am['amount']);
              if (seq != null && amount != null && amount > 0) {
                _installmentAllocations[seq] = amount;
              }
            }
          }
        }
      }
    } else {
      _selectedTransactionMethod = TransactionType.bank.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySavedDefaultPaymentMethod();
      });
      final seq = widget.initialInstallmentSeq;
      final alloc = widget.initialInstallmentAllocationAmount;
      if (seq != null && alloc != null && alloc > 0) {
        _installmentAllocations[seq] = alloc;
        _amountController.text = formatWithThousands(alloc, decimalPlaces: (alloc % 1 == 0) ? 0 : 2);
      }
      final presetDesc = widget.initialDescription;
      if (presetDesc != null && presetDesc.trim().isNotEmpty) {
        _descriptionController.text = presetDesc.trim();
      }
    }
  }

  Future<void> _applySavedDefaultPaymentMethod() async {
    if (widget.existingDocument != null || !mounted) return;
    final resolved = await InvoiceTransactionPreferences.resolveInitialTransactionType(
      widget.document.businessId,
      InvoiceTransactionPreferences.receiptPaymentDialogTypes,
    );
    if (widget.existingDocument != null || !mounted) return;
    setState(() => _selectedTransactionMethod = resolved.value);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commissionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existingDocument != null;
    final hasInstallmentPlan = _hasInstallmentPlan();
    final media = MediaQuery.sizeOf(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final maxDialogHeight = min(800.0, media.height * 0.9);
    final headerRadius = isMobile
        ? BorderRadius.zero
        : const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          );

    final shell = Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            // هدر
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: headerRadius,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    color: theme.colorScheme.onPrimary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEdit ? 'ویرایش تراکنش' : 'افزودن تراکنش',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: theme.colorScheme.onPrimary,
                  ),
                ],
              ),
            ),

            // فرم
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // نوع تراکنش (غیرقابل تغییر)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              widget.transactionType == 'receipt' 
                                  ? Icons.arrow_downward 
                                  : Icons.arrow_upward,
                              color: widget.transactionType == 'receipt' 
                                  ? Colors.green 
                                  : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'نوع تراکنش: ${widget.transactionType == 'receipt' ? 'دریافت' : 'پرداخت'}',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // شخص (غیرقابل تغییر)
                      if (widget.personId != null && widget.personName != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person),
                              const SizedBox(width: 8),
                              Text(
                                'شخص: ${widget.personName}',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      
                      // تاریخ تراکنش
                      DateInputField(
                        value: _transactionDate,
                        onChanged: (date) {
                          if (date != null) {
                            setState(() {
                              _transactionDate = date;
                            });
                          }
                        },
                        labelText: 'تاریخ تراکنش *',
                        calendarController: widget.calendarController,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      ),
                      const SizedBox(height: 16),
                      
                      // مبلغ
                      TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                          labelText: 'مبلغ *',
                          border: OutlineInputBorder(),
                          suffixText: 'ریال',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          EnglishDigitsFormatter(),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ThousandsSeparatorInputFormatter(allowDecimal: false),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'مبلغ الزامی است';
                          }
                          final cleanValue = value.replaceAll(',', '');
                          final amount = double.tryParse(cleanValue);
                          if (amount == null || amount <= 0) {
                            return 'مبلغ باید عدد مثبت باشد';
                          }
                          // اعتبارسنجی محدودیت مبلغ
                          if (!_validateAmount(amount)) {
                            return 'مجموع تراکنش‌ها از مبلغ فاکتور بیشتر است';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // روش پرداخت
                      DropdownButtonFormField<String>(
                        key: ValueKey(_selectedTransactionMethod),
                        initialValue: _selectedTransactionMethod,
                        decoration: const InputDecoration(
                          labelText: 'روش پرداخت *',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: 'bank', child: Text('بانک')),
                          const DropdownMenuItem(value: 'cash_register', child: Text('صندوق')),
                          const DropdownMenuItem(value: 'petty_cash', child: Text('تنخواهگردان')),
                          const DropdownMenuItem(value: 'check', child: Text('چک')),
                          const DropdownMenuItem(value: 'person', child: Text('شخص')),
                          const DropdownMenuItem(value: 'account', child: Text('حساب')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedTransactionMethod = value;
                            // پاک کردن انتخاب‌های قبلی
                            _selectedBankId = null;
                            _selectedCashRegisterId = null;
                            _selectedPettyCashId = null;
                            _selectedCheckId = null;
                            _selectedAccount = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // فیلدهای خاص هر روش پرداخت
                      if (_selectedTransactionMethod == 'bank')
                        BankAccountComboboxWidget(
                          businessId: widget.document.businessId,
                          selectedAccountId: _selectedBankId,
                          filterCurrencyId: widget.document.currencyId,
                          onChanged: (opt) {
                            setState(() {
                              _selectedBankId = opt?.id;
                            });
                          },
                          label: 'بانک *',
                          hintText: 'جست‌وجو و انتخاب بانک',
                          isRequired: true,
                        ),
                      if (_selectedTransactionMethod == 'cash_register')
                        CashRegisterComboboxWidget(
                          businessId: widget.document.businessId,
                          selectedRegisterId: _selectedCashRegisterId,
                          filterCurrencyId: widget.document.currencyId,
                          onChanged: (opt) {
                            setState(() {
                              _selectedCashRegisterId = opt?.id;
                            });
                          },
                          label: 'صندوق *',
                          hintText: 'جست‌وجو و انتخاب صندوق',
                          isRequired: true,
                        ),
                      if (_selectedTransactionMethod == 'petty_cash')
                        PettyCashComboboxWidget(
                          businessId: widget.document.businessId,
                          selectedPettyCashId: _selectedPettyCashId,
                          filterCurrencyId: widget.document.currencyId,
                          onChanged: (opt) {
                            setState(() {
                              _selectedPettyCashId = opt?.id;
                            });
                          },
                          label: 'تنخواهگردان *',
                          hintText: 'جست‌وجو و انتخاب تنخواه‌گردان',
                          isRequired: true,
                        ),
                      if (_selectedTransactionMethod == 'check')
                        CheckComboboxWidget(
                          businessId: widget.document.businessId,
                          selectedCheckId: _selectedCheckId,
                          selectedCheckNumber: _selectedCheckNumber,
                          filterCurrencyId: widget.document.currencyId,
                          mode: widget.transactionType == 'receipt' 
                              ? CheckPickerMode.receipt 
                              : CheckPickerMode.payment,
                          onChanged: (opt) {
                            setState(() {
                              _selectedCheckId = opt?.id;
                              _selectedCheckNumber = opt?.number;
                            });
                          },
                          label: 'چک *',
                          hintText: 'جست‌وجو و انتخاب چک',
                          calendarController: widget.calendarController,
                          authStore: null, // اختیاری است
                        ),
                      if (_selectedTransactionMethod == 'account')
                        AccountTreeComboboxWidget(
                          businessId: widget.document.businessId,
                          selectedAccount: _selectedAccount?.toAccount(),
                          onChanged: (account) {
                            setState(() {
                              if (account != null) {
                                _selectedAccount = AccountTreeNode(
                                  id: account.id!,
                                  code: account.code,
                                  name: account.name,
                                  accountType: account.accountType,
                                  parentId: account.parentId,
                                );
                              } else {
                                _selectedAccount = null;
                              }
                            });
                          },
                          label: 'حساب *',
                          hintText: 'انتخاب حساب',
                          isRequired: true,
                        ),
                      
                      if (_selectedTransactionMethod != null) const SizedBox(height: 16),
                      
                      // کارمزد
                      TextFormField(
                        controller: _commissionController,
                        decoration: const InputDecoration(
                          labelText: 'کارمزد',
                          border: OutlineInputBorder(),
                          suffixText: 'ریال',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          EnglishDigitsFormatter(),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ThousandsSeparatorInputFormatter(allowDecimal: false),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // توضیحات
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'توضیحات',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      
                      // بخش اقساط (فقط برای دریافت و اگر فاکتور دارای installment_plan باشد)
                      if (hasInstallmentPlan && widget.transactionType == 'receipt') ...[
                        const SizedBox(height: 24),
                        _buildInstallmentsSection(theme),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // دکمه‌ها
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(isMobile ? 0 : 12),
                  bottomRight: Radius.circular(isMobile ? 0 : 12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveTransaction,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isEdit ? 'ذخیره' : 'افزودن'),
                  ),
                ],
              ),
            ),
          ],
        );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Material(
          color: theme.colorScheme.surface,
          child: SafeArea(child: shell),
        ),
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 700, maxHeight: maxDialogHeight),
        child: shell,
      ),
    );
  }

  /// بررسی اینکه آیا فاکتور دارای طرح اقساط است
  bool _hasInstallmentPlan() {
    final extraInfo = widget.document.extraInfo;
    if (extraInfo == null) return false;
    final plan = extraInfo['installment_plan'] as Map<String, dynamic>?;
    return plan != null && plan['schedule'] != null;
  }

  /// ساخت بخش اقساط
  Widget _buildInstallmentsSection(ThemeData theme) {
    final extraInfo = widget.document.extraInfo;
    final plan = extraInfo?['installment_plan'] as Map<String, dynamic>?;
    final schedule = plan?['schedule'] as List<dynamic>?;
    
    if (schedule == null || schedule.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'تخصیص به اقساط',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...schedule.map((item) {
              if (item is! Map) return const SizedBox.shrink();
              final im = Map<String, dynamic>.from(item);
              final seq = _scheduleSeq(im['seq']);
              final total = _scheduleMoney(im['total']);
              final paid = _scheduleMoney(im['paid_amount']);
              final remaining = total - paid;
              final allocated = _installmentAllocations[seq] ?? 0.0;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('قسط $seq'),
                    ),
                    Expanded(
                      child: Text('مانده: ${formatWithThousands(remaining.toInt())}'),
                    ),
                    Expanded(
                      child: TextFormField(
                        initialValue: allocated > 0 ? formatWithThousands(allocated.toInt()) : '',
                        decoration: InputDecoration(
                          labelText: 'مبلغ تخصیص',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          EnglishDigitsFormatter(),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ThousandsSeparatorInputFormatter(allowDecimal: false),
                        ],
                        onChanged: (value) {
                          final cleanValue = value.replaceAll(',', '');
                          final amount = double.tryParse(cleanValue) ?? 0.0;
                          setState(() {
                            if (amount > 0) {
                              _installmentAllocations[seq] = amount;
                            } else {
                              _installmentAllocations.remove(seq);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  /// اعتبارسنجی مبلغ
  bool _validateAmount(double amount) {
    final invoiceTotal = (widget.document.extraInfo?['totals']?['net'] as num?)?.toDouble() ?? 0;
    final currentTotal = widget.existingDocuments.fold<double>(
      0,
      (sum, doc) => sum + doc.totalAmount,
    );
    // اگر در حال ویرایش هستیم، مبلغ سند فعلی را از مجموع کم می‌کنیم
    final existingAmount = widget.existingDocument?.totalAmount ?? 0;
    final adjustedTotal = currentTotal - existingAmount;
    final maxAllowed = invoiceTotal * 1.1; // 10% tolerance
    return (adjustedTotal + amount) <= maxAllowed;
  }

  /// ذخیره تراکنش
  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    
    // اعتبارسنجی روش پرداخت
    if (_selectedTransactionMethod == null) {
      SnackBarHelper.showError(context, message: 'انتخاب روش پرداخت الزامی است');
      return;
    }
    
    // اعتبارسنجی فیلدهای خاص هر روش
    if (_selectedTransactionMethod == 'bank' && _selectedBankId == null) {
      SnackBarHelper.showError(context, message: 'انتخاب بانک الزامی است');
      return;
    }
    if (_selectedTransactionMethod == 'cash_register' && _selectedCashRegisterId == null) {
      SnackBarHelper.showError(context, message: 'انتخاب صندوق الزامی است');
      return;
    }
    if (_selectedTransactionMethod == 'petty_cash' && _selectedPettyCashId == null) {
      SnackBarHelper.showError(context, message: 'انتخاب تنخواه‌گردان الزامی است');
      return;
    }
    if (_selectedTransactionMethod == 'check' && _selectedCheckId == null) {
      SnackBarHelper.showError(context, message: 'انتخاب چک الزامی است');
      return;
    }
    if (_selectedTransactionMethod == 'account' && _selectedAccount == null) {
      SnackBarHelper.showError(context, message: 'انتخاب حساب الزامی است');
      return;
    }
    
    // اعتبارسنجی اقساط
    if (_hasInstallmentPlan() && widget.transactionType == 'receipt') {
      final totalAllocated = _installmentAllocations.values.fold<double>(0, (sum, amount) => sum + amount);
      final transactionAmount = double.parse(_amountController.text.replaceAll(',', ''));
      if (totalAllocated > transactionAmount) {
        SnackBarHelper.showError(context, message: 'مجموع تخصیص اقساط از مبلغ تراکنش بیشتر است');
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final commission = _commissionController.text.isNotEmpty
          ? double.parse(_commissionController.text.replaceAll(',', ''))
          : null;

      // ساخت person_lines
      final personLines = <Map<String, dynamic>>[];
      if (widget.personId != null) {
        personLines.add({
          'person_id': widget.personId,
          'person_name': widget.personName,
          'amount': amount,
          'description': _descriptionController.text.trim().isEmpty 
              ? null 
              : _descriptionController.text.trim(),
          'extra_info': {
            'invoice_id': widget.document.id,
            'invoice_code': widget.document.code,
            'link_to_invoice': true,
          },
        });
      }

      // ساخت account_lines
      final accountLines = <Map<String, dynamic>>[];
      final accountLine = <String, dynamic>{
        'amount': amount,
        'transaction_type': _selectedTransactionMethod,
        'transaction_date': _transactionDate.toIso8601String(),
        'description': _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
      };
      
      if (commission != null && commission > 0) {
        accountLine['commission'] = commission;
      }
      
      // اضافه کردن فیلدهای خاص هر روش
      if (_selectedTransactionMethod == 'bank' && _selectedBankId != null) {
        accountLine['bank_id'] = _selectedBankId;
      } else if (_selectedTransactionMethod == 'cash_register' && _selectedCashRegisterId != null) {
        accountLine['cash_register_id'] = _selectedCashRegisterId;
      } else if (_selectedTransactionMethod == 'petty_cash' && _selectedPettyCashId != null) {
        accountLine['petty_cash_id'] = _selectedPettyCashId;
      } else if (_selectedTransactionMethod == 'check' && _selectedCheckId != null) {
        accountLine['check_id'] = _selectedCheckId;
        if (_selectedCheckNumber != null) {
          accountLine['check_number'] = _selectedCheckNumber;
        }
      } else if (_selectedTransactionMethod == 'account' && _selectedAccount != null) {
        accountLine['account_id'] = _selectedAccount!.id;
      }
      
      accountLines.add(accountLine);

      // ساخت extra_info برای اقساط
      Map<String, dynamic>? extraInfo;
      if (_hasInstallmentPlan() && 
          widget.transactionType == 'receipt' && 
          _installmentAllocations.isNotEmpty) {
        final allocations = _installmentAllocations.entries
            .where((e) => e.value > 0)
            .map((e) => {
              'seq': e.key,
              'amount': e.value,
            })
            .toList();
        
        if (allocations.isNotEmpty && widget.personId != null) {
          extraInfo = {
            'settlements': [
              {
                'invoice_id': widget.document.id,
                'person_id': widget.personId,
                'allocations': allocations,
              }
            ]
          };
        }
      }

      final data = {
        'document_date': _transactionDate,
        'person_lines': personLines,
        'account_lines': accountLines,
        'description': _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        if (extraInfo != null) 'extra_info': extraInfo,
      };

      await widget.onSave(data);

      final methodType =
          TransactionType.fromValue(_selectedTransactionMethod ?? '') ??
              TransactionType.bank;
      await InvoiceTransactionPreferences.setLastUsedTransactionType(
        widget.document.businessId,
        methodType,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

