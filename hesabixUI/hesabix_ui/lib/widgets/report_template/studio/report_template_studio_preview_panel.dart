import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../utils/web/web_utils.dart' as web_utils;
import '../embedded_pdf_iframe.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class ReportTemplateStudioPreviewPanel extends StatelessWidget {
  final bool loading;
  final Uint8List? pdfBytes;
  final int previewRevision;
  final List<String> errors;
  final List<String> warnings;
  final VoidCallback? onRefresh;

  const ReportTemplateStudioPreviewPanel({
    super.key,
    required this.loading,
    required this.pdfBytes,
    this.previewRevision = 0,
    this.errors = const [],
    this.warnings = const [],
    this.onRefresh,
  });

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
              if (kIsWeb && pdfBytes != null && pdfBytes!.isNotEmpty)
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
              if (pdfBytes != null && pdfBytes!.isNotEmpty)
                ColoredBox(
                  color: Colors.grey.shade200,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
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
                      child: SizedBox.expand(
                        child: ReportTemplateEmbeddedPdf(
                          key: ValueKey('preview-$previewRevision'),
                          bytes: pdfBytes!,
                        ),
                      ),
                    ),
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
