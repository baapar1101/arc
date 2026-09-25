import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

import '../../../models/barcode_label/label_design_v1.dart';
import '../../product/label_pdf_preview_embed.dart';
import '../render/label_pdf_renderer.dart';
import '../render/label_sheet_pdf_format.dart';

/// پیش‌نمایش زنده PDF در استودیو — از همان embed مشترک وب/دسکتاپ/موبایل استفاده می‌کند.
class LabelStudioLivePreview extends StatefulWidget {
  final LabelDesignDocument design;
  final LabelSheet sheet;
  final Map<String, dynamic> sampleContext;
  final int? businessId;

  const LabelStudioLivePreview({
    super.key,
    required this.design,
    required this.sheet,
    required this.sampleContext,
    this.businessId,
  });

  @override
  State<LabelStudioLivePreview> createState() => _LabelStudioLivePreviewState();
}

class _LabelStudioLivePreviewState extends State<LabelStudioLivePreview> {
  int _nonce = 0;
  Timer? _debounce;
  String? _contentFingerprint;

  String _fingerprint() =>
      '${widget.design.toJson()}|${widget.sheet.toJson()}|${widget.sampleContext}';

  @override
  void initState() {
    super.initState();
    _contentFingerprint = _fingerprint();
    _scheduleRefresh(immediate: true);
  }

  @override
  void didUpdateWidget(covariant LabelStudioLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fp = _fingerprint();
    if (fp != _contentFingerprint) {
      _contentFingerprint = fp;
      _scheduleRefresh();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleRefresh({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      if (mounted) setState(() => _nonce++);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _nonce++);
    });
  }

  PdfPageFormat _pageFormat() => pdfPageFormatForLabelSheet(
        widget.sheet,
        labelWidthMm: widget.design.canvas.widthMm,
        labelHeightMm: widget.design.canvas.heightMm,
      );

  Future<Uint8List> _buildPdf(PdfPageFormat format) {
    return LabelPdfRenderer.render(
      design: widget.design,
      sheet: widget.sheet,
      contexts: [widget.sampleContext],
      rollMode: widget.sheet.isRollMode,
      businessId: widget.businessId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fp = _pageFormat();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: LabelPdfPreviewEmbed(
        key: ValueKey(
          'studio-live-$_nonce-'
          '${widget.design.canvas.widthMm}x${widget.design.canvas.heightMm}-'
          '${widget.sheet.printMode}-${widget.sheet.paper}',
        ),
        pageFormat: fp,
        buildPdf: _buildPdf,
      ),
    );
  }
}
