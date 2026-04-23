import 'package:flutter/material.dart';
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
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/account_tree_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/bank_account_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/cash_register_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/petty_cash_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/check_combobox_widget.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';

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
  int? _selectedProjectId;
  final TextEditingController _descriptionController = TextEditingController();
  final List<_ItemLine> _itemLines = <_ItemLine>[];
  final List<_CounterpartyLine> _counterpartyLines = <_CounterpartyLine>[];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDocument;
    if (initial != null) {
      // حالت ویرایش: پرکردن اولیه از سند
      _isIncome = initial.isIncome;
      _docDate = initial.documentDate;
      _selectedCurrencyId = initial.currencyId;
      _selectedProjectId = initial.projectId;
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
            accountId: line.accountId?.toString(),
            accountName: line.accountName,
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

  static const double _balanceEpsilon = 1e-6;

  double _sumItems() =>
      _itemLines.fold<double>(0, (p, e) => p + e.amount);

  double _sumCounterparties() => _counterpartyLines.fold<double>(
        0,
        (p, e) => p + e.amount,
      );

  /// تعدیل آخرین ردیف طرف‌حساب تا جمع آن برابر جمع «حساب‌ها» (اقلام) شود.
  void _onBalanceFavoringItemsColumn() {
    if (_counterpartyLines.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'برای تعدیل مطابق حساب‌ها، حداقل یک ردیف طرف‌حساب لازم است',
      );
      return;
    }
    final sumI = _sumItems();
    final sumC = _sumCounterparties();
    final add = sumI - sumC;
    if (add.abs() < _balanceEpsilon) return;
    final last = _counterpartyLines.length - 1;
    final newAmt = _counterpartyLines[last].amount + add;
    if (newAmt < -_balanceEpsilon) {
      SnackBarHelper.showError(
        context,
        message: 'مبلغ ردیف آخر طرف‌حساب پس از تعدیل منفی می‌شود.',
      );
      return;
    }
    setState(() {
      _counterpartyLines[last] =
          _counterpartyLines[last].copyWith(amount: newAmt);
    });
  }

  /// تعدیل آخرین ردیف قلم حساب تا جمع اقلام برابر جمع طرف‌حساب‌ها شود.
  void _onBalanceFavoringCounterpartiesColumn() {
    if (_itemLines.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'برای تعدیل مطابق طرف‌حساب‌ها، حداقل یک ردیف حساب (قلم) لازم است',
      );
      return;
    }
    final sumI = _sumItems();
    final sumC = _sumCounterparties();
    final add = sumC - sumI;
    if (add.abs() < _balanceEpsilon) return;
    final last = _itemLines.length - 1;
    final newAmt = _itemLines[last].amount + add;
    if (newAmt < -_balanceEpsilon) {
      SnackBarHelper.showError(
        context,
        message: 'مبلغ ردیف آخر اقلام پس از تعدیل منفی می‌شود.',
      );
      return;
    }
    setState(() {
      _itemLines[last] = _itemLines[last].copyWith(amount: newAmt);
    });
  }

  Widget _buildBalanceActionButtons() {
    final diff = _sumItems() - _sumCounterparties();
    if (diff.abs() < _balanceEpsilon) return const SizedBox.shrink();
    if (_itemLines.isEmpty || _counterpartyLines.isEmpty) {
      return const SizedBox.shrink();
    }
    final sumI = _sumItems();
    final sumC = _sumCounterparties();
    final addToCp = sumI - sumC;
    final lastC = _counterpartyLines.length - 1;
    final canMatchItems =
        _counterpartyLines[lastC].amount + addToCp >= -_balanceEpsilon;
    final addToItem = sumC - sumI;
    final lastI = _itemLines.length - 1;
    final canMatchCp = _itemLines[lastI].amount + addToItem >= -_balanceEpsilon;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: canMatchItems ? _onBalanceFavoringItemsColumn : null,
          icon: const Icon(Icons.receipt_long, size: 18),
          label: const Text('مطابق حساب‌ها'),
        ),
        OutlinedButton.icon(
          onPressed: canMatchCp ? _onBalanceFavoringCounterpartiesColumn : null,
          icon: const Icon(Icons.payments, size: 18),
          label: const Text('مطابق طرف‌حساب‌ها'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    
    if (isMobile) {
      return _buildMobileLayout();
    } else {
      return _buildDesktopLayout();
    }
  }

  Widget _buildMobileLayout() {
    final t = AppLocalizations.of(context);
    final sumItems = _itemLines.fold<double>(0, (p, e) => p + e.amount);
    final sumCounterparties = _counterpartyLines.fold<double>(0, (p, e) => p + e.amount);
    final diff = sumItems - sumCounterparties;
    final padding = ResponsiveHelper.getPadding(context);

    return Dialog(
      insetPadding: EdgeInsets.zero,
      child: SafeArea(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('هزینه و درآمد'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isSaving ? null : () => Navigator.pop(context),
            ),
          ),
          body: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // هدر موبایل
                Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.initialDocument == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(value: false, label: Text('هزینه')),
                              ButtonSegment<bool>(value: true, label: Text('درآمد')),
                            ],
                            selected: {_isIncome},
                            onSelectionChanged: (s) => setState(() => _isIncome = s.first),
                          ),
                        ),
                      DateInputField(
                        value: _docDate,
                        calendarController: widget.calendarController,
                        onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                        labelText: 'تاریخ سند',
                        hintText: 'انتخاب تاریخ',
                      ),
                      const SizedBox(height: 12),
                      CurrencyPickerWidget(
                        businessId: widget.businessId,
                        selectedCurrencyId: _selectedCurrencyId,
                        onChanged: (currencyId) => setState(() => _selectedCurrencyId = currencyId),
                        label: 'ارز',
                        hintText: 'انتخاب ارز',
                      ),
                      const SizedBox(height: 12),
                      ProjectSelectorWidget(
                        businessId: widget.businessId,
                        apiClient: widget.apiClient,
                        selectedProjectId: _selectedProjectId,
                        onChanged: (projectId) => setState(() => _selectedProjectId = projectId),
                        allowNull: true,
                        labelText: 'پروژه',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'توضیحات کلی سند',
                          hintText: 'توضیحات اختیاری...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // پنل‌ها با TabBar
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        TabBar(
                          tabs: const [
                            Tab(text: 'حساب‌ها'),
                            Tab(text: 'طرف‌حساب‌ها'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _ItemLinesPanel(
                                businessId: widget.businessId,
                                isIncome: _isIncome,
                                lines: _itemLines,
                                onChanged: (ls) => setState(() {
                                  _itemLines.clear();
                                  _itemLines.addAll(ls);
                                }),
                              ),
                              _CounterpartyLinesPanel(
                                businessId: widget.businessId,
                                lines: _counterpartyLines,
                                onChanged: (ls) => setState(() {
                                  _counterpartyLines.clear();
                                  _counterpartyLines.addAll(ls);
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                // فوتر موبایل
                Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _TotalChip(label: 'حساب‌ها', value: sumItems),
                          _TotalChip(label: 'طرف‌حساب‌ها', value: sumCounterparties),
                          _TotalChip(label: 'اختلاف', value: diff, isError: diff != 0),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _buildBalanceActionButtons(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: _isSaving ? null : () => Navigator.pop(context),
                              child: Text(t.cancel),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isSaving || diff != 0 || _itemLines.isEmpty || _counterpartyLines.isEmpty
                                  ? null
                                  : _onSave,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(_isSaving ? 'در حال ذخیره...' : t.save),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final t = AppLocalizations.of(context);
    final sumItems = _itemLines.fold<double>(0, (p, e) => p + e.amount);
    final sumCounterparties = _counterpartyLines.fold<double>(0, (p, e) => p + e.amount);
    final diff = sumItems - sumCounterparties;
    final padding = ResponsiveHelper.getPadding(context);

    return Dialog(
      insetPadding: ResponsiveHelper.getDialogPadding(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1400,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // هدر دسکتاپ
              Padding(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, padding / 2),
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
                        segments: const [
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
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: ProjectSelectorWidget(
                        businessId: widget.businessId,
                        apiClient: widget.apiClient,
                        selectedProjectId: _selectedProjectId,
                        onChanged: (projectId) => setState(() => _selectedProjectId = projectId),
                        allowNull: true,
                        labelText: 'پروژه',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 0, padding, padding / 2),
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
              // پنل‌ها دسکتاپ
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _ItemLinesPanel(
                        businessId: widget.businessId,
                        isIncome: _isIncome,
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
              // فوتر دسکتاپ
              Padding(
                padding: EdgeInsets.fromLTRB(padding, padding / 2, padding, padding),
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
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _TotalChip(label: 'حساب‌ها', value: sumItems),
                              _TotalChip(label: 'طرف‌حساب‌ها', value: sumCounterparties),
                              _TotalChip(label: 'اختلاف', value: diff, isError: diff != 0),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _buildBalanceActionButtons(),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isSaving || diff != 0 || _itemLines.isEmpty || _counterpartyLines.isEmpty
                          ? null
                          : _onSave,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? 'در حال ذخیره...' : t.save),
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
    
    setState(() {
      _isSaving = true;
    });
    
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
        if (line.transactionType == TransactionType.check ||
            line.transactionType == TransactionType.checkExpense) ...{
          if (line.checkId != null) 'check_id': int.parse(line.checkId!),
          if (line.checkNumber != null) 'check_number': line.checkNumber,
        },
        if (line.transactionType == TransactionType.person) ...{
          if (line.personId != null) 'person_id': int.parse(line.personId!),
          if (line.personName != null) 'person_name': line.personName,
        },
        if (line.transactionType == TransactionType.account) ...{
          if (line.accountId != null) 'account_id': int.parse(line.accountId!),
          if (line.accountName != null) 'account_name': line.accountName,
        },
      }).toList();
      
      // اگر initialDocument وجود دارد، حالت ویرایش
      if (widget.initialDocument != null) {
        await service.update(
          documentId: widget.initialDocument!.id,
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          projectId: _selectedProjectId,
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
          projectId: _selectedProjectId,
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
      
      // بستن dialog اصلی با موفقیت
      Navigator.pop(context, true);
      
      // نمایش پیام موفقیت
      SnackBarHelper.showSuccess(
        context,
        message: widget.initialDocument != null
          ? 'سند با موفقیت ویرایش شد'
          : (_isIncome ? 'سند درآمد با موفقیت ثبت شد' : 'سند هزینه با موفقیت ثبت شد'),
      );
    } catch (e) {
      if (!mounted) return;
      
      // نمایش خطا
      SnackBarHelper.showError(context, message: 'خطا: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _ItemLinesPanel extends StatefulWidget {
  final int businessId;
  final bool isIncome;
  final List<_ItemLine> lines;
  final ValueChanged<List<_ItemLine>> onChanged;
  
  const _ItemLinesPanel({
    required this.businessId,
    required this.isIncome,
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
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.getGridSpacing(context);
    
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'حساب‌های هزینه/درآمد',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
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
          SizedBox(height: spacing),
          Expanded(
            child: widget.lines.isEmpty
                ? Center(child: Text(t.noDataFound))
                : ListView.separated(
                    itemCount: widget.lines.length,
                    separatorBuilder: (_, _) => SizedBox(height: spacing),
                    itemBuilder: (ctx, i) {
                      final line = widget.lines[i];
                      return _ItemLineTile(
                        businessId: widget.businessId,
                        isIncome: widget.isIncome,
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
  final bool isIncome;
  final _ItemLine line;
  final ValueChanged<_ItemLine> onChanged;
  final VoidCallback onDelete;
  
  const _ItemLineTile({
    required this.businessId,
    required this.isIncome,
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
    _amountController.text = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
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
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: isMobile
            ? _buildMobileLayout(t)
            : _buildDesktopLayout(t),
      ),
    );
  }

  Widget _buildMobileLayout(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountTreeComboboxWidget(
          businessId: widget.businessId,
          documentTypeFilter: widget.isIncome ? 'income' : 'expense',
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
          onChanged: (acc) {
            widget.onChanged(widget.line.copyWith(
              accountId: acc?.id?.toString(),
              accountName: acc?.displayName ?? acc?.name,
            ));
          },
          label: 'حساب',
          hintText: t.search,
          isRequired: true,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amountController,
          decoration: InputDecoration(
            labelText: t.amount,
            hintText: '1,000,000',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            EnglishDigitsFormatter(),
            ThousandsSeparatorInputFormatter(allowDecimal: false),
          ],
          validator: (v) {
            final val = parseFormattedDouble(v);
            if (val == null || val <= 0) return t.mustBePositiveNumber;
            return null;
          },
          onChanged: (v) {
            final val = parseFormattedDouble(v) ?? 0;
            widget.onChanged(widget.line.copyWith(amount: val));
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descController,
          decoration: InputDecoration(
            labelText: t.description,
          ),
          onChanged: (v) => widget.onChanged(widget.line.copyWith(
            description: v.trim().isEmpty ? null : v.trim()
          )),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: t.delete,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(AppLocalizations t) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AccountTreeComboboxWidget(
                businessId: widget.businessId,
                documentTypeFilter: widget.isIncome ? 'income' : 'expense',
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
                onChanged: (acc) {
                  widget.onChanged(widget.line.copyWith(
                    accountId: acc?.id?.toString(),
                    accountName: acc?.displayName ?? acc?.name,
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
                  ThousandsSeparatorInputFormatter(allowDecimal: false),
                ],
                validator: (v) {
                  final val = parseFormattedDouble(v);
                  if (val == null || val <= 0) return t.mustBePositiveNumber;
                  return null;
                },
                onChanged: (v) {
                  final val = parseFormattedDouble(v) ?? 0;
                  widget.onChanged(widget.line.copyWith(amount: val));
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: t.delete,
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
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.getGridSpacing(context);
    
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'طرف‌حساب‌ها',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
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
          SizedBox(height: spacing),
          Expanded(
            child: widget.lines.isEmpty
                ? Center(child: Text(t.noDataFound))
                : ListView.separated(
                    itemCount: widget.lines.length,
                    separatorBuilder: (_, _) => SizedBox(height: spacing),
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
    _amountController.text = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
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
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: isMobile
            ? _buildMobileLayout(t)
            : _buildDesktopLayout(t),
      ),
    );
  }

  Widget _buildMobileLayout(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<TransactionType>(
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
        const SizedBox(height: 12),
        TextFormField(
          controller: _amountController,
          decoration: InputDecoration(
            labelText: t.amount,
          ),
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
        const SizedBox(height: 12),
        _buildTransactionTypeFields(),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descController,
          decoration: InputDecoration(
            labelText: t.description,
          ),
          onChanged: (v) => widget.onChanged(widget.line.copyWith(
            description: v.trim().isEmpty ? null : v.trim()
          )),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: t.delete,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(AppLocalizations t) {
    return Column(
      children: [
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
                  ThousandsSeparatorInputFormatter(allowDecimal: false),
                ],
                onChanged: (v) {
                  final val = parseFormattedDouble(v) ?? 0;
                  widget.onChanged(widget.line.copyWith(amount: val));
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: t.delete,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildTransactionTypeFields(),
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
    );
  }
  
  Widget _buildTransactionTypeFields() {
    switch (widget.line.transactionType) {
      case TransactionType.bank:
        return Row(
          children: [
            Expanded(
              child: BankAccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccountId: widget.line.bankAccountId,
                onChanged: (opt) {
                  widget.onChanged(widget.line.copyWith(
                    bankAccountId: opt?.id,
                    bankAccountName: opt?.name,
                  ));
                },
                label: 'بانک',
                hintText: 'انتخاب حساب بانکی',
                isRequired: true,
              ),
            ),
          ],
        );
      case TransactionType.cashRegister:
        return Row(
          children: [
            Expanded(
              child: CashRegisterComboboxWidget(
                businessId: widget.businessId,
                selectedRegisterId: widget.line.cashRegisterId,
                onChanged: (opt) {
                  widget.onChanged(widget.line.copyWith(
                    cashRegisterId: opt?.id,
                    cashRegisterName: opt?.name,
                  ));
                },
                label: 'صندوق',
                hintText: 'انتخاب صندوق',
                isRequired: true,
              ),
            ),
          ],
        );
      case TransactionType.pettyCash:
        return Row(
          children: [
            Expanded(
              child: PettyCashComboboxWidget(
                businessId: widget.businessId,
                selectedPettyCashId: widget.line.pettyCashId,
                onChanged: (opt) {
                  widget.onChanged(widget.line.copyWith(
                    pettyCashId: opt?.id,
                    pettyCashName: opt?.name,
                  ));
                },
                label: 'تنخواهگردان',
                hintText: 'انتخاب تنخواهگردان',
                isRequired: true,
              ),
            ),
          ],
        );
      case TransactionType.check:
      case TransactionType.checkExpense:
        return Row(
          children: [
            Expanded(
              child: CheckComboboxWidget(
                businessId: widget.businessId,
                selectedCheckId: widget.line.checkId,
                onChanged: (opt) {
                  widget.onChanged(widget.line.copyWith(
                    checkId: opt?.id,
                    checkNumber: opt?.number,
                  ));
                },
                label: 'چک',
                hintText: 'انتخاب چک',
              ),
            ),
          ],
        );
      case TransactionType.account:
        return Row(
          children: [
            Expanded(
              child: AccountTreeComboboxWidget(
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
                onChanged: (acc) {
                  widget.onChanged(widget.line.copyWith(
                    accountId: acc?.id?.toString(),
                    accountName: acc?.displayName ?? acc?.name,
                  ));
                },
                label: 'حساب',
                hintText: 'انتخاب حساب',
                isRequired: true,
              ),
            ),
          ],
        );
      case TransactionType.person:
        return Row(
          children: [
            Expanded(
              child: PersonComboboxWidget(
                businessId: widget.businessId,
                showFinancialBalance: true,
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
  final String? accountId;
  final String? accountName;

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
    this.accountId,
    this.accountName,
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
    String? accountId,
    String? accountName,
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
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
    );
  }
}
