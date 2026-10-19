import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../utils/web/web_utils.dart' as web_utils;
import '../embedded_html_iframe.dart';
import '../embedded_pdf_iframe.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class ReportTemplateStudioPreviewPanel extends StatelessWidget {
  final bool loading;
  final Uint8List? pdfBytes;
  final String? html;
  final int previewRevision;
  final String? paperSize;
  final String? orientation;
  final List<String> errors;
  final List<String> warnings;
  final VoidCallback? onRefresh;
  final VoidCallback? onGeneratePdf;
  final VoidCallback? onShowHtml;
  final bool showPdf;

  const ReportTemplateStudioPreviewPanel({
    super.key,
    required this.loading,
    required this.pdfBytes,
    this.html,
    this.previewRevision = 0,
    this.paperSize,
    this.orientation,
    this.errors = const [],
    this.warnings = const [],
    this.onRefresh,
    this.onGeneratePdf,
    this.onShowHtml,
    this.showPdf = false,
  });

  double get _viewportAspectRatio {
    final paper = (paperSize ?? '').trim().toLowerCase();
    var portraitRatio = switch (paper) {
      'letter' => 8.5 / 11,
      'legal' => 8.5 / 14,
      '60mm' || '80mm' || '100mm' => 0.55,
      _ => 1 / 1.414,
    };
    if ((orientation ?? '').toLowerCase() == 'landscape') {
      portraitRatio = 1 / portraitRatio;
    }
    return portraitRatio;
  }

  Widget _pagePreview(BuildContext context, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = MediaQuery.sizeOf(context);
        final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : fallbackSize.width;
        final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : fallbackSize.height * 0.7;
        final maxWidth = availableWidth > 24 ? availableWidth - 24 : availableWidth;
        final maxHeight = availableHeight > 24 ? availableHeight - 24 : availableHeight;
        var width = maxWidth;
        var height = width / _viewportAspectRatio;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * _viewportAspectRatio;
        }

        return ColoredBox(
          color: Colors.grey.shade200,
          child: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 20),
              const SizedBox(width: 8),
              Text('پیش‌نمایش زنده', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (onRefresh != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'بروزرسانی پیش‌نمایش',
                  onPressed: loading ? null : onRefresh,
                ),
              if (html != null && html!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.code_outlined, size: 20),
                  color: !showPdf ? Theme.of(context).colorScheme.primary : null,
                  tooltip: 'پیش‌نمایش سریع',
                  onPressed: onShowHtml,
                ),
              if (onGeneratePdf != null)
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf, size: 20),
                  color: showPdf ? Theme.of(context).colorScheme.primary : null,
                  tooltip: pdfBytes == null ? 'ساخت پیش‌نمایش چاپ' : 'پیش‌نمایش چاپ',
                  onPressed: loading ? null : onGeneratePdf,
                ),
              if (showPdf && kIsWeb && pdfBytes != null && pdfBytes!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 20),
                  tooltip: 'باز کردن در تب جدید',
                  onPressed: () {
                    final url = web_utils.createObjectUrlFromBytes(
                      pdfBytes!,
                      mimeType: 'application/pdf',
                    );
                    web_utils.openUrlInNewTabWeb(url);
                  },
                ),
            ],
          ),
        ),
        if (errors.isNotEmpty)
          Container(
            width: double.infinity,
            color: SemanticColorResolver.negative(context).withValues(alpha: 0.12),
            padding: const EdgeInsets.all(8),
            child: Text(errors.join('\n'), style: TextStyle(color: SemanticColorResolver.negative(context), fontSize: 12)),
          ),
        if (warnings.isNotEmpty)
          Container(
            width: double.infinity,
            color: SemanticColorResolver.warning(context).withValues(alpha: 0.12),
            padding: const EdgeInsets.all(8),
            child: Text(warnings.join('\n'), style: TextStyle(color: SemanticColorResolver.warning(context), fontSize: 12)),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showPdf && pdfBytes != null && pdfBytes!.isNotEmpty)
                _pagePreview(
                  context,
                  ReportTemplateEmbeddedPdf(
                    key: ValueKey('pdf-preview-$previewRevision'),
                    bytes: pdfBytes!,
                  ),
                )
              else if (html != null && html!.isNotEmpty)
                _pagePreview(
                  context,
                  ReportTemplateEmbeddedHtml(
                    key: ValueKey('html-preview-$previewRevision'),
                    html: html!,
                  ),
                )
              else if (!loading)
                Center(
                  child: Text(
                    'پیش‌نمایش آماده می‌شود…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              if (loading)
                ColoredBox(
                  color: Colors.white.withValues(alpha: 0.65),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Debounced preview trigger helper for parent state.
class ReportTemplatePreviewDebouncer {
  Timer? _timer;

  void schedule(VoidCallback action, {Duration delay = const Duration(milliseconds: 600)}) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
