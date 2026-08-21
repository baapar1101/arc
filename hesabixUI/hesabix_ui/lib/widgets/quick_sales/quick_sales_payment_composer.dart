import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../models/invoice_transaction.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';
import '../../widgets/invoice/bank_account_combobox_widget.dart';
import '../../widgets/invoice/cash_register_combobox_widget.dart';
import '../../widgets/invoice/check_combobox_widget.dart';
import '../../widgets/money/amount_field_words_tooltip.dart';

/// آهنگ‌ساز پرداخت فشرده برای صندوق فروش سریع.
///
/// مسیر پیش‌فرض: یک ردیف صندوق که مبلغش با جمع فاکتور همگام است.
/// صندوق‌دار با کم کردن مبلغ یا دکمهٔ بانک/چک وارد تقسیم می‌شود.
class QuickSalesPaymentComposer extends StatefulWidget {
  final int businessId;
  final List<InvoiceTransaction> payments;
  final ValueChanged<List<InvoiceTransaction>> onChanged;
  final bool cashFollowsTotal;
  final ValueChanged<bool> onCashFollowsTotalChanged;
  final num invoiceTotal;
  final String? defaultCashRegisterId;
  final bool enabled;
  final int? currencyId;
  final String currencyUnit;
  final int decimalPlaces;
  final AuthStore authStore;
  final CalendarController calendarController;
  final bool isAnonymousCustomer;

  const QuickSalesPaymentComposer({
    super.key,
    required this.businessId,
    required this.payments,
    required this.onChanged,
    required this.cashFollowsTotal,
    required this.onCashFollowsTotalChanged,
    required this.invoiceTotal,
    required this.defaultCashRegisterId,
    required this.enabled,
    required this.authStore,
    required this.calendarController,
    this.currencyId,
    this.currencyUnit = 'ریال',
    this.decimalPlaces = 0,
    this.isAnonymousCustomer = false,
  });

  @override
  State<QuickSalesPaymentComposer> createState() =>
      _QuickSalesPaymentComposerState();
}

class _QuickSalesPaymentComposerState extends State<QuickSalesPaymentComposer> {
  static const _uuid = Uuid();
  static const _maxLines = 6;

  String? _lastBankId;
  String? _focusAmountId;

  num get _epsilon {
    if (widget.decimalPlaces <= 0) return 0.5;
    var e = 1.0;
    for (var i = 0; i < widget.decimalPlaces; i++) {
      e /= 10;
    }
    return e / 2;
  }

  num get _paid => widget.payments.fold<num>(0, (sum, p) => sum + p.amount);

  num get _remaining {
    final raw = widget.invoiceTotal - _paid;
    if (raw.abs() <= _epsilon) return 0;
    return _roundMoney(raw);
  }

  bool get _isOverpaid => _paid > widget.invoiceTotal + _epsilon;

  bool get _isSimpleCash {
    if (widget.payments.length != 1) return false;
    return widget.payments.first.type == TransactionType.cashRegister;
  }

  bool get _canAdd => widget.enabled && widget.payments.length < _maxLines;

  @override
  void initState() {
    super.initState();
    _loadLastBank();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCashFollowOrSeed();
    });
  }

  @override
  void didUpdateWidget(covariant QuickSalesPaymentComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final totalChanged = oldWidget.invoiceTotal != widget.invoiceTotal;
    final followChanged = oldWidget.cashFollowsTotal != widget.cashFollowsTotal;
    final registerChanged =
        oldWidget.defaultCashRegisterId != widget.defaultCashRegisterId;
    if (totalChanged || followChanged || registerChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncCashFollowOrSeed();
      });
    }
  }

  Future<void> _loadLastBank() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_bankPrefKey(widget.businessId));
      if (!mounted) return;
      setState(() => _lastBankId = id);
    } catch (_) {}
  }

  Future<void> _rememberBank(String id) async {
    _lastBankId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_bankPrefKey(widget.businessId), id);
    } catch (_) {}
  }

  static String _bankPrefKey(int businessId) =>
      'quick_sales_last_bank_$businessId';

  num _roundMoney(num value) {
    if (widget.decimalPlaces <= 0) return value.round();
    var f = 1;
    for (var i = 0; i < widget.decimalPlaces; i++) {
      f *= 10;
    }
    return (value * f).round() / f;
  }

  bool _amountsEqual(num a, num b) => (a - b).abs() <= _epsilon;

  bool _computeFollows(List<InvoiceTransaction> list) {
    if (list.length != 1) return false;
    if (list.first.type != TransactionType.cashRegister) return false;
    if (widget.invoiceTotal <= 0) return true;
    return _amountsEqual(list.first.amount, widget.invoiceTotal);
  }

  void _emit(List<InvoiceTransaction> next) {
    widget.onChanged(List<InvoiceTransaction>.from(next));
    widget.onCashFollowsTotalChanged(_computeFollows(next));
  }

  void _syncCashFollowOrSeed() {
    if (!widget.enabled) return;

    if (widget.payments.isEmpty) {
      if (!widget.cashFollowsTotal) return;
      final registerId = widget.defaultCashRegisterId;
      if (registerId == null || registerId.isEmpty) return;
      if (widget.invoiceTotal <= 0) return;
      _emit([_newCash(registerId: registerId, amount: widget.invoiceTotal)]);
      return;
    }

    if (!widget.cashFollowsTotal) return;
    if (widget.payments.length != 1) return;
    final only = widget.payments.first;
    if (only.type != TransactionType.cashRegister) return;
    final target = widget.invoiceTotal <= 0 ? 0 : widget.invoiceTotal;
    if (_amountsEqual(only.amount, target)) return;
    _emit([only.copyWith(amount: target)]);
  }

  InvoiceTransaction _newCash({
    String? registerId,
    String? registerName,
    required num amount,
  }) {
    final id = registerId != null && registerId.isNotEmpty ? registerId : null;
    return InvoiceTransaction(
      id: _uuid.v4(),
      type: TransactionType.cashRegister,
      cashRegisterId: id,
      cashRegisterName: registerName,
      transactionDate: DateTime.now(),
      amount: amount,
    );
  }

  InvoiceTransaction _newBank({
    String? bankId,
    String? bankName,
    required num amount,
  }) {
    return InvoiceTransaction(
      id: _uuid.v4(),
      type: TransactionType.bank,
      bankId: bankId,
      bankName: bankName,
      transactionDate: DateTime.now(),
      amount: amount,
    );
  }

  InvoiceTransaction _newCheck({required num amount}) {
    return InvoiceTransaction(
      id: _uuid.v4(),
      type: TransactionType.check,
      transactionDate: DateTime.now(),
      amount: amount,
    );
  }

  num _amountForNewLine() {
    if (_remaining > 0) return _remaining;
    return 0;
  }

  void _addCash() {
    if (!_canAdd) return;
    final tx = _newCash(
      registerId: widget.defaultCashRegisterId,
      amount: _amountForNewLine(),
    );
    _focusAmountId = tx.id;
    _emit([...widget.payments, tx]);
  }

  void _addBank() {
    if (!_canAdd) return;
    final tx = _newBank(bankId: _lastBankId, amount: _amountForNewLine());
    _focusAmountId = tx.id;
    _emit([...widget.payments, tx]);
  }

  void _addCheck() {
    if (!_canAdd) return;
    final tx = _newCheck(amount: _amountForNewLine());
    _focusAmountId = tx.id;
    _emit([...widget.payments, tx]);
  }

  void _replaceAt(int index, InvoiceTransaction tx) {
    final next = List<InvoiceTransaction>.from(widget.payments);
    next[index] = tx;
    _emit(next);
  }

  void _removeAt(int index) {
    final next = List<InvoiceTransaction>.from(widget.payments)
      ..removeAt(index);
    _emit(next);
  }

  void _fillRemaining(int index) {
    if (_remaining <= 0) return;
    final current = widget.payments[index];
    _replaceAt(index, current.copyWith(amount: current.amount + _remaining));
  }

  void _onAmountEdited(int index, num amount) {
    final safe = amount < 0 ? 0 : amount;
    _replaceAt(index, widget.payments[index].copyWith(amount: safe));
  }

  String _format(num value) =>
      formatWithThousands(value, decimalPlaces: widget.decimalPlaces);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isSimpleCash || _remaining != 0 || _isOverpaid)
          _buildBalanceStrip(t, theme, cs),
        if (_isSimpleCash) ...[
          CashRegisterComboboxWidget(
            businessId: widget.businessId,
            selectedRegisterId: widget.payments.first.cashRegisterId,
            filterCurrencyId: widget.currencyId,
            dense: true,
            onChanged: widget.enabled
                ? (option) {
                    _replaceAt(
                      0,
                      widget.payments.first.copyWith(
                        cashRegisterId: option?.id,
                        cashRegisterName: option?.name,
                      ),
                    );
                  }
                : (_) {},
            label: t.quickSalesPayCashRegister,
            hintText: t.quickSalesPayCashRegisterHint,
            isRequired: true,
          ),
          const SizedBox(height: 8),
          _PaymentAmountField(
            key: ValueKey('amt-${widget.payments.first.id}'),
            paymentId: widget.payments.first.id,
            amount: widget.payments.first.amount,
            decimalPlaces: widget.decimalPlaces,
            currencyUnit: widget.currencyUnit,
            enabled: widget.enabled,
            autofocus: false,
            onAmountChanged: (v) => _onAmountEdited(0, v),
          ),
        ] else ...[
          for (var i = 0; i < widget.payments.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PaymentRow(
              key: ValueKey(widget.payments[i].id),
              payment: widget.payments[i],
              businessId: widget.businessId,
              currencyId: widget.currencyId,
              currencyUnit: widget.currencyUnit,
              decimalPlaces: widget.decimalPlaces,
              enabled: widget.enabled,
              remaining: _remaining,
              canFillRemaining: widget.enabled && _remaining > 0,
              autofocusAmount: _focusAmountId == widget.payments[i].id,
              authStore: widget.authStore,
              calendarController: widget.calendarController,
              onChanged: (tx) {
                if (tx.type == TransactionType.bank &&
                    tx.bankId != null &&
                    tx.bankId!.isNotEmpty) {
                  unawaitedRememberBank(tx.bankId!);
                }
                _replaceAt(i, tx);
              },
              onFillRemaining: () => _fillRemaining(i),
              onRemove: () => _removeAt(i),
              onAmountChanged: (v) => _onAmountEdited(i, v),
            ),
          ],
        ],
        const SizedBox(height: 10),
        _buildAddButtons(t),
        if (_remaining > 0 && !_isOverpaid) ...[
          const SizedBox(height: 10),
          _buildRemainingNote(t, cs),
        ],
      ],
    );
  }

  void unawaitedRememberBank(String id) {
    _rememberBank(id);
  }

  Widget _buildBalanceStrip(
    AppLocalizations t,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final Color bg;
    final Color fg;
    final String status;
    if (_isOverpaid) {
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
      status = t.quickSalesPayOverpaid;
    } else if (_remaining > 0) {
      bg = cs.tertiaryContainer.withValues(alpha: 0.65);
      fg = cs.onTertiaryContainer;
      status = t.quickSalesPayPartialStatus;
    } else {
      bg = cs.primaryContainer.withValues(alpha: 0.7);
      fg = cs.onPrimaryContainer;
      status = t.quickSalesPaySettled;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _BalanceStat(
                      label: t.quickSalesPayPaidLabel,
                      value: _format(_paid),
                      color: fg,
                    ),
                  ),
                  Expanded(
                    child: _BalanceStat(
                      label: t.quickSalesPayRemainingLabel,
                      value: _format(_remaining < 0 ? 0 : _remaining),
                      color: fg,
                      emphasize: _remaining > 0 || _isOverpaid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemainingNote(AppLocalizations t, ColorScheme cs) {
    return Text(
      widget.isAnonymousCustomer
          ? t.quickSalesPayRemainingAnonymousHint
          : t.quickSalesPayRemainingCustomerHint,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
    );
  }

  Widget _buildAddButtons(AppLocalizations t) {
    final showCash = !_isSimpleCash;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (showCash)
          _AddMethodButton(
            icon: Icons.point_of_sale,
            label: t.quickSalesPayAddCash,
            enabled: _canAdd,
            onPressed: _addCash,
          ),
        _AddMethodButton(
          icon: Icons.account_balance,
          label: t.quickSalesPayAddBank,
          enabled: _canAdd,
          onPressed: _addBank,
        ),
        _AddMethodButton(
          icon: Icons.receipt_long,
          label: t.quickSalesPayAddCheck,
          enabled: _canAdd,
          onPressed: _addCheck,
        ),
      ],
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool emphasize;

  const _BalanceStat({
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AddMethodButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _AddMethodButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final InvoiceTransaction payment;
  final int businessId;
  final int? currencyId;
  final String currencyUnit;
  final int decimalPlaces;
  final bool enabled;
  final num remaining;
  final bool canFillRemaining;
  final bool autofocusAmount;
  final AuthStore authStore;
  final CalendarController calendarController;
  final ValueChanged<InvoiceTransaction> onChanged;
  final VoidCallback onFillRemaining;
  final VoidCallback onRemove;
  final ValueChanged<num> onAmountChanged;

  const _PaymentRow({
    super.key,
    required this.payment,
    required this.businessId,
    required this.currencyId,
    required this.currencyUnit,
    required this.decimalPlaces,
    required this.enabled,
    required this.remaining,
    required this.canFillRemaining,
    required this.autofocusAmount,
    required this.authStore,
    required this.calendarController,
    required this.onChanged,
    required this.onFillRemaining,
    required this.onRemove,
    required this.onAmountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                _MethodBadge(type: payment.type),
                const SizedBox(width: 8),
                Expanded(child: _buildDestination(t)),
                IconButton(
                  onPressed: enabled && canFillRemaining
                      ? onFillRemaining
                      : null,
                  tooltip: t.quickSalesPayFillRemaining,
                  icon: const Icon(Icons.done_all, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: enabled ? onRemove : null,
                  tooltip: t.quickSalesPayRemoveLine,
                  icon: const Icon(Icons.close, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PaymentAmountField(
              key: ValueKey('amt-${payment.id}'),
              paymentId: payment.id,
              amount: payment.amount,
              decimalPlaces: decimalPlaces,
              currencyUnit: currencyUnit,
              enabled: enabled,
              autofocus: autofocusAmount,
              onAmountChanged: onAmountChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestination(AppLocalizations t) {
    switch (payment.type) {
      case TransactionType.cashRegister:
        return CashRegisterComboboxWidget(
          businessId: businessId,
          selectedRegisterId: payment.cashRegisterId,
          filterCurrencyId: currencyId,
          dense: true,
          onChanged: enabled
              ? (option) {
                  onChanged(
                    payment.copyWith(
                      cashRegisterId: option?.id,
                      cashRegisterName: option?.name,
                    ),
                  );
                }
              : (_) {},
          label: t.quickSalesPayCashRegister,
          hintText: t.quickSalesPayCashRegisterHint,
          isRequired: true,
        );
      case TransactionType.bank:
        return BankAccountComboboxWidget(
          businessId: businessId,
          selectedAccountId: payment.bankId,
          filterCurrencyId: currencyId,
          dense: true,
          onChanged: enabled
              ? (option) {
                  onChanged(
                    payment.copyWith(
                      bankId: option?.id,
                      bankName: option?.name,
                    ),
                  );
                }
              : (_) {},
          label: t.quickSalesPayBank,
          hintText: t.quickSalesPayBankHint,
          isRequired: true,
        );
      case TransactionType.check:
        return CheckComboboxWidget(
          businessId: businessId,
          selectedCheckId: payment.checkId,
          selectedCheckNumber: payment.checkNumber,
          filterCurrencyId: currencyId,
          dense: true,
          mode: CheckPickerMode.receipt,
          authStore: authStore,
          calendarController: calendarController,
          onChanged: enabled
              ? (option) {
                  var amount = payment.amount;
                  if (option?.amount != null && option!.amount! > 0) {
                    if (payment.amount <= 0 || payment.checkId == null) {
                      final maxAllowed = remaining + payment.amount;
                      amount = option.amount! > maxAllowed
                          ? maxAllowed
                          : option.amount!;
                      if (amount <= 0) amount = payment.amount;
                    }
                  }
                  onChanged(
                    payment.copyWith(
                      checkId: option?.id,
                      checkNumber: option?.number,
                      amount: amount,
                    ),
                  );
                }
              : (_) {},
          label: t.quickSalesPayCheck,
          hintText: t.quickSalesPayCheckHint,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _MethodBadge extends StatelessWidget {
  final TransactionType type;

  const _MethodBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final IconData icon;
    switch (type) {
      case TransactionType.cashRegister:
        icon = Icons.point_of_sale;
        break;
      case TransactionType.bank:
        icon = Icons.account_balance;
        break;
      case TransactionType.check:
        icon = Icons.receipt_long;
        break;
      default:
        icon = Icons.payments;
    }
    return Tooltip(
      message: type.label,
      child: CircleAvatar(
        radius: 16,
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        child: Icon(icon, size: 16),
      ),
    );
  }
}

class _PaymentAmountField extends StatefulWidget {
  final String paymentId;
  final num amount;
  final int decimalPlaces;
  final String currencyUnit;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<num> onAmountChanged;

  const _PaymentAmountField({
    super.key,
    required this.paymentId,
    required this.amount,
    required this.decimalPlaces,
    required this.currencyUnit,
    required this.enabled,
    required this.autofocus,
    required this.onAmountChanged,
  });

  @override
  State<_PaymentAmountField> createState() => _PaymentAmountFieldState();
}

class _PaymentAmountFieldState extends State<_PaymentAmountField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.amount));
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _PaymentAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paymentId != widget.paymentId) {
      _controller.text = _format(widget.amount);
      _editing = false;
      return;
    }
    if (!_editing && !_focus.hasFocus && oldWidget.amount != widget.amount) {
      _controller.text = _format(widget.amount);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _format(num value) =>
      formatWithThousands(value, decimalPlaces: widget.decimalPlaces);

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _editing = true;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
      return;
    }
    _editing = false;
    final parsed = parseFormattedNumber(_controller.text) ?? 0;
    _controller.text = _format(parsed);
    widget.onAmountChanged(parsed);
  }

  void _commitFromText() {
    final parsed = parseFormattedNumber(_controller.text) ?? 0;
    widget.onAmountChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final allowDecimal = widget.decimalPlaces > 0;
    return AmountFieldWordsTooltip(
      controller: _controller,
      currencyUnit: widget.currencyUnit,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
        textInputAction: TextInputAction.next,
        inputFormatters: [
          EnglishDigitsFormatter(),
          FilteringTextInputFormatter.allow(
            allowDecimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9,]'),
          ),
          ThousandsSeparatorInputFormatter(
            allowDecimal: allowDecimal,
            maxDecimalPlaces: allowDecimal ? widget.decimalPlaces : null,
          ),
        ],
        decoration: InputDecoration(
          labelText: t.quickSalesPayAmount,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixText: widget.currencyUnit,
        ),
        onChanged: (_) => _commitFromText(),
        onSubmitted: (_) => _commitFromText(),
      ),
    );
  }
}
