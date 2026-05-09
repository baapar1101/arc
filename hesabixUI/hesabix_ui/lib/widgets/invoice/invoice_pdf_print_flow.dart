import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/services/report_template_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;

import 'invoice_print_options_bottom_sheet.dart';

/// دادهٔ اولیه برای برگهٔ چاپ PDF (هم‌سو با بارگذاری در دیالوگ جزئیات فاکتور).
class InvoicePdfPrintPreflight {
  final List<Map<String, dynamic>> templates;
  final bool initialShowStamp;
  final bool allowShareQr;
  final bool initialShowShareQr;

  const InvoicePdfPrintPreflight({
    required this.templates,
    required this.initialShowStamp,
    required this.allowShareQr,
    required this.initialShowShareQr,
  });

  static Future<InvoicePdfPrintPreflight> load({
    required int businessId,
    required String documentType,
  }) async {
    final templateService = ReportTemplateService(ApiClient());
    List<Map<String, dynamic>> templates = [];
    try {
      templates = await templateService.listTemplates(
        businessId: businessId,
        moduleKey: 'invoices',
        subtype: 'detail',
        status: 'published',
      );
    } catch (_) {
      templates = const [];
    }

    var initialShowStamp = true;
    var allowShareQr = false;
    var initialShowShareQr = false;
    try {
      final data = await BusinessApiService.getPrintSettings(businessId);
      final defaultSettings = (data['default'] as Map?)?.cast<String, dynamic>();
      final perType = (data['per_type'] as Map?)?.cast<String, dynamic>();
      Map<String, dynamic>? target = perType?[documentType];
      target ??= defaultSettings;
      if (target != null) {
        final ss = target['show_stamp'];
        if (ss is bool) initialShowStamp = ss;
        final sqr = target['show_share_qr'];
        if (sqr is bool) {
          allowShareQr = sqr;
          initialShowShareQr = sqr;
        }
      }
    } catch (_) {}

    return InvoicePdfPrintPreflight(
      templates: templates,
      initialShowStamp: initialShowStamp,
      allowShareQr: allowShareQr,
      initialShowShareQr: initialShowShareQr,
    );
  }
}

/// جریان مشترک چاپ/دانلود PDF فاکتور (لیست، دیالوگ جزئیات، …).
class InvoicePdfPrintFlow {
  InvoicePdfPrintFlow._();

  static Future<void> savePdfBytesWeb(List<int> bytes, String filename) async {
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

  static Future<void> downloadWithPrintOptions({
    required BuildContext context,
    required int businessId,
    required int invoiceId,
    required String invoiceCode,
    required InvoicePrintOptionsResult invoicePrint,
  }) async {
    if (!context.mounted) return;
    try {
      final api = ApiClient();
      final path = '/invoices/business/$businessId/$invoiceId/pdf';
      final query = <String, dynamic>{};
      final ps = invoicePrint.paperSize;
      if (ps != null && ps.isNotEmpty) query['paper_size'] = ps;
      if (invoicePrint.orientation.isNotEmpty) query['orientation'] = invoicePrint.orientation;
      query['show_stamp'] = invoicePrint.showStamp ? 'true' : 'false';
      query['show_share_qr'] = invoicePrint.showShareQr ? 'true' : 'false';
      final tid = invoicePrint.templateId;
      if (tid != null) query['template_id'] = tid;

      final bytes = await api.downloadPdf(path, query: query.isNotEmpty ? query : null);
      await savePdfBytesWeb(bytes, invoiceCode);
      if (!context.mounted) return;
      SnackBarHelper.showSuccess(context, message: 'فایل PDF با موفقیت ذخیره شد');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در تولید PDF: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  /// همان رفتار دکمهٔ چاپ در دیالوگ جزئیات: برگهٔ گزینه‌ها و سپس دانلود.
  static Future<void> showPrintOptionsSheetAndDownload({
    required BuildContext context,
    required int businessId,
    required int invoiceId,
    required String invoiceCode,
    required String documentType,
    String? initialPaperSize,
    String initialOrientation = 'landscape',
    bool? initialShowStamp,
    bool? allowShareQrOption,
    bool? initialShowShareQr,
    int? initialTemplateId,
  }) async {
    if (!context.mounted) return;
    final preflight = await InvoicePdfPrintPreflight.load(
      businessId: businessId,
      documentType: documentType,
    );
    if (!context.mounted) return;
    final result = await showInvoicePrintOptionsBottomSheet(
      context: context,
      templates: preflight.templates,
      loadingTemplates: false,
      initialPaperSize: initialPaperSize,
      initialOrientation: initialOrientation,
      initialShowStamp: initialShowStamp ?? preflight.initialShowStamp,
      allowShareQrOption: allowShareQrOption ?? preflight.allowShareQr,
      initialShowShareQr: initialShowShareQr ?? preflight.initialShowShareQr,
      initialTemplateId: initialTemplateId,
    );
    if (result == null || !context.mounted) return;
    await downloadWithPrintOptions(
      context: context,
      businessId: businessId,
      invoiceId: invoiceId,
      invoiceCode: invoiceCode,
      invoicePrint: result,
    );
  }
}
