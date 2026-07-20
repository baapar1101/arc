import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';

/// ویجت نمایش صورت ترازنامه
class BalanceSheetStatementView extends StatelessWidget {
  final List<Map<String, dynamic>> statementLines;
  final bool hasCompare;
  final void Function(Map<String, dynamic> accountLine)? onAccountTap;

  const BalanceSheetStatementView({
    super.key,
    required this.statementLines,
    this.hasCompare = false,
    this.onAccountTap,
  });

  String _fmt(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (statementLines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.25),
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'صورت وضعیت مالی (ترازنامه)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          ...statementLines.map((line) => _buildLine(context, line)),
        ],
      ),
    );
  }

  Widget _buildLine(BuildContext context, Map<String, dynamic> line) {
    final cs = Theme.of(context).colorScheme;
    final type = line['type']?.toString() ?? '';
    final label = line['label_fa']?.toString() ?? '';
    final amount = _fmt(line['amount']);

    if (type == 'section_header') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      );
    }

    if (type == 'account') {
      final indent = (int.tryParse(line['level']?.toString() ?? '0') ?? 0) * 16.0;
      final canDrill = onAccountTap != null &&
          line['account_code'] != null &&
          line['account_code'].toString().isNotEmpty &&
          !line['account_code'].toString().startsWith('__');
      return InkWell(
        onTap: canDrill ? () => onAccountTap!(line) : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16 + indent, 8, 16, 8),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(line['account_code']?.toString() ?? '', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Text(line['account_name']?.toString() ?? '')),
                    if (canDrill)
                      Icon(Icons.menu_book_outlined, size: 16, color: cs.primary.withValues(alpha: 0.7)),
                  ],
                ),
              ),
              if (hasCompare) ...[
                SizedBox(width: 100, child: Text(_fmt(line['prior_amount']), textAlign: TextAlign.center)),
                SizedBox(width: 80, child: Text(_fmt(line['variance']), textAlign: TextAlign.center)),
              ],
              SizedBox(width: 120, child: Text(amount, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      );
    }

    if (type == 'subtotal' || type == 'grand_total') {
      final isHighlight = line['highlight'] == true;
      final isGrand = type == 'grand_total';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isGrand
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : (isHighlight ? cs.secondaryContainer.withValues(alpha: 0.25) : cs.surfaceContainerHighest.withValues(alpha: 0.35)),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontWeight: isGrand ? FontWeight.w800 : FontWeight.w700)),
            ),
            if (hasCompare) ...[
              SizedBox(width: 100, child: Text(_fmt(line['prior_amount']), textAlign: TextAlign.center)),
              SizedBox(width: 80, child: Text(_fmt(line['variance']), textAlign: TextAlign.center)),
            ],
            SizedBox(
              width: 120,
              child: Text(amount, textAlign: TextAlign.end, style: TextStyle(fontWeight: isGrand ? FontWeight.w800 : FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    if (type == 'equation_check') {
      final balanced = line['equation_balanced'] == true;
      return Container(
        padding: const EdgeInsets.all(16),
        color: balanced ? Colors.green.withValues(alpha: 0.08) : Colors.orange.withValues(alpha: 0.1),
        child: Row(
          children: [
            Icon(balanced ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                color: balanced ? Colors.green[700] : Colors.orange[800]),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(
              balanced ? 'متوازن' : 'اختلاف: ${_fmt(line['amount'])}',
              style: TextStyle(fontWeight: FontWeight.w700, color: balanced ? Colors.green[800] : Colors.orange[900]),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class BalanceSheetSummaryPanel extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final bool isMobile;

  const BalanceSheetSummaryPanel({super.key, required this.summary, required this.isMobile});

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  @override
  Widget build(BuildContext context) {
    if (summary == null) return const SizedBox.shrink();
    final s = summary!;
    final cards = [
      ('دارایی‌ها', s['total_assets'], const Color(0xFF1D4ED8)),
      ('بدهی‌ها', s['total_liabilities'], const Color(0xFFC2410C)),
      ('حقوق صاحبان سهام', s['total_equity'], const Color(0xFF7C3AED)),
      ('سود دوره جاری', s['current_period_profit'], const Color(0xFF15803D)),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards.map((c) {
        return SizedBox(
          width: isMobile ? double.infinity : 220,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: (c.$3).withValues(alpha: 0.25))),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.$1, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  Text(_fmt(c.$2), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.$3)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
