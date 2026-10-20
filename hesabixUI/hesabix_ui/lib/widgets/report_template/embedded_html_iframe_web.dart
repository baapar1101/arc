import 'dart:convert';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../utils/web/web_utils.dart' as web_utils;

class ReportTemplateEmbeddedHtml extends StatefulWidget {
  final String html;
  final Map<String, dynamic>? previewMarginsMm;

  const ReportTemplateEmbeddedHtml({
    super.key,
    required this.html,
    this.previewMarginsMm,
  });

  @override
  State<ReportTemplateEmbeddedHtml> createState() =>
      _ReportTemplateEmbeddedHtmlState();
}

class _ReportTemplateEmbeddedHtmlState
    extends State<ReportTemplateEmbeddedHtml> {
  static int _sequence = 0;

  late final String _viewType;
  web.HTMLIFrameElement? _iframe;
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    _viewType = 'report-html-${++_sequence}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createView);
  }

  @override
  void didUpdateWidget(covariant ReportTemplateEmbeddedHtml oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.previewMarginsMm != widget.previewMarginsMm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyHtml();
      });
    }
  }

  web.Element _createView(int viewId) {
    final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
      ..title = 'HTML preview'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.backgroundColor = '#ffffff';
    iframe.setAttribute('sandbox', 'allow-same-origin');
    _iframe = iframe;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyHtml();
    });
    return iframe;
  }

  void _applyHtml() {
    final iframe = _iframe;
    if (iframe == null) return;
    final previousUrl = _objectUrl;
    final url = web_utils.createObjectUrlFromBytes(
      utf8.encode(_htmlWithWebFonts(widget.html)),
      mimeType: 'text/html;charset=utf-8',
    );
    iframe.removeAttribute('srcdoc');
    iframe.src = url;
    _objectUrl = url;
    if (previousUrl != null && previousUrl != url) {
      _scheduleRevoke(previousUrl);
    }
  }

  String _htmlWithWebFonts(String source) {
    final baseUri = Uri.parse(web.document.baseURI);
    String fontUrl(String name) => baseUri.resolve('fonts/$name').toString();
    String margin(String side) {
      final value = widget.previewMarginsMm?[side];
      final number = value is num
          ? value.toDouble()
          : double.tryParse((value ?? '').toString());
      return '${number ?? 0}mm';
    }

    final head =
        '''
<base href="${baseUri.toString()}">
<style id="hesabix-preview-fonts">
@font-face {
  font-family: 'YekanBakhFaNum';
  src: url('${fontUrl('YekanBakhFaNum-Regular.woff2')}') format('woff2');
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: 'YekanBakhFaNum';
  src: url('${fontUrl('YekanBakhFaNum-SemiBold.woff2')}') format('woff2');
  font-weight: 600;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: 'YekanBakhFaNum';
  src: url('${fontUrl('YekanBakhFaNum-Bold.woff2')}') format('woff2');
  font-weight: 700;
  font-style: normal;
  font-display: swap;
}
html[dir='rtl'] body, html[dir='rtl'] body * {
  font-family: 'YekanBakhFaNum', 'Vazirmatn', Tahoma, Arial, sans-serif !important;
}
html, body {
  box-sizing: border-box;
  margin: 0;
  min-height: 100%;
}
body {
  padding: ${margin('top')} ${margin('right')} ${margin('bottom')} ${margin('left')};
  overflow-wrap: anywhere;
}
</style>
''';
    if (source.contains('<head>')) {
      return source.replaceFirst('<head>', '<head>$head');
    }
    return '<!doctype html><html dir="rtl"><head>$head</head><body>$source</body></html>';
  }

  void _scheduleRevoke(String url) {
    Future<void>.delayed(const Duration(seconds: 30), () {
      web_utils.revokeBlobUrl(url);
    });
  }

  @override
  void dispose() {
    final url = _objectUrl;
    _objectUrl = null;
    _iframe = null;
    super.dispose();
    if (url != null) _scheduleRevoke(url);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: HtmlElementView(viewType: _viewType));
  }
}
