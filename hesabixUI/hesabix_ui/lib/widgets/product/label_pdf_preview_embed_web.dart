import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:web/web.dart' as web;

/// پیش‌نمایش PDF در وب: blob + iframe ثبت‌شده با [platformViewRegistry].
class LabelPdfPreviewEmbed extends StatefulWidget {
  final PdfPageFormat pageFormat;
  final Future<Uint8List> Function(PdfPageFormat format) buildPdf;

  const LabelPdfPreviewEmbed({
    super.key,
    required this.pageFormat,
    required this.buildPdf,
  });

  @override
  State<LabelPdfPreviewEmbed> createState() => _LabelPdfPreviewEmbedState();
}

class _LabelPdfPreviewEmbedState extends State<LabelPdfPreviewEmbed> {
  String? _viewType;
  String? _objectUrl;
  bool _loading = true;
  Object? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant LabelPdfPreviewEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageFormat != widget.pageFormat || oldWidget.buildPdf != widget.buildPdf) {
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    _revokeBlob();
    _viewType = null;

    try {
      final bytes = await widget.buildPdf(widget.pageFormat);
      if (!mounted || seq != _seq) return;
      if (bytes.isEmpty) {
        setState(() {
          _error = 'فایل PDF خالی است';
          _loading = false;
        });
        return;
      }

      final blob = web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'application/pdf'),
      );
      final url = web.URL.createObjectURL(blob);
      final vt = 'hesabix-label-pdf-$seq-${DateTime.now().microsecondsSinceEpoch}';

      ui_web.platformViewRegistry.registerViewFactory(vt, (int viewId) {
        final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement;
        iframe.src = url;
        iframe.style.border = 'none';
        iframe.style.width = '100%';
        iframe.style.height = '100%';
        iframe.style.display = 'block';
        return iframe;
      });

      setState(() {
        _objectUrl = url;
        _viewType = vt;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('LabelPdfPreviewEmbed: $e\n$st');
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _revokeBlob() {
    final u = _objectUrl;
    if (u != null) {
      try {
        web.URL.revokeObjectURL(u);
      } catch (_) {}
      _objectUrl = null;
    }
  }

  @override
  void dispose() {
    _revokeBlob();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'در حال آماده‌سازی پیش‌نمایش…',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'پیش‌نمایش باز نشد.',
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$_error',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final vt = _viewType;
    if (vt == null) {
      return const SizedBox.shrink();
    }
    return SizedBox.expand(
      child: HtmlElementView(
        key: ValueKey(vt),
        viewType: vt,
      ),
    );
  }
}
