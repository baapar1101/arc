import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/calendar_controller.dart';
import '../../models/credit_models.dart';
import '../../services/credit_api_service.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../date_input_field.dart';

/// ویرایشگر طرح اقساط (فروش / برگشت از فروش) برای صفحهٔ ویرایش فاکتور و موارد مشابه.
class InvoiceInstallmentsEditor extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final num sumTotal;
  final DateTime? invoiceDate;
  final Map<String, dynamic>? initialInstallmentPlan;

  const InvoiceInstallmentsEditor({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.sumTotal,
    this.invoiceDate,
    this.initialInstallmentPlan,
  });

  @override
  State<InvoiceInstallmentsEditor> createState() => InvoiceInstallmentsEditorState();
}

class InvoiceInstallmentsEditorState extends State<InvoiceInstallmentsEditor> {
  int? _numInstallments;
  double? _downPayment;
  double? _interestRate;
  DateTime? _firstInstallmentDueDate;
  String _installmentPeriod = 'monthly';
  int? _installmentPeriodDays;
  List<Map<String, dynamic>> _installmentRows = <Map<String, dynamic>>[];
  List<InstallmentPlan> _installmentPlans = <InstallmentPlan>[];
  InstallmentPlan? _selectedInstallmentPlan;

  late final TextEditingController _numInstallmentsController;
  late final TextEditingController _downPaymentController;
  late final TextEditingController _interestRateController;
  late final TextEditingController _installmentPeriodDaysController;

  final Map<int, TextEditingController> _installmentPrincipalControllers = {};
  final Map<int, TextEditingController> _installmentInterestControllers = {};
  final Map<int, TextEditingController> _installmentTotalControllers = {};

  double get _installmentsPrincipalTotal {
    double sum = 0;
    for (final r in _installmentRows) {
      sum += (r['principal'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  double get _installmentsInterestTotal {
    double sum = 0;
    for (final r in _installmentRows) {
      sum += (r['interest'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  double get _installmentsTotal {
    double sum = 0;
    for (final r in _installmentRows) {
      sum += (r['total'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  bool get _anyPaid =>
      _installmentRows.any((r) => ((r['paid_amount'] as num?)?.toDouble() ?? 0.0) > 0.009);

  bool _rowHasPayment(Map<String, dynamic> r) =>
      ((r['paid_amount'] as num?)?.toDouble() ?? 0.0) > 0.009;

  @override
  void initState() {
    super.initState();
    _numInstallmentsController = TextEditingController();
    _downPaymentController = TextEditingController();
    _interestRateController = TextEditingController();
    _installmentPeriodDaysController = TextEditingController();
    _hydrateFromPlan(widget.initialInstallmentPlan);
    _loadInstallmentPlans();
  }

  @override
  void didUpdateWidget(covariant InvoiceInstallmentsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialInstallmentPlan != widget.initialInstallmentPlan &&
        widget.initialInstallmentPlan != null) {
      _disposeRowControllers();
      _hydrateFromPlan(widget.initialInstallmentPlan);
    }
  }

  void _hydrateFromPlan(Map<String, dynamic>? plan) {
    if (plan == null || plan.isEmpty) {
      _numInstallments = null;
      _downPayment = null;
      _interestRate = null;
      _firstInstallmentDueDate = widget.invoiceDate;
      _installmentPeriod = 'monthly';
      _installmentPeriodDays = 30;
      _installmentRows = [];
      return;
    }
    _downPayment = (plan['down_payment'] as num?)?.toDouble() ?? 0.0;
    _numInstallments = (plan['num_installments'] as num?)?.toInt();
    _interestRate = (plan['interest_rate'] as num?)?.toDouble();
    if (_interestRate == null && plan['interest_total'] != null && _numInstallments != null && _numInstallments! > 0) {
      final pt = (plan['principal_total'] as num?)?.toDouble();
      if (pt != null && pt > 0) {
        final it = (plan['interest_total'] as num?)?.toDouble() ?? 0;
        _interestRate = (it / pt) * 100.0;
      }
    }
    _interestRate ??= 0.0;

    final pd = plan['period_days'];
    if (pd != null) {
      _installmentPeriod = 'days';
      _installmentPeriodDays = (pd as num).toInt();
    } else {
      final per = plan['period']?.toString().toLowerCase();
      _installmentPeriod = per == 'days' ? 'days' : 'monthly';
      _installmentPeriodDays = (plan['period_days'] as num?)?.toInt() ?? 30;
    }

    final fd = plan['first_due_date']?.toString();
    if (fd != null && fd.length >= 10) {
      _firstInstallmentDueDate = DateTime.tryParse(fd.length >= 10 ? fd.substring(0, 10) : fd) ?? widget.invoiceDate;
    } else {
      _firstInstallmentDueDate = widget.invoiceDate;
    }

    final sch = plan['schedule'];
    final rows = <Map<String, dynamic>>[];
    if (sch is List) {
      for (var i = 0; i < sch.length; i++) {
        final it = sch[i];
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        DateTime? due;
        final ds = m['due_date']?.toString();
        if (ds != null && ds.length >= 10) {
          due = DateTime.tryParse(ds.substring(0, 10));
        }
        rows.add({
          'seq': (m['seq'] as num?)?.toInt() ?? (i + 1),
          'due_date': due ?? _firstInstallmentDueDate ?? widget.invoiceDate ?? DateTime.now(),
          'principal': (m['principal'] as num?)?.toDouble() ?? 0.0,
          'interest': (m['interest'] as num?)?.toDouble() ?? 0.0,
          'total': (m['total'] as num?)?.toDouble() ??
              (((m['principal'] as num?)?.toDouble() ?? 0) + ((m['interest'] as num?)?.toDouble() ?? 0)),
          'paid_amount': (m['paid_amount'] as num?)?.toDouble() ?? 0.0,
          if (m['status'] != null) 'status': m['status'].toString(),
        });
      }
    }
    _installmentRows = rows;
    _numInstallments ??= rows.isNotEmpty ? rows.length : null;

    _numInstallmentsController.text = formatNumberForInput(_numInstallments, decimalPlaces: 0);
    _downPaymentController.text = formatNumberForInput(_downPayment);
    _interestRateController.text = formatNumberForInput(_interestRate);
    _installmentPeriodDaysController.text =
        formatNumberForInput(_installmentPeriodDays ?? 30, decimalPlaces: 0);

    for (int idx = 0; idx < _installmentRows.length; idx++) {
      final principal = (_installmentRows[idx]['principal'] as num?)?.toDouble() ?? 0.0;
      final interest = (_installmentRows[idx]['interest'] as num?)?.toDouble() ?? 0.0;
      final total = (_installmentRows[idx]['total'] as num?)?.toDouble() ?? 0.0;
      _getInstallmentController(_installmentPrincipalControllers, idx, principal, updateIfChanged: false);
      _getInstallmentController(_installmentInterestControllers, idx, interest, updateIfChanged: false);
      _getInstallmentController(_installmentTotalControllers, idx, total, updateIfChanged: false);
    }
  }

  void _disposeRowControllers() {
    for (final c in _installmentPrincipalControllers.values) {
      c.dispose();
    }
    for (final c in _installmentInterestControllers.values) {
      c.dispose();
    }
    for (final c in _installmentTotalControllers.values) {
      c.dispose();
    }
    _installmentPrincipalControllers.clear();
    _installmentInterestControllers.clear();
    _installmentTotalControllers.clear();
  }

  @override
  void dispose() {
    _numInstallmentsController.dispose();
    _downPaymentController.dispose();
    _interestRateController.dispose();
    _installmentPeriodDaysController.dispose();
    _disposeRowControllers();
    super.dispose();
  }

  Future<void> _loadInstallmentPlans() async {
    try {
      final items = await CreditApiService.listInstallmentPlans(widget.businessId, onlyActive: true);
      if (mounted) {
        setState(() => _installmentPlans = items);
      }
    } catch (_) {}
  }

  TextEditingController _getInstallmentController(
    Map<int, TextEditingController> controllers,
    int index,
    double value, {
    bool updateIfChanged = true,
  }) {
    if (!controllers.containsKey(index)) {
      controllers[index] = TextEditingController(
        text: formatNumberForInput(value, decimalPlaces: 0),
      );
    } else if (updateIfChanged) {
      final currentText = formatNumberForInput(value, decimalPlaces: 0);
      final controller = controllers[index]!;
      if (controller.text != currentText) {
        controller.text = currentText;
      }
    }
    return controllers[index]!;
  }

  void _cleanupInstallmentControllers() {
    final maxIndex = _installmentRows.length - 1;
    _installmentPrincipalControllers.removeWhere((key, _) => key > maxIndex);
    _installmentInterestControllers.removeWhere((key, _) => key > maxIndex);
    _installmentTotalControllers.removeWhere((key, _) => key > maxIndex);
  }

  /// خطای فارسی یا null در صورت اعتبار.
  String? validate() {
    if (_installmentRows.isEmpty) {
      return 'برنامه اقساط خالی است. حداقل یک قسط تعریف کنید یا از «تولید خودکار اقساط» استفاده کنید.';
    }
    if ((_numInstallments ?? 0) <= 0) {
      return 'تعداد اقساط باید بیشتر از صفر باشد.';
    }
    final totalNet = widget.sumTotal.toDouble();
    final principalTarget = (totalNet - (_downPayment ?? 0)).clamp(0, double.infinity);
    double sumPrincipal = 0;
    for (final r in _installmentRows) {
      sumPrincipal += (r['principal'] as num?)?.toDouble() ?? 0.0;
    }
    if ((sumPrincipal - principalTarget).abs() > 1) {
      return 'جمع اصل اقساط (${sumPrincipal.toStringAsFixed(0)}) با مبلغ قابل دریافت (${principalTarget.toStringAsFixed(0)}) برابر نیست.';
    }
    for (final r in _installmentRows) {
      final total = (r['total'] as num?)?.toDouble() ?? 0.0;
      final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
      if (paid - total > 0.02) {
        return 'مبلغ قسط نمی‌تواند کمتر از مبلغ پرداخت‌شده (${paid.toStringAsFixed(0)}) باشد.';
      }
    }
    return null;
  }

  Map<String, dynamic> buildPlanMap() {
    final due0 = (_firstInstallmentDueDate ?? widget.invoiceDate ?? DateTime.now())
        .toIso8601String()
        .split('T')
        .first;
    final plan = <String, dynamic>{
      'down_payment': _downPayment ?? 0,
      'num_installments': _numInstallments ?? _installmentRows.length,
      'first_due_date': due0,
      if (_installmentPeriod == 'monthly') 'period': 'monthly',
      if (_installmentPeriod == 'days') 'period_days': _installmentPeriodDays ?? 30,
      if (_interestRate != null && _installmentRows.isEmpty) 'interest_rate': _interestRate,
      'method': 'flat',
    };
    final rows = <Map<String, dynamic>>[];
    double interestTotal = 0;
    for (var i = 0; i < _installmentRows.length; i++) {
      final r = _installmentRows[i];
      final dueDate = (r['due_date'] as DateTime? ?? _firstInstallmentDueDate ?? widget.invoiceDate ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first;
      final principal = (r['principal'] as num?)?.toDouble() ?? 0.0;
      final interest = (r['interest'] as num?)?.toDouble() ?? 0.0;
      final total = (r['total'] as num?)?.toDouble() ?? (principal + interest);
      interestTotal += interest;
      final row = <String, dynamic>{
        'seq': (r['seq'] as int?) ?? (i + 1),
        'due_date': dueDate,
        'principal': principal,
        'interest': interest,
        'total': total,
      };
      final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
      if (paid > 0) {
        row['paid_amount'] = paid;
      }
      final st = r['status']?.toString();
      if (st != null && st.isNotEmpty) {
        row['status'] = st;
      }
      rows.add(row);
    }
    plan['schedule'] = rows;
    plan['interest_total'] = interestTotal;
    return plan;
  }

  void _autoDistribute() {
    if (_anyPaid) {
      SnackBarHelper.show(context, message: 'به‌دلیل وجود پرداخت روی اقساط، تولید خودکار غیرفعال است. فقط ردیف‌های بدون پرداخت را دستی ویرایش کنید.');
      return;
    }
    final n = _numInstallments ?? 0;
    if (n <= 0) return;
    final start = _firstInstallmentDueDate ?? widget.invoiceDate ?? DateTime.now();
    final periodDays = (_installmentPeriod == 'monthly') ? 30 : (_installmentPeriodDays ?? 30);
    final totalNet = widget.sumTotal.toDouble();
    final principalTarget = (totalNet - (_downPayment ?? 0)).clamp(0, double.infinity);
    final principalTotal = principalTarget;
    final method = _selectedInstallmentPlan?.method ?? 'flat';
    final rate = (_interestRate ?? 0.0);
    final rows = <Map<String, dynamic>>[];

    if (method == 'amortized' && rate > 0) {
      final i = rate / 100.0;
      final nDouble = n.toDouble();
      double installmentAmount;
      if (i == 0) {
        installmentAmount = principalTotal / nDouble;
      } else {
        final powFactor = math.pow(1 + i, nDouble) as double;
        installmentAmount = principalTotal * i * powFactor / (powFactor - 1);
      }
      double remainingPrincipal = principalTotal.toDouble();
      for (int k = 0; k < n; k++) {
        final due = start.add(Duration(days: periodDays * k));
        double interest = remainingPrincipal * i;
        double principalPay = installmentAmount - interest;
        if (k == n - 1) {
          principalPay = remainingPrincipal;
          interest = installmentAmount - principalPay;
        }
        if (principalPay < 0) principalPay = 0;
        remainingPrincipal -= principalPay;
        final principalInt = principalPay.round();
        final interestInt = interest.round();
        rows.add({
          'seq': k + 1,
          'due_date': due,
          'principal': principalInt.toDouble(),
          'interest': interestInt.toDouble(),
          'total': (principalInt + interestInt).toDouble(),
          'paid_amount': 0.0,
        });
      }
    } else {
      final principalTotalRounded = principalTotal.round();
      final basePrincipal = principalTotalRounded ~/ n;
      int remainderPrincipal = principalTotalRounded - (basePrincipal * n);
      final interestTotal = ((principalTotal * (rate / 100.0))).round();
      final baseInterest = interestTotal ~/ n;
      int remainderInterest = interestTotal - (baseInterest * n);
      for (int i = 0; i < n; i++) {
        final due = start.add(Duration(days: periodDays * i));
        final principal = basePrincipal + (remainderPrincipal > 0 ? 1 : 0);
        if (remainderPrincipal > 0) remainderPrincipal -= 1;
        final interest = baseInterest + (remainderInterest > 0 ? 1 : 0);
        if (remainderInterest > 0) remainderInterest -= 1;
        rows.add({
          'seq': i + 1,
          'due_date': due,
          'principal': principal.toDouble(),
          'interest': interest.toDouble(),
          'total': (principal + interest).toDouble(),
          'paid_amount': 0.0,
        });
      }
    }
    setState(() {
      _installmentRows = rows;
      for (int idx = 0; idx < rows.length; idx++) {
        final principal = rows[idx]['principal'] as double? ?? 0.0;
        final interest = rows[idx]['interest'] as double? ?? 0.0;
        final total = rows[idx]['total'] as double? ?? 0.0;
        _getInstallmentController(_installmentPrincipalControllers, idx, principal, updateIfChanged: false);
        _getInstallmentController(_installmentInterestControllers, idx, interest, updateIfChanged: false);
        _getInstallmentController(_installmentTotalControllers, idx, total, updateIfChanged: false);
      }
      _cleanupInstallmentControllers();
    });
  }

  void _balancePrincipal() {
    final n = _installmentRows.length;
    if (n == 0) return;
    final totalNet = widget.sumTotal.toDouble();
    final principalTarget = (totalNet - (_downPayment ?? 0)).clamp(0, double.infinity);
    double sumPrincipal = 0;
    for (final r in _installmentRows) {
      sumPrincipal += (r['principal'] as num?)?.toDouble() ?? 0.0;
    }
    double remaining = sumPrincipal - principalTarget;
    for (int idx = n - 1; idx >= 0 && remaining.abs() > 0.0001; idx--) {
      if (_rowHasPayment(_installmentRows[idx])) continue;
      final current = (_installmentRows[idx]['principal'] as num?)?.toDouble() ?? 0.0;
      double newPrincipal;
      if (remaining > 0) {
        final canReduce = current;
        final reduce = remaining > canReduce ? canReduce : remaining;
        newPrincipal = (current - reduce).clamp(0, double.infinity);
        remaining -= reduce;
      } else {
        newPrincipal = current + (-remaining);
        remaining = 0;
      }
      _installmentRows[idx]['principal'] = newPrincipal;
      _installmentRows[idx]['total'] =
          newPrincipal + ((_installmentRows[idx]['interest'] as num?)?.toDouble() ?? 0.0);
      _getInstallmentController(_installmentPrincipalControllers, idx, newPrincipal, updateIfChanged: false);
      _getInstallmentController(
        _installmentTotalControllers,
        idx,
        (_installmentRows[idx]['total'] as num).toDouble(),
        updateIfChanged: false,
      );
    }
    setState(() {});
    SnackBarHelper.show(context, message: 'اختلاف اصل اقساط (ردیف‌های بدون پرداخت) تراز شد');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_anyPaid)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'برخی اقساط پرداخت شده‌اند. مبالغ آن ردیف‌ها قفل است؛ فقط می‌توانید ردیف‌های بدون پرداخت را ویرایش یا تاریخ سررسید را تغییر دهید.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<InstallmentPlan>(
                  value: _selectedInstallmentPlan,
                  items: _installmentPlans.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(
                        '${p.name} • ${p.numInstallments} ${t.installmentsCount} / ${p.periodDays} ${t.installmentDaysLength}',
                      ),
                    );
                  }).toList(),
                  onChanged: _anyPaid
                      ? null
                      : (v) {
                          setState(() {
                            _selectedInstallmentPlan = v;
                            final plan = v;
                            if (plan != null) {
                              _numInstallments = plan.numInstallments;
                              _installmentPeriod = 'days';
                              _installmentPeriodDays = plan.periodDays;
                              _interestRate = plan.interestRate ?? 0.0;
                              final dpPercent = plan.downPaymentPercent ?? 0.0;
                              _downPayment = (widget.sumTotal.toDouble() * dpPercent / 100.0);
                              _numInstallmentsController.text =
                                  formatNumberForInput(_numInstallments, decimalPlaces: 0);
                              _downPaymentController.text = formatNumberForInput(_downPayment);
                              _interestRateController.text = formatNumberForInput(_interestRate);
                              _installmentPeriodDaysController.text =
                                  formatNumberForInput(_installmentPeriodDays, decimalPlaces: 0);
                            }
                          });
                          _autoDistribute();
                        },
                  decoration: InputDecoration(labelText: t.selectInstallmentPlan),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _anyPaid
                    ? null
                    : () {
                        final plan = _selectedInstallmentPlan;
                        if (plan == null) return;
                        setState(() {
                          _numInstallments = plan.numInstallments;
                          _installmentPeriod = 'days';
                          _installmentPeriodDays = plan.periodDays;
                          _interestRate = plan.interestRate ?? 0.0;
                          final dpPercent = plan.downPaymentPercent ?? 0.0;
                          _downPayment = (widget.sumTotal.toDouble() * dpPercent / 100.0);
                          _firstInstallmentDueDate = widget.invoiceDate ?? DateTime.now();
                          _numInstallmentsController.text =
                              formatNumberForInput(_numInstallments, decimalPlaces: 0);
                          _downPaymentController.text = formatNumberForInput(_downPayment);
                          _interestRateController.text = formatNumberForInput(_interestRate);
                          _installmentPeriodDaysController.text =
                              formatNumberForInput(_installmentPeriodDays, decimalPlaces: 0);
                        });
                        _autoDistribute();
                      },
                icon: const Icon(Icons.playlist_add_check),
                label: Text(t.applyPlan),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _numInstallmentsController,
                          decoration: InputDecoration(
                            labelText: t.installmentsCount,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: false),
                          ],
                          onChanged: (v) {
                            _numInstallments = parseFormattedInt(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _downPaymentController,
                          decoration: InputDecoration(
                            labelText: t.downPayment,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: true),
                          ],
                          onChanged: (v) {
                            _downPayment = parseFormattedDouble(v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _interestRateController,
                          decoration: InputDecoration(
                            labelText: t.interestRatePercent,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: true),
                          ],
                          onChanged: (v) {
                            _interestRate = parseFormattedDouble(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _installmentPeriod,
                          decoration: InputDecoration(
                            labelText: t.installmentsPeriod,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(value: 'monthly', child: Text(t.installmentsMonthly)),
                            DropdownMenuItem(value: 'days', child: Text(t.installmentsDaysBased)),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _installmentPeriod = v ?? 'monthly';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_installmentPeriod == 'days')
                    TextFormField(
                      controller: _installmentPeriodDaysController,
                      decoration: InputDecoration(
                        labelText: t.installmentDaysLength,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: const [
                        EnglishDigitsFormatter(),
                        ThousandsSeparatorInputFormatter(allowDecimal: false),
                      ],
                      onChanged: (v) {
                        _installmentPeriodDays = parseFormattedInt(v);
                      },
                    ),
                  if (_installmentPeriod == 'days') const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 320,
                      child: DateInputField(
                        labelText: t.firstInstallmentDueDate,
                        value: _firstInstallmentDueDate ?? widget.invoiceDate ?? DateTime.now(),
                        onChanged: (d) {
                          setState(() => _firstInstallmentDueDate = d);
                        },
                        calendarController: widget.calendarController,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _autoDistribute,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('تولید خودکار اقساط'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _anyPaid
                    ? null
                    : () {
                        setState(() {
                          final idx = _installmentRows.length + 1;
                          final newIndex = _installmentRows.length;
                          _installmentRows.add({
                            'seq': idx,
                            'due_date': _firstInstallmentDueDate ?? widget.invoiceDate ?? DateTime.now(),
                            'principal': 0.0,
                            'interest': 0.0,
                            'total': 0.0,
                            'paid_amount': 0.0,
                          });
                          _getInstallmentController(_installmentPrincipalControllers, newIndex, 0.0);
                          _getInstallmentController(_installmentInterestControllers, newIndex, 0.0);
                          _getInstallmentController(_installmentTotalControllers, newIndex, 0.0);
                        });
                      },
                icon: const Icon(Icons.add),
                label: const Text('افزودن قسط'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _balancePrincipal,
                icon: const Icon(Icons.tune),
                label: const Text('تراز اختلاف اصل'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 50, child: Text('ردیف', textAlign: TextAlign.center)),
                      const Expanded(child: Text('تاریخ سررسید')),
                      const Expanded(child: Text('اصل')),
                      const Expanded(child: Text('سود')),
                      const Expanded(child: Text('جمع')),
                      const SizedBox(width: 72, child: Text('پرداخت', textAlign: TextAlign.center)),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const Divider(),
                  ..._installmentRows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final r = entry.value;
                    final seq = (r['seq'] as int?) ?? (i + 1);
                    final due = (r['due_date'] as DateTime?) ?? DateTime.now();
                    final principal = (r['principal'] as num?)?.toDouble() ?? 0.0;
                    final interest = (r['interest'] as num?)?.toDouble() ?? 0.0;
                    final total = (r['total'] as num?)?.toDouble() ?? (principal + interest);
                    final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
                    final locked = _rowHasPayment(r);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 50,
                            child: Center(child: Text('#$seq', style: Theme.of(context).textTheme.bodyMedium)),
                          ),
                          Expanded(
                            child: DateInputField(
                              value: due,
                              calendarController: widget.calendarController,
                              labelText: 'تاریخ',
                              isDense: true,
                              onChanged: (d) {
                                setState(() => _installmentRows[i]['due_date'] = d ?? due);
                              },
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              enabled: !locked,
                              controller: _getInstallmentController(_installmentPrincipalControllers, i, principal),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final pInt = parseFormattedInt(v) ?? 0;
                                final p = pInt.toDouble();
                                _installmentRows[i]['principal'] = p;
                                _installmentRows[i]['total'] =
                                    p + ((_installmentRows[i]['interest'] as num?)?.toDouble() ?? 0.0);
                                final newTotal = _installmentRows[i]['total'] as double? ?? 0.0;
                                _getInstallmentController(_installmentTotalControllers, i, newTotal);
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              enabled: !locked,
                              controller: _getInstallmentController(_installmentInterestControllers, i, interest),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final sInt = parseFormattedInt(v) ?? 0;
                                final s = sInt.toDouble();
                                _installmentRows[i]['interest'] = s;
                                _installmentRows[i]['total'] =
                                    s + ((_installmentRows[i]['principal'] as num?)?.toDouble() ?? 0.0);
                                final newTotal = _installmentRows[i]['total'] as double? ?? 0.0;
                                _getInstallmentController(_installmentTotalControllers, i, newTotal);
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              enabled: !locked,
                              controller: _getInstallmentController(_installmentTotalControllers, i, total),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final totInt = parseFormattedInt(v) ?? 0;
                                final tot = totInt.toDouble();
                                _installmentRows[i]['total'] = tot;
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          SizedBox(
                            width: 72,
                            child: Center(
                              child: Text(
                                formatWithThousands(paid, decimalPlaces: 0),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: locked
                                ? null
                                : () {
                                    setState(() {
                                      _installmentPrincipalControllers[i]?.dispose();
                                      _installmentInterestControllers[i]?.dispose();
                                      _installmentTotalControllers[i]?.dispose();
                                      _installmentPrincipalControllers.remove(i);
                                      _installmentInterestControllers.remove(i);
                                      _installmentTotalControllers.remove(i);
                                      _installmentRows.removeAt(i);
                                      for (int idx = i; idx < _installmentRows.length + 10; idx++) {
                                        if (_installmentPrincipalControllers.containsKey(idx)) {
                                          _installmentPrincipalControllers[idx]?.dispose();
                                          _installmentInterestControllers[idx]?.dispose();
                                          _installmentTotalControllers[idx]?.dispose();
                                          _installmentPrincipalControllers.remove(idx);
                                          _installmentInterestControllers.remove(idx);
                                          _installmentTotalControllers.remove(idx);
                                        }
                                      }
                                      for (int idx = 0; idx < _installmentRows.length; idx++) {
                                        final pr = (_installmentRows[idx]['principal'] as num?)?.toDouble() ?? 0.0;
                                        final ir = (_installmentRows[idx]['interest'] as num?)?.toDouble() ?? 0.0;
                                        final tt = (_installmentRows[idx]['total'] as num?)?.toDouble() ?? 0.0;
                                        _getInstallmentController(
                                          _installmentPrincipalControllers,
                                          idx,
                                          pr,
                                          updateIfChanged: false,
                                        );
                                        _getInstallmentController(
                                          _installmentInterestControllers,
                                          idx,
                                          ir,
                                          updateIfChanged: false,
                                        );
                                        _getInstallmentController(
                                          _installmentTotalControllers,
                                          idx,
                                          tt,
                                          updateIfChanged: false,
                                        );
                                      }
                                    });
                                  },
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'حذف',
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Builder(
                    builder: (context) {
                      final sumPrincipal = _installmentsPrincipalTotal;
                      final sumInterest = _installmentsInterestTotal;
                      final sumTotal = _installmentsTotal;
                      final targetPrincipal =
                          (widget.sumTotal.toDouble() - (_downPayment ?? 0)).clamp(0, double.infinity);
                      final diff = sumPrincipal - targetPrincipal;
                      final diffColor = diff.abs() <= 1 ? Colors.green : Colors.orange;
                      return Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(label: Text('جمع اصل: ${formatWithThousands(sumPrincipal, decimalPlaces: 0)}')),
                            Chip(label: Text('جمع سود: ${formatWithThousands(sumInterest, decimalPlaces: 0)}')),
                            Chip(label: Text('جمع اقساط: ${formatWithThousands(sumTotal, decimalPlaces: 0)}')),
                            Chip(
                              label: Text('اختلاف اصل: ${formatWithThousands(diff, decimalPlaces: 0)}'),
                              backgroundColor: diffColor.withValues(alpha: 0.12),
                              labelStyle: TextStyle(color: diffColor),
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
        ],
      ),
    );
  }
}
