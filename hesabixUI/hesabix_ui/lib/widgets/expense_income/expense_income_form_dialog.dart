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
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';

int _expenseIncomeStableRowIdSeq = 0;

/// شناسهٔ یکتا برای هر ردیف؛ برای [ValueKey] تا پس از حذف ردیف، State ویجت با ردیف اشتباه ادغام نشود.
String _nextExpenseIncomeRowId() {
  _expenseIncomeStableRowIdSeq++;
  return 'ei_row_$_expenseIncomeStableRowIdSeq';
}

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

class _ExpenseIncomeFormDialogState extends State<ExpenseIncomeFormDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late DateTime _docDate;
  late bool _isIncome;
  int? _selectedCurrencyId;
  int? _selectedProjectId;
  final TextEditingController _descriptionController = TextEditingController();
  final List<_ItemLine> _itemLines = <_ItemLine>[];
  final List<_CounterpartyLine> _counterpartyLines = <_CounterpartyLine>[];
  bool _isSaving = false;
  late final TabController _mobileTabController;

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 2, vsync: this);
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
            rowId: _nextExpenseIncomeRowId(),
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
            rowId: _nextExpenseIncomeRowId(),
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
    _mobileTabController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// با عوض‌کردن «هزینه / درآمد» در حالت ایجاد، حساب‌های اقلام پاک می‌شود تا حساب هزینه روی درآمد (و برعکس) گیر نکند.
  void _onDocIncomeTypeChanged(Set<bool> selection) {
    if (selection.isEmpty) return;
    final next = selection.first;
    if (next == _isIncome) return;
    setState(() {
      _isIncome = next;
      _itemLines.clear();
    });
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
    final scheme = Theme.of(context).colorScheme;
    final mobilePanelInset = EdgeInsets.symmetric(
      horizontal: padding,
      vertical: padding * 0.45,
    );

    return Dialog(
      insetPadding: EdgeInsets.zero,
      child: SafeArea(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('هزینه و درآمد'),
            toolbarHeight: 48,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isSaving ? null : () => Navigator.pop(context),
            ),
          ),
          resizeToAvoidBottomInset: true,
          body: Form(
            key: _formKey,
            child: Theme(
              data: Theme.of(context).copyWith(visualDensity: VisualDensity.compact),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.initialDocument == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment<bool>(value: false, label: Text('هزینه')),
                                  ButtonSegment<bool>(value: true, label: Text('درآمد')),
                                ],
                                selected: {_isIncome},
                                onSelectionChanged: _onDocIncomeTypeChanged,
                              ),
                            ),
                          DateInputField(
                            value: _docDate,
                            calendarController: widget.calendarController,
                            isDense: true,
                            onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                            labelText: 'تاریخ سند',
                            hintText: 'انتخاب تاریخ',
                          ),
                          const SizedBox(height: 8),
                          CurrencyPickerWidget(
                            businessId: widget.businessId,
                            selectedCurrencyId: _selectedCurrencyId,
                            isDense: true,
                            onChanged: (currencyId) =>
                                setState(() => _selectedCurrencyId = currencyId),
                            label: 'ارز',
                            hintText: 'انتخاب ارز',
                          ),
                          const SizedBox(height: 8),
                          ProjectSelectorWidget(
                            businessId: widget.businessId,
                            apiClient: widget.apiClient,
                            selectedProjectId: _selectedProjectId,
                            isDense: true,
                            onChanged: (projectId) => setState(() => _selectedProjectId = projectId),
                            allowNull: true,
                            labelText: 'پروژه',
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'توضیحات کلی سند',
                              hintText: 'توضیحات اختیاری...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    TabBar(
                      controller: _mobileTabController,
                      labelColor: scheme.primary,
                      unselectedLabelColor: scheme.onSurfaceVariant,
                      onTap: (_) => setState(() {}),
                      tabs: const [
                        Tab(text: 'حساب‌ها'),
                        Tab(text: 'طرف‌حساب‌ها'),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      alignment: Alignment.topCenter,
                      child: _mobileTabController.index == 0
                          ? _ItemLinesPanel(
                              businessId: widget.businessId,
                              isIncome: _isIncome,
                              lines: _itemLines,
                              panelPadding: mobilePanelInset,
                              onChanged: (ls) => setState(() {
                                _itemLines.clear();
                                _itemLines.addAll(ls);
                              }),
                            )
                          : _CounterpartyLinesPanel(
                              businessId: widget.businessId,
                              lines: _counterpartyLines,
                              panelPadding: mobilePanelInset,
                              onChanged: (ls) => setState(() {
                                _counterpartyLines.clear();
                                _counterpartyLines.addAll(ls);
                              }),
                            ),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    Padding(
                      padding: EdgeInsets.fromLTRB(padding, padding * 0.75, padding, padding),
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
                          const SizedBox(height: 14),
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
                                  onPressed:
                                      _isSaving || diff != 0 || _itemLines.isEmpty || _counterpartyLines.isEmpty
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vDesk = padding * 0.5;
    final colSep = padding * 0.4;
    final itemPanelPad = EdgeInsets.fromLTRB(0, vDesk, colSep, vDesk);
    final cpPanelPad = EdgeInsets.fromLTRB(colSep, vDesk, 0, vDesk);

    return Dialog(
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Theme(
          data: theme.copyWith(visualDensity: VisualDensity.compact),
          child: SizedBox.expand(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, padding * 0.55, padding, padding * 0.35),
                    child: Row(
                      children: [
                        Text(
                          'هزینه و درآمد',
                          style: theme.textTheme.titleLarge,
                        ),
                        const Spacer(),
                        if (widget.initialDocument == null)
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(value: false, label: Text('هزینه')),
                              ButtonSegment<bool>(value: true, label: Text('درآمد')),
                            ],
                            selected: {_isIncome},
                            onSelectionChanged: _onDocIncomeTypeChanged,
                          ),
                        const SizedBox(width: 8),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _isSaving ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          tooltip: 'بستن',
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(padding, padding * 0.6, padding, padding * 0.75),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(0, 0, 0, padding * 0.4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: DateInputField(
                                          value: _docDate,
                                          calendarController: widget.calendarController,
                                          isDense: true,
                                          onChanged: (d) =>
                                              setState(() => _docDate = d ?? DateTime.now()),
                                          labelText: 'تاریخ سند',
                                          hintText: 'انتخاب تاریخ',
                                        ),
                                      ),
                                      SizedBox(width: padding * 0.5),
                                      Expanded(
                                        child: CurrencyPickerWidget(
                                          businessId: widget.businessId,
                                          selectedCurrencyId: _selectedCurrencyId,
                                          isDense: true,
                                          onChanged: (currencyId) =>
                                              setState(() => _selectedCurrencyId = currencyId),
                                          label: 'ارز',
                                          hintText: 'انتخاب ارز',
                                        ),
                                      ),
                                      SizedBox(width: padding * 0.5),
                                      Expanded(
                                        child: ProjectSelectorWidget(
                                          businessId: widget.businessId,
                                          apiClient: widget.apiClient,
                                          selectedProjectId: _selectedProjectId,
                                          isDense: true,
                                          onChanged: (projectId) =>
                                              setState(() => _selectedProjectId = projectId),
                                          allowNull: true,
                                          labelText: 'پروژه',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(0, 0, 0, padding * 0.45),
                              child: TextField(
                                controller: _descriptionController,
                                decoration: const InputDecoration(
                                  labelText: 'توضیحات کلی سند',
                                  hintText: 'توضیحات اختیاری...',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                minLines: 1,
                                maxLines: 2,
                              ),
                            ),
                            Divider(height: 1, color: scheme.outlineVariant),
                            LayoutBuilder(
                              builder: (context, lc) {
                                final usable = lc.maxWidth - 1;
                                final half = usable > 2 ? usable / 2 : lc.maxWidth / 2;
                                return IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: half,
                                        child: _ItemLinesPanel(
                                          businessId: widget.businessId,
                                          isIncome: _isIncome,
                                          lines: _itemLines,
                                          panelPadding: itemPanelPad,
                                          onChanged: (ls) => setState(() {
                                            _itemLines.clear();
                                            _itemLines.addAll(ls);
                                          }),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 1,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: scheme.outlineVariant,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: half,
                                        child: _CounterpartyLinesPanel(
                                          businessId: widget.businessId,
                                          lines: _counterpartyLines,
                                          panelPadding: cpPanelPad,
                                          onChanged: (ls) => setState(() {
                                            _counterpartyLines.clear();
                                            _counterpartyLines.addAll(ls);
                                          }),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, padding * 0.5, padding, padding * 0.55),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _TotalChip(label: 'حساب‌ها', value: sumItems),
                                  _TotalChip(
                                    label: 'طرف‌حساب‌ها',
                                    value: sumCounterparties,
                                  ),
                                  _TotalChip(
                                    label: 'اختلاف',
                                    value: diff,
                                    isError: diff != 0,
                                  ),
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
                          onPressed: _isSaving ||
                                  diff != 0 ||
                                  _itemLines.isEmpty ||
                                  _counterpartyLines.isEmpty
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
      SnackBarHelper.showError(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
      );
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
  final EdgeInsetsGeometry? panelPadding;
  
  const _ItemLinesPanel({
    required this.businessId,
    required this.isIncome,
    required this.lines,
    required this.onChanged,
    this.panelPadding,
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
    final defaultPad =
        EdgeInsets.fromLTRB(padding, padding * 0.65, padding, padding * 0.65);
    final inset = widget.panelPadding ?? defaultPad;
    final lineGap = spacing * 0.65;

    Widget body;
    if (widget.lines.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text(t.noDataFound)),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < widget.lines.length; i++) ...[
            if (i > 0) SizedBox(height: lineGap),
            _ItemLineTile(
              key: ValueKey(widget.lines[i].rowId),
              businessId: widget.businessId,
              isIncome: widget.isIncome,
              line: widget.lines[i],
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
            ),
          ],
        ],
      );
    }

    return Padding(
      padding: inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'حساب‌های هزینه/درآمد',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
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
          SizedBox(height: lineGap),
          body,
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
    super.key,
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
  /// هم‌تراز با [_ExpenseIncomeFormDialogState._balanceEpsilon]؛ برای تشخیص تفاوت مبلغ پارس‌شدهٔ فیلد با state والد (تعادل خودکار، بارگذاری اولیه).
  static const double _amountApplyEpsilon = 1e-6;

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
  void didUpdateWidget(covariant _ItemLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.line.amount - widget.line.amount).abs() > _amountApplyEpsilon) {
      final parsed = parseFormattedDouble(_amountController.text) ?? 0;
      final next = widget.line.amount;
      if ((parsed - next).abs() > _amountApplyEpsilon) {
        final formatted = next == 0 ? '' : formatNumberForInput(next);
        _amountController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);
    final tilePad = padding * 0.45;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(tilePad),
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
          dense: true,
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
        const SizedBox(height: 7),
        TextFormField(
          controller: _amountController,
          decoration: InputDecoration(
            labelText: t.amount,
            hintText: '1,000,000',
            isDense: true,
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
        const SizedBox(height: 7),
        TextFormField(
          controller: _descController,
          decoration: InputDecoration(
            labelText: t.description,
            isDense: true,
          ),
          onChanged: (v) => widget.onChanged(widget.line.copyWith(
            description: v.trim().isEmpty ? null : v.trim()
          )),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              iconSize: 20,
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
                dense: true,
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
            const SizedBox(width: 6),
            SizedBox(
              width: 146,
              child: TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: t.amount,
                  hintText: '1,000,000',
                  isDense: true,
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
            const SizedBox(width: 6),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              iconSize: 20,
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: t.delete,
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _descController,
          decoration: InputDecoration(
            labelText: t.description,
            isDense: true,
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
  final EdgeInsetsGeometry? panelPadding;

  const _CounterpartyLinesPanel({
    required this.businessId,
    required this.lines,
    required this.onChanged,
    this.panelPadding,
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
    final defaultPad =
        EdgeInsets.fromLTRB(padding, padding * 0.65, padding, padding * 0.65);
    final inset = widget.panelPadding ?? defaultPad;
    final lineGap = spacing * 0.65;

    Widget body;
    if (widget.lines.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text(t.noDataFound)),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < widget.lines.length; i++) ...[
            if (i > 0) SizedBox(height: lineGap),
            _CounterpartyLineTile(
              key: ValueKey(widget.lines[i].rowId),
              businessId: widget.businessId,
              line: widget.lines[i],
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
            ),
          ],
        ],
      );
    }

    return Padding(
      padding: inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'طرف‌حساب‌ها',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
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
          SizedBox(height: lineGap),
          body,
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
    super.key,
    required this.businessId,
    required this.line,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_CounterpartyLineTile> createState() => _CounterpartyLineTileState();
}

class _CounterpartyLineTileState extends State<_CounterpartyLineTile> {
  static const double _amountApplyEpsilon = 1e-6;

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
  void didUpdateWidget(covariant _CounterpartyLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.line.amount - widget.line.amount).abs() > _amountApplyEpsilon) {
      final parsed = parseFormattedDouble(_amountController.text) ?? 0;
      final next = widget.line.amount;
      if ((parsed - next).abs() > _amountApplyEpsilon) {
        final formatted = next == 0 ? '' : formatNumberForInput(next);
        _amountController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);
    final tilePad = padding * 0.45;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(tilePad),
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
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'نوع تراکنش',
            isDense: true,
            contentPadding: EdgeInsetsDirectional.only(start: 12, top: 10, bottom: 10, end: 12),
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
        const SizedBox(height: 7),
        TextFormField(
          controller: _amountController,
          decoration: InputDecoration(
            labelText: t.amount,
            isDense: true,
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
        const SizedBox(height: 7),
        _buildTransactionTypeFields(),
        const SizedBox(height: 7),
        TextFormField(
          controller: _descController,
          decoration: InputDecoration(
            labelText: t.description,
            isDense: true,
          ),
          onChanged: (v) => widget.onChanged(widget.line.copyWith(
            description: v.trim().isEmpty ? null : v.trim()
          )),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              iconSize: 20,
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
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'نوع تراکنش',
                  isDense: true,
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
            const SizedBox(width: 6),
            SizedBox(
              width: 130,
              child: TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: t.amount,
                  isDense: true,
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
            const SizedBox(width: 6),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              iconSize: 20,
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: t.delete,
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildTransactionTypeFields(),
        const SizedBox(height: 6),
        TextFormField(
          controller: _descController,
          decoration: InputDecoration(
            labelText: t.description,
            isDense: true,
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
                dense: true,
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
                dense: true,
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
                dense: true,
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
                dense: true,
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
                dense: true,
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
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: isError ? scheme.onErrorContainer : scheme.onSurfaceVariant,
        );
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      label: Text(
        '$label: ${formatWithThousands(value)}',
        style: textStyle,
      ),
      backgroundColor: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
    );
  }
}

class _ItemLine {
  final String rowId;
  final String? accountId;
  final String? accountName;
  final double amount;
  final String? description;

  _ItemLine({required this.rowId, this.accountId, this.accountName, required this.amount, this.description});

  factory _ItemLine.empty() => _ItemLine(rowId: _nextExpenseIncomeRowId(), amount: 0);

  _ItemLine copyWith({
    String? rowId,
    String? accountId,
    String? accountName,
    double? amount,
    String? description,
  }) {
    return _ItemLine(
      rowId: rowId ?? this.rowId,
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      amount: amount ?? this.amount,
      description: description ?? this.description,
    );
  }
}

class _CounterpartyLine {
  final String rowId;
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

  _CounterpartyLine({
    required this.rowId,
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
    rowId: _nextExpenseIncomeRowId(),
    transactionType: TransactionType.bank,
    amount: 0,
    transactionDate: DateTime.now(),
  );

  _CounterpartyLine copyWith({
    String? rowId,
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
      rowId: rowId ?? this.rowId,
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
