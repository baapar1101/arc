import 'package:flutter/material.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// بنر هشدار کیفیت داده چندارزی (خطوط بدون معادل پایه).
class FxDataQualityBanner extends StatelessWidget {
  const FxDataQualityBanner({
    super.key,
    required this.quality,
    this.compact = false,
  });

  /// شیء `meta.fx_data_quality` از پاسخ گزارش.
  final Map<String, dynamic>? quality;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final q = quality;
    if (q == null) return const SizedBox.shrink();
    final severity = (q['severity'] ?? '').toString();
    if (severity != 'warning' && severity != 'high') {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final missing = q['missing_line_count'] ?? 0;
    final docs = q['affected_document_count'] ?? 0;
    final message = (q['message_fa'] ?? q['message_en'] ?? '').toString();
    final isHigh = severity == 'high';
    final bg = isHigh
        ? SemanticColorResolver.warning(context).withValues(alpha: 0.14)
        : cs.tertiaryContainer.withValues(alpha: 0.45);
    final fg = isHigh ? SemanticColorResolver.warning(context) : cs.onTertiaryContainer;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 8 : 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isHigh ? Icons.error_outline : Icons.warning_amber_rounded,
              color: fg,
              size: compact ? 18 : 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'کیفیت داده چندارزی',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: fg,
                      fontSize: compact ? 12 : 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.isNotEmpty
                        ? message
                        : '$missing خط در $docs سند بدون معادل پایه (*_base)',
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.92),
                      fontSize: compact ? 11.5 : 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
