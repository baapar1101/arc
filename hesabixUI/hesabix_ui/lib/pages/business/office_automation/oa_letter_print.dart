import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/api_client.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../services/business_storage_service.dart';
import '../../../services/office_automation_service.dart';

Future<void> oaPrintLetter({
  required int businessId,
  required int letterId,
  int? positionId,
  required CalendarController calendar,
}) async {
  final svc = OfficeAutomationService();
  final storage = BusinessStorageService(ApiClient());
  final data = await svc.getLetterPrint(
    businessId: businessId,
    letterId: letterId,
    positionId: positionId,
  );
  final print = Map<String, dynamic>.from(data['print'] as Map? ?? const {});
  final font = await PdfGoogleFonts.notoNaskhArabicRegular();
  final fontBold = await PdfGoogleFonts.notoNaskhArabicBold();
  pw.ImageProvider? letterhead;
  pw.ImageProvider? background;
  final headId = (print['letterhead_file_id'] ?? '').toString();
  final bgId = (print['background_file_id'] ?? '').toString();
  if (headId.isNotEmpty) {
    final bytes = await storage.downloadFile(businessId: businessId, fileId: headId);
    if (bytes.isNotEmpty) letterhead = pw.MemoryImage(Uint8List.fromList(bytes));
  }
  if (bgId.isNotEmpty) {
    final bytes = await storage.downloadFile(businessId: businessId, fileId: bgId);
    if (bytes.isNotEmpty) background = pw.MemoryImage(Uint8List.fromList(bytes));
  }
  final pageFormat = _pageFormat(
    (print['paper_size'] ?? 'a4').toString(),
    (print['paper_orientation'] ?? 'portrait').toString(),
  );
  final margin = pw.EdgeInsets.fromLTRB(
    _mm(print['margin_left']),
    _mm(print['margin_top']),
    _mm(print['margin_right']),
    _mm(print['margin_bottom']),
  );
  final letterDate = HesabixDateUtils.formatApiDateForDisplay(
    data['letter_date'],
    calendar.isJalali,
    rawValue: data['letter_date_raw'],
    fallback: '',
  );
  final paraphs = List<Map>.from(data['paraphs'] as List? ?? const []);
  final copies = List.from(print['copies'] as List? ?? const []);
  final signatures = List<Map>.from(print['signatures'] as List? ?? const []);
  final signatureImages = <pw.ImageProvider?>[];
  for (final sig in signatures) {
    final fileId = (sig['image_file_id'] ?? '').toString();
    if (fileId.isEmpty) {
      signatureImages.add(null);
      continue;
    }
    final bytes = await storage.downloadFile(businessId: businessId, fileId: fileId);
    signatureImages.add(bytes.isNotEmpty ? pw.MemoryImage(Uint8List.fromList(bytes)) : null);
  }
  final body = _plainBody((data['body'] ?? '').toString(), (data['body_format'] ?? print['body_format'] ?? 'markdown').toString());
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: margin,
      textDirection: pw.TextDirection.rtl,
      build: (_) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Stack(
          children: [
            if (background != null)
              pw.Positioned.fill(
                child: pw.Opacity(opacity: 0.12, child: pw.Image(background, fit: pw.BoxFit.cover)),
              ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (letterhead != null) pw.Center(child: pw.Image(letterhead, height: 56)),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${data['secretariat_number'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 11)),
                    if (letterDate.isNotEmpty) pw.Text(letterDate, style: pw.TextStyle(font: font, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 10),
                if ((data['receiver_name'] ?? '').toString().isNotEmpty)
                  pw.Text(
                    '${data['receiver_name']} ${data['receiver_org'] ?? ''}',
                    style: pw.TextStyle(font: font, fontSize: 11),
                  ),
                if ((data['sender_name'] ?? '').toString().isNotEmpty)
                  pw.Text(
                    '${data['sender_name']} ${data['sender_org'] ?? ''}',
                    style: pw.TextStyle(font: font, fontSize: 11),
                  ),
                pw.SizedBox(height: 12),
                pw.Text('${data['subject'] ?? ''}', style: pw.TextStyle(font: fontBold, fontSize: 14)),
                pw.SizedBox(height: 10),
                pw.Text(body, style: pw.TextStyle(font: font, fontSize: 11, lineSpacing: 4)),
                pw.SizedBox(height: 16),
                for (final p in paraphs)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(
                      '${p['position_title'] ?? ''}: ${p['text'] ?? ''}',
                      style: pw.TextStyle(font: font, fontSize: 10),
                    ),
                  ),
                if (signatureImages.isNotEmpty) ...[
                  pw.SizedBox(height: 18),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      for (var i = 0; i < signatures.length; i++)
                        pw.Column(
                          children: [
                            if (signatureImages[i] != null)
                              pw.Image(signatureImages[i]!, height: 42)
                            else
                              pw.SizedBox(height: 28),
                            pw.Text(
                              '${signatures[i]['title'] ?? ''}',
                              style: pw.TextStyle(font: font, fontSize: 9),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
                if (copies.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  pw.Text(
                    '${print['copies_label'] ?? ''}: ${copies.map((c) => '$c').join(' ، ')}',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ],
                pw.Spacer(),
                if ((print['footer_text'] ?? '').toString().isNotEmpty)
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text('${print['footer_text']}', style: pw.TextStyle(font: font, fontSize: 9)),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  await Printing.layoutPdf(onLayout: (_) => doc.save());
}

double _mm(dynamic value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 20;
  return (n.clamp(4, 80)) * PdfPageFormat.mm;
}

PdfPageFormat _pageFormat(String size, String orientation) {
  PdfPageFormat format;
  switch (size) {
    case 'a5':
      format = PdfPageFormat.a5;
    case 'letter':
      format = PdfPageFormat.letter;
    default:
      format = PdfPageFormat.a4;
  }
  if (orientation == 'landscape') return format.landscape;
  return format;
}

String _plainBody(String raw, String format) {
  var text = raw;
  if (format == 'html') {
    text = text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'<[^>]+>'), '');
  } else if (format == 'markdown') {
    text = text
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll('**', '')
        .replaceAll('*', '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
  }
  return text;
}
