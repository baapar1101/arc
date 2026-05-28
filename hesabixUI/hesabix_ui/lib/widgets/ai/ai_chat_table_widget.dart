import 'package:flutter/material.dart';

import 'ai_visualization_spec.dart';

export 'ai_visualization_spec.dart' show AITableSpec, AITableColumn;

class AIChatTableWidget extends StatelessWidget {
  static const int maxDisplayRows = 50;

  final AITableSpec spec;

  const AIChatTableWidget({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    if (!spec.hasData) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayRows = spec.rows.length > maxDisplayRows
        ? spec.rows.sublist(0, maxDisplayRows)
        : spec.rows;
    final truncated = spec.rows.length > maxDisplayRows;

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (spec.title != null && spec.title!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                spec.title!,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 56,
              horizontalMargin: 16,
              columnSpacing: 20,
              headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
              dataTextStyle: theme.textTheme.bodyMedium,
              columns: spec.columns
                  .map(
                    (c) => DataColumn(
                      label: Text(c.label),
                      numeric: c.align == 'right' || c.align == 'center',
                    ),
                  )
                  .toList(),
              rows: displayRows
                  .map(
                    (row) => DataRow(
                      cells: spec.columns
                          .map(
                            (c) => DataCell(
                              Align(
                                alignment: _cellAlignment(c.align),
                                child: Text(
                                  spec.cellText(c, row),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'نمایش $maxDisplayRows از ${spec.rows.length} ردیف',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  static Alignment _cellAlignment(String align) {
    switch (align.toLowerCase()) {
      case 'left':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      default:
        return Alignment.centerRight;
    }
  }
}
