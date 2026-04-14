import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../utils/web/web_utils.dart' as web_utils;

/// نمایش PDF داخل صفحه (وب) با iframe و blob URL.
///
/// ریشهٔ DOM باید ظرفی با ابعاد قطعی باشد؛ فقط iframe با height:100% کافی نیست
/// چون در platform view والد اغلب ارتفاع محاسبه‌شده ندارد.
class ReportTemplateEmbeddedPdf extends StatefulWidget {
  final Uint8List bytes;

  const ReportTemplateEmbeddedPdf({super.key, required this.bytes});

  @override
  State<ReportTemplateEmbeddedPdf> createState() => _ReportTemplateEmbeddedPdfState();
}

class _ReportTemplateEmbeddedPdfState extends State<ReportTemplateEmbeddedPdf> {
  late final String _viewType;
  late final String _blobUrl;

  @override
  void initState() {
    super.initState();
    _viewType = 'report-pdf-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';
    _blobUrl = web_utils.createObjectUrlFromBytes(
      widget.bytes,
      mimeType: 'application/pdf',
    );
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final root = web.document.createElement('div') as web.HTMLDivElement
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'relative'
        ..style.overflow = 'hidden'
        ..style.display = 'block';

      final iframe = web.HTMLIFrameElement()
        ..src = _blobUrl
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
  }

  @override
  void dispose() {
    final url = _blobUrl;
    super.dispose();
    // تأخیر تا iframe فرصت بارگذاری blob را داشته باشد؛ revoke زودهنگام صفحهٔ سفید می‌دهد.
    Future<void>.delayed(const Duration(seconds: 3), () {
      web_utils.revokeBlobUrl(url);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
