import 'package:hesabix_ui/theme/glass.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bytes_export/bytes_export_service.dart';

enum PdfOutputAction { ask, save, print }

class PdfPrinterChoice {
  final String url;
  final String name;

  const PdfPrinterChoice({required this.url, required this.name});

  factory PdfPrinterChoice.fromJson(Map<String, dynamic> json) =>
      PdfPrinterChoice(
        url: (json['url'] ?? '').toString(),
        name: (json['name'] ?? json['url'] ?? '').toString(),
      );

  Map<String, String> toJson() => {'url': url, 'name': name};
}

class PdfOutputPreferences {
  final PdfOutputAction action;
  final Map<String, PdfPrinterChoice> printersByPaper;

  const PdfOutputPreferences({
    this.action = PdfOutputAction.print,
    this.printersByPaper = const {},
  });

  PdfPrinterChoice? printerFor(String? paperSize) {
    final key = normalizePaperKey(paperSize);
    return printersByPaper[key] ?? printersByPaper['default'];
  }

  PdfOutputPreferences copyWith({
    PdfOutputAction? action,
    Map<String, PdfPrinterChoice>? printersByPaper,
  }) => PdfOutputPreferences(
    action: action ?? this.action,
    printersByPaper: printersByPaper ?? this.printersByPaper,
  );

  static String normalizePaperKey(String? paperSize) {
    final value = (paperSize ?? '').trim().toLowerCase();
    if (value.isEmpty) return 'default';
    return value.replaceAll(' ', '');
  }
}

/// Device-local output preferences and a single delivery path for PDF actions.
/// Printer names are device-specific, so they are intentionally not synced to
/// the business print-settings API.
class PdfOutputService {
  PdfOutputService._();

  static String _storageKey(int? businessId) =>
      'pdf_output_preferences_v1_${businessId ?? 0}';

  static Future<PdfOutputPreferences> loadPreferences({int? businessId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(businessId));
    if (raw == null || raw.isEmpty) return const PdfOutputPreferences();
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final actionRaw = decoded['action'];
      final action = PdfOutputAction.values.firstWhere(
        (candidate) => candidate.name == actionRaw,
        orElse: () => PdfOutputAction.print,
      );
      final printers = <String, PdfPrinterChoice>{};
      for (final entry in decoded.entries.where(
        (e) => e.key.startsWith('printer:'),
      )) {
        final value = Map<String, dynamic>.from(entry.value as Map);
        final url = (value['url'] ?? '').toString();
        if (url.isEmpty) continue;
        printers[entry.key.substring('printer:'.length)] =
            PdfPrinterChoice.fromJson(value);
      }
      return PdfOutputPreferences(action: action, printersByPaper: printers);
    } catch (_) {
      return const PdfOutputPreferences();
    }
  }

  static Future<void> savePreferences(
    PdfOutputPreferences value, {
    int? businessId,
  }) async {
    final fields = <String, dynamic>{'action': value.action.name};
    value.printersByPaper.forEach((paper, printer) {
      if (printer.url.isEmpty) return;
      fields['printer:$paper'] = printer.toJson();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(businessId), jsonEncode(fields));
  }

  static Future<List<Printer>> listAvailablePrinters() async {
    final info = await Printing.info();
    if (!info.canListPrinters) return const [];
    final printers = await Printing.listPrinters();
    printers.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return printers.where((printer) => printer.isAvailable).toList();
  }

  static Future<void> deliverPdf({
    required BuildContext context,
    required List<int> bytes,
    required String filename,
    int? businessId,
    String? paperSize,
    PdfOutputAction? actionOverride,
  }) async {
    if (!context.mounted) return;
    if (bytes.isEmpty) {
      throw ArgumentError('Cannot print or save an empty PDF');
    }

    final preferences = await loadPreferences(businessId: businessId);
    if (!context.mounted) return;
    var action = actionOverride ?? preferences.action;
    if (action == PdfOutputAction.ask) {
      if (kIsWeb) {
        action = PdfOutputAction.save;
      } else {
        final selected = await _askOutputAction(context);
        if (selected == null || !context.mounted) return;
        action = selected;
      }
    }

    if (action == PdfOutputAction.save || kIsWeb) {
      final result = await BytesExportService.export(
        bytes: bytes,
        filename: _pdfFilename(filename),
        mimeType: 'application/pdf',
        mode: BytesExportMode.save,
      );
      if (context.mounted) BytesExportService.showFeedback(context, result);
      return;
    }

    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final printInfo = await Printing.info();
    if (!printInfo.canPrint) {
      throw UnsupportedError('PDF printing is not available on this device.');
    }

    final selectedPrinter = preferences.printerFor(paperSize);
    Printer? printer;
    if (selectedPrinter != null && printInfo.canListPrinters) {
      try {
        final available = await Printing.listPrinters();
        for (final candidate in available) {
          if (candidate.isAvailable &&
              (candidate.url == selectedPrinter.url ||
                  candidate.name == selectedPrinter.name)) {
            printer = candidate;
            break;
          }
        }
      } catch (_) {
        // If enumeration fails, keep the system print dialog as a safe fallback.
      }
    }

    final bool printed;
    if (printer != null && printInfo.directPrint) {
      printed = await Printing.directPrintPdf(
        printer: printer,
        name: _pdfFilename(filename),
        onLayout: (_) async => data,
      );
    } else {
      if (selectedPrinter != null && context.mounted) {
        final isFa = Localizations.localeOf(context).languageCode == 'fa';
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              isFa
                  ? 'چاپگر ذخیره‌شده در دسترس نیست؛ چاپگر را از پنجرهٔ چاپ انتخاب کنید.'
                  : 'The saved printer is unavailable. Select a printer in the print dialog.',
            ),
          ),
        );
      }
      printed = await Printing.layoutPdf(
        name: _pdfFilename(filename),
        onLayout: (_) async => data,
      );
    }

    if (!context.mounted || !printed) return;
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          isFa ? 'سند به صف چاپ ارسال شد' : 'Document sent to the print queue',
        ),
      ),
    );
  }

  static Future<PdfOutputAction?> _askOutputAction(BuildContext context) {
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    return showGlassModalBottomSheet<PdfOutputAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: Text(isFa ? 'چاپ سند' : 'Print document'),
              onTap: () => Navigator.pop(sheetContext, PdfOutputAction.print),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(isFa ? 'ذخیره PDF' : 'Save PDF'),
              onTap: () => Navigator.pop(sheetContext, PdfOutputAction.save),
            ),
          ],
        ),
      ),
    );
  }

  static String _pdfFilename(String input) {
    final base = input.trim().isEmpty ? 'document' : input.trim();
    return base.toLowerCase().endsWith('.pdf') ? base : '$base.pdf';
  }
}
