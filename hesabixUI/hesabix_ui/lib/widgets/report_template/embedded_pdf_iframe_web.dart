import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// نمایش PDF داخل صفحه (وب) با iframe و blob URL.
class ReportTemplateEmbeddedPdf extends StatefulWidget {
  final Uint8List bytes;

  const ReportTemplateEmbeddedPdf({super.key, required this.bytes});

  @override
  State<ReportTemplateEmbeddedPdf> createState() => _ReportTemplateEmbeddedPdfState();
}

class _ReportTemplateEmbeddedPdfState extends State<ReportTemplateEmbeddedPdf> {
  String? _viewType;
  String? _objectUrl;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _scheduleMount();
  }

  @override
  void didUpdateWidget(covariant ReportTemplateEmbeddedPdf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.bytes, widget.bytes)) {
      _scheduleMount();
    }
  }

  void _scheduleMount() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mountView();
    });
  }

  void _mountView() {
    _revokeBlob();
    _viewType = null;

    if (widget.bytes.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    final seq = ++_seq;
    final bytes = widget.bytes;
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final url = web.URL.createObjectURL(blob);
    final vt = 'report-pdf-$seq-${DateTime.now().microsecondsSinceEpoch}';

    ui_web.platformViewRegistry.registerViewFactory(vt, (int viewId) {
      final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.src = url;
      iframe.title = 'PDF preview';
      iframe.style.border = 'none';
      iframe.style.width = '100%';
      iframe.style.height = '100%';
      iframe.style.display = 'block';
      return iframe;
    });

    if (mounted) {
      setState(() {
        _objectUrl = url;
        _viewType = vt;
      });
    }
  }

  void _revokeBlob() {
    final url = _objectUrl;
    if (url == null || url.isEmpty) return;
    try {
      web.URL.revokeObjectURL(url);
    } catch (_) {}
    _objectUrl = null;
  }

  @override
  void dispose() {
    _revokeBlob();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bytes.isEmpty) {
      return Center(
        child: Text(
          'فایل PDF خالی است',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    final vt = _viewType;
    if (vt == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SizedBox.expand(
      child: HtmlElementView(
        key: ValueKey(vt),
        viewType: vt,
      ),
    );
  }
}
