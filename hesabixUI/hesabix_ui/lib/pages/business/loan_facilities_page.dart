import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../services/currency_service.dart';
import '../../services/loan_facilities_service.dart';
import '../../utils/currency_display_utils.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/number_normalizer.dart'
    show
        EnglishDigitsFormatter,
        ThousandsSeparatorInputFormatter,
        formatNumberForInput,
        parseFormattedDouble,
        toEnglishDigits;
import '../../utils/snackbar_helper.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/document/document_details_dialog.dart';
import '../../widgets/invoice/bank_account_combobox_widget.dart';
import '../../widgets/money/amount_field_words_tooltip.dart';
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
  List<Map<String, dynamic>> _bizCurrencies = const [];
  static const _pageSize = 50;
  Timer? _searchDebounce;

  bool get _canEdit => widget.authStore.hasBusinessPermission('loan_facilities', 'edit');

  @override
  void initState() {
    super.initState();
    LoanFacilitiesPage._states[widget.businessId] = this;
    _load(refresh: true);
    _loadBizCurrencies();
  }

  Future<void> _loadBizCurrencies() async {
    try {
      final list = await CurrencyService(ApiClient()).listBusinessCurrencies(
        businessId: widget.businessId,
      );
      if (mounted) setState(() => _bizCurrencies = list);
    } catch (_) {}
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
    final moneyDp = loanFacilityMoneyDecimalPlaces(row, _bizCurrencies);
    final cid = _asInt(row['currency_id']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.real_estate_agent_outlined, color: Theme.of(context).colorScheme.primary),
        title: Text(titleText),
        subtitle: Text(
          '$st · ${_formatMoneyLine(pr, currencyId: cid, bizCurrencies: _bizCurrencies, decimalPlaces: moneyDp)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: id == null
            ? null
            : () {
                _showFacilitySheet(id);
              },
      ),
    );
  }

}

String _normalizeNumericText(String raw) {
  return toEnglishDigits(raw)
      .trim()
      .replaceAll('٫', '.')
      .replaceAll('٬', '')
      .replaceAll(',', '')
      .replaceAll(RegExp(r'\s+'), '');
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) {
    final normalized = _normalizeNumericText(v);
    if (normalized.isEmpty) return null;
    return int.tryParse(normalized) ?? double.tryParse(normalized)?.round();
  }
  return null;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = _normalizeNumericText(v);
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

/// تعداد اعشار نمایش مبلغ از `currency_decimal_places` (API) یا ستون `decimal_places` در ارزهای کسب‌کار.
int loanFacilityMoneyDecimalPlaces(
  Map<String, dynamic>? facilityRow,
  List<Map<String, dynamic>> bizCurrencies,
) {
  if (facilityRow != null && facilityRow['currency_decimal_places'] != null) {
    final api = facilityRow['currency_decimal_places'];
    if (api is num) return api.toInt().clamp(0, 8);
  }
  final cid = facilityRow == null ? null : _asInt(facilityRow['currency_id']);
  if (cid != null && bizCurrencies.isNotEmpty) {
    for (final raw in bizCurrencies) {
      if (_asInt(raw['id']) == cid) {
        final dp = (raw['decimal_places'] as num?)?.toInt();
        if (dp != null) return dp.clamp(0, 8);
      }
    }
  }
  return 2;
}

String _formatAmount(dynamic value, {int? decimalPlaces}) {
  final n = _asDouble(value);
  if (n == null) return '—';
  final places = decimalPlaces ?? (n % 1 == 0 ? 0 : 2);
  return formatWithThousands(n, decimalPlaces: places);
}

/// مبلغ + برچسب کوتاه ارز (نماد/کد از فهرست ارز کسب‌کار).
String _formatMoneyLine(
  dynamic value, {
  required int? currencyId,
  required List<Map<String, dynamic>> bizCurrencies,
  int? decimalPlaces,
}) {
  final a = _formatAmount(value, decimalPlaces: decimalPlaces);
  if (a == '—') return a;
  final unit = currencyUnitLabelForBusinessCurrencyIdOrNull(currencyId, bizCurrencies);
  if (unit == null || unit.isEmpty) return a;
  return '$a $unit';
}

String _formatInputAmount(dynamic value, {int? decimalPlaces}) {
  final n = _asDouble(value);
  if (n == null) return '';
  if (decimalPlaces != null && decimalPlaces <= 0) {
    return formatNumberForInput(n.round(), decimalPlaces: 0);
  }
  return formatNumberForInput(n, decimalPlaces: decimalPlaces);
}

String _uiText(BuildContext context, {required String fa, required String en}) {
  final locale = Localizations.localeOf(context).languageCode.toLowerCase();
  return locale.startsWith('fa') ? fa : en;
}

/// نمایش تاریخ API (میلادی `YYYY-MM-DD`) مطابق تقویم انتخاب‌شده در اپ.
String _formatLoanFacilityDateLabel(CalendarController calendar, dynamic apiValue) {
  if (apiValue == null) return '—';
  final raw = apiValue.toString().trim();
  if (raw.isEmpty) return '—';
  return HesabixDateUtils.formatApiDateForDisplay(apiValue, calendar.isJalali, fallback: '—');
}

double _roundMoney(double value, int moneyDecimalPlaces) {
  final factor = math.pow(10, moneyDecimalPlaces).toDouble();
  if (factor <= 0) return value;
  return (value * factor).roundToDouble() / factor;
}

double _installmentRemainingTotal(Map<String, dynamic> instMap) {
  return (_asDouble(instMap['remaining_principal']) ?? 0) +
      (_asDouble(instMap['remaining_interest']) ?? 0) +
      (_asDouble(instMap['remaining_penalty']) ?? 0);
}

class _SchedulePreview {
  final double firstInstallment;
  final double lastInstallment;
  final double totalInterest;
  final double totalRepayment;

  const _SchedulePreview({
    required this.firstInstallment,
    required this.lastInstallment,
    required this.totalInterest,
    required this.totalRepayment,
  });
}

_SchedulePreview? _calculateSchedulePreview({
  required String method,
  required double principal,
  required double annualRatePercent,
  required int installmentCount,
  int moneyDecimalPlaces = 2,
}) {
  if (principal <= 0 || installmentCount < 1 || annualRatePercent < 0) return null;

  final monthlyRate = annualRatePercent / 100 / 12;
  var balance = _roundMoney(principal, moneyDecimalPlaces);
  var totalInterest = 0.0;
  double? firstInstallment;
  double? lastInstallment;

  for (var period = 1; period <= installmentCount; period++) {
    final interestPart = _roundMoney(balance * monthlyRate, moneyDecimalPlaces);
    double principalPart;
    if (method == _RegenerateScheduleDialogState._equalPrincipal || monthlyRate == 0) {
      final eachPrincipal = _roundMoney(principal / installmentCount, moneyDecimalPlaces);
      principalPart = period < installmentCount ? eachPrincipal : _roundMoney(balance, moneyDecimalPlaces);
    } else {
      final onePlus = math.pow(1 + monthlyRate, installmentCount).toDouble();
      final emi = _roundMoney(principal * monthlyRate * onePlus / (onePlus - 1), moneyDecimalPlaces);
      principalPart = period < installmentCount
          ? _roundMoney(math.min(math.max(emi - interestPart, 0.0), balance), moneyDecimalPlaces)
          : _roundMoney(balance, moneyDecimalPlaces);
    }
    final installmentTotal = _roundMoney(principalPart + interestPart, moneyDecimalPlaces);
    firstInstallment ??= installmentTotal;
    lastInstallment = installmentTotal;
    totalInterest = _roundMoney(totalInterest + interestPart, moneyDecimalPlaces);
    balance = _roundMoney(balance - principalPart, moneyDecimalPlaces);
  }

  return _SchedulePreview(
    firstInstallment: firstInstallment ?? 0,
    lastInstallment: lastInstallment ?? 0,
    totalInterest: totalInterest,
    totalRepayment: _roundMoney(principal + totalInterest, moneyDecimalPlaces),
  );
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
  List<Map<String, dynamic>> _formCurrencies = const [];

  bool get _isEdit => widget.facilityId != null;

  Map<String, dynamic>? get _i => widget.initial;

  Map<String, dynamic> _rowSnapshotForMoneyDp() {
    final i = _i ?? const {};
    final row = Map<String, dynamic>.from(i);
    if (_currencyId != null) row['currency_id'] = _currencyId;
    return row;
  }

  int _moneyDpForForm() => loanFacilityMoneyDecimalPlaces(_rowSnapshotForMoneyDp(), _formCurrencies);

  @override
  void initState() {
    super.initState();
    final i = _i ?? const {};
    _titleCtl = TextEditingController(text: '${i['title'] ?? ''}');
    _currencyId = _asInt(i['currency_id']);
    final startDp = loanFacilityMoneyDecimalPlaces(_rowSnapshotForMoneyDp(), const []);
    _principalCtl = TextEditingController(
      text: _formatInputAmount(i['principal_amount'], decimalPlaces: startDp),
    );
    _rateCtl = TextEditingController(
      text: i['annual_interest_rate_percent'] != null ? '${i['annual_interest_rate_percent']}' : '',
    );
    final ic = i['installment_count'];
    _instCountCtl = TextEditingController(text: _formatInputAmount(ic, decimalPlaces: 0));
    _notesCtl = TextEditingController(text: '${i['notes'] ?? ''}');
    _contractDate = _parseIsoDate(i['contract_date']) ?? DateTime.now();
    _firstInstallmentDate = _parseIsoDate(i['first_installment_date']);
    final lb = i['lender_bank_account_id'];
    _lenderBankAccountIdStr = lb != null ? '$lb' : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFormCurrencies());
  }

  Future<void> _loadFormCurrencies() async {
    try {
      final list = await CurrencyService(ApiClient()).listBusinessCurrencies(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        _formCurrencies = list;
        final dpp = _moneyDpForForm();
        final parsed = parseFormattedDouble(_principalCtl.text) ?? _asDouble(_principalCtl.text);
        if (parsed != null) {
          _principalCtl.text = _formatInputAmount(parsed, decimalPlaces: dpp);
        }
      });
    } catch (_) {}
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
      final annual = _asDouble(_rateCtl.text.trim());
      if (_rateCtl.text.trim().isNotEmpty && (annual == null || annual < 0)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(lt.loanFacilityValidationAmountInvalid)),
        );
        return;
      }
      final installmentCount = _asInt(_instCountCtl.text.trim());
      if (_instCountCtl.text.trim().isNotEmpty && (installmentCount == null || installmentCount < 1)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(lt.loanFacilityRegenerateValidationCount)),
        );
        return;
      }
      if (_firstInstallmentDate != null && _firstInstallmentDate!.isBefore(_contractDate)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(lt.loanFacilityRegenerateValidationFirstDue)),
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
          if (_instCountCtl.text.trim().isNotEmpty) 'installment_count': _asInt(_instCountCtl.text.trim()),
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
          body['installment_count'] = icText.isEmpty ? null : _asInt(icText);
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
    final moneyDp = _moneyDpForForm();
    final allowDec = moneyDp > 0;

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
                    onChanged: (id) {
                      setState(() {
                        final prev = _currencyId;
                        _currencyId = id;
                        if (prev != id) {
                          _lenderBankAccountIdStr = null;
                        }
                        final dpp = _moneyDpForForm();
                        final parsed =
                            parseFormattedDouble(_principalCtl.text) ?? _asDouble(_principalCtl.text);
                        if (parsed != null) {
                          _principalCtl.text = _formatInputAmount(parsed, decimalPlaces: dpp);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  AmountFieldWordsTooltip(
                    controller: _principalCtl,
                    currencyUnit:
                        currencyUnitLabelForBusinessCurrencyIdOrNull(_currencyId, _formCurrencies) ?? '',
                    child: TextFormField(
                      controller: _principalCtl,
                      keyboardType: TextInputType.numberWithOptions(decimal: allowDec),
                      inputFormatters: [
                        const EnglishDigitsFormatter(),
                        ThousandsSeparatorInputFormatter(allowDecimal: allowDec),
                      ],
                      decoration: InputDecoration(
                        labelText: t.loanFacilityFieldPrincipal,
                        border: const OutlineInputBorder(),
                      ),
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
                    inputFormatters: [
                      const EnglishDigitsFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: t.loanFacilityFieldAnnualRate,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _instCountCtl,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [
                      EnglishDigitsFormatter(),
                      ThousandsSeparatorInputFormatter(allowDecimal: false),
                    ],
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
                  if (_currencyId != null) ...[
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

  int _moneyDp() => loanFacilityMoneyDecimalPlaces(_detail, _bizCurrencies);

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

  Future<void> _deleteFacility() async {
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
        businessCurrencies: _bizCurrencies,
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
    final remainingTotal = _installmentRemainingTotal(instMap);
    final moneyDp = _moneyDp();
    final amountCtl = TextEditingController(
      text: _formatInputAmount(remainingTotal, decimalPlaces: moneyDp),
    );
    String? bankIdStr;
    final allowPayDec = moneyDp > 0;

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
                  Text(
                    '${_uiText(dlgCtx, fa: 'مانده قابل پرداخت', en: 'Remaining payable')}: ${_formatMoneyLine(remainingTotal, currencyId: currencyId, bizCurrencies: _bizCurrencies, decimalPlaces: moneyDp)}',
                    style: Theme.of(dlgCtx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  AmountFieldWordsTooltip(
                    controller: amountCtl,
                    currencyUnit: _currencyLabel(dlgCtx, currencyId),
                    child: TextField(
                      controller: amountCtl,
                      decoration: InputDecoration(labelText: dt.loanFacilityAmount),
                      keyboardType: TextInputType.numberWithOptions(decimal: allowPayDec),
                      inputFormatters: [
                        const EnglishDigitsFormatter(),
                        ThousandsSeparatorInputFormatter(allowDecimal: allowPayDec),
                      ],
                    ),
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
                  if (amt == null || amt <= 0 || (remainingTotal > 0 && amt > remainingTotal + 0.000001)) {
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

    final amountText = amountCtl.text;
    amountCtl.dispose();
    if (submitted != true || !mounted) return;
    final amt = _asDouble(amountText.trim());
    final bankInt = bankIdStr != null ? int.tryParse(bankIdStr!) : null;
    if (amt == null || amt <= 0 || (remainingTotal > 0 && amt > remainingTotal + 0.000001) || bankInt == null) return;

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

  bool get _canDeleteFacility =>
      widget.canEdit &&
      widget.authStore.hasBusinessPermission('loan_facilities', 'delete') &&
      _detail != null;

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
    final moneyDp = _moneyDp();

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
                if (_canDeleteFacility)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                    tooltip: t.loanFacilityTooltipDeleteDraft,
                    onPressed: _deleteFacility,
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
                      Text(
                        '${t.loanFacilitySummaryPrincipal}: ${_formatMoneyLine(d['principal_amount'], currencyId: cid, bizCurrencies: _bizCurrencies, decimalPlaces: moneyDp)}',
                      ),
                      Text('${t.loanFacilitySummaryAnnualRate}: ${d['annual_interest_rate_percent'] ?? '—'}'),
                      Text(
                        '${t.loanFacilitySummaryContractDate}: ${_formatLoanFacilityDateLabel(widget.calendarController, d['contract_date'])}',
                      ),
                      Text(
                        '${t.loanFacilitySummaryFirstInstallment}: ${_formatLoanFacilityDateLabel(widget.calendarController, d['first_installment_date'])}',
                      ),
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
    final due = _formatLoanFacilityDateLabel(widget.calendarController, instMap['due_date']);
    final moneyDp = _moneyDp();
    final facCid = _asInt(_detail?['currency_id']);
    final remPri = _formatMoneyLine(
      instMap['remaining_principal'],
      currencyId: facCid,
      bizCurrencies: _bizCurrencies,
      decimalPlaces: moneyDp,
    );
    final remInt = _formatMoneyLine(
      instMap['remaining_interest'],
      currencyId: facCid,
      bizCurrencies: _bizCurrencies,
      decimalPlaces: moneyDp,
    );
    final remTotal = _formatMoneyLine(
      _installmentRemainingTotal(instMap),
      currencyId: facCid,
      bizCurrencies: _bizCurrencies,
      decimalPlaces: moneyDp,
    );
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
        subtitle: Text('${st.loanFacilityRemainingPrincipalInterest(remPri, remInt)} · $remTotal'),
        children: [
          if (widget.canEdit && !fullyPaid)
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(st.loanFacilityRecordPayment),
              onTap: () => _openPayDialog(sheetCtx, instMap),
            ),
          ...pays.map((p) {
            final docId = _asInt(p['document_id']);
            final amt = _formatMoneyLine(
              p['amount_total'],
              currencyId: facCid,
              bizCurrencies: _bizCurrencies,
              decimalPlaces: moneyDp,
            );
            final pdate = _formatLoanFacilityDateLabel(widget.calendarController, p['payment_date']);
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
  final List<Map<String, dynamic>> businessCurrencies;
  final VoidCallback onSuccess;

  const _RegenerateScheduleDialog({
    required this.businessId,
    required this.facilityId,
    required this.calendarController,
    required this.service,
    required this.detail,
    this.businessCurrencies = const [],
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
    _countCtl = TextEditingController(text: _formatInputAmount(ic, decimalPlaces: 0));
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

  _SchedulePreview? get _preview {
    final principal = _asDouble(widget.detail['principal_amount']);
    final annual = _asDouble(widget.detail['annual_interest_rate_percent']) ?? 0;
    final count = _asInt(_countCtl.text);
    if (principal == null || count == null) return null;
    final moneyDp = loanFacilityMoneyDecimalPlaces(
      Map<String, dynamic>.from(widget.detail),
      widget.businessCurrencies,
    );
    return _calculateSchedulePreview(
      method: _method,
      principal: principal,
      annualRatePercent: annual,
      installmentCount: count,
      moneyDecimalPlaces: moneyDp,
    );
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final n = _asInt(_countCtl.text.trim());
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
    final contractDate = _parseIsoDate(widget.detail['contract_date']);
    if (contractDate != null && _firstDue!.isBefore(contractDate)) {
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
    final preview = _preview;
    final moneyDp = loanFacilityMoneyDecimalPlaces(
      Map<String, dynamic>.from(widget.detail),
      widget.businessCurrencies,
    );
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
              inputFormatters: const [
                EnglishDigitsFormatter(),
                ThousandsSeparatorInputFormatter(allowDecimal: false),
              ],
              decoration: InputDecoration(
                labelText: t.loanFacilityRegenerateCountRequired,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DateInputField(
              calendarController: widget.calendarController,
              value: _firstDue,
              isDense: true,
              labelText: t.loanFacilityRegenerateFirstDueRequired,
              onChanged: (d) => setState(() => _firstDue = d),
            ),
            if (preview != null) ...[
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _uiText(context, fa: 'پیش‌نمایش اقساط', en: 'Installment preview'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_uiText(context, fa: 'قسط اول', en: 'First installment')}: ${_formatMoneyLine(preview.firstInstallment, currencyId: _currencyId, bizCurrencies: widget.businessCurrencies, decimalPlaces: moneyDp)}',
                      ),
                      Text(
                        '${_uiText(context, fa: 'قسط آخر', en: 'Last installment')}: ${_formatMoneyLine(preview.lastInstallment, currencyId: _currencyId, bizCurrencies: widget.businessCurrencies, decimalPlaces: moneyDp)}',
                      ),
                      Text(
                        '${_uiText(context, fa: 'جمع بهره', en: 'Total interest')}: ${_formatMoneyLine(preview.totalInterest, currencyId: _currencyId, bizCurrencies: widget.businessCurrencies, decimalPlaces: moneyDp)}',
                      ),
                      Text(
                        '${_uiText(context, fa: 'جمع بازپرداخت', en: 'Total repayment')}: ${_formatMoneyLine(preview.totalRepayment, currencyId: _currencyId, bizCurrencies: widget.businessCurrencies, decimalPlaces: moneyDp)}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
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