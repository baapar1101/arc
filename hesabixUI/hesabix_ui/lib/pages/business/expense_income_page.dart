import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/invoice/invoice_transactions_widget.dart';
import '../../widgets/invoice/account_tree_combobox_widget.dart';
import '../../models/invoice_type_model.dart';
import '../../models/invoice_transaction.dart';
import '../../models/account_model.dart';
import '../../models/expense_income_document.dart' as expense;
import '../../utils/number_formatters.dart';
import '../../services/expense_income_service.dart';
import '../../core/api_client.dart';
import '../../utils/number_normalizer.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../utils/snackbar_helper.dart';

class ExpenseIncomePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final ApiClient apiClient;
  const ExpenseIncomePage({super.key, required this.businessId, required this.authStore, required this.calendarController, required this.apiClient});

  @override
  State<ExpenseIncomePage> createState() => _ExpenseIncomePageState();
}

class _ExpenseIncomePageState extends State<ExpenseIncomePage> {
  // uuid reserved for future draft IDs if needed
  DateTime _docDate = DateTime.now();
  String _docType = 'expense';
  int? _currencyId;
  final _descriptionController = TextEditingController();

  final List<_ItemLine> _itemLines = <_ItemLine>[];
  final List<_TxLine> _txLines = <_TxLine>[];

  @override
  void initState() {
    super.initState();
    _currencyId = widget.authStore.currentBusiness?.defaultCurrency?.id;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('هزینه و درآمد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(value: 'expense', label: Text('هزینه')),
                      ButtonSegment<String>(value: 'income', label: Text('درآمد')),
                    ],
                    selected: {_docType},
                    onSelectionChanged: (s) => setState(() => _docType = s.first),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 220,
                    child: DateInputField(
                      value: _docDate,
                      calendarController: widget.calendarController,
                      onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                      labelText: 'تاریخ سند',
                      hintText: 'انتخاب تاریخ',
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 220,
                    child: CurrencyPickerWidget(
                      businessId: widget.businessId,
                      selectedCurrencyId: _currencyId,
                      onChanged: (currencyId) => setState(() => _currencyId = currencyId),
                      label: 'ارز',
                      hintText: 'انتخاب ارز',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'توضیحات کلی سند',
                  hintText: 'توضیحات اختیاری...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  // پنل سطرهای حساب (هزینه/درآمد)
                  Expanded(
                    child: _ItemsPanel(
                      businessId: widget.businessId,
                      lines: _itemLines,
                      documentType: _docType,
                      onChanged: (ls) => setState(() {
                        _itemLines
                          ..clear()
                          ..addAll(ls);
                      }),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  // پنل سطرهای طرف‌حساب (بازاستفاده از ویجت تراکنش‌ها)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: InvoiceTransactionsWidget(
                        transactions: const <InvoiceTransaction>[],
                        onChanged: (txs) => setState(() {
                          _txLines
                            ..clear()
                            ..addAll(txs.map(_TxLine.fromInvoiceTransaction));
                        }),
                        businessId: widget.businessId,
                        calendarController: widget.calendarController,
                        invoiceType: _docType == 'income' ? InvoiceType.sales : InvoiceType.purchase,
                        selectedCurrencyId: _currencyId,
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
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _chip('جمع اقلام', _sumItems()),
                        _chip('جمع طرف‌حساب', _sumTxs()),
                        _chip('اختلاف', (_docType == 'income' ? _sumTxs() - _sumItems() : _sumItems() - _sumTxs()), isError: _sumItems() != _sumTxs()),
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
    );
  }

  double _sumItems() => _itemLines.fold<double>(0, (p, e) => p + e.amount);
  double _sumTxs() => _txLines.fold<double>(0, (p, e) => p + e.amount);
  bool get _canSave => _currencyId != null && _itemLines.isNotEmpty && _txLines.isNotEmpty && _sumItems() == _sumTxs();

  Future<void> _save() async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final service = ExpenseIncomeService(widget.apiClient);
      final itemLinesData = _itemLines
          .map(
            (line) => expense.ItemLineData(
              accountId: line.account?.id,
              accountName: line.account?.displayName,
              amount: line.amount,
              description: line.description,
            ),
          )
          .toList();
      final counterpartyLinesData = _txLines.map((line) => line.toCounterpartyData()).toList();
      await service.create(
        businessId: widget.businessId,
        documentType: _docType,
        documentDate: _docDate,
        currencyId: _currencyId!,
        description: _descriptionController.text.trim(),
        itemLines: itemLinesData,
        counterpartyLines: counterpartyLinesData,
      );
      if (!mounted) return;
      Navigator.pop(context); // loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سند با موفقیت ثبت شد'), backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // loading
      SnackBarHelper.showError(context, message: 'خطا: $e');
    }
  }
}

class _ItemsPanel extends StatelessWidget {
  final int businessId;
  final List<_ItemLine> lines;
  final ValueChanged<List<_ItemLine>> onChanged;
  final String documentType; // 'expense' | 'income'
  const _ItemsPanel({required this.businessId, required this.lines, required this.onChanged, required this.documentType});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('اقلام هزینه/درآمد')),
              IconButton(
                onPressed: () {
                  final newLines = List<_ItemLine>.from(lines);
                  newLines.add(_ItemLine.empty());
                  onChanged(newLines);
                },
                icon: const Icon(Icons.add),
              ),
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
                      documentType: documentType,
                      line: lines[i],
                      onChanged: (l) {
                        final newLines = List<_ItemLine>.from(lines);
                        newLines[i] = l;
                        onChanged(newLines);
                      },
                      onDelete: () {
                        final newLines = List<_ItemLine>.from(lines);
                        newLines.removeAt(i);
                        onChanged(newLines);
                      },
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
  final String documentType; // 'expense' | 'income'
  final _ItemLine line;
  final ValueChanged<_ItemLine> onChanged;
  final VoidCallback onDelete;
  const _ItemTile({required this.businessId, required this.documentType, required this.line, required this.onChanged, required this.onDelete});

  @override
  State<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<_ItemTile> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.line.amount == 0 ? '' : widget.line.amount.toStringAsFixed(0);
    _descController.text = widget.line.description ?? '';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
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
                    documentTypeFilter: widget.documentType,
                    onChanged: (acc) => widget.onChanged(widget.line.copyWith(account: acc)),
                    label: 'حساب *',
                    hintText: 'انتخاب حساب هزینه/درآمد',
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(labelText: 'مبلغ', hintText: '1,000,000'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      EnglishDigitsFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (v) {
                      final val = double.tryParse(v.replaceAll(',', '')) ?? 0;
                      widget.onChanged(widget.line.copyWith(amount: val));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline)),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
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

class _TxLine {
  final String id;
  final DateTime date;
  final String type; // bank|cash_register|petty_cash|check|check_expense|person|account
  final double amount;
  final double? commission;
  final String? description;
  final String? bankId;
  final String? bankName;
  final String? cashRegisterId;
  final String? cashRegisterName;
  final String? pettyCashId;
  final String? pettyCashName;
  final String? checkId;
  final String? checkNumber;
  final String? personId;
  final String? personName;
  final String? accountId;
  final String? accountName;

  _TxLine({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    this.commission,
    this.description,
    this.bankId,
    this.bankName,
    this.cashRegisterId,
    this.cashRegisterName,
    this.pettyCashId,
    this.pettyCashName,
    this.checkId,
    this.checkNumber,
    this.personId,
    this.personName,
    this.accountId,
    this.accountName,
  });

  expense.CounterpartyLineData toCounterpartyData() {
    final mappedType = expense.TransactionType.fromValue(type) ?? expense.TransactionType.person;
    int? parseId(String? value) => value == null || value.isEmpty ? null : int.tryParse(value);
    return expense.CounterpartyLineData(
      transactionType: mappedType,
      amount: amount,
      transactionDate: date,
      description: description,
      commission: commission,
      bankAccountId: parseId(bankId),
      bankAccountName: bankName,
      cashRegisterId: parseId(cashRegisterId),
      cashRegisterName: cashRegisterName,
      pettyCashId: parseId(pettyCashId),
      pettyCashName: pettyCashName,
      checkId: parseId(checkId),
      checkNumber: checkNumber,
      personId: parseId(personId),
      personName: personName,
      accountId: parseId(accountId),
      accountName: accountName,
    );
  }

  factory _TxLine.fromInvoiceTransaction(InvoiceTransaction tx) => _TxLine(
        id: tx.id.isNotEmpty ? tx.id : const Uuid().v4(),
        date: tx.transactionDate,
        type: tx.type.value,
        amount: tx.amount.toDouble(),
        commission: tx.commission?.toDouble(),
        description: tx.description,
        bankId: tx.bankId,
        bankName: tx.bankName,
        cashRegisterId: tx.cashRegisterId,
        cashRegisterName: tx.cashRegisterName,
        pettyCashId: tx.pettyCashId,
        pettyCashName: tx.pettyCashName,
        checkId: tx.checkId,
        checkNumber: tx.checkNumber,
        personId: tx.personId,
        personName: tx.personName,
        accountId: tx.accountId,
        accountName: tx.accountName,
      );
}

Widget _chip(String label, double value, {bool isError = false}) {
  return Chip(
    label: Text('$label: ${formatWithThousands(value)}'),
    backgroundColor: isError ? Colors.red.shade100 : Colors.grey.shade200,
  );
}


