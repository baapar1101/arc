import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/person_model.dart';
import '../../models/quick_sales_change_resolution.dart';
import '../../services/person_service.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';
import '../invoice/bank_account_combobox_widget.dart';
import '../invoice/cash_register_combobox_widget.dart';
import '../invoice/person_combobox_widget.dart';

class QuickSalesChangeResolutionDialog extends StatefulWidget {
  final int businessId;
  final int? currencyId;
  final num overpaymentAmount;
  final String currencyUnit;
  final int decimalPlaces;
  final String customerName;
  final int? customerId;
  final bool isAnonymousCustomer;
  final QuickSalesChangeResolution? initialValue;

  const QuickSalesChangeResolutionDialog({
    super.key,
    required this.businessId,
    required this.currencyId,
    required this.overpaymentAmount,
    required this.currencyUnit,
    required this.decimalPlaces,
    required this.customerName,
    required this.customerId,
    required this.isAnonymousCustomer,
    this.initialValue,
  });

  @override
  State<QuickSalesChangeResolutionDialog> createState() =>
      _QuickSalesChangeResolutionDialogState();
}

class _QuickSalesChangeResolutionDialogState
    extends State<QuickSalesChangeResolutionDialog> {
  static const _uuid = Uuid();
  final List<_ChangeAllocationDraft> _rows = [];
  bool _creditRemainder = false;

  num get _epsilon {
    if (widget.decimalPlaces <= 0) return 0.5;
    var value = 1.0;
    for (var i = 0; i < widget.decimalPlaces; i++) {
      value /= 10;
    }
    return value / 2;
  }

  num get _returned => _rows.fold<num>(0, (sum, row) => sum + row.amount);
  num get _credit => _creditRemainder
      ? (widget.overpaymentAmount - _returned).clamp(
          0,
          widget.overpaymentAmount,
        )
      : 0;
  num get _unresolved => (widget.overpaymentAmount - _returned - _credit).clamp(
    0,
    widget.overpaymentAmount,
  );
  bool get _isOverAllocated => _returned - widget.overpaymentAmount > _epsilon;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    if (initial != null &&
        (initial.overpaymentAmount - widget.overpaymentAmount).abs() <=
            _epsilon) {
      for (final allocation in initial.allocations) {
        final row = _ChangeAllocationDraft.fromAllocation(
          allocation,
          decimalPlaces: widget.decimalPlaces,
        );
        _rows.add(row);
        if (allocation.sourceType == QuickSalesChangeSourceType.person) {
          unawaited(_loadPerson(row));
        }
      }
      _creditRemainder = initial.creditAmount > _epsilon;
    }
  }

  Future<void> _loadPerson(_ChangeAllocationDraft row) async {
    try {
      final person = await PersonService().getPerson(row.sourceId!);
      if (!mounted || !_rows.contains(row)) return;
      setState(() {
        row.person = person;
        row.sourceName = person.displayName;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  String _format(num value) =>
      formatWithThousands(value, decimalPlaces: widget.decimalPlaces);

  void _addRow(QuickSalesChangeSourceType type) {
    final available = (widget.overpaymentAmount - _returned).clamp(
      0,
      widget.overpaymentAmount,
    );
    final row = _ChangeAllocationDraft(
      id: _uuid.v4(),
      sourceType: type,
      amount: available,
      decimalPlaces: widget.decimalPlaces,
    );
    setState(() => _rows.add(row));
  }

  void _removeRow(_ChangeAllocationDraft row) {
    setState(() => _rows.remove(row));
    row.dispose();
  }

  String? _validationMessage() {
    if (_isOverAllocated) {
      return 'جمع مبالغ برگشتی از مبلغ اضافه‌دریافت بیشتر است.';
    }
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (row.sourceId == null || row.sourceId! <= 0) {
        return 'منبع ردیف ${i + 1} را انتخاب کنید.';
      }
      if (row.sourceType == QuickSalesChangeSourceType.person &&
          row.sourceId == widget.customerId) {
        return 'مشتری فاکتور نمی‌تواند منبع برگشت وجه همان فاکتور باشد.';
      }
      if (row.amount <= _epsilon) {
        return 'مبلغ ردیف ${i + 1} باید بیشتر از صفر باشد.';
      }
      if (row.commission < 0) {
        return 'کارمزد بانکی نمی‌تواند منفی باشد.';
      }
    }
    if (_unresolved > _epsilon) {
      return 'هنوز ${_format(_unresolved)} ${widget.currencyUnit} تعیین تکلیف نشده است.';
    }
    if (_rows.isEmpty && _credit <= _epsilon) {
      return 'حداقل یک روش برگشت یا بستانکاری مشتری را انتخاب کنید.';
    }
    return null;
  }

  void _submit() {
    final validation = _validationMessage();
    if (validation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validation), backgroundColor: Colors.red),
      );
      return;
    }
    Navigator.of(context).pop(
      QuickSalesChangeResolution(
        overpaymentAmount: widget.overpaymentAmount,
        allocations: _rows
            .map(
              (row) => QuickSalesChangeAllocation(
                id: row.id,
                sourceType: row.sourceType,
                sourceId: row.sourceId!,
                sourceName: row.sourceName,
                amount: row.amount,
                commission: row.sourceType == QuickSalesChangeSourceType.bank
                    ? row.commission
                    : 0,
              ),
            )
            .toList(),
        creditAmount: _credit,
      ),
    );
  }

  void _continueAsCustomerCredit() {
    Navigator.of(context).pop(
      QuickSalesChangeResolution(
        overpaymentAmount: widget.overpaymentAmount,
        allocations: const [],
        creditAmount: widget.overpaymentAmount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final validation = _validationMessage();
    return AlertDialog(
      title: const Text('تعیین تکلیف اضافه‌دریافت'),
      content: SizedBox(
        width: 820,
        height: 590,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                children: [
                  Text('مشتری دریافت‌کننده: ${widget.customerName}'),
                  Text(
                    'اضافه‌دریافت: ${_format(widget.overpaymentAmount)} ${widget.currencyUnit}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'منابع وجه برگشتی',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                PopupMenuButton<QuickSalesChangeSourceType>(
                  tooltip: 'افزودن منبع برگشت',
                  onSelected: _addRow,
                  itemBuilder: (context) => QuickSalesChangeSourceType.values
                      .map(
                        (type) =>
                            PopupMenuItem(value: type, child: Text(type.label)),
                      )
                      .toList(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 18, color: cs.onPrimary),
                          const SizedBox(width: 6),
                          Text(
                            'افزودن منبع',
                            style: TextStyle(color: cs.onPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _rows.isEmpty
                  ? Center(
                      child: Text(
                        'برای پرداخت به مشتری، صندوق، بانک یا شخص را اضافه کنید.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _buildRow(context, _rows[index], index),
                    ),
            ),
            const Divider(),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _creditRemainder,
              onChanged: widget.isAnonymousCustomer
                  ? null
                  : (value) => setState(() => _creditRemainder = value),
              title: const Text('باقی‌مانده به بستانکاری مشتری منتقل شود'),
              subtitle: Text(
                widget.isAnonymousCustomer
                    ? 'برای مشتری ناشناس امکان ایجاد بستانکاری وجود ندارد.'
                    : 'مبلغ بستانکاری: ${_format(_credit)} ${widget.currencyUnit}',
              ),
            ),
            Wrap(
              spacing: 20,
              runSpacing: 6,
              children: [
                Text('برگشت به مشتری: ${_format(_returned)}'),
                Text('بستانکاری: ${_format(_credit)}'),
                Text(
                  'تعیین‌تکلیف‌نشده: ${_format(_unresolved)}',
                  style: TextStyle(
                    color: validation == null ? cs.primary : cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        if (!widget.isAnonymousCustomer)
          TextButton.icon(
            onPressed: _continueAsCustomerCredit,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('ادامه بدون تعیین تکلیف'),
          ),
        FilledButton.icon(
          onPressed: validation == null ? _submit : null,
          icon: const Icon(Icons.check),
          label: const Text('تأیید تعیین تکلیف'),
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    _ChangeAllocationDraft row,
    int index,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: CircleAvatar(radius: 15, child: Text('${index + 1}')),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: _buildSourcePicker(row)),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: row.amountController,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  ThousandsSeparatorInputFormatter(
                    allowDecimal: widget.decimalPlaces > 0,
                  ),
                ],
                decoration: InputDecoration(
                  labelText: 'مبلغ برگشتی',
                  suffixText: widget.currencyUnit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (row.sourceType == QuickSalesChangeSourceType.bank) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: row.commissionController,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.end,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    ThousandsSeparatorInputFormatter(
                      allowDecimal: widget.decimalPlaces > 0,
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'کارمزد انتقال',
                    suffixText: widget.currencyUnit,
                    helperText: 'هزینه جدا از مبلغ مشتری',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
            IconButton(
              tooltip: 'حذف ردیف',
              color: cs.error,
              onPressed: () => _removeRow(row),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcePicker(_ChangeAllocationDraft row) =>
      switch (row.sourceType) {
        QuickSalesChangeSourceType.cashRegister => CashRegisterComboboxWidget(
          key: ValueKey('change-cash-${row.id}'),
          businessId: widget.businessId,
          selectedRegisterId: row.sourceId?.toString(),
          filterCurrencyId: widget.currencyId,
          dense: true,
          label: 'صندوق پرداخت‌کننده',
          isRequired: true,
          onChanged: (option) => setState(() {
            row.sourceId = int.tryParse(option?.id ?? '');
            row.sourceName = option?.name ?? '';
          }),
        ),
        QuickSalesChangeSourceType.bank => BankAccountComboboxWidget(
          key: ValueKey('change-bank-${row.id}'),
          businessId: widget.businessId,
          selectedAccountId: row.sourceId?.toString(),
          filterCurrencyId: widget.currencyId,
          dense: true,
          label: 'بانک پرداخت‌کننده',
          isRequired: true,
          onChanged: (option) => setState(() {
            row.sourceId = int.tryParse(option?.id ?? '');
            row.sourceName = option?.name ?? '';
          }),
        ),
        QuickSalesChangeSourceType.person => PersonComboboxWidget(
          key: ValueKey('change-person-${row.id}'),
          businessId: widget.businessId,
          selectedPerson: row.person,
          dense: true,
          showFinancialBalance: true,
          label: 'شخص پرداخت‌کننده',
          hintText: row.sourceName.isEmpty ? 'انتخاب شخص' : row.sourceName,
          isRequired: true,
          onChanged: (person) => setState(() {
            row.person = person;
            row.sourceId = person?.id;
            row.sourceName = person?.displayName ?? '';
          }),
        ),
      };
}

class _ChangeAllocationDraft {
  final String id;
  final QuickSalesChangeSourceType sourceType;
  int? sourceId;
  String sourceName;
  Person? person;
  final TextEditingController amountController;
  final TextEditingController commissionController;

  _ChangeAllocationDraft({
    required this.id,
    required this.sourceType,
    required num amount,
    required int decimalPlaces,
    this.sourceId,
    this.sourceName = '',
    num commission = 0,
  }) : amountController = TextEditingController(
         text: formatNumberForInput(amount, decimalPlaces: decimalPlaces),
       ),
       commissionController = TextEditingController(
         text: formatNumberForInput(commission, decimalPlaces: decimalPlaces),
       );

  factory _ChangeAllocationDraft.fromAllocation(
    QuickSalesChangeAllocation allocation, {
    required int decimalPlaces,
  }) => _ChangeAllocationDraft(
    id: allocation.id.isEmpty ? const Uuid().v4() : allocation.id,
    sourceType: allocation.sourceType,
    sourceId: allocation.sourceId,
    sourceName: allocation.sourceName,
    amount: allocation.amount,
    commission: allocation.commission,
    decimalPlaces: decimalPlaces,
  );

  num get amount => parseFormattedNumber(amountController.text) ?? 0;
  num get commission => parseFormattedNumber(commissionController.text) ?? 0;

  void dispose() {
    amountController.dispose();
    commissionController.dispose();
  }
}
