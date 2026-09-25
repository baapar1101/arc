import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/credit_models.dart';
import 'package:hesabix_ui/services/credit_api_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import '../../utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class InstallmentPlansPage extends StatefulWidget {
  final int businessId;
  const InstallmentPlansPage({super.key, required this.businessId});

  @override
  State<InstallmentPlansPage> createState() => _InstallmentPlansPageState();
}

class _InstallmentPlansPageState extends State<InstallmentPlansPage> {
  bool _loading = true;
  String? _error;
  List<InstallmentPlan> _items = [];
  String _query = '';
  bool _activeOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CreditApiService.listInstallmentPlans(widget.businessId);
      setState(() {
        _items = items;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => InstallmentPlanDialog(businessId: widget.businessId),
    );
    if (created == true) {
      _load();
    }
  }

  Future<void> _openEditDialog(InstallmentPlan plan) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => InstallmentPlanDialog(businessId: widget.businessId, plan: plan),
    );
    if (updated == true) {
      _load();
    }
  }

  Future<void> _deletePlan(InstallmentPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deletePlan),
        content: Text(AppLocalizations.of(context).deletePlanConfirm(plan.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context).cancel)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(context).delete)),
        ],
      ),
    );
    if (ok != true) return;
    await CreditApiService.deleteInstallmentPlan(widget.businessId, plan.id);
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: 'طرح اقساط با موفقیت حذف شد');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).installmentPlansTitle),
        leading: businessSubpageBackLeading(context, widget.businessId),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        actions: [
          IconButton(
            onPressed: _openCreateDialog,
            icon: const Icon(Icons.add),
            tooltip: AppLocalizations.of(context).newInstallmentPlan,
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(AppLocalizations.of(context).reload),
                        ),
                      ],
                    ),
                  ),
                )
              : (_items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.playlist_add, size: 56),
                            const SizedBox(height: 12),
                            Text(
                              AppLocalizations.of(context).newInstallmentPlan,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context).installmentsSubtitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _openCreateDialog,
                              icon: const Icon(Icons.add),
                              label: Text(AppLocalizations.of(context).newInstallmentPlan),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => _load(),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: (_items
                                    .where((it) =>
                                        (_query.trim().isEmpty ||
                                            it.name.toLowerCase().contains(_query.trim().toLowerCase())) &&
                                        (_activeOnly ? it.isActive : true))
                                    .toList()
                                    .length) +
                                1,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(Icons.search),
                                          labelText: AppLocalizations.of(context).search,
                                          border: const OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (v) => setState(() => _query = v),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    FilterChip(
                                      label: Text(AppLocalizations.of(context).active),
                                      selected: _activeOnly,
                                      onSelected: (v) => setState(() => _activeOnly = v),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final filtered = _items.where((it) {
                            final qok = _query.trim().isEmpty || it.name.toLowerCase().contains(_query.trim().toLowerCase());
                            final aok = _activeOnly ? it.isActive : true;
                            return qok && aok;
                          }).toList();
                          final it = filtered[index - 1];
                          final methodTitle = it.method == 'amortized'
                              ? AppLocalizations.of(context).planMethodAmortized
                              : AppLocalizations.of(context).planMethodFlat;
                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.schedule, color: cs.onPrimaryContainer),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                it.name,
                                                style: Theme.of(context).textTheme.titleMedium,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.edit),
                                              tooltip: AppLocalizations.of(context).editPlan,
                                              onPressed: () => _openEditDialog(it),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline),
                                              tooltip: AppLocalizations.of(context).deletePlan,
                                              onPressed: () => _deletePlan(it),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${it.numInstallments} ${AppLocalizations.of(context).installmentsCount} • '
                                          '${it.periodDays} ${AppLocalizations.of(context).planPeriodDays}${it.interestRate != null ? ' • ${it.interestRate!.toStringAsFixed(2)}%' : ''}'
                                          '${it.downPaymentPercent != null ? ' • ${AppLocalizations.of(context).planDownPaymentPercent}: ${it.downPaymentPercent!.toStringAsFixed(2)}%' : ''}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: -6,
                                          children: [
                                            Chip(
                                              label: Text(methodTitle),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            Chip(
                                              label: Text('${AppLocalizations.of(context).planNumInstallments}: ${it.numInstallments}'),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            Chip(
                                              label: Text('${AppLocalizations.of(context).planPeriodDays}: ${it.periodDays}'),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            if (it.isActive)
                                              Chip(
                                                label: Text(AppLocalizations.of(context).planIsActive),
                                                visualDensity: VisualDensity.compact,
                                                backgroundColor: cs.primaryContainer,
                                              )
                                            else
                                              Chip(
                                                label: Text(AppLocalizations.of(context).inactive),
                                                visualDensity: VisualDensity.compact,
                                                backgroundColor: cs.surfaceContainerHighest,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )),
    );
  }
}

class InstallmentPlanDialog extends StatefulWidget {
  final int businessId;
  final InstallmentPlan? plan;
  const InstallmentPlanDialog({super.key, required this.businessId, this.plan});

  @override
  State<InstallmentPlanDialog> createState() => _InstallmentPlanDialogState();
}

class _InstallmentPlanDialogState extends State<InstallmentPlanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _numController = TextEditingController();
  final _periodDaysController = TextEditingController(text: '30');
  final _downPaymentController = TextEditingController();
  final _interestRateController = TextEditingController();
  final _lateFeeController = TextEditingController();
  final _issueFeeController = TextEditingController();
  final _previewAmountController = TextEditingController(text: '10000000');
  String _method = 'flat';
  bool _isActive = true;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _numController.dispose();
    _periodDaysController.dispose();
    _downPaymentController.dispose();
    _interestRateController.dispose();
    _lateFeeController.dispose();
    _issueFeeController.dispose();
    _previewAmountController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.plan != null) {
      final p = widget.plan!;
      _nameController.text = p.name;
      _numController.text = p.numInstallments.toString();
      _periodDaysController.text = p.periodDays.toString();
      _downPaymentController.text = p.downPaymentPercent?.toString() ?? '';
      _interestRateController.text = p.interestRate?.toString() ?? '';
      _lateFeeController.text = p.lateFeeRate?.toString() ?? '';
      _issueFeeController.text = p.issueFee?.toString() ?? '';
      _method = p.method;
      _isActive = p.isActive;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final String name = _nameController.text.trim();
      final String method = _method;
      final int numInstallments = int.parse(_numController.text.trim());
      final int periodDays = int.parse(_periodDaysController.text.trim());
      final double? downPaymentPercent = _downPaymentController.text.trim().isEmpty ? null : double.parse(_downPaymentController.text.trim());
      final double? interestRate = _interestRateController.text.trim().isEmpty ? null : double.parse(_interestRateController.text.trim());
      final double? lateFeeRate = _lateFeeController.text.trim().isEmpty ? null : double.parse(_lateFeeController.text.trim());
      final double? issueFee = _issueFeeController.text.trim().isEmpty ? null : double.parse(_issueFeeController.text.trim());
      if (widget.plan == null) {
        await CreditApiService.createInstallmentPlan(widget.businessId, InstallmentPlan(
          id: 0,
          businessId: widget.businessId,
          name: name,
          method: method,
          numInstallments: numInstallments,
          periodDays: periodDays,
          downPaymentPercent: downPaymentPercent,
          interestRate: interestRate,
          lateFeeRate: lateFeeRate,
          issueFee: issueFee,
          description: null,
          isActive: _isActive,
        ));
      } else {
        await CreditApiService.updateInstallmentPlan(widget.businessId, widget.plan!.id, {
          'name': name,
          'method': method,
          'num_installments': numInstallments,
          'period_days': periodDays,
          'down_payment_percent': downPaymentPercent,
          'interest_rate': interestRate,
          'late_fee_rate': lateFeeRate,
          'issue_fee': issueFee,
          'is_active': _isActive,
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      SnackBarHelper.showSuccess(context, message: 'طرح اقساط با موفقیت ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.plan == null ? AppLocalizations.of(context).installmentPlanCreateTitle : AppLocalizations.of(context).installmentPlanEditTitle),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // نام پلن
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).planName,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? AppLocalizations.of(context).requiredField : null,
                ),
                const SizedBox(height: 12),
                // روش محاسبه
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  items: [
                    DropdownMenuItem(value: 'flat', child: Text(AppLocalizations.of(context).planMethodFlat)),
                    DropdownMenuItem(value: 'amortized', child: Text(AppLocalizations.of(context).planMethodAmortized)),
                  ],
                  onChanged: (v) => setState(() => _method = v ?? 'flat'),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).planMethod,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // تعداد اقساط و فاصله روزها
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _numController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).planNumInstallments,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) return AppLocalizations.of(context).invalidInstallmentsCount;
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _periodDaysController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).planPeriodDays,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) return AppLocalizations.of(context).requiredField;
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // پیش‌پرداخت و نرخ سود
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _downPaymentController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).planDownPaymentPercent,
                          suffixText: '%',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final d = double.tryParse(v.trim());
                          if (d == null || d < 0 || d > 100) return 'مقدار نامعتبر';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _interestRateController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).planInterestRate,
                          suffixText: '%',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final d = double.tryParse(v.trim());
                          if (d == null || d < 0 || d > 100) return 'مقدار نامعتبر';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // جریمه دیرکرد و کارمزد صدور
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _lateFeeController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).planLateFeeRate,
                          suffixText: '%',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final d = double.tryParse(v.trim());
                          if (d == null || d < 0 || d > 100) return 'مقدار نامعتبر';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _issueFeeController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).planIssueFee,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: Text(AppLocalizations.of(context).planIsActive),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                // پیش‌نمایش
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(AppLocalizations.of(context).preview, style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _previewAmountController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).moneyAmount,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildPreviewTable(context),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context).cancel)),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(AppLocalizations.of(context).save),
        ),
      ],
    );
  }

  Widget _buildPreviewTable(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isJalali = ApiClient.getCalendarController()?.isJalali ?? true;
    final amount = double.tryParse(_previewAmountController.text.replaceAll(',', '').trim()) ?? 0.0;
    final n = int.tryParse(_numController.text.trim()) ?? 0;
    final periodDays = int.tryParse(_periodDaysController.text.trim()) ?? 30;
    final dpPercent = double.tryParse(_downPaymentController.text.trim()) ?? 0.0;
    final rate = double.tryParse(_interestRateController.text.trim()) ?? 0.0;
    if (amount <= 0 || n <= 0) {
      return Text(t.descriptionOptional);
    }
    final downPayment = amount * (dpPercent / 100.0);
    final principal = (amount - downPayment).clamp(0, double.infinity);
    final totalInterest = principal * (rate / 100.0);
    final perPrincipal = principal / n;
    final perInterest = totalInterest / n;
    final int showCount = n < 3 ? n : 3;
    final List<Widget> previewRows = <Widget>[];
    for (int i = 0; i < showCount; i++) {
      final due = DateTime.now().add(Duration(days: periodDays * i));
      final total = perPrincipal + perInterest;
      final dueDisplay = HesabixDateUtils.formatForDisplay(due.toLocal(), isJalali);
      previewRows.add(
        Row(
          children: [
            Expanded(child: Text('#${i + 1}')),
            Expanded(
              flex: 2,
              child: Text('${t.firstInstallmentDueDate}: $dueDisplay'),
            ),
            Expanded(child: Text('${t.lineTotalAmount}: ${total.toStringAsFixed(0)}')),
          ],
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t.total}: ${amount.toStringAsFixed(0)}'),
            Text('${t.downPayment}: ${downPayment.toStringAsFixed(0)}'),
            Text('${t.planInterestRate}: ${rate.toStringAsFixed(2)}%'),
            const Divider(),
            ...previewRows,
            if (n > showCount) const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('...'),
            ),
          ],
        ),
      ),
    );
  }
}


