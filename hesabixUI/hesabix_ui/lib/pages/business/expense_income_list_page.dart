import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../services/expense_income_service.dart';
import 'expense_income_dialog.dart';

class ExpenseIncomeListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;
  const ExpenseIncomeListPage({super.key, required this.businessId, required this.calendarController, required this.authStore, required this.apiClient});

  @override
  State<ExpenseIncomeListPage> createState() => _ExpenseIncomeListPageState();
}

class _ExpenseIncomeListPageState extends State<ExpenseIncomeListPage> {
  int _tabIndex = 0; // 0 expense, 1 income
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  int _skip = 0;
  int _take = 20;
  int _total = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final svc = ExpenseIncomeService(widget.apiClient);
      final res = await svc.list(
        businessId: widget.businessId,
        documentType: _tabIndex == 0 ? 'expense' : 'income',
        skip: _skip,
        take: _take,
      );
      final data = (res['items'] as List<dynamic>? ?? const <dynamic>[]).cast<Map<String, dynamic>>();
      setState(() {
        _items
          ..clear()
          ..addAll(data);
        _total = (res['pagination']?['total'] as int?) ?? data.length;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('هزینه و درآمد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                  SegmentedButton<int>(
                    segments: const [ButtonSegment(value: 0, label: Text('هزینه')), ButtonSegment(value: 1, label: Text('درآمد'))],
                    selected: {_tabIndex},
                    onSelectionChanged: (s) async {
                      setState(() { _tabIndex = s.first; _skip = 0; });
                      await _load();
                    },
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => ExpenseIncomeDialog(
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          authStore: widget.authStore,
                          apiClient: widget.apiClient,
                        ),
                      );
                      if (ok == true) _load();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Card(
                margin: const EdgeInsets.all(8),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                        ? const Center(child: Text('داده‌ای یافت نشد'))
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final it = _items[i];
                              final code = (it['code'] ?? '').toString();
                              final type = (it['document_type'] ?? '').toString();
                              final dateStr = (it['document_date'] ?? '').toString();
                              final date = dateStr.isNotEmpty ? DateTime.tryParse(dateStr) : null;
                              final sumItems = _sum(it['items'] as List<dynamic>?);
                              final sumCps = _sum(it['counterparties'] as List<dynamic>?);
                              return ListTile(
                                title: Text(code),
                                subtitle: Text('${type == 'income' ? 'درآمد' : 'هزینه'}  •  ${date != null ? HesabixDateUtils.formatForDisplay(date, true) : '-'}'),
                                trailing: Text('${formatWithThousands(sumItems)} | ${formatWithThousands(sumCps)}'),
                                onTap: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => ExpenseIncomeDialog(
                                      businessId: widget.businessId,
                                      calendarController: widget.calendarController,
                                      authStore: widget.authStore,
                                      apiClient: widget.apiClient,
                                      initial: it,
                                    ),
                                  );
                                  if (ok == true) _load();
                                },
                              );
                            },
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text('$_skip - ${_skip + _items.length} از $_total'),
                  const Spacer(),
                  IconButton(onPressed: _skip <= 0 ? null : () { setState(() { _skip = (_skip - _take).clamp(0, _total); }); _load(); }, icon: const Icon(Icons.chevron_right)),
                  IconButton(onPressed: (_skip + _take) >= _total ? null : () { setState(() { _skip = _skip + _take; }); _load(); }, icon: const Icon(Icons.chevron_left)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  double _sum(List<dynamic>? lines) {
    if (lines == null) return 0;
    double s = 0;
    for (final l in lines) {
      final m = (l as Map<String, dynamic>);
      s += ((m['debit'] ?? 0) as num).toDouble();
      s += ((m['credit'] ?? 0) as num).toDouble();
    }
    return s;
  }
}


