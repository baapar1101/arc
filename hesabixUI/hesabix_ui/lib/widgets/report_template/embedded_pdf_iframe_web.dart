import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../utils/web/web_utils.dart' as web_utils;

bool _isPdfBytes(Uint8List bytes) {
  return bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}

/// نمایش PDF داخل صفحه (وب) با platform view و blob URL.
class ReportTemplateEmbeddedPdf extends StatefulWidget {
  final Uint8List bytes;

  const ReportTemplateEmbeddedPdf({super.key, required this.bytes});

  @override
  State<ReportTemplateEmbeddedPdf> createState() => _ReportTemplateEmbeddedPdfState();
}

class _ReportTemplateEmbeddedPdfState extends State<ReportTemplateEmbeddedPdf> {
  static int _factorySeq = 0;

  late final String _viewType;
  web.HTMLIFrameElement? _iframe;
  String? _objectUrl;
  String? _error;
  bool _viewMounted = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'report-pdf-${++_factorySeq}-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createView);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyBytes();
    });
  }

  @override
  void didUpdateWidget(covariant ReportTemplateEmbeddedPdf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.bytes, widget.bytes)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyBytes();
      });
    }
  }

  web.Element _createView(int viewId) {
    final root = web.document.createElement('div') as web.HTMLDivElement
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.minHeight = '320px'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.display = 'block'
      ..style.backgroundColor = '#ffffff';

    final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
      ..title = 'PDF preview'
      ..style.border = 'none'
      ..style.position = 'absolute'
      ..style.left = '0'
      ..style.top = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block';

    root.append(iframe);
    _iframe = iframe;
    _viewMounted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyBytes();
    });
    return root;
  }

  void _applyBytes() {
    if (!_viewMounted || _iframe == null) return;

    if (widget.bytes.isEmpty) {
      setState(() => _error = 'فایل PDF خالی است');
      return;
    }

    if (!_isPdfBytes(widget.bytes)) {
      setState(() => _error = 'پاسخ سرور فایل PDF معتبر نیست');
      return;
    }

    final previousUrl = _objectUrl;
    final url = web_utils.createObjectUrlFromBytes(
      widget.bytes,
      mimeType: 'application/pdf',
    );
    _iframe!.src = url;
    _objectUrl = url;
    if (previousUrl != null && previousUrl != url) {
      _scheduleRevoke(previousUrl);
    }

    if (_error != null) {
      setState(() => _error = null);
    }
  }

  void _scheduleRevoke(String url) {
    if (url.isEmpty) return;
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
    if (url != null) {
      _scheduleRevoke(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      );
    }

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

    return LayoutBuilder(
      builder: (context, constraints) {
        var width = constraints.maxWidth;
        var height = constraints.maxHeight;
        if (!width.isFinite || width <= 0) {
          width = MediaQuery.sizeOf(context).width;
        }
        if (!height.isFinite || height <= 0) {
          height = MediaQuery.sizeOf(context).height * 0.55;
        }
        return SizedBox(
          width: width,
          height: height,
          child: HtmlElementView(viewType: _viewType),
        );
      },
    );
  }
}
