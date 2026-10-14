import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth_store.dart';
import '../../models/invoice_transaction.dart';
import '../../models/person_model.dart';
import '../../models/quick_sales_payment_button.dart';
import '../../models/quick_sales_change_resolution.dart';
import '../../services/person_service.dart';
import '../../services/quick_sales_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../invoice/bank_account_combobox_widget.dart';
import '../invoice/cash_register_combobox_widget.dart';
import '../invoice/person_combobox_widget.dart';

class QuickSalesPaymentDock extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final List<InvoiceTransaction> payments;
  final ValueChanged<List<InvoiceTransaction>> onChanged;
  final num invoiceTotal;
  final QuickSalesChangeResolution? changeResolution;
  final Future<QuickSalesChangeResolution?> Function() onConfigureChange;
  final String? defaultCashRegisterId;
  final String currencyUnit;
  final int decimalPlaces;
  final bool enabled;
  final VoidCallback onSave;
  final VoidCallback onSaveAndPrint;

  const QuickSalesPaymentDock({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.payments,
    required this.onChanged,
    required this.invoiceTotal,
    required this.changeResolution,
    required this.onConfigureChange,
    required this.defaultCashRegisterId,
    required this.currencyUnit,
    required this.decimalPlaces,
    required this.enabled,
    required this.onSave,
    required this.onSaveAndPrint,
  });

  @override
  State<QuickSalesPaymentDock> createState() => _QuickSalesPaymentDockState();
}

class _QuickSalesPaymentDockState extends State<QuickSalesPaymentDock> {
  static const _uuid = Uuid();
  static const double _defaultButtonWidth = 384;
  static const double _minButtonWidth = 300;
  static const double _minListWidth = 360;
  static const double _summaryWidth = 384;
  static const int _maxPaymentLines = 50;

  final QuickSalesService _service = QuickSalesService();
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  final ScrollController _paymentScroll = ScrollController();
  final ScrollController _buttonScroll = ScrollController();
  List<QuickSalesPaymentButtonModel> _buttons = const [];
  bool _loadingButtons = true;
  double _buttonWidth = _defaultButtonWidth;

  num get _epsilon {
    if (widget.decimalPlaces <= 0) return 0.5;
    var value = 1.0;
    for (var i = 0; i < widget.decimalPlaces; i++) {
      value /= 10;
    }
    return value / 2;
  }

  num get _paid =>
      widget.payments.fold<num>(0, (sum, p) => sum + p.settlesAgainstInvoice);
  num get _remaining => (widget.invoiceTotal - _paid) > _epsilon
      ? widget.invoiceTotal - _paid
      : 0;
  num get _change => (_paid - widget.invoiceTotal) > _epsilon
      ? _paid - widget.invoiceTotal
      : 0;

  String get _preferenceKey =>
      'quick_sales_payment_dock_buttons_width_v2_${widget.businessId}_${widget.authStore.currentUserId ?? 0}';

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleShortcutKeyEvent);
    _amountFocus.addListener(() {
      if (_amountFocus.hasFocus) {
        _amountController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _amountController.text.length,
        );
      }
    });
    _syncAmount();
    unawaited(_loadButtons());
    unawaited(_loadWidth());
  }

  @override
  void didUpdateWidget(covariant QuickSalesPaymentDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoiceTotal != widget.invoiceTotal ||
        oldWidget.payments != widget.payments) {
      _syncAmount();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleShortcutKeyEvent);
    _amountController.dispose();
    _amountFocus.dispose();
    _paymentScroll.dispose();
    _buttonScroll.dispose();
    super.dispose();
  }

  void _syncAmount() {
    final next = formatNumberForInput(
      _remaining,
      decimalPlaces: widget.decimalPlaces,
    );
    if (_amountController.text == next) return;
    _amountController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  bool _handleShortcutKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || !widget.enabled || _loadingButtons) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final key = event.logicalKey.keyLabel.trim().toUpperCase();
    if (key.isEmpty) return false;
    final keyboard = HardwareKeyboard.instance;
    final parts = <String>[
      if (keyboard.isControlPressed || keyboard.isMetaPressed) 'CTRL',
      if (keyboard.isAltPressed) 'ALT',
      if (keyboard.isShiftPressed) 'SHIFT',
      key,
    ];
    final shortcut = parts.join('+');
    for (final button in _buttons) {
      if ((button.shortcut ?? '').replaceAll(' ', '').toUpperCase() ==
          shortcut) {
        _addPayment(button);
        return true;
      }
    }
    return false;
  }

  Future<void> _loadButtons() async {
    try {
      final rows = await _service.listPaymentButtons(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        _buttons = rows;
        _loadingButtons = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingButtons = false);
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.forContext(e, context),
        isError: true,
      );
    }
  }

  Future<void> _loadWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_preferenceKey);
    if (mounted && value != null) setState(() => _buttonWidth = value);
  }

  Future<void> _saveWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_preferenceKey, _buttonWidth);
  }

  String _format(num value) =>
      formatWithThousands(value, decimalPlaces: widget.decimalPlaces);

  void _addPayment(QuickSalesPaymentButtonModel button) {
    if (!widget.enabled) return;
    if (widget.payments.length >= _maxPaymentLines) {
      SnackBarHelper.show(
        context,
        message: 'حداکثر ۵۰ ردیف پرداخت برای یک فاکتور مجاز است.',
        isError: true,
      );
      return;
    }
    final amount = parseFormattedNumber(_amountController.text) ?? 0;
    if (amount <= _epsilon) {
      SnackBarHelper.show(
        context,
        message: 'مبلغ پرداخت را وارد کنید.',
        isError: true,
      );
      _amountFocus.requestFocus();
      return;
    }
    final tx = switch (button.targetType) {
      QuickSalesPaymentTargetType.cashRegister => InvoiceTransaction(
        id: _uuid.v4(),
        type: TransactionType.cashRegister,
        cashRegisterId: button.targetId.toString(),
        cashRegisterName: button.targetName,
        transactionDate: DateTime.now(),
        amount: amount,
      ),
      QuickSalesPaymentTargetType.bank => InvoiceTransaction(
        id: _uuid.v4(),
        type: TransactionType.bank,
        bankId: button.targetId.toString(),
        bankName: button.targetName,
        transactionDate: DateTime.now(),
        amount: amount,
      ),
      QuickSalesPaymentTargetType.person => InvoiceTransaction(
        id: _uuid.v4(),
        type: TransactionType.person,
        personId: button.targetId.toString(),
        personName: button.targetName,
        transactionDate: DateTime.now(),
        amount: amount,
      ),
    };
    widget.onChanged([...widget.payments, tx]);
  }

  void _removePayment(String id) {
    widget.onChanged(widget.payments.where((p) => p.id != id).toList());
  }

  void _updatePaymentAmount(InvoiceTransaction payment, String raw) {
    final amount = parseFormattedNumber(raw) ?? 0;
    if (amount <= _epsilon) {
      _removePayment(payment.id);
      return;
    }
    widget.onChanged([
      for (final row in widget.payments)
        if (row.id == payment.id) row.copyWith(amount: amount) else row,
    ]);
  }

  String _paymentTitle(InvoiceTransaction payment) => switch (payment.type) {
    TransactionType.cashRegister =>
      'دریافت در ${payment.cashRegisterName ?? 'صندوق'}',
    TransactionType.bank => 'دریافت در ${payment.bankName ?? 'بانک'}',
    TransactionType.person => 'دریافت نزد ${payment.personName ?? 'شخص'}',
    TransactionType.check => 'دریافت با چک ${payment.checkNumber ?? ''}',
    _ => payment.type.label,
  };

  IconData _paymentIcon(TransactionType type) => switch (type) {
    TransactionType.cashRegister => Icons.payments_outlined,
    TransactionType.bank => Icons.account_balance,
    TransactionType.person => Icons.person_outline,
    TransactionType.check => Icons.receipt_long,
    _ => Icons.account_balance_wallet_outlined,
  };

  IconData _buttonIcon(QuickSalesPaymentTargetType type) => switch (type) {
    QuickSalesPaymentTargetType.cashRegister => Icons.payments_outlined,
    QuickSalesPaymentTargetType.bank => Icons.account_balance,
    QuickSalesPaymentTargetType.person => Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: cs.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 1050) {
            return SizedBox(height: 260, child: _buildCompact(cs));
          }
          final maxButtons =
              (constraints.maxWidth - _summaryWidth - _minListWidth - 12)
                  .clamp(_minButtonWidth, constraints.maxWidth * .62)
                  .toDouble();
          final buttonWidth = _buttonWidth
              .clamp(_minButtonWidth, maxButtons)
              .toDouble();
          return SizedBox(
            height: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: buttonWidth,
                    child: ColoredBox(
                      color: cs.surfaceContainerLow,
                      child: _buildAmountAndButtons(cs),
                    ),
                  ),
                  _ResizeHandle(
                    onReset: () {
                      setState(
                        () => _buttonWidth = _defaultButtonWidth
                            .clamp(_minButtonWidth, maxButtons)
                            .toDouble(),
                      );
                      unawaited(_saveWidth());
                    },
                    onDrag: (dx) {
                      setState(() {
                        _buttonWidth = (_buttonWidth - dx)
                            .clamp(_minButtonWidth, maxButtons)
                            .toDouble();
                      });
                    },
                    onDragEnd: () => unawaited(_saveWidth()),
                    onNudge: (dx) {
                      setState(() {
                        _buttonWidth = (_buttonWidth + dx)
                            .clamp(_minButtonWidth, maxButtons)
                            .toDouble();
                      });
                      unawaited(_saveWidth());
                    },
                  ),
                  Expanded(child: _buildPaymentList(cs)),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: cs.outlineVariant,
                  ),
                  SizedBox(
                    width: _summaryWidth,
                    child: ColoredBox(
                      color: cs.surfaceContainerLow,
                      child: _buildSummary(cs),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompact(ColorScheme cs) {
    return Column(
      children: [
        Expanded(
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(child: _buildAmountAndButtons(cs)),
              Expanded(child: _buildPaymentList(cs)),
            ],
          ),
        ),
        SizedBox(height: 76, child: _buildSummary(cs, horizontal: true)),
      ],
    );
  }

  Widget _buildSummary(ColorScheme cs, {bool horizontal = false}) {
    final figures = [
      _SummaryValue(label: 'جمع کل', value: _format(widget.invoiceTotal)),
      _SummaryValue(label: 'پرداخت‌شده', value: _format(_paid)),
    ];
    final actions = [
      OutlinedButton.icon(
        onPressed: widget.enabled ? widget.onSave : null,
        icon: const Icon(Icons.save_outlined),
        label: const Text('ثبت'),
      ),
      FilledButton.icon(
        onPressed: widget.enabled ? widget.onSaveAndPrint : null,
        icon: const Icon(Icons.print_outlined),
        label: const Text('ثبت و چاپ'),
      ),
    ];
    if (horizontal) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ...figures.map((e) => Expanded(child: e)),
            ...actions.map(
              (e) => Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: e,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...figures,
          const Spacer(),
          Row(
            children: [
              Expanded(child: actions.first),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: actions.last),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentList(ColorScheme cs) {
    if (widget.payments.isEmpty) {
      return Center(
        child: Text(
          'هنوز پرداختی ثبت نشده است',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Scrollbar(
      controller: _paymentScroll,
      thumbVisibility: true,
      child: ListView.separated(
        controller: _paymentScroll,
        padding: const EdgeInsets.all(10),
        itemCount: widget.payments.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, color: cs.outlineVariant),
        itemBuilder: (context, index) {
          final payment = widget.payments[index];
          return SizedBox(
            height: 58,
            child: Row(
              children: [
                Icon(_paymentIcon(payment.type), color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _paymentTitle(payment),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 145,
                  child: TextFormField(
                    key: ValueKey('payment-${payment.id}'),
                    initialValue: formatNumberForInput(
                      payment.amount,
                      decimalPlaces: widget.decimalPlaces,
                    ),
                    enabled: widget.enabled,
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
                      isDense: true,
                      suffixText: widget.currencyUnit,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final amount = parseFormattedNumber(value);
                      if (amount != null && amount > _epsilon) {
                        _updatePaymentAmount(payment, value);
                      }
                    },
                    onFieldSubmitted: (value) =>
                        _updatePaymentAmount(payment, value),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف پرداخت',
                  onPressed: widget.enabled
                      ? () => _removePayment(payment.id)
                      : null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAmountAndButtons(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _amountController,
            focusNode: _amountFocus,
            enabled: widget.enabled,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              const EnglishDigitsFormatter(),
              ThousandsSeparatorInputFormatter(
                allowDecimal: widget.decimalPlaces > 0,
              ),
            ],
            decoration: InputDecoration(
              labelText: 'مبلغ پرداخت',
              suffixText: widget.currencyUnit,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_change > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: widget.enabled
                    ? () => unawaited(widget.onConfigureChange())
                    : null,
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.changeResolution == null
                              ? 'تعیین تکلیف ${_format(_change)} ${widget.currencyUnit}'
                              : 'برگشت ${_format(widget.changeResolution!.returnedAmount)} • بستانکاری ${_format(widget.changeResolution!.creditAmount)}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        widget.changeResolution == null
                            ? Icons.rule_folder_outlined
                            : Icons.edit_outlined,
                        size: 18,
                        color: cs.onErrorContainer,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loadingButtons
                ? const Center(child: CircularProgressIndicator())
                : Scrollbar(
                    controller: _buttonScroll,
                    thumbVisibility: _buttons.length > 6,
                    child: GridView.builder(
                      controller: _buttonScroll,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 122,
                            mainAxisExtent: 66,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: _buttons.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _buttons.length) {
                          return OutlinedButton.icon(
                            onPressed: widget.enabled
                                ? () => _openEditor()
                                : null,
                            icon: const Icon(Icons.add),
                            label: const Text(
                              'تعریف دکمه',
                              textAlign: TextAlign.center,
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: cs.primary,
                                style: BorderStyle.solid,
                              ),
                            ),
                          );
                        }
                        final button = _buttons[index];
                        final canReorder =
                            !button.isSystem &&
                            (widget.authStore.hasBusinessPermission(
                                  'settings',
                                  'business',
                                ) ||
                                _buttons.every((row) => row.isPersonal));
                        return _PaymentTargetTile(
                          button: button,
                          icon: _buttonIcon(button.targetType),
                          enabled: widget.enabled,
                          onPressed: () => _addPayment(button),
                          onEdit: button.isSystem
                              ? null
                              : () => _openEditor(existing: button),
                          onDelete: button.isSystem
                              ? null
                              : () => _deleteButton(button),
                          onMoveBefore: canReorder && index > 0
                              ? () => _moveButton(index, -1)
                              : null,
                          onMoveAfter: canReorder && index < _buttons.length - 1
                              ? () => _moveButton(index, 1)
                              : null,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteButton(QuickSalesPaymentButtonModel button) async {
    final numericId = button.id is num
        ? (button.id as num).toInt()
        : int.tryParse('${button.id}');
    if (numericId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف دکمه پرداخت'),
        content: Text('دکمه «${button.label}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deletePaymentButton(
        businessId: widget.businessId,
        buttonId: numericId,
      );
      await _loadButtons();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    }
  }

  Future<void> _moveButton(int index, int offset) async {
    final destination = index + offset;
    if (index < 0 ||
        index >= _buttons.length ||
        destination < 0 ||
        destination >= _buttons.length) {
      return;
    }
    final next = List<QuickSalesPaymentButtonModel>.from(_buttons);
    final moved = next.removeAt(index);
    next.insert(destination, moved);
    final ids = <int>[];
    for (final button in next) {
      final id = button.id is num
          ? (button.id as num).toInt()
          : int.tryParse('${button.id}');
      if (id == null) return;
      ids.add(id);
    }
    setState(() => _buttons = next);
    try {
      final saved = await _service.reorderPaymentButtons(
        businessId: widget.businessId,
        buttonIds: ids,
      );
      if (mounted) setState(() => _buttons = saved);
    } catch (e) {
      if (!mounted) return;
      await _loadButtons();
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    }
  }

  Future<void> _openEditor({QuickSalesPaymentButtonModel? existing}) async {
    Person? selectedPerson;
    if (existing?.targetType == QuickSalesPaymentTargetType.person) {
      try {
        selectedPerson = await PersonService().getPerson(existing!.targetId);
      } catch (_) {}
    }
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _PaymentButtonEditorDialog(
        businessId: widget.businessId,
        service: _service,
        existing: existing,
        initialPerson: selectedPerson,
        canCreateShared: widget.authStore.hasBusinessPermission(
          'settings',
          'business',
        ),
      ),
    );
    if (changed == true) await _loadButtons();
  }
}

class _ResizeHandle extends StatelessWidget {
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onNudge;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  const _ResizeHandle({
    required this.onDrag,
    required this.onNudge,
    required this.onDragEnd,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onNudge(24);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onNudge(-24);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          onDoubleTap: onReset,
          onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
          onHorizontalDragEnd: (_) => onDragEnd(),
          child: Semantics(
            label: 'تغییر عرض دکمه‌ها و فهرست پرداخت',
            hint: 'با کلیدهای جهت چپ و راست نیز قابل تغییر است',
            child: Container(
              width: 12,
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Container(
                width: 3,
                height: 54,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PaymentTargetTile extends StatelessWidget {
  final QuickSalesPaymentButtonModel button;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveBefore;
  final VoidCallback? onMoveAfter;

  const _PaymentTargetTile({
    required this.button,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.onEdit,
    this.onDelete,
    this.onMoveBefore,
    this.onMoveAfter,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: OutlinedButton(
            onPressed: enabled ? onPressed : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 3),
                Text(
                  button.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (button.shortcut != null)
                  Text(
                    button.shortcut!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ),
        if (onEdit != null ||
            onDelete != null ||
            onMoveBefore != null ||
            onMoveAfter != null)
          PositionedDirectional(
            top: 0,
            end: 0,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              iconSize: 17,
              tooltip: 'مدیریت دکمه',
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit?.call();
                    break;
                  case 'delete':
                    onDelete?.call();
                    break;
                  case 'before':
                    onMoveBefore?.call();
                    break;
                  case 'after':
                    onMoveAfter?.call();
                    break;
                }
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                if (onMoveBefore != null)
                  const PopupMenuItem(
                    value: 'before',
                    child: Text('جابه‌جایی به قبل'),
                  ),
                if (onMoveAfter != null)
                  const PopupMenuItem(
                    value: 'after',
                    child: Text('جابه‌جایی به بعد'),
                  ),
                if (onDelete != null)
                  const PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
          ),
      ],
    );
  }
}

class _PaymentButtonEditorDialog extends StatefulWidget {
  final int businessId;
  final QuickSalesService service;
  final QuickSalesPaymentButtonModel? existing;
  final Person? initialPerson;
  final bool canCreateShared;

  const _PaymentButtonEditorDialog({
    required this.businessId,
    required this.service,
    required this.existing,
    required this.initialPerson,
    required this.canCreateShared,
  });

  @override
  State<_PaymentButtonEditorDialog> createState() =>
      _PaymentButtonEditorDialogState();
}

class _PaymentButtonEditorDialogState
    extends State<_PaymentButtonEditorDialog> {
  late QuickSalesPaymentTargetType _type;
  late final TextEditingController _labelController;
  late final TextEditingController _shortcutController;
  String? _cashId;
  String? _bankId;
  Person? _person;
  bool _shared = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.targetType ?? QuickSalesPaymentTargetType.cashRegister;
    _labelController = TextEditingController(
      text: existing?.targetType == QuickSalesPaymentTargetType.person
          ? ''
          : existing?.label ?? '',
    );
    _shortcutController = TextEditingController(text: existing?.shortcut ?? '');
    _shared = existing?.scope == 'business';
    if (existing?.targetType == QuickSalesPaymentTargetType.cashRegister) {
      _cashId = existing!.targetId.toString();
    }
    if (existing?.targetType == QuickSalesPaymentTargetType.bank) {
      _bankId = existing!.targetId.toString();
    }
    _person = widget.initialPerson;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _shortcutController.dispose();
    super.dispose();
  }

  int? get _targetId => switch (_type) {
    QuickSalesPaymentTargetType.cashRegister => int.tryParse(_cashId ?? ''),
    QuickSalesPaymentTargetType.bank => int.tryParse(_bankId ?? ''),
    QuickSalesPaymentTargetType.person => _person?.id,
  };

  Future<void> _save() async {
    if (_targetId == null) {
      SnackBarHelper.show(
        context,
        message: 'مقصد پرداخت را انتخاب کنید.',
        isError: true,
      );
      return;
    }
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'scope': _shared ? 'business' : 'user',
      'target_type': QuickSalesPaymentButtonModel.targetTypeValue(_type),
      'target_id': _targetId,
      if (_type != QuickSalesPaymentTargetType.person)
        'label': _labelController.text.trim(),
      'shortcut': _shortcutController.text.trim(),
    };
    try {
      final existingId = widget.existing?.id;
      final numericId = existingId is num
          ? existingId.toInt()
          : int.tryParse('$existingId');
      if (numericId == null) {
        await widget.service.createPaymentButton(
          businessId: widget.businessId,
          payload: payload,
        );
      } else {
        await widget.service.updatePaymentButton(
          businessId: widget.businessId,
          buttonId: numericId,
          payload: payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.forContext(e, context),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'تعریف دکمه پرداخت' : 'ویرایش دکمه پرداخت',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<QuickSalesPaymentTargetType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'نوع مقصد',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: QuickSalesPaymentTargetType.cashRegister,
                    child: Text('صندوق'),
                  ),
                  DropdownMenuItem(
                    value: QuickSalesPaymentTargetType.bank,
                    child: Text('بانک'),
                  ),
                  DropdownMenuItem(
                    value: QuickSalesPaymentTargetType.person,
                    child: Text('شخص'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 12),
              if (_type == QuickSalesPaymentTargetType.cashRegister)
                CashRegisterComboboxWidget(
                  businessId: widget.businessId,
                  selectedRegisterId: _cashId,
                  dense: true,
                  isRequired: true,
                  onChanged: (value) => setState(() => _cashId = value?.id),
                )
              else if (_type == QuickSalesPaymentTargetType.bank)
                BankAccountComboboxWidget(
                  businessId: widget.businessId,
                  selectedAccountId: _bankId,
                  dense: true,
                  isRequired: true,
                  onChanged: (value) => setState(() => _bankId = value?.id),
                )
              else
                PersonComboboxWidget(
                  businessId: widget.businessId,
                  selectedPerson: _person,
                  dense: true,
                  isRequired: true,
                  onChanged: (value) => setState(() => _person = value),
                ),
              if (_type != QuickSalesPaymentTargetType.person) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان دکمه (اختیاری)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _shortcutController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'کلید میانبر (اختیاری)',
                  hintText: 'مثلاً Alt+1',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.canCreateShared)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('نمایش برای همه کاربران'),
                  value: _shared,
                  onChanged: _saving || widget.existing != null
                      ? null
                      : (value) => setState(() => _shared = value),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ذخیره'),
        ),
      ],
    );
  }
}
