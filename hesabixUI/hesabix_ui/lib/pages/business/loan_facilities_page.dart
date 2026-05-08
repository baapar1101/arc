import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/permission/access_denied_page.dart';
import '../../services/loan_facilities_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/document/document_details_dialog.dart';
import '../../widgets/invoice/bank_account_combobox_widget.dart';

/// لیست و جزئیات تسهیلات دریافتی (اقساط، پرداخت‌ها، سند حسابداری، حذف پرداخت)
class LoanFacilitiesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const LoanFacilitiesPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<LoanFacilitiesPage> createState() => _LoanFacilitiesPageState();

  static final Map<int, _LoanFacilitiesPageState> _states = {};

  static _LoanFacilitiesPageState? getPageState(int businessId) => _states[businessId];
}

class _LoanFacilitiesPageState extends State<LoanFacilitiesPage> {
  final _service = LoanFacilitiesService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  bool get _fa => Localizations.localeOf(context).languageCode.startsWith('fa');

  bool get _canEdit => widget.authStore.hasBusinessPermission('loan_facilities', 'edit');

  @override
  void initState() {
    super.initState();
    LoanFacilitiesPage._states[widget.businessId] = this;
    _load();
  }

  @override
  void dispose() {
    LoanFacilitiesPage._states.remove(widget.businessId);
    super.dispose();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.query(businessId: widget.businessId, take: 100, skip: 0);
      final raw = data['items'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _showFacilitySheet(int facilityId) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: _FacilityDetailSheet(
            businessId: widget.businessId,
            facilityId: facilityId,
            service: _service,
            calendarController: widget.calendarController,
            authStore: widget.authStore,
            fa: sheetCtx.maybeFa,
            canEdit: _canEdit,
            onClosedRefreshList: () {
              if (mounted) _load();
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('loan_facilities')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    final title = t.loanFacilities;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      if (_error != null)
                        IconButton(
                          tooltip: _fa ? 'بارگذاری مجدد' : 'Reload',
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 8),
                  if (_items.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(
                        _fa
                            ? 'قراردادی ثبت نشده است. با API یا دکمهٔ افزودن می‌توانید پیش‌نویس بسازید.'
                            : 'No contracts yet. Create a draft via API or the add button.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ..._items.map((row) => _tile(context, row)),
                ],
              ),
      ),
      floatingActionButton: widget.authStore.hasBusinessPermission('loan_facilities', 'add')
          ? FloatingActionButton(
              tooltip: '${t.add} ${t.loanFacilities}',
              onPressed: () => _promptCreateDraft(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _promptCreateDraft(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_fa ? 'پیش‌نویس قرارداد' : 'New draft contract'),
          content: TextField(
            controller: ctl,
            decoration: InputDecoration(labelText: t.loanFacilities),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.localeName.startsWith('fa') ? 'لغو' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.add)),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    final name = ctl.text.trim();
    if (name.isEmpty) {
      SnackBarHelper.show(context, message: _fa ? 'عنوان لازم است' : 'Title is required');
      return;
    }
    try {
      await _service.createDraft(businessId: widget.businessId, payload: {'title': name});
      if (!mounted) return;
      SnackBarHelper.show(context, message: _fa ? 'پیش‌نویس ثبت شد' : 'Draft created');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _tile(BuildContext context, Map<String, dynamic> row) {
    final id = _asInt(row['id']);
    final st = '${row['status'] ?? ''}';
    final pr = row['principal_amount'];
    final title = '${row['title'] ?? id}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.real_estate_agent_outlined, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text('$st · ${_formatAmt(pr)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: id == null
            ? null
            : () {
                _showFacilitySheet(id);
              },
      ),
    );
  }

  String _formatAmt(dynamic x) => x?.toString() ?? '—';
}

extension on BuildContext {
  bool get maybeFa => Localizations.localeOf(this).languageCode.startsWith('fa');
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim().replaceAll(',', ''));
  return null;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

class _FacilityDetailSheet extends StatefulWidget {
  final int businessId;
  final int facilityId;
  final LoanFacilitiesService service;
  final CalendarController calendarController;
  final AuthStore authStore;
  final bool fa;
  final bool canEdit;
  final VoidCallback onClosedRefreshList;

  const _FacilityDetailSheet({
    required this.businessId,
    required this.facilityId,
    required this.service,
    required this.calendarController,
    required this.authStore,
    required this.fa,
    required this.canEdit,
    required this.onClosedRefreshList,
  });

  @override
  State<_FacilityDetailSheet> createState() => _FacilityDetailSheetState();
}

class _FacilityDetailSheetState extends State<_FacilityDetailSheet> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await widget.service.getDetail(facilityId: widget.facilityId);
      if (!mounted) return;
      setState(() {
        _detail = row;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  void _showDocument(BuildContext ctx, int documentId) {
    showDialog<void>(
      context: ctx,
      builder: (_) => DocumentDetailsDialog(
        documentId: documentId,
        calendarController: widget.calendarController,
      ),
    );
  }

  Future<void> _confirmDeletePayment(
    BuildContext ctx, {
    required int installmentId,
    required Map<String, dynamic> pay,
  }) async {
    final pid = _asInt(pay['id']);
    if (pid == null) return;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(widget.fa ? 'حذف پرداخت؟' : 'Delete payment?'),
        content: Text(
          widget.fa
              ? 'سند حسابداری مرتبط حذف و ماندهٔ قسط اصلاح می‌شود.'
              : 'Linked accounting voucher will be removed and installment balances will be rolled back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(widget.fa ? 'لغو' : 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(widget.fa ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.deleteInstallmentPayment(
        businessId: widget.businessId,
        facilityId: widget.facilityId,
        installmentId: installmentId,
        paymentId: pid,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: widget.fa ? 'پرداخت حذف شد' : 'Payment deleted');
      await _reload();
      widget.onClosedRefreshList();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _openPayDialog(BuildContext sheetCtx, Map<String, dynamic> instMap) async {
    final installmentId = _asInt(instMap['id']);
    if (installmentId == null) return;

    bool fullyPaid = instMap['is_fully_paid'] == true;
    if (fullyPaid) return;

    final currencyId = _asInt(_detail?['currency_id']);
    final amountCtl = TextEditingController();
    String? bankIdStr;

    final submitted = await showDialog<bool>(
      context: sheetCtx,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(widget.fa ? 'ثبت پرداخت قسط' : 'Record installment payment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: amountCtl,
                    decoration: InputDecoration(labelText: widget.fa ? 'مبلغ' : 'Amount'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  BankAccountComboboxWidget(
                    businessId: widget.businessId,
                    filterCurrencyId: currencyId,
                    isRequired: true,
                    dense: true,
                    label: widget.fa ? 'حساب بانکی' : 'Bank account',
                    selectedAccountId: bankIdStr,
                    onChanged: (opt) {
                      setLocal(() {
                        bankIdStr = opt?.id;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.fa
                        ? 'سند دستی (۱۰۲۰۳ با کد بانک، بدهی ۲۰۵۰۵، بهره ۷۰۹۰۱، جریمه ۷۰۹۰۳) ثبت می‌شود.'
                        : 'A balanced manual voucher (10203+bank_account_id; principal 20505; interest 70901; penalty 70903) will be posted.',
                    style: Theme.of(dlgCtx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: Text(widget.fa ? 'لغو' : 'Cancel')),
              FilledButton(
                onPressed: () {
                  final amt = _asDouble(amountCtl.text.trim());
                  if (amt == null || amt <= 0) {
                    ScaffoldMessenger.maybeOf(dlgCtx)?.showSnackBar(
                      SnackBar(content: Text(widget.fa ? 'مبلغ معتبر وارد کنید' : 'Enter a valid amount')),
                    );
                    return;
                  }
                  if (bankIdStr == null || bankIdStr!.isEmpty) {
                    ScaffoldMessenger.maybeOf(dlgCtx)?.showSnackBar(
                      SnackBar(content: Text(widget.fa ? 'حساب بانکی را انتخاب کنید' : 'Pick a bank account')),
                    );
                    return;
                  }
                  Navigator.pop(dlgCtx, true);
                },
                child: Text(widget.fa ? 'ثبت' : 'Save'),
              ),
            ],
          ),
        );
      },
    );

    if (submitted != true || !mounted) return;
    final amt = _asDouble(amountCtl.text.trim());
    final bankInt = bankIdStr != null ? int.tryParse(bankIdStr!) : null;
    if (amt == null || amt <= 0 || bankInt == null) return;

    try {
      await widget.service.recordInstallmentPayment(
        businessId: widget.businessId,
        facilityId: widget.facilityId,
        installmentId: installmentId,
        body: <String, dynamic>{
          'amount': amt,
          'bank_account_id': bankInt,
          'post_accounting_payment': true,
        },
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: widget.fa ? 'پرداخت ثبت شد' : 'Payment recorded');
      await _reload();
      widget.onClosedRefreshList();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _reload, child: Text(widget.fa ? 'تلاش مجدد' : 'Retry')),
          ],
        ),
      );
    }

    final d = _detail ?? const {};
    final title = '${d['title'] ?? widget.facilityId}';
    final disburseDoc = _asInt(d['disbursement_document_id']);
    final installments = d['installments'];
    final instList = installments is List
        ? installments.map((e) => e is Map ? Map<String, dynamic>.from(e) : null).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.fa ? 'وضعیت' : 'Status'}: ${d['status'] ?? '—'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (disburseDoc != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(widget.fa ? 'سند دریافت وام / تنخواص' : 'Disbursement document'),
                    subtitle: Text('#$disburseDoc'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _showDocument(context, disburseDoc),
                  ),
                ),
              const Divider(height: 24),
              Text(widget.fa ? 'اقساط' : 'Schedule', style: Theme.of(context).textTheme.titleMedium),
              ...instList.map((instMap) => _instTile(context, instMap)),
              if (widget.canEdit &&
                  !_facilityHasPayments(instList) &&
                  (d['status'] == 'draft' || d['status'] == 'active'))
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          final scheduleBody = <String, dynamic>{};
                          final method = d['schedule_method'];
                          if (method is String && method.isNotEmpty) scheduleBody['schedule_method'] = method;
                          final ic = _asInt(d['installment_count']);
                          if (ic != null) scheduleBody['installment_count'] = ic;
                          final fir = d['first_installment_date'];
                          if (fir is String && fir.isNotEmpty) {
                            scheduleBody['first_installment_date'] = fir;
                          }
                          await widget.service.regenerateSchedule(
                            facilityId: widget.facilityId,
                            body: scheduleBody,
                          );
                          if (!mounted) return;
                          SnackBarHelper.show(context,
                              message: widget.fa ? 'جدول اقساط بازسازی شد' : 'Schedule regenerated');
                          await _reload();
                          widget.onClosedRefreshList();
                        } catch (e) {
                          if (!mounted) return;
                          SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context));
                        }
                      },
                      icon: const Icon(Icons.calculate_outlined),
                      label: Text(widget.fa ? 'بازسازی جدول اقساط' : 'Regenerate installment schedule'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _facilityHasPayments(List<Map<String, dynamic>> instList) {
    for (final m in instList) {
      final p = m['payments'];
      if (p is List && p.isNotEmpty) return true;
    }
    return false;
  }

  Widget _instTile(BuildContext sheetCtx, Map<String, dynamic> instMap) {
    final installmentId = _asInt(instMap['id']);
    if (installmentId == null) return const SizedBox.shrink();

    final seq = instMap['sequence_no'];
    final due = '${instMap['due_date'] ?? ''}';
    final remPri = '${instMap['remaining_principal']}';
    final remInt = '${instMap['remaining_interest']}';
    final fullyPaid = instMap['is_fully_paid'] == true;

    final paysRaw = instMap['payments'];
    final pays = paysRaw is List
        ? paysRaw.map((e) => e is Map ? Map<String, dynamic>.from(e) : null).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(fullyPaid ? Icons.check_circle_outline : Icons.pending_outlined),
        title: Text('${widget.fa ? 'قسط' : '#'} $seq · $due'),
        subtitle:
            Text('${widget.fa ? 'مانده اصل / بهره' : 'Rem. pr./int.'}: $remPri / $remInt'),
        children: [
          if (widget.canEdit && !fullyPaid)
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(widget.fa ? 'ثبت پرداخت' : 'Record payment'),
              onTap: () => _openPayDialog(sheetCtx, instMap),
            ),
          ...pays.map((p) {
            final docId = _asInt(p['document_id']);
            final amt = '${p['amount_total'] ?? ''}';
            final pdate = '${p['payment_date'] ?? ''}';
            final pid = _asInt(p['id']);
            return ListTile(
              dense: true,
              leading: const Icon(Icons.receipt_long, size: 20),
              title: Text('$pdate · $amt'),
              subtitle: docId != null ? Text('${widget.fa ? 'سند' : 'Doc'} #$docId') : null,
              trailing: Wrap(
                spacing: 4,
                children: [
                  if (docId != null)
                    IconButton(
                      tooltip: widget.fa ? 'مشاهده سند' : 'View voucher',
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: () => _showDocument(sheetCtx, docId),
                    ),
                  if (widget.canEdit && pid != null)
                    IconButton(
                      tooltip: widget.fa ? 'حذف پرداخت' : 'Delete payment',
                      icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(sheetCtx).colorScheme.error),
                      onPressed: () => _confirmDeletePayment(sheetCtx, installmentId: installmentId, pay: p),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
