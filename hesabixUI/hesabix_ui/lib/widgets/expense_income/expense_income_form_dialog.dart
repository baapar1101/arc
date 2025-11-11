import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/expense_income_document.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/models/business_dashboard_models.dart';
import 'package:hesabix_ui/services/expense_income_service.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/account_combobox_widget.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// دیالوگ ایجاد/ویرایش سند هزینه/درآمد
class ExpenseIncomeFormDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final bool isIncome;
  final BusinessWithPermission? businessInfo;
  final ApiClient apiClient;
  final ExpenseIncomeDocument? initialDocument;

  const ExpenseIncomeFormDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.isIncome,
    this.businessInfo,
    required this.apiClient,
    this.initialDocument,
  });

  @override
  State<ExpenseIncomeFormDialog> createState() => _ExpenseIncomeFormDialogState();
}

class _ExpenseIncomeFormDialogState extends State<ExpenseIncomeFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _docDate;
  late bool _isIncome;
  int? _selectedCurrencyId;
  final TextEditingController _descriptionController = TextEditingController();
  final List<_ItemLine> _itemLines = <_ItemLine>[];
  final List<_CounterpartyLine> _counterpartyLines = <_CounterpartyLine>[];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDocument;
    if (initial != null) {
      // حالت ویرایش: پرکردن اولیه از سند
      _isIncome = initial.isIncome;
      _docDate = initial.documentDate;
      _selectedCurrencyId = initial.currencyId;
      _descriptionController.text = initial.description ?? '';
      
      // تبدیل خطوط آیتم‌ها
      _itemLines.clear();
      for (final line in initial.itemLines) {
        _itemLines.add(
          _ItemLine(
            accountId: line.accountId.toString(),
            accountName: line.accountName,
            amount: line.amount,
            description: line.description,
          ),
        );
      }
      
      // تبدیل خطوط طرف‌حساب‌ها
      _counterpartyLines.clear();
      for (final line in initial.counterpartyLines) {
        _counterpartyLines.add(
          _CounterpartyLine(
            transactionType: TransactionType.fromValue(line.transactionType) ?? TransactionType.bank,
            amount: line.amount,
            transactionDate: line.transactionDate,
            description: line.description,
            commission: line.commission,
            bankAccountId: line.bankAccountId?.toString(),
            bankAccountName: line.bankAccountName,
            cashRegisterId: line.cashRegisterId?.toString(),
            cashRegisterName: line.cashRegisterName,
            pettyCashId: line.pettyCashId?.toString(),
            pettyCashName: line.pettyCashName,
            checkId: line.checkId?.toString(),
            checkNumber: line.checkNumber,
            personId: line.personId?.toString(),
            personName: line.personName,
          ),
        );
      }
    } else {
      // حالت ایجاد
      _docDate = DateTime.now();
      _isIncome = widget.isIncome;
      _selectedCurrencyId = widget.businessInfo?.defaultCurrency?.id;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final sumItems = _itemLines.fold<double>(0, (p, e) => p + e.amount);
    final sumCounterparties = _counterpartyLines.fold<double>(0, (p, e) => p + e.amount);
    final diff = sumItems - sumCounterparties;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 800),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'هزینه و درآمد',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (widget.initialDocument == null)
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment<bool>(value: false, label: Text('هزینه')),
                          ButtonSegment<bool>(value: true, label: Text('درآمد')),
                        ],
                        selected: {_isIncome},
                        onSelectionChanged: (s) => setState(() => _isIncome = s.first),
                      ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
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
                      width: 200,
                      child: CurrencyPickerWidget(
                        businessId: widget.businessId,
                        selectedCurrencyId: _selectedCurrencyId,
                        onChanged: (currencyId) => setState(() => _selectedCurrencyId = currencyId),
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
                    Expanded(
                      child: _ItemLinesPanel(
                        businessId: widget.businessId,
                        lines: _itemLines,
                        onChanged: (ls) => setState(() {
                          _itemLines.clear();
                          _itemLines.addAll(ls);
                        }),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _CounterpartyLinesPanel(
                        businessId: widget.businessId,
                        lines: _counterpartyLines,
                        onChanged: (ls) => setState(() {
                          _counterpartyLines.clear();
                          _counterpartyLines.addAll(ls);
                        }),
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
                          _TotalChip(label: 'حساب‌ها', value: sumItems),
                          _TotalChip(label: 'طرف‌حساب‌ها', value: sumCounterparties),
                          _TotalChip(label: 'اختلاف', value: diff, isError: diff != 0),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: diff == 0 && _itemLines.isNotEmpty && _counterpartyLines.isNotEmpty
                          ? _onSave
                          : null,
                      icon: const Icon(Icons.save),
                      label: Text(t.save),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (!mounted) return;
    
    // نمایش loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final service = ExpenseIncomeService(widget.apiClient);
      
      // تبدیل itemLines به فرمت مورد نیاز API
      final itemLinesData = _itemLines.map((line) => {
        'account_id': int.parse(line.accountId!),
        'amount': line.amount,
        if (line.description != null && line.description!.isNotEmpty)
          'description': line.description,
      }).toList();
      
      // تبدیل counterpartyLines به فرمت مورد نیاز API
      final counterpartyLinesData = _counterpartyLines.map((line) => {
        'transaction_type': line.transactionType.value,
        'amount': line.amount,
        'transaction_date': line.transactionDate.toIso8601String(),
        if (line.commission != null && line.commission! > 0)
          'commission': line.commission,
        if (line.description != null && line.description!.isNotEmpty)
          'description': line.description,
        // اطلاعات اضافی بر اساس نوع تراکنش
        if (line.transactionType == TransactionType.bank) ...{
          if (line.bankAccountId != null) 'bank_account_id': int.parse(line.bankAccountId!),
          if (line.bankAccountName != null) 'bank_account_name': line.bankAccountName,
        },
        if (line.transactionType == TransactionType.cashRegister) ...{
          if (line.cashRegisterId != null) 'cash_register_id': int.parse(line.cashRegisterId!),
          if (line.cashRegisterName != null) 'cash_register_name': line.cashRegisterName,
        },
        if (line.transactionType == TransactionType.pettyCash) ...{
          if (line.pettyCashId != null) 'petty_cash_id': int.parse(line.pettyCashId!),
          if (line.pettyCashName != null) 'petty_cash_name': line.pettyCashName,
        },
        if (line.transactionType == TransactionType.check) ...{
          if (line.checkId != null) 'check_id': int.parse(line.checkId!),
          if (line.checkNumber != null) 'check_number': line.checkNumber,
        },
        if (line.transactionType == TransactionType.person) ...{
          if (line.personId != null) 'person_id': int.parse(line.personId!),
          if (line.personName != null) 'person_name': line.personName,
        },
      }).toList();
      
      // اگر initialDocument وجود دارد، حالت ویرایش
      if (widget.initialDocument != null) {
        await service.update(
          documentId: widget.initialDocument!.id,
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          itemLines: itemLinesData.map((data) => ItemLineData(
            accountId: data['account_id'] as int,
            amount: (data['amount'] as num).toDouble(),
            description: data['description'] as String?,
          )).toList(),
          counterpartyLines: counterpartyLinesData.map((data) => CounterpartyLineData(
            transactionType: TransactionType.fromValue(data['transaction_type'] as String) ?? TransactionType.bank,
            amount: (data['amount'] as num).toDouble(),
            transactionDate: DateTime.parse(data['transaction_date'] as String),
            description: data['description'] as String?,
            commission: data['commission'] != null ? (data['commission'] as num).toDouble() : null,
            bankAccountId: data['bank_account_id'] as int?,
            bankAccountName: data['bank_account_name'] as String?,
            cashRegisterId: data['cash_register_id'] as int?,
            cashRegisterName: data['cash_register_name'] as String?,
            pettyCashId: data['petty_cash_id'] as int?,
            pettyCashName: data['petty_cash_name'] as String?,
            checkId: data['check_id'] as int?,
            checkNumber: data['check_number'] as String?,
            personId: data['person_id'] as int?,
            personName: data['person_name'] as String?,
          )).toList(),
        );
      } else {
        // ایجاد سند جدید
        await service.create(
          businessId: widget.businessId,
          documentType: _isIncome ? 'income' : 'expense',
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          itemLines: itemLinesData.map((data) => ItemLineData(
            accountId: data['account_id'] as int,
            amount: (data['amount'] as num).toDouble(),
            description: data['description'] as String?,
          )).toList(),
          counterpartyLines: counterpartyLinesData.map((data) => CounterpartyLineData(
            transactionType: TransactionType.fromValue(data['transaction_type'] as String) ?? TransactionType.bank,
            amount: (data['amount'] as num).toDouble(),
            transactionDate: DateTime.parse(data['transaction_date'] as String),
            description: data['description'] as String?,
            commission: data['commission'] != null ? (data['commission'] as num).toDouble() : null,
            bankAccountId: data['bank_account_id'] as int?,
            bankAccountName: data['bank_account_name'] as String?,
            cashRegisterId: data['cash_register_id'] as int?,
            cashRegisterName: data['cash_register_name'] as String?,
            pettyCashId: data['petty_cash_id'] as int?,
            pettyCashName: data['petty_cash_name'] as String?,
            checkId: data['check_id'] as int?,
            checkNumber: data['check_number'] as String?,
            personId: data['person_id'] as int?,
            personName: data['person_name'] as String?,
          )).toList(),
        );
      }
      
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // بستن dialog اصلی با موفقیت
      Navigator.pop(context, true);
      
      // نمایش پیام موفقیت
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialDocument != null
              ? 'سند با موفقیت ویرایش شد'
              : (_isIncome ? 'سند درآمد با موفقیت ثبت شد' : 'سند هزینه با موفقیت ثبت شد'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // نمایش خطا
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _ItemLinesPanel extends StatefulWidget {
  final int businessId;
  final List<_ItemLine> lines;
  final ValueChanged<List<_ItemLine>> onChanged;
  
  const _ItemLinesPanel({
    required this.businessId,
    required this.lines,
    required this.onChanged,
  });

  @override
  State<_ItemLinesPanel> createState() => _ItemLinesPanelState();
}

class _ItemLinesPanelState extends State<_ItemLinesPanel> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('حساب‌های هزینه/درآمد', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                onPressed: () {
                  final newLines = List<_ItemLine>.from(widget.lines);
                  newLines.add(_ItemLine.empty());
                  widget.onChanged(newLines);
                },
                icon: const Icon(Icons.add),
                tooltip: t.add,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.lines.isEmpty
                ? Center(child: Text(t.noDataFound))
                : ListView.separated(
                    itemCount: widget.lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final line = widget.lines[i];
                      return _ItemLineTile(
                        businessId: widget.businessId,
                        line: line,
                        onChanged: (l) {
                          final newLines = List<_ItemLine>.from(widget.lines);
                          newLines[i] = l;
                          widget.onChanged(newLines);
                        },
                        onDelete: () {
                          final newLines = List<_ItemLine>.from(widget.lines);
                          newLines.removeAt(i);
                          widget.onChanged(newLines);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ItemLineTile extends StatefulWidget {
  final int businessId;
  final _ItemLine line;
  final ValueChanged<_ItemLine> onChanged;
  final VoidCallback onDelete;
  
  const _ItemLineTile({
    required this.businessId,
    required this.line,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_ItemLineTile> createState() => _ItemLineTileState();
}

class _ItemLineTileState extends State<_ItemLineTile> {
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
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AccountComboboxWidget(
                    businessId: widget.businessId,
                    selectedAccount: widget.line.accountId != null 
                        ? Account(
                            id: int.tryParse(widget.line.accountId!),
                            businessId: widget.businessId,
                            name: widget.line.accountName ?? '',
                            code: '',
                            accountType: '',
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          )
                        : null,
                    onChanged: (opt) {
                      widget.onChanged(widget.line.copyWith(
                        accountId: opt?.id?.toString(), 
                        accountName: opt?.name
                      ));
                    },
                    label: 'حساب',
                    hintText: t.search,
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: t.amount,
                      hintText: '1,000,000',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      EnglishDigitsFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    validator: (v) {
                      final val = double.tryParse((v ?? '').replaceAll(',', ''));
                      if (val == null || val <= 0) return t.mustBePositiveNumber;
                      return null;
                    },
                    onChanged: (v) {
                      final val = double.tryParse(v.replaceAll(',', '')) ?? 0;
                      widget.onChanged(widget.line.copyWith(amount: val));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: t.description,
              ),
              onChanged: (v) => widget.onChanged(widget.line.copyWith(
                description: v.trim().isEmpty ? null : v.trim()
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterpartyLinesPanel extends StatefulWidget {
  final int businessId;
  final List<_CounterpartyLine> lines;
  final ValueChanged<List<_CounterpartyLine>> onChanged;
  
  const _CounterpartyLinesPanel({
    required this.businessId,
    required this.lines,
    required this.onChanged,
  });

  @override
  State<_CounterpartyLinesPanel> createState() => _CounterpartyLinesPanelState();
}

class _CounterpartyLinesPanelState extends State<_CounterpartyLinesPanel> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('طرف‌حساب‌ها', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                onPressed: () {
                  final newLines = List<_CounterpartyLine>.from(widget.lines);
                  newLines.add(_CounterpartyLine.empty());
                  widget.onChanged(newLines);
                },
                icon: const Icon(Icons.add),
                tooltip: t.add,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.lines.isEmpty
                ? Center(child: Text(t.noDataFound))
                : ListView.separated(
                    itemCount: widget.lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final line = widget.lines[i];
                      return _CounterpartyLineTile(
                        businessId: widget.businessId,
                        line: line,
                        onChanged: (l) {
                          final newLines = List<_CounterpartyLine>.from(widget.lines);
                          newLines[i] = l;
                          widget.onChanged(newLines);
                        },
                        onDelete: () {
                          final newLines = List<_CounterpartyLine>.from(widget.lines);
                          newLines.removeAt(i);
                          widget.onChanged(newLines);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CounterpartyLineTile extends StatefulWidget {
  final int businessId;
  final _CounterpartyLine line;
  final ValueChanged<_CounterpartyLine> onChanged;
  final VoidCallback onDelete;
  
  const _CounterpartyLineTile({
    required this.businessId,
    required this.line,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_CounterpartyLineTile> createState() => _CounterpartyLineTileState();
}

class _CounterpartyLineTileState extends State<_CounterpartyLineTile> {
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
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // انتخاب نوع تراکنش
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TransactionType>(
                    value: widget.line.transactionType,
                    decoration: const InputDecoration(
                      labelText: 'نوع تراکنش',
                    ),
                    items: TransactionType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.displayName),
                      );
                    }).toList(),
                    onChanged: (type) {
                      if (type != null) {
                        widget.onChanged(widget.line.copyWith(transactionType: type));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                
                // مبلغ
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: t.amount,
                    ),
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
                
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // فیلدهای اضافی بر اساس نوع تراکنش
            _buildTransactionTypeFields(),
            
            const SizedBox(height: 8),
            
            // توضیحات
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: t.description,
              ),
              onChanged: (v) => widget.onChanged(widget.line.copyWith(
                description: v.trim().isEmpty ? null : v.trim()
              )),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTransactionTypeFields() {
    switch (widget.line.transactionType) {
      case TransactionType.person:
        return Row(
          children: [
            Expanded(
              child: PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: widget.line.personId != null 
                    ? Person(
                        id: int.tryParse(widget.line.personId!),
                        businessId: widget.businessId,
                        aliasName: widget.line.personName ?? '',
                        personTypes: const [],
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      )
                    : null,
                onChanged: (person) {
                  widget.onChanged(widget.line.copyWith(
                    personId: person?.id?.toString(),
                    personName: person?.aliasName,
                  ));
                },
                label: 'شخص',
                hintText: 'انتخاب شخص',
                isRequired: true,
              ),
            ),
          ],
        );
        
      default:
        return const SizedBox.shrink();
    }
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final double value;
  final bool isError;
  
  const _TotalChip({
    required this.label, 
    required this.value, 
    this.isError = false
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label: ${formatWithThousands(value)}'),
      backgroundColor: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: isError ? scheme.onErrorContainer : scheme.onSurfaceVariant),
    );
  }
}

class _ItemLine {
  final String? accountId;
  final String? accountName;
  final double amount;
  final String? description;

  const _ItemLine({this.accountId, this.accountName, required this.amount, this.description});

  factory _ItemLine.empty() => const _ItemLine(amount: 0);

  _ItemLine copyWith({String? accountId, String? accountName, double? amount, String? description}) {
    return _ItemLine(
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      amount: amount ?? this.amount,
      description: description ?? this.description,
    );
  }
}

class _CounterpartyLine {
  final TransactionType transactionType;
  final double amount;
  final DateTime transactionDate;
  final String? description;
  final double? commission;
  
  // فیلدهای اختیاری بر اساس نوع تراکنش
  final String? bankAccountId;
  final String? bankAccountName;
  final String? cashRegisterId;
  final String? cashRegisterName;
  final String? pettyCashId;
  final String? pettyCashName;
  final String? checkId;
  final String? checkNumber;
  final String? personId;
  final String? personName;

  const _CounterpartyLine({
    required this.transactionType,
    required this.amount,
    required this.transactionDate,
    this.description,
    this.commission,
    this.bankAccountId,
    this.bankAccountName,
    this.cashRegisterId,
    this.cashRegisterName,
    this.pettyCashId,
    this.pettyCashName,
    this.checkId,
    this.checkNumber,
    this.personId,
    this.personName,
  });

  factory _CounterpartyLine.empty() => _CounterpartyLine(
    transactionType: TransactionType.bank,
    amount: 0,
    transactionDate: DateTime.now(),
  );

  _CounterpartyLine copyWith({
    TransactionType? transactionType,
    double? amount,
    DateTime? transactionDate,
    String? description,
    double? commission,
    String? bankAccountId,
    String? bankAccountName,
    String? cashRegisterId,
    String? cashRegisterName,
    String? pettyCashId,
    String? pettyCashName,
    String? checkId,
    String? checkNumber,
    String? personId,
    String? personName,
  }) {
    return _CounterpartyLine(
      transactionType: transactionType ?? this.transactionType,
      amount: amount ?? this.amount,
      transactionDate: transactionDate ?? this.transactionDate,
      description: description ?? this.description,
      commission: commission ?? this.commission,
      bankAccountId: bankAccountId ?? this.bankAccountId,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      cashRegisterId: cashRegisterId ?? this.cashRegisterId,
      cashRegisterName: cashRegisterName ?? this.cashRegisterName,
      pettyCashId: pettyCashId ?? this.pettyCashId,
      pettyCashName: pettyCashName ?? this.pettyCashName,
      checkId: checkId ?? this.checkId,
      checkNumber: checkNumber ?? this.checkNumber,
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
    );
  }
}
