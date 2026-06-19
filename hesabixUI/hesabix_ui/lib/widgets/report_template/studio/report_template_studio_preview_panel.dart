import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../embedded_pdf_iframe.dart';

class ReportTemplateStudioPreviewPanel extends StatelessWidget {
  final bool loading;
  final Uint8List? pdfBytes;
  final List<String> errors;
  final List<String> warnings;
  final VoidCallback? onRefresh;

  const ReportTemplateStudioPreviewPanel({
    super.key,
    required this.loading,
    required this.pdfBytes,
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
            ],
          ),
        ),
        if (errors.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.red.shade50,
            padding: const EdgeInsets.all(8),
            child: Text(errors.join('\n'), style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
          ),
        if (warnings.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.all(8),
            child: Text(warnings.join('\n'), style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : pdfBytes == null
                  ? Center(
                      child: Text(
                        'پیش‌نمایش آماده می‌شود…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade200,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1 / 1.414,
                          child: Container(
                            margin: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
                              ],
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: ReportTemplateEmbeddedPdf(bytes: pdfBytes!),
                          ),
                        ),
                      ),
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
