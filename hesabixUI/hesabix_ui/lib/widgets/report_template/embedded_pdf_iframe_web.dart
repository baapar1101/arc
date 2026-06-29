import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../utils/web/web_utils.dart' as web_utils;

/// نمایش PDF داخل صفحه (وب) با iframe و blob URL.
///
/// ریشهٔ DOM باید ظرفی با ابعاد قطعی باشد؛ فقط iframe با height:100% کافی نیست
/// چون در platform view والد اغلب ارتفاع محاسبه‌شده ندارد.
/// همچنین revoke زودهنگام blob URL باعث صفحهٔ سفید در iframe می‌شود.
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
    final previousUrl = _objectUrl;
    if (previousUrl != null) {
      _scheduleRevoke(previousUrl);
    }

    _objectUrl = null;
    _viewType = null;

    if (widget.bytes.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    final seq = ++_seq;
    final url = web_utils.createObjectUrlFromBytes(
      widget.bytes,
      mimeType: 'application/pdf',
    );
    final vt = 'report-pdf-$seq-${DateTime.now().microsecondsSinceEpoch}';

    ui_web.platformViewRegistry.registerViewFactory(vt, (int viewId) {
      final root = web.document.createElement('div') as web.HTMLDivElement
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'relative'
        ..style.overflow = 'hidden'
        ..style.display = 'block';

      final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
        ..src = url
        ..title = 'PDF preview'
        ..style.border = 'none'
        ..style.position = 'absolute'
        ..style.left = '0'
        ..style.top = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block';

      root.append(iframe);
      return root;
    });

    if (!mounted || seq != _seq) {
      _scheduleRevoke(url);
      return;
    }

    setState(() {
      _objectUrl = url;
      _viewType = vt;
    });
  }

  void _scheduleRevoke(String url) {
    if (url.isEmpty) return;
    Future<void>.delayed(const Duration(seconds: 3), () {
      web_utils.revokeBlobUrl(url);
    });
  }

  @override
  void dispose() {
    final url = _objectUrl;
    _objectUrl = null;
    super.dispose();
    if (url != null) {
      _scheduleRevoke(url);
    }
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
