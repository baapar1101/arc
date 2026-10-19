import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class ReportTemplateEmbeddedHtml extends StatefulWidget {
  final String html;

  const ReportTemplateEmbeddedHtml({super.key, required this.html});

  @override
  State<ReportTemplateEmbeddedHtml> createState() =>
      _ReportTemplateEmbeddedHtmlState();
}

class _ReportTemplateEmbeddedHtmlState
    extends State<ReportTemplateEmbeddedHtml> {
  static int _sequence = 0;

  late final String _viewType;
  web.HTMLIFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    _viewType = 'report-html-${++_sequence}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createView);
  }

  @override
  void didUpdateWidget(covariant ReportTemplateEmbeddedHtml oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) _applyHtml();
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
    _applyHtml();
    return iframe;
  }

  void _applyHtml() {
    final iframe = _iframe;
    if (iframe == null) return;
    iframe.srcdoc = widget.html.toJS;
  }

  @override
  void dispose() {
    _iframe = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: HtmlElementView(viewType: _viewType));
  }
}
