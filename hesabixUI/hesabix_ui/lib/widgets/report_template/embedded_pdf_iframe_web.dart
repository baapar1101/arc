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
///
/// استفاده از embed به جای iframe مهم است: برخی مرورگرها نمایشگر PDF را برای
/// blob داخل iframe سفید رندر می‌کنند، در حالی که همان URL در تب جدید سالم است.
class ReportTemplateEmbeddedPdf extends StatefulWidget {
  final Uint8List bytes;

  const ReportTemplateEmbeddedPdf({super.key, required this.bytes});

  @override
  State<ReportTemplateEmbeddedPdf> createState() =>
      _ReportTemplateEmbeddedPdfState();
}

class _ReportTemplateEmbeddedPdfState extends State<ReportTemplateEmbeddedPdf> {
  static int _factorySeq = 0;

  late final String _viewType;
  web.HTMLEmbedElement? _embed;
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
    final embed = web.document.createElement('embed') as web.HTMLEmbedElement
      ..type = 'application/pdf'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.backgroundColor = '#ffffff';

    embed.setAttribute('aria-label', 'PDF preview');
    _embed = embed;
    _viewMounted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyBytes();
    });
    return embed;
  }

  void _applyBytes() {
    if (!_viewMounted || _embed == null) return;

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
    _embed!.src = url;
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
    _embed = null;
    _viewMounted = false;
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
          final screenWidth = MediaQuery.sizeOf(context).width;
          width = screenWidth > 720 ? 720 : screenWidth;
        }
        if (!height.isFinite || height <= 0) {
          final screenHeight = MediaQuery.sizeOf(context).height;
          height = screenHeight > 520 ? 520 : screenHeight;
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
