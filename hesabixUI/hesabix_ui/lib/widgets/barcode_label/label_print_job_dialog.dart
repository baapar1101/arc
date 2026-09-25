import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../models/barcode_label/label_design_v1.dart';
import '../../models/barcode_label/label_printer_profile.dart';
import '../../services/barcode_label_service.dart';
import '../../services/bytes_export/bytes_export_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../product/label_pdf_preview_embed.dart';
import 'render/label_escpos_generator.dart';
import 'render/label_escpos_tcp.dart';
import 'render/label_pdf_renderer.dart';
import 'render/label_sheet_pdf_format.dart';
import 'render/label_zpl_generator.dart';
import 'render/label_zpl_tcp.dart';

/// یک ردیف قابل چاپ برای job برچسب.
class LabelPrintJobRow {
  final String key;
  final String title;
  final String subtitle;
  final Map<String, dynamic> context;
  int qty;

  LabelPrintJobRow({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.context,
    this.qty = 1,
  });
}

/// دیالوگ چاپ حرفه‌ای با انتخاب طرح، تعداد، پیش‌نمایش، PDF و چاپ سیستم.
class LabelPrintJobDialog extends StatefulWidget {
  final int businessId;
  final List<LabelPrintJobRow> rows;
  final int? initialTemplateId;

  const LabelPrintJobDialog({
    super.key,
    required this.businessId,
    required this.rows,
    this.initialTemplateId,
  });

  static Future<void> show(
    BuildContext context, {
    required int businessId,
    required List<LabelPrintJobRow> rows,
    int? initialTemplateId,
  }) {
    if (rows.isEmpty) return Future.value();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LabelPrintJobDialog(
        businessId: businessId,
        rows: rows,
        initialTemplateId: initialTemplateId,
      ),
    );
  }

  static dynamic _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final v = map[key];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      return v;
    }
    return null;
  }

  /// فیلدهای کالا برای binding طرح برچسب.
  ///
  /// لیست کالا از API فیلدهای `base_sales_price` / `base_purchase_price` دارد،
  /// در حالی که طرح‌ها به `product.price` و `product.sale_price` وصل می‌شوند.
  /// فرم کالا این نام‌ها را از قبل نگاشت می‌کند؛ چاپ گروهی باید همین کار را بکند.
  static Map<String, dynamic> productBindingMap(
    Map<String, dynamic> product, {
    String? barcodeOverride,
  }) {
    final name = product['name']?.toString() ?? '';
    final code = product['code']?.toString() ?? '';
    final gb = barcodeOverride ??
        product['general_barcodes']?.toString() ??
        product['barcode']?.toString() ??
        '';
    final firstBarcode = gb
        .split(RegExp(r'[,،\n]+'))
        .map((e) => e.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => code);
    final salePrice = _firstNonEmpty(product, const [
      'sale_price',
      'price',
      'base_sales_price',
      'sales_price',
    ]);
    final buyPrice = _firstNonEmpty(product, const [
      'buy_price',
      'base_purchase_price',
      'purchase_price',
    ]);
    return {
      'name': name,
      'code': code,
      'price': salePrice ?? buyPrice,
      'sale_price': salePrice ?? buyPrice,
      'general_barcode': firstBarcode,
      'image_url': product['image_url'] ?? product['thumbnail_url'],
    };
  }

  /// ساخت ردیف از داده کالای عمومی.
  static LabelPrintJobRow fromProductMap(Map<String, dynamic> product, {String? barcodeOverride, int qty = 1}) {
    final fields = productBindingMap(product, barcodeOverride: barcodeOverride);
    final name = fields['name']?.toString() ?? '';
    final code = fields['code']?.toString() ?? '';
    final firstBarcode = fields['general_barcode']?.toString() ?? '';
    return LabelPrintJobRow(
      key: 'p-${product['id']}-$firstBarcode',
      title: name,
      subtitle: '$code · $firstBarcode',
      qty: qty,
      context: {
        'product': fields,
        'instance': {'serial': '', 'barcode': ''},
        'warehouse': {'name': product['warehouse_name']?.toString() ?? ''},
        'business': {'name': ''},
        'print': {'counter': 1, 'copy_index': 1},
      },
    );
  }

  @override
  State<LabelPrintJobDialog> createState() => _LabelPrintJobDialogState();
}

class _LabelPrintJobDialogState extends State<LabelPrintJobDialog> {
  final _service = BarcodeLabelService();
  bool _loading = true;
  String? _error;
  List<LabelTemplateSummary> _templates = const [];
  int? _templateId;
  LabelTemplateDetail? _detail;
  LabelSheet? _printSheet;
  LabelDesignDocument? _printDesignOverride;
  late List<LabelPrintJobRow> _rows;
  int _applyQty = 1;
  int _previewNonce = 0;
  LabelPrinterSettings _printerSettings = const LabelPrinterSettings();
  String? _profileId;

  @override
  void initState() {
    super.initState();
    _rows = widget.rows
        .map(
          (r) => LabelPrintJobRow(
            key: r.key,
            title: r.title,
            subtitle: r.subtitle,
            context: Map<String, dynamic>.from(r.context),
            qty: r.qty < 1 ? 1 : r.qty,
          ),
        )
        .toList();
    _bootstrap();
  }

  LabelDesignDocument? get _designForPrint => _printDesignOverride ?? _detail?.design;

  int get _totalLabels => _rows.fold<int>(0, (s, r) => s + r.qty);

  LabelPrinterProfile? get _selectedProfile {
    final id = _profileId;
    if (id == null) return null;
    for (final p in _printerSettings.enabledProfiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.listTemplates(businessId: widget.businessId, status: 'published');
      LabelPrinterSettings printerSettings = const LabelPrinterSettings();
      try {
        printerSettings = await _service.getPrinterSettings(businessId: widget.businessId);
      } catch (_) {}
      var selected = widget.initialTemplateId;
      selected ??= list.cast<LabelTemplateSummary?>().firstWhere(
            (t) => t?.isDefault == true,
            orElse: () => list.isNotEmpty ? list.first : null,
          )?.id;
      LabelTemplateDetail? detail;
      if (selected != null) {
        detail = await _service.getTemplate(businessId: widget.businessId, templateId: selected);
      }
      if (!mounted) return;
      setState(() {
        _templates = list;
        _templateId = selected;
        _detail = detail;
        _printSheet = detail?.sheet;
        _printerSettings = printerSettings;
        _profileId = printerSettings.activeProfileId ??
            (printerSettings.enabledProfiles.isNotEmpty
                ? printerSettings.enabledProfiles.first.id
                : null);
        _loading = false;
      });
      await _refreshPreview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _selectTemplate(int? id) async {
    if (id == null) return;
    try {
      final detail = await _service.getTemplate(businessId: widget.businessId, templateId: id);
      if (!mounted) return;
      setState(() {
        _templateId = id;
        _detail = detail;
        _printSheet = detail.sheet;
        _printDesignOverride = null;
      });
      await _refreshPreview();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  List<Map<String, dynamic>> _expandContexts() {
    final out = <Map<String, dynamic>>[];
    var counter = 1;
    for (final row in _rows) {
      for (var i = 0; i < row.qty; i++) {
        final ctx = Map<String, dynamic>.from(row.context);
        ctx['print'] = {'counter': counter, 'copy_index': i + 1};
        out.add(ctx);
        counter++;
      }
    }
    return out;
  }

  Future<Uint8List> _buildPdf({bool rollMode = false}) async {
    final detail = _detail;
    final design = _designForPrint;
    final sheet = _printSheet ?? detail?.sheet;
    if (detail == null || sheet == null || design == null) {
      throw StateError('No template');
    }
    final contexts = _expandContexts();
    if (contexts.isEmpty) {
      throw StateError('No labels');
    }
    if (contexts.length > 10000) {
      throw StateError('Too many labels (max 10000)');
    }
    final useRoll = rollMode || sheet.isRollMode;
    return LabelPdfRenderer.render(
      design: design,
      sheet: sheet,
      contexts: contexts,
      rollMode: useRoll,
      businessId: widget.businessId,
    );
  }

  Future<void> _refreshPreview() async {
    if (!mounted) return;
    setState(() {
      _previewNonce++;
    });
  }

  PdfPageFormat _previewFormat() {
    final design = _designForPrint;
    final sheet = _printSheet ?? _detail?.sheet;
    if (design == null || sheet == null) return PdfPageFormat.a4;
    return pdfPageFormatForLabelSheet(
      sheet,
      labelWidthMm: design.canvas.widthMm,
      labelHeightMm: design.canvas.heightMm,
    );
  }

  Future<Uint8List> _buildPreviewPdf(PdfPageFormat format) async {
    final design = _designForPrint;
    final sheet = _printSheet ?? _detail?.sheet;
    if (design == null || sheet == null) return Uint8List(0);
    final slots = sheet.isRollMode ? 1 : (sheet.columns * sheet.rows).clamp(1, 24);
    final contexts = _expandContexts().take(slots).toList();
    if (contexts.isEmpty) return Uint8List(0);
    return LabelPdfRenderer.render(
      design: design,
      sheet: sheet,
      contexts: contexts,
      rollMode: sheet.isRollMode,
      businessId: widget.businessId,
    );
  }

  Future<void> _savePdf() async {
    final t = AppLocalizations.of(context);
    try {
      final bytes = await _buildPdf();
      if (!mounted) return;
      final result = await BytesExportService.export(
        bytes: bytes,
        filename: 'labels-${DateTime.now().millisecondsSinceEpoch}.pdf',
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      BytesExportService.showFeedback(context, result, successOverride: t.labelPdfSaved);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _systemPrint() async {
    if (kIsWeb) {
      SnackBarHelper.showInfo(
        context,
        message: AppLocalizations.of(context).barcodeLabelPrintWebHint,
      );
      await _savePdf();
      return;
    }
    try {
      final bytes = await _buildPdf();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _printToProfile() async {
    final t = AppLocalizations.of(context);
    final profile = _selectedProfile;
    final detail = _detail;
    if (profile == null || detail == null) {
      SnackBarHelper.showError(context, message: t.barcodeLabelNoPrinterProfile);
      return;
    }
    if (!profile.enabled) {
      SnackBarHelper.showError(context, message: t.barcodeLabelPrinterDisabled);
      return;
    }

    try {
      if (profile.mode == 'escpos') {
        if (kIsWeb) {
          SnackBarHelper.showError(context, message: t.barcodeLabelPrintersWebBanner);
          return;
        }
        if (profile.connection == 'tcp' && (profile.host ?? '').isNotEmpty) {
          final design = _designForPrint ?? detail.design;
          final data = LabelEscPosGenerator.forContexts(
            design: design,
            contexts: _expandContexts(),
            dpi: profile.dpi,
          );
          await sendEscPosOverTcp(
            host: profile.host!,
            port: profile.port ?? 9100,
            data: data,
          );
          if (!mounted) return;
          SnackBarHelper.show(context, message: t.barcodeLabelPrinterEscPosSent);
          return;
        }
        SnackBarHelper.showInfo(context, message: t.barcodeLabelPrinterEscPosFallback);
        final bytes = await _buildPdf(rollMode: true);
        await Printing.layoutPdf(onLayout: (_) async => bytes);
        return;
      }

      if (profile.isPdfSpooler) {
        final bytes = await _buildPdf(rollMode: true);
        if (kIsWeb) {
          SnackBarHelper.showInfo(context, message: t.barcodeLabelPrintWebHint);
          if (!mounted) return;
          final result = await BytesExportService.export(
            bytes: bytes,
            filename: 'roll-labels-${DateTime.now().millisecondsSinceEpoch}.pdf',
            mimeType: 'application/pdf',
          );
          if (!mounted) return;
          BytesExportService.showFeedback(context, result, successOverride: t.labelPdfSaved);
          return;
        }
        await Printing.layoutPdf(onLayout: (_) async => bytes);
        return;
      }

      if (profile.isZpl) {
        if (kIsWeb) {
          SnackBarHelper.showError(context, message: t.barcodeLabelPrintersWebBanner);
          return;
        }
        if (profile.connection != 'tcp' || (profile.host ?? '').isEmpty) {
          SnackBarHelper.showError(context, message: t.barcodeLabelPrinterZplNeedsTcp);
          return;
        }
        final zpl = await LabelZplGenerator.forContexts(
          design: _designForPrint ?? detail.design,
          contexts: _expandContexts(),
          dpi: profile.dpi,
          businessId: widget.businessId,
        );
        await sendZplOverTcp(
          host: profile.host!,
          port: profile.port ?? 9100,
          zpl: zpl,
        );
        if (!mounted) return;
        SnackBarHelper.show(context, message: t.barcodeLabelPrinterZplSent);
        return;
      }

      SnackBarHelper.showError(context, message: t.barcodeLabelPrinterUnsupportedMode);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _applyQtyToAll() {
    setState(() {
      for (final r in _rows) {
        r.qty = _applyQty.clamp(1, 9999);
      }
    });
    _refreshPreview();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 1100 : 640,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.qr_code_2_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t.barcodeLabelPrintJobTitle, style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                      : _templates.isEmpty
                          ? _emptyTemplates(t)
                          : wide
                              ? Row(
                                  children: [
                                    Expanded(flex: 5, child: _leftPane(t, cs)),
                                    const VerticalDivider(width: 1),
                                    Expanded(flex: 4, child: _previewPane(t)),
                                  ],
                                )
                              : ListView(
                                  children: [
                                    SizedBox(height: 280, child: _leftPane(t, cs)),
                                    const Divider(),
                                    SizedBox(height: 320, child: _previewPane(t)),
                                  ],
                                ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      t.barcodeLabelPrintTotal(_totalLabels),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
                  OutlinedButton.icon(
                    onPressed: _detail == null ? null : _savePdf,
                    icon: const Icon(Icons.save_alt),
                    label: Text(t.barcodeLabelSavePdf),
                  ),
                  OutlinedButton.icon(
                    onPressed: _detail == null || _selectedProfile == null ? null : _printToProfile,
                    icon: const Icon(Icons.print_outlined),
                    label: Text(t.barcodeLabelRollPrint),
                  ),
                  FilledButton.icon(
                    onPressed: _detail == null ? null : _systemPrint,
                    icon: const Icon(Icons.print),
                    label: Text(t.barcodeLabelSystemPrint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTemplates(AppLocalizations t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dashboard_customize_outlined, size: 48),
            const SizedBox(height: 12),
            Text(t.barcodeLabelNoPublishedTemplates, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _onProfileChanged(String? id) {
    setState(() {
      _profileId = id;
      if (id != null && _printSheet != null) {
        _printSheet = _printSheet!.copyWith(printMode: 'roll');
      }
      _printDesignOverride = null;
    });
    _refreshPreview();
  }

  void _applyPrinterSizeToPrint() {
    final profile = _selectedProfile;
    final detail = _detail;
    if (profile == null || detail == null) return;
    setState(() {
      _printDesignOverride = detail.design.copyWith(
        canvas: detail.design.canvas.copyWith(
          widthMm: profile.labelWidthMm,
          heightMm: profile.labelHeightMm,
        ),
      );
      if (_printSheet != null && !_printSheet!.isRollMode) {
        _printSheet = _printSheet!.copyWith(printMode: 'roll');
      }
    });
    _refreshPreview();
  }

  Widget _leftPane(AppLocalizations t, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          initialValue: _templateId,
          decoration: InputDecoration(
            labelText: t.barcodeLabelSelectTemplate,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final tpl in _templates)
              DropdownMenuItem(
                value: tpl.id,
                child: Text(
                  '${tpl.isDefault ? '★ ' : ''}${tpl.name}'
                  '${tpl.canvasWidthMm != null ? ' (${tpl.canvasWidthMm!.toStringAsFixed(0)}×${tpl.canvasHeightMm!.toStringAsFixed(0)})' : ''}',
                ),
              ),
          ],
          onChanged: _selectTemplate,
        ),
        if (_printerSettings.enabledProfiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _profileId,
            decoration: InputDecoration(
              labelText: t.barcodeLabelSelectPrinter,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final p in _printerSettings.enabledProfiles)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '${p.id == _printerSettings.activeProfileId ? '★ ' : ''}${p.name} (${p.mode})',
                  ),
                ),
            ],
            onChanged: _onProfileChanged,
          ),
        ],
        const SizedBox(height: 12),
        _buildPrintSettings(t),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: '$_applyQty',
                decoration: InputDecoration(labelText: t.barcodeLabelQtyAll, isDense: true),
                keyboardType: TextInputType.number,
                onChanged: (s) => _applyQty = int.tryParse(s) ?? 1,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _applyQtyToAll,
              child: Text(t.barcodeLabelApplyQty),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(t.barcodeLabelPrintItems, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ..._rows.asMap().entries.map((e) {
          final i = e.key;
          final row = e.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(row.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: SizedBox(
                width: 88,
                child: TextFormField(
                  key: ValueKey('${row.key}-${row.qty}'),
                  initialValue: '${row.qty}',
                  decoration: const InputDecoration(isDense: true, labelText: 'Qty'),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (s) {
                    final q = int.tryParse(s) ?? 1;
                    setState(() => _rows[i].qty = q.clamp(1, 9999));
                    _refreshPreview();
                  },
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPrintSettings(AppLocalizations t) {
    final sheet = _printSheet;
    if (sheet == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.barcodeLabelPrintSettings, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: sheet.printMode,
          decoration: InputDecoration(
            labelText: t.barcodeLabelPrintLayout,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(value: 'sheet', child: Text(t.barcodeLabelPrintLayoutSheet)),
            DropdownMenuItem(value: 'roll', child: Text(t.barcodeLabelPrintLayoutRoll)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _printSheet = sheet.copyWith(printMode: v));
            _refreshPreview();
          },
        ),
        if (!sheet.isRollMode) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: sheet.paper,
            decoration: InputDecoration(
              labelText: t.barcodeLabelPaperSize,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: 'A4', child: Text('A4')),
              const DropdownMenuItem(value: 'A5', child: Text('A5')),
              const DropdownMenuItem(value: 'Letter', child: Text('Letter')),
              DropdownMenuItem(value: 'custom', child: Text(t.barcodeLabelPaperCustom)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _printSheet = sheet.copyWith(paper: v));
              _refreshPreview();
            },
          ),
          if (sheet.paper == 'custom') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('pw-${sheet.customPaperMm?['width']}'),
                    initialValue: '${sheet.customPaperMm?['width'] ?? 210}',
                    decoration: InputDecoration(
                      labelText: t.barcodeLabelPaperWidth,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (s) {
                      final v = double.tryParse(s.replaceAll(',', '.'));
                      if (v == null) return;
                      setState(() => _printSheet = sheet.copyWith(
                            customPaperMm: {
                              'width': v,
                              'height': sheet.customPaperMm?['height'] ?? 297,
                            },
                          ));
                      _refreshPreview();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('ph-${sheet.customPaperMm?['height']}'),
                    initialValue: '${sheet.customPaperMm?['height'] ?? 297}',
                    decoration: InputDecoration(
                      labelText: t.barcodeLabelPaperHeight,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (s) {
                      final v = double.tryParse(s.replaceAll(',', '.'));
                      if (v == null) return;
                      setState(() => _printSheet = sheet.copyWith(
                            customPaperMm: {
                              'width': sheet.customPaperMm?['width'] ?? 210,
                              'height': v,
                            },
                          ));
                      _refreshPreview();
                    },
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: sheet.orientation,
            decoration: InputDecoration(
              labelText: t.barcodeLabelOrientation,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: 'portrait', child: Text(t.barcodeLabelPortrait)),
              DropdownMenuItem(value: 'landscape', child: Text(t.barcodeLabelLandscape)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _printSheet = sheet.copyWith(orientation: v));
              _refreshPreview();
            },
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t.barcodeLabelRollModeHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        if (sheet.isRollMode && _selectedProfile != null && _detail != null) ...[
          const SizedBox(height: 8),
          _printerSizeBanner(t),
        ],
      ],
    );
  }

  Widget _printerSizeBanner(AppLocalizations t) {
    final profile = _selectedProfile!;
    final canvas = _detail!.design.canvas;
    final wDiff = (profile.labelWidthMm - canvas.widthMm).abs() > 0.5;
    final hDiff = (profile.labelHeightMm - canvas.heightMm).abs() > 0.5;
    if (!wDiff && !hDiff) {
      return Text(
        t.barcodeLabelPrinterSizeMatch(
          profile.labelWidthMm.toStringAsFixed(0),
          profile.labelHeightMm.toStringAsFixed(0),
        ),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.barcodeLabelPrinterSizeMismatch(
            profile.labelWidthMm.toStringAsFixed(0),
            profile.labelHeightMm.toStringAsFixed(0),
            canvas.widthMm.toStringAsFixed(0),
            canvas.heightMm.toStringAsFixed(0),
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.tertiary,
              ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _applyPrinterSizeToPrint,
            icon: const Icon(Icons.sync, size: 18),
            label: Text(
              t.barcodeLabelApplyPrinterSize(
                profile.labelWidthMm.toStringAsFixed(0),
                profile.labelHeightMm.toStringAsFixed(0),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewPane(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(t.barcodeLabelPreviewPdf, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                tooltip: t.refresh,
                onPressed: _refreshPreview,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _detail == null
                  ? Center(child: Text(t.barcodeLabelPreviewEmpty))
                  : LabelPdfPreviewEmbed(
                      key: ValueKey(
                        'preview-$_previewNonce-$_templateId-${_printSheet?.printMode}-'
                        '${_designForPrint?.canvas.widthMm}x${_designForPrint?.canvas.heightMm}',
                      ),
                      pageFormat: _previewFormat(),
                      buildPdf: _buildPreviewPdf,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
