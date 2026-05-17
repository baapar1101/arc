import 'package:flutter/material.dart';
import '../../core/calendar_controller.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/invoice/invoice_transactions_widget.dart';
import '../../widgets/invoice/account_tree_combobox_widget.dart';
import '../../models/invoice_type_model.dart';
import '../../models/invoice_transaction.dart';
import '../../models/account_model.dart';
import '../../models/expense_income_document.dart' as expense;
import '../../services/expense_income_service.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/error_extractor.dart';
import '../../constants/frequent_description_scope.dart';
import '../../widgets/inputs/frequent_description_text_field.dart';

class ExpenseIncomeDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;
  final Map<String, dynamic>? initial; // optional document for edit
  const ExpenseIncomeDialog({super.key, required this.businessId, required this.calendarController, required this.authStore, required this.apiClient, this.initial});

  @override
  State<ExpenseIncomeDialog> createState() => _ExpenseIncomeDialogState();
}

class _ExpenseIncomeDialogState extends State<ExpenseIncomeDialog> {
  final _formKey = GlobalKey<FormState>();
  String _docType = 'expense';
  DateTime _docDate = DateTime.now();
  int? _currencyId;
  final _descCtrl = TextEditingController();

  final List<_ItemLine> _items = <_ItemLine>[];
  final List<InvoiceTransaction> _transactions = <InvoiceTransaction>[];

  @override
  void initState() {
    super.initState();
    _currencyId = widget.authStore.currentBusiness?.defaultCurrency?.id;
    if (widget.initial != null) {
      _docType = (widget.initial!['document_type'] as String?) ?? 'expense';
      final dd = widget.initial!['document_date'] as String?;
      if (dd != null) _docDate = DateTime.tryParse(dd) ?? _docDate;
      _descCtrl.text = (widget.initial!['description'] as String?) ?? '';
      // items and counterparties could be mapped if provided
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  static const double _balanceEpsilon = 1e-6;

  double _sumItems() => _items.fold<double>(0, (p, e) => p + e.amount);

  double _sumTx() =>
      _transactions.fold<double>(0, (p, e) => p + e.amount.toDouble());

  void _onBalanceFavoringItemsColumn() {
    if (_transactions.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'برای تعدیل مطابق اقلام، حداقل یک ردیف طرف‌حساب لازم است',
      );
      return;
    }
    final add = _sumItems() - _sumTx();
    if (add.abs() < _balanceEpsilon) return;
    final last = _transactions.length - 1;
    final newAmt = _transactions[last].amount.toDouble() + add;
    if (newAmt < -_balanceEpsilon) {
      SnackBarHelper.showError(
        context,
        message: 'مبلغ ردیف آخر طرف‌حساب پس از تعدیل منفی می‌شود.',
      );
      return;
    }
    setState(() {
      _transactions[last] =
          _transactions[last].copyWith(amount: newAmt);
    });
  }

  void _onBalanceFavoringCounterpartiesColumn() {
    if (_items.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'برای تعدیل مطابق طرف‌حساب، حداقل یک ردیف اقلام لازم است',
      );
      return;
    }
    final add = _sumTx() - _sumItems();
    if (add.abs() < _balanceEpsilon) return;
    final last = _items.length - 1;
    final newAmt = _items[last].amount + add;
    if (newAmt < -_balanceEpsilon) {
      SnackBarHelper.showError(
        context,
        message: 'مبلغ ردیف آخر اقلام پس از تعدیل منفی می‌شود.',
      );
      return;
    }
    setState(() {
      _items[last] = _items[last].copyWith(amount: newAmt);
    });
  }

  Widget _buildBalanceActionButtons() {
    final sumItems = _sumItems();
    final sumTx = _sumTx();
    if ((sumItems - sumTx).abs() < _balanceEpsilon) {
      return const SizedBox.shrink();
    }
    if (_items.isEmpty || _transactions.isEmpty) {
      return const SizedBox.shrink();
    }
    final addToTx = sumItems - sumTx;
    final lastT = _transactions.length - 1;
    final canMatchItems = _transactions[lastT].amount.toDouble() + addToTx >=
        -_balanceEpsilon;
    final addToItem = sumTx - sumItems;
    final lastI = _items.length - 1;
    final canMatchTx =
        _items[lastI].amount + addToItem >= -_balanceEpsilon;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: canMatchItems ? _onBalanceFavoringItemsColumn : null,
          icon: const Icon(Icons.receipt_long, size: 18),
          label: const Text('مطابق اقلام'),
        ),
        OutlinedButton.icon(
          onPressed: canMatchTx ? _onBalanceFavoringCounterpartiesColumn : null,
          icon: const Icon(Icons.payments, size: 18),
          label: const Text('مطابق طرف‌حساب'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sumItems = _items.fold<double>(0, (p, e) => p + e.amount);
    final sumTx = _transactions.fold<double>(0, (p, e) => p + (e.amount.toDouble()));
    final diff = (_docType == 'income') ? (sumTx - sumItems) : (sumItems - sumTx);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Expanded(child: Text('هزینه و درآمد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                    SegmentedButton<String>(
                      segments: const [ButtonSegment(value: 'expense', label: Text('هزینه')), ButtonSegment(value: 'income', label: Text('درآمد'))],
                      selected: {_docType},
                      onSelectionChanged: (s) => setState(() => _docType = s.first),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: DateInputField(
                        value: _docDate,
                        calendarController: widget.calendarController,
                        onChanged: (d) => setState(() => _docDate = d ?? _docDate),
                        labelText: 'تاریخ سند',
                        hintText: 'انتخاب تاریخ',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FrequentDescriptionTextField(
                  businessId: widget.businessId,
                  scope: FrequentDescriptionScope.expenseIncome,
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'توضیحات کلی سند', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _ItemsPanel(businessId: widget.businessId, lines: _items, onChanged: (ls) => setState(() { _items..clear()..addAll(ls);}))),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: InvoiceTransactionsWidget(
                          transactions: _transactions,
                          onChanged: (txs) => setState(() { _transactions..clear()..addAll(txs); }),
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          invoiceType: _docType == 'income' ? InvoiceType.sales : InvoiceType.purchase,
                          authStore: widget.authStore,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _chip('جمع اقلام', sumItems),
                              _chip('جمع طرف‌حساب', sumTx),
                              _chip('اختلاف', diff, isError: diff != 0),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _buildBalanceActionButtons(),
                          ),
                        ],
                      ),
                    ),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
                    const SizedBox(width: 8),
                    FilledButton.icon(onPressed: _canSave ? _save : null, icon: const Icon(Icons.save), label: const Text('ثبت')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSave {
    if (_currencyId == null) return false;
    if (_items.isEmpty || _transactions.isEmpty) return false;
    final sumItems = _items.fold<double>(0, (p, e) => p + e.amount);
    final sumTx = _transactions.fold<double>(0, (p, e) => p + (e.amount.toDouble()));
    return sumItems == sumTx;
  }

  Future<void> _save() async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final service = ExpenseIncomeService(widget.apiClient);
      final itemLines = _items
          .map(
            (line) => expense.ItemLineData(
              accountId: line.account?.id,
              accountName: line.account?.displayName,
              amount: line.amount,
              description: line.description,
            ),
          )
          .toList();
      final counterpartyLines = _transactions.map(_mapTransaction).toList();
      await service.create(
        businessId: widget.businessId,
        documentType: _docType,
        documentDate: _docDate,
        currencyId: _currencyId!,
        description: _descCtrl.text.trim(),
        itemLines: itemLines,
        counterpartyLines: counterpartyLines,
      );
      if (!mounted) return;
      Navigator.pop(context); // loading
      Navigator.pop(context, true); // dialog success
      SnackBarHelper.showSuccess(context, message: 'سند با موفقیت ثبت شد');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // loading
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  expense.CounterpartyLineData _mapTransaction(InvoiceTransaction tx) {
    final mappedType = expense.TransactionType.fromValue(tx.type.value) ?? expense.TransactionType.person;
    return expense.CounterpartyLineData(
      transactionType: mappedType,
      amount: tx.amount.toDouble(),
      transactionDate: tx.transactionDate,
      description: tx.description,
      commission: tx.commission?.toDouble(),
      bankAccountId: _parseId(tx.bankId),
      bankAccountName: tx.bankName,
      cashRegisterId: _parseId(tx.cashRegisterId),
      cashRegisterName: tx.cashRegisterName,
      pettyCashId: _parseId(tx.pettyCashId),
      pettyCashName: tx.pettyCashName,
      checkId: _parseId(tx.checkId),
      checkNumber: tx.checkNumber,
      personId: _parseId(tx.personId),
      personName: tx.personName,
      accountId: _parseId(tx.accountId),
      accountName: tx.accountName,
    );
  }

  int? _parseId(String? value) {
    if (value == null || value.isEmpty) return null;
    return int.tryParse(value);
  }
}

class _ItemsPanel extends StatelessWidget {
  final int businessId;
  final List<_ItemLine> lines;
  final ValueChanged<List<_ItemLine>> onChanged;
  const _ItemsPanel({required this.businessId, required this.lines, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('اقلام')),
              IconButton(onPressed: () { final nl = List<_ItemLine>.from(lines); nl.add(_ItemLine.empty()); onChanged(nl); }, icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('موردی ثبت نشده'))
                : ListView.separated(
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _ItemTile(
                      businessId: businessId,
                      line: lines[i],
                      onChanged: (l) { final nl = List<_ItemLine>.from(lines); nl[i] = l; onChanged(nl); },
                      onDelete: () { final nl = List<_ItemLine>.from(lines); nl.removeAt(i); onChanged(nl); },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatefulWidget {
  final int businessId;
  final _ItemLine line;
  final ValueChanged<_ItemLine> onChanged;
  final VoidCallback onDelete;
  const _ItemTile({required this.businessId, required this.line, required this.onChanged, required this.onDelete});

  @override
  State<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<_ItemTile> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
    _descCtrl.text = widget.line.description ?? '';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AccountTreeComboboxWidget(
                    businessId: widget.businessId,
                    selectedAccount: widget.line.account,
                    onChanged: (acc) => widget.onChanged(widget.line.copyWith(account: acc)),
                    label: 'حساب *',
                    hintText: 'انتخاب حساب',
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(labelText: 'مبلغ', hintText: '1,000,000'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      EnglishDigitsFormatter(),
                      ThousandsSeparatorInputFormatter(allowDecimal: false),
                    ],
                    onChanged: (v) {
                      final val = parseFormattedDouble(v) ?? 0;
                      widget.onChanged(widget.line.copyWith(amount: val));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline)),
              ],
            ),
            const SizedBox(height: 8),
            FrequentDescriptionTextField(
              businessId: widget.businessId,
              scope: FrequentDescriptionScope.expenseIncome,
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'توضیحات'),
              onChanged: (v) => widget.onChanged(widget.line.copyWith(description: v.trim().isEmpty ? null : v.trim())),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemLine {
  final Account? account;
  final double amount;
  final String? description;
  const _ItemLine({this.account, required this.amount, this.description});
  factory _ItemLine.empty() => const _ItemLine(amount: 0);
  _ItemLine copyWith({Account? account, double? amount, String? description}) => _ItemLine(
        account: account ?? this.account,
        amount: amount ?? this.amount,
        description: description ?? this.description,
      );
}

Widget _chip(String label, double value, {bool isError = false}) {
  return Chip(
    label: Text('$label: ${value.toStringAsFixed(0)}'),
    backgroundColor: isError ? Colors.red.shade100 : Colors.grey.shade200,
  );
}


