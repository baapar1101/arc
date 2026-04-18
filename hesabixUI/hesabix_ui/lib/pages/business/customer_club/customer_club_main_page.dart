import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../models/person_model.dart';
import '../../../services/customer_club_service.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';

/// صفحهٔ اصلی باشگاه مشتریان (تراکنش‌ها و در صورت مجوز اصلاح دستی). تنظیمات در مسیر جدا است.
class CustomerClubMainPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const CustomerClubMainPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.calendarController,
  });

  @override
  State<CustomerClubMainPage> createState() => _CustomerClubMainPageState();
}

class _CustomerClubMainPageState extends State<CustomerClubMainPage> with SingleTickerProviderStateMixin {
  static const double _largeDeltaThreshold = 500;

  TabController? _tabController;

  bool _showAdjustTab = false;

  final CustomerClubService _svc = CustomerClubService();

  List<Map<String, dynamic>> _ledgerRows = [];
  int _ledgerTotal = 0;
  final int _pageSize = 30;

  Person? _ledgerFilterPerson;

  bool _loadingLedger = true;

  /// اصلاح دستی
  Person? _adjustPerson;
  double? _adjustBalancePreview;
  bool _loadingAdjustBalance = false;
  final TextEditingController _adjustDeltaCtl = TextEditingController();
  final TextEditingController _adjustDescCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _showAdjustTab = _computeCanAdjust();
    if (_showAdjustTab) {
      _tabController = TabController(length: 2, vsync: this);
      _tabController!.addListener(() {
        if (mounted) setState(() {});
      });
    }
    widget.calendarController?.addListener(_onCalendarChanged);
    _loadLedger(reset: true);
  }

  bool _computeCanAdjust() {
    return widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.hasBusinessPermission('customer_club', 'adjust');
  }

  void _onCalendarChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.calendarController?.removeListener(_onCalendarChanged);
    _tabController?.dispose();
    _adjustDeltaCtl.dispose();
    _adjustDescCtl.dispose();
    super.dispose();
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '';
    if (v is num && v == v.roundToDouble()) return v.toStringAsFixed(0).replaceFirst(RegExp(r'\.?0+$'), '');
    return v.toString();
  }

  bool get _isJalaliCalendar =>
      widget.calendarController?.isJalali ?? ApiClient.getCalendarController()?.isJalali ?? true;

  String _formatLedgerCreatedAt(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return s;
    return HesabixDateUtils.formatDateTime(parsed.toLocal(), _isJalaliCalendar);
  }

  String _transactionTypeLabel(AppLocalizations t, String? raw) {
    switch (raw) {
      case 'adjustment':
        return t.customerClubTxnAdjustment;
      case 'redeem':
        return t.customerClubTxnRedeem;
      case 'redeem_void':
        return t.customerClubTxnRedeemVoid;
      case 'invoice_sync':
        return t.customerClubTxnInvoiceSync;
      case 'invoice_delete_reversal':
        return t.customerClubTxnInvoiceDeleteReversal;
      case 'invoice_delete_reversal_redeem':
        return t.customerClubTxnInvoiceDeleteReversalRedeem;
      default:
        return raw ?? '—';
    }
  }

  Color _deltaColor(ThemeData theme, num? delta) {
    if (delta == null) return theme.colorScheme.onSurface;
    if (delta > 0) return Colors.green.shade700;
    if (delta < 0) return theme.colorScheme.error;
    return theme.colorScheme.onSurface;
  }

  Future<void> _loadLedger({bool reset = false, bool append = false}) async {
    if (!mounted) return;
    setState(() => _loadingLedger = true);
    final skip = append ? _ledgerRows.length : 0;
    final filterId = _ledgerFilterPerson?.id;
    try {
      final data = await _svc.listLedger(
        businessId: widget.businessId,
        limit: _pageSize,
        skip: skip,
        personId: filterId,
      );
      if (!mounted) return;
      final items = data['items'];
      final total = data['total'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            list.add(Map<String, dynamic>.from(e));
          }
        }
      }
      setState(() {
        if (append && !reset) {
          _ledgerRows = [..._ledgerRows, ...list];
        } else {
          _ledgerRows = list;
        }
        _ledgerTotal = total is int ? total : int.tryParse('$total') ?? 0;
      });
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    } finally {
      if (mounted) setState(() => _loadingLedger = false);
    }
  }

  Future<void> _loadAdjustBalancePreview() async {
    final id = _adjustPerson?.id;
    if (id == null) {
      setState(() {
        _adjustBalancePreview = null;
        _loadingAdjustBalance = false;
      });
      return;
    }
    setState(() {
      _loadingAdjustBalance = true;
      _adjustBalancePreview = null;
    });
    try {
      final data = await _svc.getPersonBalance(businessId: widget.businessId, personId: id);
      if (!mounted) return;
      final raw = data['balance_points'];
      final v = raw is num ? raw.toDouble() : double.tryParse('$raw');
      setState(() => _adjustBalancePreview = v);
    } catch (_) {
      if (mounted) setState(() => _adjustBalancePreview = null);
    } finally {
      if (mounted) setState(() => _loadingAdjustBalance = false);
    }
  }

  Future<bool> _confirmLargeAdjustment(AppLocalizations t, double delta) async {
    if (delta.abs() < _largeDeltaThreshold) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.customerClubAdjustmentLargeDeltaTitle),
        content: Text(t.customerClubAdjustmentLargeDeltaBody(_fmtNum(delta))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.confirm)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submitAdjustment() async {
    final t = AppLocalizations.of(context);
    final pid = _adjustPerson?.id;
    final delta = double.tryParse(_adjustDeltaCtl.text.trim().replaceAll(',', ''));
    final desc = _adjustDescCtl.text.trim();
    if (pid == null || pid <= 0) {
      SnackBarHelper.showError(context, message: t.customerClubInvalidPersonId);
      return;
    }
    if (delta == null) {
      SnackBarHelper.showError(context, message: t.customerClubInvalidDelta);
      return;
    }
    if (desc.isEmpty) {
      SnackBarHelper.showError(context, message: t.customerClubDescriptionRequired);
      return;
    }
    if (!await _confirmLargeAdjustment(t, delta)) return;
    try {
      await _svc.submitAdjustment(
        businessId: widget.businessId,
        personId: pid,
        deltaPoints: delta,
        description: desc,
      );
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: t.customerClubAdjustmentSaved,
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: t.customerClubViewLedgerAction,
          onPressed: () {
            _tabController?.animateTo(0);
          },
        ),
      );
      _adjustDeltaCtl.clear();
      _adjustDescCtl.clear();
      await _loadAdjustBalancePreview();
      await _loadLedger(reset: true);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    final ledgerView = _buildLedgerTab(Theme.of(context), t);

    if (!_showAdjustTab) {
      return Scaffold(
        appBar: AppBar(title: Text(t.customerClubTitle)),
        body: ledgerView,
      );
    }

    final tc = _tabController!;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.customerClubTitle),
        bottom: TabBar(
          controller: tc,
          tabs: [
            Tab(icon: const Icon(Icons.receipt_long_outlined), text: t.customerClubTabLedger),
            Tab(icon: const Icon(Icons.edit_note_outlined), text: t.customerClubTabAdjust),
          ],
        ),
      ),
      body: TabBarView(
        controller: tc,
        children: [
          ledgerView,
          _buildAdjustTab(Theme.of(context), t),
        ],
      ),
    );
  }

  Widget _buildLedgerTab(ThemeData theme, AppLocalizations t) {
    if (_loadingLedger && _ledgerRows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final hasMore = _ledgerRows.length < _ledgerTotal;
    final empty = _ledgerRows.isEmpty && !_loadingLedger;

    return RefreshIndicator(
      onRefresh: () => _loadLedger(reset: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: PersonComboboxWidget(
              businessId: widget.businessId,
              selectedPerson: _ledgerFilterPerson,
              label: t.customerClubLedgerFilterPerson,
              hintText: t.workflowConfigSearchSelectPerson,
              onChanged: (p) {
                setState(() => _ledgerFilterPerson = p);
                _loadLedger(reset: true);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t.customerClubLedgerTotal}: $_ledgerTotal',
                        style: theme.textTheme.titleSmall,
                      ),
                      if (_ledgerTotal > 0)
                        Text(
                          t.customerClubLedgerShowingCount(_ledgerRows.length, _ledgerTotal),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _loadLedger(reset: true),
                  icon: const Icon(Icons.refresh),
                  label: Text(t.refresh),
                ),
              ],
            ),
          ),
          if (empty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 56, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        t.customerClubLedgerEmpty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _ledgerRows.length + (hasMore ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= _ledgerRows.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: OutlinedButton(
                          onPressed: _loadingLedger
                              ? null
                              : () async {
                                  await _loadLedger(append: true);
                                },
                          child: Text(t.customerClubLoadMore),
                        ),
                      ),
                    );
                  }
                  final r = _ledgerRows[i];
                  final dt = _formatLedgerCreatedAt(r['created_at']);
                  final docId = r['reference_document_id'];
                  final txnRaw = r['transaction_type']?.toString();
                  final txnLabel = _transactionTypeLabel(t, txnRaw);
                  final deltaRaw = r['delta_points'];
                  final deltaNum = deltaRaw is num ? deltaRaw : num.tryParse('$deltaRaw');
                  final desc = (r['description'] ?? '').toString().trim();

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      title: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            label: Text(txnLabel),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          Text(
                            '${deltaRaw ?? '-'} ${t.customerClubPointsShort}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: _deltaColor(theme, deltaNum),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${t.customerClubBalanceAfter}: ${r['balance_after']} · '
                          '${t.customerClubPerson}: ${r['person_id'] ?? '-'}'
                          '${docId != null ? ' · ${t.customerClubReferenceDocument}: $docId' : ''}'
                          '${dt.isEmpty ? '' : '\n$dt'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      children: [
                        if (desc.isNotEmpty)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(desc, style: theme.textTheme.bodyMedium),
                          )
                        else
                          Text(
                            '—',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAdjustTab(ThemeData theme, AppLocalizations t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(t.customerClubAdjustIntro, style: theme.textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: 16),
          PersonComboboxWidget(
            businessId: widget.businessId,
            selectedPerson: _adjustPerson,
            label: t.customerClubPerson,
            hintText: t.workflowConfigSearchSelectPerson,
            onChanged: (p) {
              setState(() => _adjustPerson = p);
              _loadAdjustBalancePreview();
            },
          ),
          if (_adjustPerson != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.customerClubCurrentPointsBalance,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (_loadingAdjustBalance)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    _adjustBalancePreview == null ? '—' : _fmtNum(_adjustBalancePreview),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _adjustDeltaCtl,
            decoration: InputDecoration(labelText: t.customerClubDeltaPoints),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
          TextField(
            controller: _adjustDescCtl,
            decoration: InputDecoration(labelText: t.description),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitAdjustment,
            icon: const Icon(Icons.add),
            label: Text(t.customerClubSubmitAdjustment),
          ),
        ],
      ),
    );
  }
}
