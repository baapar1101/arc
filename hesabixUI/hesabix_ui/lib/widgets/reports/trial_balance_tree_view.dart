import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/utils/financial_report_navigation.dart';

/// نمای درختی تراز آزمایشی با امکان drill-down به دفتر کل.
class TrialBalanceTreeView extends StatefulWidget {
  final int businessId;
  final List<Map<String, dynamic>> accounts;
  final int columnMode;
  final FinancialReportLedgerContext ledgerContext;
  final Map<String, dynamic>? summary;

  const TrialBalanceTreeView({
    super.key,
    required this.businessId,
    required this.accounts,
    required this.columnMode,
    required this.ledgerContext,
    this.summary,
  });

  @override
  State<TrialBalanceTreeView> createState() => _TrialBalanceTreeViewState();
}

class _TrialBalanceTreeViewState extends State<TrialBalanceTreeView> {
  final Map<String, bool> _expanded = {};

  String _fmt(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  void _toggle(String key) {
    setState(() => _expanded[key] = !(_expanded[key] ?? false));
  }

  void _openLedger(Map<String, dynamic> account) {
    final route = buildGeneralLedgerRoute(
      businessId: widget.businessId,
      accountRow: account,
      context: widget.ledgerContext,
    );
    context.push(route);
  }

  List<Widget> _amountCells(Map<String, dynamic> account) {
    final cells = <Widget>[];
    if (widget.columnMode >= 6) {
      cells.addAll([
        _amountCell(_fmt(account['opening_debit'])),
        _amountCell(_fmt(account['opening_credit'])),
      ]);
    }
    if (widget.columnMode >= 4) {
      cells.addAll([
        _amountCell(_fmt(account['period_debit'])),
        _amountCell(_fmt(account['period_credit'])),
      ]);
    }
    cells.addAll([
      _amountCell(_fmt(account['closing_debit'])),
      _amountCell(_fmt(account['closing_credit'])),
    ]);
    return cells;
  }

  Widget _amountCell(String text) {
    return SizedBox(
      width: 110,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(text, textAlign: TextAlign.end),
      ),
    );
  }

  Widget _buildHeader() {
    final labels = <String>[];
    if (widget.columnMode >= 6) {
      labels.addAll(['مانده ابتدا (بدهکار)', 'مانده ابتدا (بستانکار)']);
    }
    if (widget.columnMode >= 4) {
      labels.addAll(['گردش بدهکار', 'گردش بستانکار']);
    }
    labels.addAll(['مانده پایان (بدهکار)', 'مانده پایان (بستانکار)']);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          const SizedBox(width: 28),
          const SizedBox(width: 90, child: Text('کد', style: TextStyle(fontWeight: FontWeight.w700))),
          const Expanded(child: Text('نام حساب', style: TextStyle(fontWeight: FontWeight.w700))),
          ...labels.map(
            (l) => SizedBox(
              width: 110,
              child: Text(l, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _buildNode(Map<String, dynamic> account, int level) {
    final accountId = account['account_id'];
    if (accountId == null) return const SizedBox.shrink();
    final key = accountId.toString();
    final children = List<Map<String, dynamic>>.from(account['children'] ?? []);
    final hasChildren = account['has_children'] == true || children.isNotEmpty;
    final expanded = _expanded[key] ?? (level < 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (hasChildren) {
                _toggle(key);
              } else {
                _openLedger(account);
              }
            },
            onLongPress: () => _openLedger(account),
            child: Padding(
              padding: EdgeInsets.only(right: level * 16.0, left: 8, top: 6, bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: hasChildren
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            onPressed: () => _toggle(key),
                            icon: Icon(expanded ? Icons.expand_more : Icons.chevron_left),
                          )
                        : const SizedBox.shrink(),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(account['account_code']?.toString() ?? '', style: const TextStyle(fontFeatures: [])),
                  ),
                  Expanded(
                    child: Text(
                      account['account_name']?.toString() ?? '',
                      style: TextStyle(fontWeight: hasChildren ? FontWeight.w700 : FontWeight.normal),
                    ),
                  ),
                  ..._amountCells(account),
                  IconButton(
                    tooltip: 'دفتر کل',
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    onPressed: () => _openLedger(account),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasChildren && expanded)
          ...children.map((child) => _buildNode(child, level + 1)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final balanceValid = summary?['balance_valid'] == true;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    balanceValid ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                    color: balanceValid ? Colors.green[700] : Colors.orange[800],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      balanceValid
                          ? 'تراز آزمایشی متوازن است'
                          : (summary['balance_error']?.toString() ?? 'تراز آزمایشی نامتوازن'),
                      style: TextStyle(
                        color: balanceValid ? Colors.green[800] : Colors.orange[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    'برای مشاهده دفتر کل روی حساب بزنید',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          _buildHeader(),
          ...widget.accounts.map((a) => _buildNode(a, 0)),
        ],
      ),
    );
  }
}
