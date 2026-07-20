import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';

/// فیلترهای مشترک گزارش سود و زیان
class PnlReportFilters extends StatelessWidget {
  final bool isCumulative;
  final bool isMobile;
  final List<Map<String, dynamic>> fiscalYears;
  final List<Map<String, dynamic>> currencies;
  final int? selectedFiscalYearId;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int? selectedCurrencyId;
  final int? selectedProjectId;
  final int businessId;
  final CalendarController calendarController;
  final bool includeZeroBalance;
  final String? compareMode;
  final ValueChanged<int?> onFiscalYearChanged;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final ValueChanged<int?> onCurrencyChanged;
  final ValueChanged<int?> onProjectChanged;
  final ValueChanged<bool> onIncludeZeroBalanceChanged;
  final ValueChanged<String?> onCompareModeChanged;

  const PnlReportFilters({
    super.key,
    required this.isCumulative,
    required this.isMobile,
    required this.fiscalYears,
    required this.currencies,
    required this.selectedFiscalYearId,
    required this.fromDate,
    required this.toDate,
    required this.selectedCurrencyId,
    required this.selectedProjectId,
    required this.businessId,
    required this.calendarController,
    required this.includeZeroBalance,
    required this.compareMode,
    required this.onFiscalYearChanged,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onCurrencyChanged,
    required this.onProjectChanged,
    required this.onIncludeZeroBalanceChanged,
    required this.onCompareModeChanged,
  });

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fieldWidth = isMobile ? double.infinity : 220.0;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'فیلترها',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<int>(
                    value: selectedFiscalYearId,
                    isExpanded: true,
                    decoration: _decoration('سال مالی'),
                    items: fiscalYears
                        .map(
                          (fy) => DropdownMenuItem<int>(
                            value: fy['id'] as int?,
                            child: Text(
                              fy['title']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onFiscalYearChanged,
                  ),
                ),
                if (!isCumulative)
                  SizedBox(
                    width: fieldWidth,
                    child: DateInputField(
                      value: fromDate,
                      calendarController: calendarController,
                      labelText: 'از تاریخ',
                      onChanged: onFromDateChanged,
                    ),
                  ),
                SizedBox(
                  width: fieldWidth,
                  child: DateInputField(
                    value: toDate,
                    calendarController: calendarController,
                    labelText: isCumulative ? 'تا تاریخ (تجمعی)' : 'تا تاریخ',
                    onChanged: onToDateChanged,
                  ),
                ),
                if (isCumulative)
                  SizedBox(
                    width: isMobile ? double.infinity : 280,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'شروع: ابتدای سال مالی',
                              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.75)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<int>(
                    value: selectedCurrencyId,
                    isExpanded: true,
                    decoration: _decoration('ارز'),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('همه ارزها')),
                      ...currencies.map((c) {
                        final id = c['id'] as int?;
                        final code = (c['code'] ?? '').toString();
                        final name = (c['name'] ?? '').toString();
                        final displayName = code.isNotEmpty ? '$code - $name' : name;
                        return DropdownMenuItem<int>(
                          key: ValueKey('currency_$id'),
                          value: id,
                          child: Text(displayName, overflow: TextOverflow.ellipsis, maxLines: 1),
                        );
                      }),
                    ],
                    onChanged: onCurrencyChanged,
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 260,
                  child: ProjectSelectorWidget(
                    businessId: businessId,
                    apiClient: ApiClient(),
                    selectedProjectId: selectedProjectId,
                    onChanged: onProjectChanged,
                    allowNull: true,
                    labelText: 'پروژه (همه)',
                    calendarController: calendarController,
                    isDense: true,
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 220,
                  child: FilterChip(
                    label: const Text('نمایش حساب‌های بدون گردش'),
                    selected: includeZeroBalance,
                    onSelected: onIncludeZeroBalanceChanged,
                    avatar: Icon(
                      includeZeroBalance ? Icons.check_circle : Icons.circle_outlined,
                      size: 18,
                    ),
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 240,
                  child: DropdownButtonFormField<String?>(
                    value: compareMode,
                    isExpanded: true,
                    decoration: _decoration('مقایسه دوره‌ای'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('بدون مقایسه')),
                      if (!isCumulative)
                        const DropdownMenuItem<String?>(
                          value: 'prior_period',
                          child: Text('مقایسه با دوره قبل'),
                        ),
                      DropdownMenuItem<String?>(
                        value: 'prior_year',
                        child: Text(
                          isCumulative ? 'مقایسه با سال مالی قبل' : 'مقایسه با همان بازه سال قبل',
                        ),
                      ),
                    ],
                    onChanged: onCompareModeChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PnlSummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
  final dynamic priorValue;
  final dynamic variance;

  const PnlSummaryMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
    this.priorValue,
    this.variance,
  });

  String _fmt(dynamic v) {
    if (v == null) return '';
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  @override
  Widget build(BuildContext context) {
    final hasCompare = priorValue != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
                ),
                if (hasCompare) ...[
                  const SizedBox(height: 4),
                  Text(
                    'دوره قبل: ${_fmt(priorValue)} · تغییر: ${_fmt(variance)}',
                    style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.75)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PnlSummaryPanel extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final Map<String, dynamic>? comparison;
  final bool isMobile;
  final bool isCumulative;

  const PnlSummaryPanel({
    super.key,
    required this.summary,
    this.comparison,
    required this.isMobile,
    this.isCumulative = false,
  });

  String _fmt(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  double _dbl(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (summary == null) return const SizedBox.shrink();

    final suffix = isCumulative ? ' (تجمعی)' : '';
    final net = _dbl(summary!['net_profit_after_tax'] ?? summary!['net_profit_loss']);
    final cards = [
      PnlSummaryMetric(
        label: 'جمع درآمد$suffix',
        value: _fmt(summary!['total_revenue']),
        icon: Icons.south_west_rounded,
        color: const Color(0xFF15803D),
        background: const Color(0xFFECFDF5),
        priorValue: comparison?['total_revenue']?['prior'],
        variance: comparison?['total_revenue']?['variance'],
      ),
      PnlSummaryMetric(
        label: 'سود قبل از مالیات$suffix',
        value: _fmt(summary!['profit_before_tax']),
        icon: Icons.analytics_outlined,
        color: const Color(0xFF0369A1),
        background: const Color(0xFFE0F2FE),
        priorValue: comparison?['profit_before_tax']?['prior'],
        variance: comparison?['profit_before_tax']?['variance'],
      ),
      PnlSummaryMetric(
        label: 'مالیات بر درآمد$suffix',
        value: _fmt(summary!['total_tax_expense']),
        icon: Icons.receipt_long_outlined,
        color: const Color(0xFF9A3412),
        background: const Color(0xFFFFF7ED),
        priorValue: comparison?['total_tax_expense']?['prior'],
        variance: comparison?['total_tax_expense']?['variance'],
      ),
      PnlSummaryMetric(
        label: 'سود خالص پس از مالیات$suffix',
        value: _fmt(summary!['net_profit_after_tax'] ?? summary!['net_profit_loss']),
        icon: net >= 0 ? Icons.insights_rounded : Icons.warning_amber_rounded,
        color: net >= 0 ? const Color(0xFF1D4ED8) : const Color(0xFFC2410C),
        background: net >= 0 ? const Color(0xFFEFF6FF) : const Color(0xFFFFF7ED),
        priorValue: comparison?['net_profit_after_tax']?['prior'],
        variance: comparison?['net_profit_after_tax']?['variance'],
      ),
    ];

    if (isMobile) {
      return Column(
        children: [for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 8), cards[i]]],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cards.map((c) => SizedBox(width: 280, child: c)).toList(),
    );
  }
}

/// صورت سود و زیان سلسله‌مراتبی
class PnlStatementView extends StatelessWidget {
  final List<Map<String, dynamic>> statementLines;
  final void Function(Map<String, dynamic> accountLine)? onAccountTap;

  const PnlStatementView({
    super.key,
    required this.statementLines,
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
                Icon(Icons.account_balance_wallet_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'صورت سود و زیان',
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
    final isHighlight = line['highlight'] == true;

    if (type == 'section_header') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      );
    }

    if (type == 'account') {
      final hasCompare = line['prior_amount'] != null;
      final canDrill = onAccountTap != null &&
          line['account_code'] != null &&
          line['account_code'].toString().isNotEmpty;
      return InkWell(
        onTap: canDrill ? () => onAccountTap!(line) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  line['account_code']?.toString() ?? '',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65)),
                ),
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
              SizedBox(width: 100, child: Text(amount, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w500))),
              if (hasCompare) ...[
                SizedBox(
                  width: 100,
                  child: Text(
                    _fmt(line['prior_amount']),
                    textAlign: TextAlign.end,
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    _fmt(line['variance']),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: ((line['variance'] as num?) ?? 0) >= 0
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB91C1C),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (type == 'subtotal' || type == 'grand_total') {
      final isGrand = type == 'grand_total';
      final net = (line['amount'] as num?)?.toDouble() ?? 0;
      final hasCompare = line['prior_amount'] != null;
      final bg = isGrand
          ? (net >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED))
          : (isHighlight ? const Color(0xFFE8F4FD) : const Color(0xFFFFF8E1));
      final color = isGrand
          ? (net >= 0 ? const Color(0xFF065F46) : const Color(0xFF9A3412))
          : cs.onSurface;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: isGrand ? 15 : 13),
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                amount,
                textAlign: TextAlign.end,
                style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: isGrand ? 16 : 14),
              ),
            ),
            if (hasCompare) ...[
              SizedBox(
                width: 100,
                child: Text(
                  _fmt(line['prior_amount']),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.85)),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  _fmt(line['variance']),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class PnlDetailSection extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color accent;
  final String emptyText;
  final List<String> headers;
  final List<List<String>> rows;
  final String totalLabel;
  final String totalValue;

  const PnlDetailSection({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    required this.accent,
    required this.emptyText,
    required this.headers,
    required this.rows,
    required this.totalLabel,
    required this.totalValue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);

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
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text('$count مورد', style: Theme.of(context).textTheme.labelMedium),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Center(
                child: Text(emptyText, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final table = DataTable(
                  headingRowHeight: 42,
                  dataRowMinHeight: 38,
                  dataRowMaxHeight: 50,
                  columnSpacing: isMobile ? 14 : 24,
                  horizontalMargin: isMobile ? 10 : 14,
                  headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerHighest.withValues(alpha: 0.45)),
                  columns: [
                    for (final h in headers)
                      DataColumn(
                        label: Text(h, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                        cells: [
                          for (var i = 0; i < row.length; i++)
                            DataCell(
                              Text(
                                row[i],
                                textAlign: i >= 2 ? TextAlign.center : TextAlign.start,
                                style: i == row.length - 1
                                    ? const TextStyle(fontWeight: FontWeight.w600)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    DataRow(
                      color: WidgetStatePropertyAll(cs.surfaceContainerHighest.withValues(alpha: 0.55)),
                      cells: [
                        const DataCell(SizedBox.shrink()),
                        DataCell(Text(totalLabel, style: const TextStyle(fontWeight: FontWeight.w800))),
                        const DataCell(SizedBox.shrink()),
                        const DataCell(SizedBox.shrink()),
                        DataCell(
                          Text(
                            totalValue,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w800, color: accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                );

                if (constraints.maxWidth < 720) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 720),
                      child: table,
                    ),
                  );
                }
                return table;
              },
            ),
        ],
      ),
    );
  }
}

/// کمک‌کننده ساخت ردیف‌های جدول تفصیلی
class PnlTableRows {
  static String fmt(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  static List<List<String>> revenueRows(List<Map<String, dynamic>> items) => items
      .map(
        (item) => [
          item['account_code']?.toString() ?? '',
          item['account_name']?.toString() ?? '',
          fmt(item['credit']),
          fmt(item['debit']),
          fmt(item['revenue'] ?? item['amount']),
        ],
      )
      .toList();

  static List<List<String>> expenseRows(List<Map<String, dynamic>> items) => items
      .map(
        (item) => [
          item['account_code']?.toString() ?? '',
          item['account_name']?.toString() ?? '',
          fmt(item['debit']),
          fmt(item['credit']),
          fmt(item['expense'] ?? item['amount']),
        ],
      )
      .toList();
}
