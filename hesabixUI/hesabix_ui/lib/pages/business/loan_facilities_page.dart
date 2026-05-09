import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../services/currency_service.dart';
import '../../services/loan_facilities_service.dart';
import '../../utils/currency_display_utils.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/document/document_details_dialog.dart';
import '../../widgets/invoice/bank_account_combobox_widget.dart';
import '../../widgets/permission/access_denied_page.dart';

/// لیست و جزئیات تسهیلات دریافتی (قرارداد، اقساط، پرداخت‌ها، سند حسابداری)
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

  /// فراخوان از FAB، منوی کناری یا هر مسیر دلخواه (با دسترسی add).
  static Future<void> showUpsertFacilityDialog({
    required BuildContext context,
    required int businessId,
    required CalendarController calendarController,
    required AuthStore authStore,
    int? facilityId,
    Map<String, dynamic>? initial,
    VoidCallback? onSuccess,
  }) async {
    if (facilityId == null) {
      if (!authStore.hasBusinessPermission('loan_facilities', 'add')) return;
    } else {
      if (!authStore.hasBusinessPermission('loan_facilities', 'edit')) return;
    }
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LoanFacilityUpsertDialog(
        businessId: businessId,
        calendarController: calendarController,
        facilityId: facilityId,
        initial: initial,
        loanService: LoanFacilitiesService(),
        onSaved: () {
          Navigator.pop(ctx, true);
          onSuccess?.call();
        },
      ),
    );
  }
}

class _LoanFacilitiesPageState extends State<LoanFacilitiesPage> {
  final _service = LoanFacilitiesService();
  final _searchCtl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int? _listTotal;
  static const _pageSize = 50;
  Timer? _searchDebounce;

  bool get _canEdit => widget.authStore.hasBusinessPermission('loan_facilities', 'edit');

  @override
  void initState() {
    super.initState();
    LoanFacilitiesPage._states[widget.businessId] = this;
    _load(refresh: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    LoanFacilitiesPage._states.remove(widget.businessId);
    super.dispose();
  }

  Future<void> refresh() => _load(refresh: true);

  void _scheduleSearchQuery() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load(refresh: true);
    });
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final skip = refresh ? 0 : _items.length;
    try {
      final data = await _service.query(
        businessId: widget.businessId,
        take: _pageSize,
        skip: skip,
        search: _searchCtl.text.trim(),
        sortDesc: true,
      );
      final raw = data['items'];
      final pag = data['pagination'];
      final total = pag is Map ? _asInt(pag['total']) : null;

      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items = list;
        } else {
          _items = [..._items, ...list];
        }
        _listTotal = total ?? _items.length;
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
            canEdit: _canEdit,
            onClosedRefreshList: () {
              if (mounted) _load(refresh: true);
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
    final canLoadMore = _listTotal != null && _items.length < _listTotal!;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _loading && _items.isEmpty
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
                          tooltip: t.loanFacilityReloadTooltip,
                          onPressed: () => _load(refresh: true),
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtl,
                    decoration: InputDecoration(
                      labelText: t.loanFacilitySearchTitlesLabel,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtl.clear();
                          _load(refresh: true);
                        },
                      ),
                    ),
                    onChanged: (_) => _scheduleSearchQuery(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 8),
                  if (_items.isEmpty && _error == null && !_loading)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(
                        t.loanFacilityEmptyState,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ..._items.map((row) => _tile(context, row)),
                  if (canLoadMore) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : () => _load(refresh: false),
                        icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
                        label: Text(t.loanFacilityLoadMore),
                      ),
                    ),
                  ],
                ],
              ),
      ),
      floatingActionButton: widget.authStore.hasBusinessPermission('loan_facilities', 'add')
          ? FloatingActionButton(
              tooltip: '${t.add} ${t.loanFacilities}',
              onPressed: () => LoanFacilitiesPage.showUpsertFacilityDialog(
                    context: context,
                    businessId: widget.businessId,
                    calendarController: widget.calendarController,
                    authStore: widget.authStore,
                    onSuccess: () => _load(refresh: true),
                  ),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> row) {
    final id = _asInt(row['id']);
    final st = '${row['status'] ?? ''}';
    final pr = row['principal_amount'];
    final titleText = '${row['title'] ?? id}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.real_estate_agent_outlined, color: Theme.of(context).colorScheme.primary),
        title: Text(titleText),
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
    final t = v.trim().replaceAll(',', '').replaceAll('٫', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

DateTime? _parseIsoDate(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.length >= 10) {
    final d = DateTime.tryParse(s.substring(0, 10));
    if (d != null) return d;
  }
  return DateTime.tryParse(s);
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// دیالوگ ایجاد / ویرایش قرارداد (همسو با بدنهٔ `create` و `PATCH` بک‌اند).
class LoanFacilityUpsertDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final int? facilityId;
  final Map<String, dynamic>? initial;
  final LoanFacilitiesService loanService;
  final VoidCallback onSaved;

  const LoanFacilityUpsertDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.loanService,
    required this.onSaved,
    this.facilityId,
    this.initial,
  });

  @override
  State<LoanFacilityUpsertDialog> createState() => _LoanFacilityUpsertDialogState();
}

class _LoanFacilityUpsertDialogState extends State<LoanFacilityUpsertDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtl;
  late final TextEditingController _principalCtl;
  late final TextEditingController _rateCtl;
  late final TextEditingController _instCountCtl;
  late final TextEditingController _notesCtl;

  late DateTime _contractDate;
  DateTime? _firstInstallmentDate;
  int? _currencyId;
  String? _lenderBankAccountIdStr;
  bool _saving = false;

  bool get _isEdit => widget.facilityId != null;

  Map<String, dynamic>? get _i => widget.initial;

  @override
  void initState() {
    super.initState();
    final i = _i ?? const {};
    _titleCtl = TextEditingController(text: '${i['title'] ?? ''}');
    _principalCtl = TextEditingController(
      text: i['principal_amount'] != null ? '${i['principal_amount']}' : '',
    );
    _rateCtl = TextEditingController(
      text: i['annual_interest_rate_percent'] != null ? '${i['annual_interest_rate_percent']}' : '',
    );
    final ic = i['installment_count'];
    _instCountCtl = TextEditingController(text: ic != null ? '$ic' : '');
    _notesCtl = TextEditingController(text: '${i['notes'] ?? ''}');
    _contractDate = _parseIsoDate(i['contract_date']) ?? DateTime.now();
    _firstInstallmentDate = _parseIsoDate(i['first_installment_date']);
    _currencyId = _asInt(i['currency_id']);
    final lb = i['lender_bank_account_id'];
    _lenderBankAccountIdStr = lb != null ? '$lb' : null;
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _principalCtl.dispose();
    _rateCtl.dispose();
    _instCountCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lt = AppLocalizations.of(context);
    final tTitle = _titleCtl.text.trim();
    if (tTitle.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(lt.loanFacilityValidationTitleRequired)),
      );
      return;
    }

    if (!_isEdit || _financialUnlockedInitial) {
      if (_currencyId == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(lt.loanFacilityValidationSelectCurrency)),
        );
        return;
      }
      final p = _asDouble(_principalCtl.text.trim());
      if (p == null || p <= 0) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(lt.loanFacilityValidationPrincipalInvalid)),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      if (!_isEdit) {
        final p = _asDouble(_principalCtl.text.trim())!;
        final body = <String, dynamic>{
          'title': tTitle,
          'currency_id': _currencyId,
          'principal_amount': p,
          'contract_date': _isoDate(_contractDate),
          if (_rateCtl.text.trim().isNotEmpty) 'annual_interest_rate_percent': _asDouble(_rateCtl.text.trim()),
          if (_firstInstallmentDate != null) 'first_installment_date': _isoDate(_firstInstallmentDate!),
          if (_instCountCtl.text.trim().isNotEmpty) 'installment_count': int.tryParse(_instCountCtl.text.trim()),
          if (_notesCtl.text.trim().isNotEmpty) 'notes': _notesCtl.text.trim(),
        };
        final bid = _lenderBankAccountIdStr != null && _lenderBankAccountIdStr!.isNotEmpty
            ? int.tryParse(_lenderBankAccountIdStr!)
            : null;
        if (bid != null) body['lender_bank_account_id'] = bid;

        await widget.loanService.createDraft(
          businessId: widget.businessId,
          payload: body,
        );
      } else {
        final fid = widget.facilityId!;
        final body = <String, dynamic>{'title': tTitle};
        if (_financialUnlockedInitial) {
          final p = _asDouble(_principalCtl.text.trim())!;
          body['principal_amount'] = p;
          body['currency_id'] = _currencyId;
          body['contract_date'] = _isoDate(_contractDate);
          final ap = _rateCtl.text.trim();
          if (ap.isEmpty) {
            body['annual_interest_rate_percent'] = null;
          } else if (_asDouble(ap) != null) {
            body['annual_interest_rate_percent'] = _asDouble(ap);
          }
          final fi = _firstInstallmentDate;
          body['first_installment_date'] = fi != null ? _isoDate(fi) : null;
          final icText = _instCountCtl.text.trim();
          body['installment_count'] = icText.isEmpty ? null : int.tryParse(icText);
          final lb = _lenderBankAccountIdStr != null && _lenderBankAccountIdStr!.isNotEmpty
              ? int.tryParse(_lenderBankAccountIdStr!)
              : null;
          body['lender_bank_account_id'] = lb;
        }
        if (_notesCtl.text.trim().isNotEmpty || _isEdit) {
          body['notes'] = _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim();
        }
        await widget.loanService.updateFacility(facilityId: fid, body: body);
      }

      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// مانند بک‌اند: پیش‌نویس + بدون قسط.
  bool get _financialUnlockedInitial {
    final i = _i;
    if (i == null) return !_isEdit;
    if (i['status']?.toString() != 'draft') return false;
    final inst = i['installments'];
    if (inst is List && inst.isNotEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final finOpen = !_isEdit || _financialUnlockedInitial;

    return AlertDialog(
      title: Text(_isEdit ? t.loanFacilityDialogEditTitle : t.loanFacilityDialogNewTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleCtl,
                  decoration: InputDecoration(
                    labelText: t.loanFacilityFieldTitle,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (finOpen) ...[
                  CurrencyPickerWidget(
                    businessId: widget.businessId,
                    selectedCurrencyId: _currencyId,
                    isDense: true,
                    label: t.loanFacilityFieldCurrency,
                    hintText: t.loanFacilityFieldCurrencyHint,
                    onChanged: (id) => setState(() => _currencyId = id),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _principalCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]+'))],
                    decoration: InputDecoration(
                      labelText: t.loanFacilityFieldPrincipal,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DateInputField(
                    calendarController: widget.calendarController,
                    value: _contractDate,
                    isDense: true,
                    labelText: t.loanFacilityFieldContractDate,
                    hintText: t.loanFacilityFieldContractDateHint,
                    onChanged: (d) => setState(() => _contractDate = d ?? _contractDate),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rateCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: t.loanFacilityFieldAnnualRate,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _instCountCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t.loanFacilityFieldInstallmentCountOptional,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DateInputField(
                    calendarController: widget.calendarController,
                    value: _firstInstallmentDate,
                    isDense: true,
                    labelText: t.loanFacilityFieldFirstInstallment,
                    hintText: t.loanFacilityFieldFirstInstallmentHint,
                    onChanged: (d) => setState(() => _firstInstallmentDate = d),
                  ),
                  const SizedBox(height: 12),
                  BankAccountComboboxWidget(
                    businessId: widget.businessId,
                    filterCurrencyId: _currencyId,
                    isRequired: false,
                    dense: true,
                    label: t.loanFacilityFieldLenderBank,
                    selectedAccountId: _lenderBankAccountIdStr,
                    onChanged: (opt) => setState(() => _lenderBankAccountIdStr = opt?.id),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _notesCtl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: t.loanFacilityFieldNotes,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? t.save : t.submit),
        ),
      ],
    );
  }
}

class _FacilityDetailSheet extends StatefulWidget {
  final int businessId;
  final int facilityId;
  final LoanFacilitiesService service;
  final CalendarController calendarController;
  final AuthStore authStore;
  final bool canEdit;
  final VoidCallback onClosedRefreshList;

  const _FacilityDetailSheet({
    required this.businessId,
    required this.facilityId,
    required this.service,
    required this.calendarController,
    required this.authStore,
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
  List<Map<String, dynamic>> _bizCurrencies = const [];

  @override
  void initState() {
    super.initState();
    _reload();
    _loadBusinessCurrencies();
  }

  Future<void> _loadBusinessCurrencies() async {
    try {
      final list = await CurrencyService(ApiClient()).listBusinessCurrencies(
        businessId: widget.businessId,
      );
      if (mounted) setState(() => _bizCurrencies = list);
    } catch (_) {}
  }

  String _currencyLabel(BuildContext context, int? id) {
    final t = AppLocalizations.of(context);
    if (id == null) return '—';
    final label = currencyUnitLabelForBusinessCurrencyIdOrNull(id, _bizCurrencies);
    if (label != null && label.isNotEmpty) return label;
    return t.loanFacilityCurrencyId('$id');
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

  Future<void> _editContract() async {
    final d = _detail;
    if (d == null) return;
    if (!mounted) return;
    await LoanFacilitiesPage.showUpsertFacilityDialog(
      context: context,
      businessId: widget.businessId,
      calendarController: widget.calendarController,
      authStore: widget.authStore,
      facilityId: widget.facilityId,
      initial: d,
      onSuccess: () {
        _reload();
        widget.onClosedRefreshList();
      },
    );
  }

  Future<void> _deleteDraft() async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        final dt = AppLocalizations.of(dCtx);
        return AlertDialog(
          title: Text(dt.loanFacilityConfirmDeleteDraftTitle),
          content: Text(dt.loanFacilityConfirmDeleteDraftBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(dt.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dCtx).colorScheme.error,
                foregroundColor: Theme.of(dCtx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(dt.delete),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.deleteFacility(facilityId: widget.facilityId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.loanFacilityDeleted);
      widget.onClosedRefreshList();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _openRegenerateDialog() async {
    final d = _detail;
    if (d == null) return;
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => _RegenerateScheduleDialog(
        businessId: widget.businessId,
        facilityId: widget.facilityId,
        calendarController: widget.calendarController,
        service: widget.service,
        detail: d,
        onSuccess: () {
          _reload();
          widget.onClosedRefreshList();
        },
      ),
    );
    if (ok == true && mounted) {
      SnackBarHelper.show(context, message: t.loanFacilityScheduleUpdated);
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
      builder: (dCtx) {
        final dt = AppLocalizations.of(dCtx);
        return AlertDialog(
          title: Text(dt.loanFacilityDeletePaymentTitle),
          content: Text(dt.loanFacilityDeletePaymentBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(dt.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(dt.delete),
            ),
          ],
        );
      },
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
      SnackBarHelper.show(context, message: AppLocalizations.of(context).loanFacilityPaymentDeleted);
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

    final fullyPaid = instMap['is_fully_paid'] == true;
    if (fullyPaid) return;

    final currencyId = _asInt(_detail?['currency_id']);
    final amountCtl = TextEditingController();
    String? bankIdStr;

    final submitted = await showDialog<bool>(
      context: sheetCtx,
      builder: (dlgCtx) {
        final dt = AppLocalizations.of(dlgCtx);
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(dt.loanFacilityRecordPaymentTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: amountCtl,
                    decoration: InputDecoration(labelText: dt.loanFacilityAmount),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  BankAccountComboboxWidget(
                    businessId: widget.businessId,
                    filterCurrencyId: currencyId,
                    isRequired: true,
                    dense: true,
                    label: dt.loanFacilityBankAccount,
                    selectedAccountId: bankIdStr,
                    onChanged: (opt) {
                      setLocal(() {
                        bankIdStr = opt?.id;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dt.loanFacilityPaymentPostingHint,
                    style: Theme.of(dlgCtx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: Text(dt.cancel)),
              FilledButton(
                onPressed: () {
                  final amt = _asDouble(amountCtl.text.trim());
                  if (amt == null || amt <= 0) {
                    ScaffoldMessenger.maybeOf(dlgCtx)?.showSnackBar(
                      SnackBar(content: Text(dt.loanFacilityValidationAmountInvalid)),
                    );
                    return;
                  }
                  if (bankIdStr == null || bankIdStr!.isEmpty) {
                    ScaffoldMessenger.maybeOf(dlgCtx)?.showSnackBar(
                      SnackBar(content: Text(dt.loanFacilityValidationPickBank)),
                    );
                    return;
                  }
                  Navigator.pop(dlgCtx, true);
                },
                child: Text(dt.save),
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
      SnackBarHelper.show(context, message: AppLocalizations.of(context).loanFacilityPaymentRecorded);
      await _reload();
      widget.onClosedRefreshList();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  bool _facilityHasPayments(List<Map<String, dynamic>> instList) {
    for (final m in instList) {
      final p = m['payments'];
      if (p is List && p.isNotEmpty) return true;
    }
    return false;
  }

  bool get _canDeleteDraft =>
      widget.canEdit &&
      widget.authStore.hasBusinessPermission('loan_facilities', 'delete') &&
      _detail?['status']?.toString() == 'draft';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _reload, child: Text(t.loanFacilityRetry)),
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

    final cid = _asInt(d['currency_id']);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              if (widget.canEdit) ...[
                IconButton(icon: const Icon(Icons.edit_outlined), tooltip: t.loanFacilityTooltipEdit, onPressed: _editContract),
                if (_canDeleteDraft)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                    tooltip: t.loanFacilityTooltipDeleteDraft,
                    onPressed: _deleteDraft,
                  ),
              ],
              IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.loanFacilityContractSummary, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text('${t.loanFacilitySummaryStatus}: ${d['status'] ?? '—'}'),
                      Text('${t.loanFacilitySummaryCurrency}: ${_currencyLabel(context, cid)}'),
                      Text('${t.loanFacilitySummaryPrincipal}: ${d['principal_amount'] ?? '—'}'),
                      Text('${t.loanFacilitySummaryAnnualRate}: ${d['annual_interest_rate_percent'] ?? '—'}'),
                      Text('${t.loanFacilitySummaryContractDate}: ${d['contract_date'] ?? '—'}'),
                      Text('${t.loanFacilitySummaryFirstInstallment}: ${d['first_installment_date'] ?? '—'}'),
                      Text('${t.loanFacilitySummaryInstallmentCount}: ${d['installment_count'] ?? '—'}'),
                      Text('${t.loanFacilitySummaryScheduleMethod}: ${d['schedule_method'] ?? '—'}'),
                      Text('${t.loanFacilitySummaryLenderBankId}: ${d['lender_bank_account_id'] ?? '—'}'),
                      if ((d['notes'] ?? '').toString().isNotEmpty)
                        Text('${t.loanFacilitySummaryNotes}: ${d['notes']}'),
                    ],
                  ),
                ),
              ),
              if (disburseDoc != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(t.loanFacilityDisbursementDocument),
                    subtitle: Text('#$disburseDoc'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _showDocument(context, disburseDoc),
                  ),
                ),
              const Divider(height: 24),
              Text(t.loanFacilityScheduleSection, style: Theme.of(context).textTheme.titleMedium),
              ...instList.map((instMap) => _instTile(context, instMap)),
              if (widget.canEdit &&
                  !_facilityHasPayments(instList) &&
                  (d['status'] == 'draft' || d['status'] == 'active'))
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: _openRegenerateDialog,
                      icon: const Icon(Icons.calculate_outlined),
                      label: Text(t.loanFacilityRegenerateSchedule),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _instTile(BuildContext sheetCtx, Map<String, dynamic> instMap) {
    final st = AppLocalizations.of(sheetCtx);
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
        title: Text(st.loanFacilityInstallmentLine('$seq', due)),
        subtitle:
            Text(st.loanFacilityRemainingPrincipalInterest(remPri, remInt)),
        children: [
          if (widget.canEdit && !fullyPaid)
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(st.loanFacilityRecordPayment),
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
              subtitle: docId != null ? Text(st.loanFacilityDocumentNumber('$docId')) : null,
              trailing: Wrap(
                spacing: 4,
                children: [
                  if (docId != null)
                    IconButton(
                      tooltip: st.loanFacilityViewVoucher,
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: () => _showDocument(sheetCtx, docId),
                    ),
                  if (widget.canEdit && pid != null)
                    IconButton(
                      tooltip: st.loanFacilityDeletePayment,
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

class _RegenerateScheduleDialog extends StatefulWidget {
  final int businessId;
  final int facilityId;
  final CalendarController calendarController;
  final LoanFacilitiesService service;
  final Map<String, dynamic> detail;
  final VoidCallback onSuccess;

  const _RegenerateScheduleDialog({
    required this.businessId,
    required this.facilityId,
    required this.calendarController,
    required this.service,
    required this.detail,
    required this.onSuccess,
  });

  @override
  State<_RegenerateScheduleDialog> createState() => _RegenerateScheduleDialogState();
}

class _RegenerateScheduleDialogState extends State<_RegenerateScheduleDialog> {
  late String _method;
  late final TextEditingController _countCtl;
  DateTime? _firstDue;
  String? _disburseBankIdStr;
  bool _postAccounting = true;
  bool _busy = false;

  static const _annuity = 'annuity';
  static const _equalPrincipal = 'equal_principal';

  @override
  void initState() {
    super.initState();
    final sm = widget.detail['schedule_method']?.toString();
    if (sm == _equalPrincipal) {
      _method = _equalPrincipal;
    } else {
      _method = _annuity;
    }
    final ic = widget.detail['installment_count'];
    _countCtl = TextEditingController(text: ic != null ? '$ic' : '');
    _firstDue = _parseIsoDate(widget.detail['first_installment_date']);
    _disburseBankIdStr = widget.detail['lender_bank_account_id'] != null
        ? '${widget.detail['lender_bank_account_id']}'
        : null;
  }

  @override
  void dispose() {
    _countCtl.dispose();
    super.dispose();
  }

  int? get _currencyId => _asInt(widget.detail['currency_id']);

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final n = int.tryParse(_countCtl.text.trim());
    if (n == null || n < 1) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(t.loanFacilityRegenerateValidationCount)),
      );
      return;
    }
    if (_firstDue == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(t.loanFacilityRegenerateValidationFirstDue)),
      );
      return;
    }
    if (_postAccounting) {
      final hasBank = _disburseBankIdStr != null && _disburseBankIdStr!.isNotEmpty;
      if (!hasBank) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(t.loanFacilityRegenerateValidationDisburseBank),
          ),
        );
        return;
      }
    }

    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'schedule_method': _method,
        'installment_count': n,
        'first_installment_date': _isoDate(_firstDue!),
        'post_accounting_disbursement': _postAccounting,
      };
      final db = _disburseBankIdStr != null && _disburseBankIdStr!.isNotEmpty
          ? int.tryParse(_disburseBankIdStr!)
          : null;
      if (db != null) body['disbursement_bank_account_id'] = db;

      await widget.service.regenerateSchedule(
        facilityId: widget.facilityId,
        body: body,
      );
      if (!mounted) return;
      widget.onSuccess();
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.loanFacilityRegenerateDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InputDecorator(
              decoration: InputDecoration(
                labelText: t.loanFacilityRegenerateMethod,
                border: const OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _method,
                  items: [
                    DropdownMenuItem(value: _annuity, child: Text(t.loanFacilityScheduleMethodAnnuity)),
                    DropdownMenuItem(
                      value: _equalPrincipal,
                      child: Text(t.loanFacilityScheduleMethodEqualPrincipal),
                    ),
                  ],
                  onChanged: (v) => setState(() => _method = v ?? _annuity),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _countCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.loanFacilityRegenerateCountRequired,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DateInputField(
              calendarController: widget.calendarController,
              value: _firstDue,
              isDense: true,
              labelText: t.loanFacilityRegenerateFirstDueRequired,
              onChanged: (d) => setState(() => _firstDue = d),
            ),
            const SizedBox(height: 12),
            BankAccountComboboxWidget(
              businessId: widget.businessId,
              filterCurrencyId: _currencyId,
              isRequired: _postAccounting,
              dense: true,
              label: t.loanFacilityRegenerateDisburseBank,
              selectedAccountId: _disburseBankIdStr,
              onChanged: (opt) => setState(() => _disburseBankIdStr = opt?.id),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.loanFacilityRegeneratePostAccounting),
              value: _postAccounting,
              onChanged: (v) => setState(() => _postAccounting = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.loanFacilityRegenerateApply),
        ),
      ],
    );
  }
}