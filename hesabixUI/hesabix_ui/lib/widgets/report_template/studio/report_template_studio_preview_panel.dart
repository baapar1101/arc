import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../utils/web/web_utils.dart' as web_utils;
import '../embedded_html_iframe.dart';
import '../embedded_pdf_iframe.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'report_template_media_settings.dart';

class ReportTemplateStudioPreviewPanel extends StatelessWidget {
  final bool loading;
  final Uint8List? pdfBytes;
  final String? html;
  final int previewRevision;
  final String? paperSize;
  final String? orientation;
  final Map<String, dynamic>? media;
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
    this.media,
    this.errors = const [],
    this.warnings = const [],
    this.onRefresh,
    this.onGeneratePdf,
    this.onShowHtml,
    this.showPdf = false,
  });

  Map<String, dynamic> get _effectiveMedia {
    if (media != null) return Map<String, dynamic>.from(media!);
    return reportTemplateMediaFromLegacy(
      paperSize: paperSize,
      orientation: orientation,
      preferRoll: RegExp(
        r'^\s*[0-9.]+\s*mm\s*$',
        caseSensitive: false,
      ).hasMatch(paperSize ?? ''),
    );
  }

  Widget _pagePreview(BuildContext context, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = MediaQuery.sizeOf(context);
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackSize.width;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackSize.height * 0.7;
        final maxWidth = availableWidth > 24
            ? availableWidth - 24
            : availableWidth;
        final maxHeight = availableHeight > 24
            ? availableHeight - 24
            : availableHeight;
        final effectiveMedia = _effectiveMedia;
        final isRoll = effectiveMedia['type'] == 'roll';
        final mediaSize = reportTemplateMediaSizeMm(effectiveMedia);
        var width = isRoll ? maxWidth.clamp(180.0, 430.0).toDouble() : maxWidth;
        var height = isRoll
            ? maxHeight
            : width * mediaSize.height / mediaSize.width;
        if (!isRoll && height > maxHeight) {
          height = maxHeight;
          width = height * mediaSize.width / mediaSize.height;
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
                  border: isRoll
                      ? Border.symmetric(
                          vertical: BorderSide(color: Colors.grey.shade400),
                        )
                      : null,
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
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final effectiveMedia = _effectiveMedia;
              final paperLabel = effectiveMedia['type'] == 'roll'
                  ? reportTemplatePaperSizeFromMedia(effectiveMedia)
                  : (effectiveMedia['preset'] ??
                            reportTemplatePaperSizeFromMedia(effectiveMedia))
                        .toString();
              IconButton button({
                required IconData icon,
                required String tooltip,
                required VoidCallback? onPressed,
                Color? color,
              }) {
                return IconButton(
                  icon: Icon(icon, size: 20),
                  tooltip: tooltip,
                  onPressed: onPressed,
                  color: color,
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  constraints: compact
                      ? const BoxConstraints.tightFor(width: 34, height: 36)
                      : null,
                  padding: compact ? EdgeInsets.zero : null,
                );
              }

              return Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      compact ? 'پیش‌نمایش · $paperLabel' : 'پیش‌نمایش زنده',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        effectiveMedia['type'] == 'roll'
                            ? '$paperLabel · ارتفاع خودکار'
                            : '$paperLabel · ${effectiveMedia['orientation'] == 'landscape' ? 'افقی' : 'عمودی'}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (onRefresh != null)
                    button(
                      icon: Icons.refresh,
                      tooltip: 'بروزرسانی پیش‌نمایش',
                      onPressed: loading ? null : onRefresh,
                    ),
                  if (html != null && html!.isNotEmpty)
                    button(
                      icon: Icons.code_outlined,
                      tooltip: 'پیش‌نمایش سریع',
                      onPressed: onShowHtml,
                      color: !showPdf
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  if (onGeneratePdf != null)
                    button(
                      icon: Icons.picture_as_pdf,
                      tooltip: pdfBytes == null
                          ? 'ساخت پیش‌نمایش چاپ'
                          : 'پیش‌نمایش چاپ',
                      onPressed: loading ? null : onGeneratePdf,
                      color: showPdf
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  if (showPdf &&
                      kIsWeb &&
                      pdfBytes != null &&
                      pdfBytes!.isNotEmpty)
                    button(
                      icon: Icons.open_in_new,
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
              );
            },
          ),
        ),
        if (errors.isNotEmpty)
          Container(
            width: double.infinity,
            color: SemanticColorResolver.negative(
              context,
            ).withValues(alpha: 0.12),
            padding: const EdgeInsets.all(8),
            child: Text(
              errors.join('\n'),
              style: TextStyle(
                color: SemanticColorResolver.negative(context),
                fontSize: 12,
              ),
            ),
          ),
        if (warnings.isNotEmpty)
          Container(
            width: double.infinity,
            color: SemanticColorResolver.warning(
              context,
            ).withValues(alpha: 0.12),
            padding: const EdgeInsets.all(8),
            child: Text(
              warnings.join('\n'),
              style: TextStyle(
                color: SemanticColorResolver.warning(context),
                fontSize: 12,
              ),
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (html != null && html!.isNotEmpty)
                _pagePreview(
                  context,
                  ReportTemplateEmbeddedHtml(
                    key: ValueKey('html-preview-$previewRevision'),
                    html: html!,
                    previewMarginsMm: (_effectiveMedia['margins_mm'] as Map?)
                        ?.cast<String, dynamic>(),
                  ),
                )
              else if (pdfBytes != null && pdfBytes!.isNotEmpty)
                _pagePreview(
                  context,
                  ReportTemplateEmbeddedPdf(
                    key: ValueKey('pdf-preview-$previewRevision'),
                    bytes: pdfBytes!,
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

  void schedule(
    VoidCallback action, {
    Duration delay = const Duration(milliseconds: 600),
  }) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
