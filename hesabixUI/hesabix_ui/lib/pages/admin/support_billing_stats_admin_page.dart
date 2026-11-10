import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_billing_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';

class SupportBillingStatsAdminPage extends StatefulWidget {
  const SupportBillingStatsAdminPage({super.key});

  @override
  State<SupportBillingStatsAdminPage> createState() => _SupportBillingStatsAdminPageState();
}

class _SupportBillingStatsAdminPageState extends State<SupportBillingStatsAdminPage> {
  late final AdminSupportBillingService _service;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _invoices = const [];
  int _invoiceTotal = 0;

  int _rangeDays = 30;
  DateTimeRange? _customRange;
  String? _invoiceStatus;
  final TextEditingController _searchCtrl = TextEditingController();

  static const _statusFa = <String, String>{
    'draft': 'پیش‌نویس',
    'awaiting_payment': 'در انتظار پرداخت',
    'paid': 'پرداخت‌شده',
    'failed': 'ناموفق',
    'expired': 'منقضی',
    'void': 'ابطال‌شده',
    'refunded': 'بازگشت وجه',
  };

  static const _statusEn = <String, String>{
    'draft': 'Draft',
    'awaiting_payment': 'Awaiting payment',
    'paid': 'Paid',
    'failed': 'Failed',
    'expired': 'Expired',
    'void': 'Voided',
    'refunded': 'Refunded',
  };

  static const _invoiceTypeFa = <String, String>{
    'purchase': 'خرید',
    'renewal': 'تمدید',
    'upgrade': 'ارتقاء',
    'trial': 'آزمایشی',
  };

  static const _invoiceTypeEn = <String, String>{
    'purchase': 'Purchase',
    'renewal': 'Renewal',
    'upgrade': 'Upgrade',
    'trial': 'Trial',
  };

  @override
  void initState() {
    super.initState();
    _service = AdminSupportBillingService(ApiClient());
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  (DateTime, DateTime) _resolveRange() {
    final now = DateTime.now().toUtc();
    if (_customRange != null) {
      final from = DateTime.utc(
        _customRange!.start.year,
        _customRange!.start.month,
        _customRange!.start.day,
      );
      final to = DateTime.utc(
        _customRange!.end.year,
        _customRange!.end.month,
        _customRange!.end.day,
        23,
        59,
        59,
      );
      return (from, to);
    }
    return (now.subtract(Duration(days: _rangeDays)), now);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _resolveRange();
      final stats = await _service.getStats(
        dateFrom: from.toIso8601String(),
        dateTo: to.toIso8601String(),
      );
      final invoices = await _service.listInvoices(
        limit: 50,
        status: _invoiceStatus,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      );
      final items = (invoices['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _invoices = items;
        _invoiceTotal = (invoices['total'] is int)
            ? invoices['total'] as int
            : int.tryParse('${invoices['total'] ?? 0}') ?? items.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  String _money(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return formatWithThousands(n, decimalPlaces: 0);
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '—';
    final s = '$v';
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s.length > 16 ? s.substring(0, 16) : s;
    }
  }

  String _statusLabel(String? status) {
    final fa = _statusFa[status];
    final en = _statusEn[status];
    if (fa == null || en == null) return status ?? '—';
    return adminTx(context, fa, en);
  }

  String _invoiceTypeLabel(String? type) {
    final fa = _invoiceTypeFa[type];
    final en = _invoiceTypeEn[type];
    if (fa == null || en == null) return type ?? '—';
    return adminTx(context, fa, en);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      helpText: adminTx(context, 'بازه گزارش', 'Report range'),
      cancelText: adminTx(context, 'انصراف', 'Cancel'),
      confirmText: adminTx(context, 'اعمال', 'Apply'),
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _rangeDays = -1;
    });
    await _load();
  }

  Future<void> _openInvoiceDetail(Map<String, dynamic> inv) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _InvoiceDetailSheet(
        invoice: inv,
        money: _money,
        formatDate: _fmtDate,
        statusLabel: _statusLabel,
        invoiceTypeLabel: _invoiceTypeLabel,
      ),
    );
    if (result == 'voided' && mounted) {
      SnackBarHelper.showSuccess(context, message: adminTx(context, 'صورت‌حساب ابطال شد', 'Invoice voided'));
      await _load();
    }
  }

  void _showBreakdownDialog({
    required String title,
    required List<(String, String)> rows,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: rows.isEmpty
              ? Text(adminTx(context, 'داده‌ای وجود ندارد', 'No data'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final (label, value) = rows[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(label),
                      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(adminTx(context, 'بستن', 'Close'))),
        ],
      ),
    );
  }

  void _showExpiringDialog() {
    final list = (_stats?['expiring_soon'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(adminTx(context, 'اشتراک‌های در شرف انقضا', 'Subscriptions about to expire')),
        content: SizedBox(
          width: 480,
          child: list.isEmpty
              ? Text(adminTx(context, 'موردی در ۷ روز آینده نیست', 'Nothing expires in the next 7 days'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = list[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule, size: 20),
                      title: Text(s['plan_name']?.toString() ?? adminTx(context, 'پلن', 'Plan')),
                      subtitle: Text(adminTx(context, 'کاربر #${s['user_id']} · ${_fmtDate(s['ends_at'])}', 'User #${s['user_id']} · ${_fmtDate(s['ends_at'])}')),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(adminTx(context, 'بستن', 'Close'))),
        ],
      ),
    );
  }

  Widget _kpi({
    required String title,
    required String value,
    required IconData icon,
    Color? color,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accent.withValues(alpha: 0.12),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_left, size: 18, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {String? actionLabel, VoidCallback? onAction}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final theme = Theme.of(context);
    final csat = (s?['csat'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final hybrid = (s?['hybrid_usage'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final byPlan = (s?['subscriptions_by_plan'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final revenueByPlan = (s?['revenue_by_plan'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final revenueByGw = (s?['revenue_by_gateway'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final byStatus = (s?['invoices_by_status'] as Map? ?? {}).cast<String, dynamic>();
    final timeseries = (s?['timeseries'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final rangeLabel = _customRange != null
        ? '${_customRange!.start.year}/${_customRange!.start.month}/${_customRange!.start.day} – '
            '${_customRange!.end.year}/${_customRange!.end.month}/${_customRange!.end.day}'
        : adminTx(context, '$_rangeDays روز اخیر', 'Last $_rangeDays days');

    return AdminCompactScaffold(
      title: adminTx(context, 'درآمد پشتیبانی', 'Support revenue'),
      subtitle: adminTx(context, 'آمار پشتیبانی غیررایگان', 'Paid support statistics'),
      actions: [
        IconButton(
          tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: Text(adminTx(context, 'تلاش مجدد', 'Retry'))),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // بازه زمانی
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(adminTx(context, 'بازه گزارش: $rangeLabel', 'Range: $rangeLabel'), style: theme.textTheme.titleSmall),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final days in [7, 30, 90])
                                    ChoiceChip(
                                      label: Text(adminTx(context, '$days روز', '$days days')),
                                      selected: _customRange == null && _rangeDays == days,
                                      onSelected: (_) {
                                        setState(() {
                                          _customRange = null;
                                          _rangeDays = days;
                                        });
                                        _load();
                                      },
                                    ),
                                  ActionChip(
                                    avatar: Icon(Icons.date_range, size: 16),
                                    label: Text(adminTx(context, 'بازه سفارشی', 'Custom range')),
                                    onPressed: _pickCustomRange,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // KPIها
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'درآمد دوره', 'Period revenue'),
                              value: adminTx(context, '${_money(s?['revenue'])} ریال', '${_money(s?['revenue'])} IRR'),
                              icon: Icons.payments,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'MRR تقریبی', 'Approximate MRR'),
                              value: adminTx(context, '${_money(s?['approximate_mrr'])} ریال', '${_money(s?['approximate_mrr'])} IRR'),
                              icon: Icons.trending_up,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'پرداخت موفق', 'Successful payments'),
                              value: '${s?['paid_count'] ?? 0}',
                              icon: Icons.check_circle,
                              color: SemanticColorResolver.positive(context),
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'پرداخت ناموفق', 'Failed payments'),
                              value: '${s?['failed_count'] ?? 0}',
                              icon: Icons.error_outline,
                              color: theme.colorScheme.error,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'نرخ موفقیت پرداخت', 'Payment success rate'),
                              value: s?['success_rate_pct'] == null
                                  ? '—'
                                  : '${s?['success_rate_pct']}%',
                              icon: Icons.percent,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'در انتظار پرداخت', 'Awaiting payment'),
                              value: '${s?['awaiting_payment_count'] ?? 0}',
                              icon: Icons.hourglass_empty,
                              color: SemanticColorResolver.warning(context),
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'اشتراک فعال', 'Active subscriptions'),
                              value:
                                  adminTx(context, '${s?['active_subscriptions'] ?? 0} (فعال ${s?['active_only'] ?? 0} · مهلت ${s?['grace_subscriptions'] ?? 0})', '${s?['active_subscriptions'] ?? 0} (active ${s?['active_only'] ?? 0} · grace ${s?['grace_subscriptions'] ?? 0})'),
                              icon: Icons.workspace_premium,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'در شرف انقضا (۷ روز)', 'Expiring in 7 days'),
                              value: '${s?['expiring_in_7_days'] ?? 0}',
                              icon: Icons.schedule,
                              color: Colors.deepOrange,
                              onTap: _showExpiringDialog,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'انقضاشده در دوره', 'Expired in period'),
                              value: '${s?['expired_in_period'] ?? 0}',
                              icon: Icons.event_busy,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi(
                              title: adminTx(context, 'تیکت به‌ازای مشترک', 'Tickets per subscriber'),
                              value: '${s?['tickets_per_subscriber'] ?? 0}',
                              icon: Icons.confirmation_number_outlined,
                            ),
                          ),
                        ],
                      ),

                      // نمودار درآمد
                      _sectionTitle(adminTx(context, 'روند درآمد روزانه', 'Daily revenue')),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                          child: _RevenueTimeseriesChart(points: timeseries, money: _money),
                        ),
                      ),

                      // تفکیک پلن و درآمد
                      _sectionTitle(
                        adminTx(context, 'تفکیک اشتراک و درآمد', 'Subscriptions and revenue'),
                        actionLabel: adminTx(context, 'جزئیات', 'Details'),
                        onAction: () {
                          final rows = <(String, String)>[
                            ...byPlan.map(
                              (p) => (
                                adminTx(context, '${p['plan_name']} (${p['period_months']} ماهه)', '${p['plan_name']} (${p['period_months']} mo)'),
                                adminTx(context, '${p['count']} اشتراک', '${p['count']} subscriptions'),
                              ),
                            ),
                            if (revenueByPlan.isNotEmpty) ('—', '—'),
                            ...revenueByPlan.map(
                              (p) => (
                                adminTx(context, 'درآمد ${p['plan_name']}', 'Revenue ${p['plan_name']}'),
                                adminTx(context, '${_money(p['revenue'])} (${p['paid_count']} پرداخت)', '${_money(p['revenue'])} (${p['paid_count']} payments)'),
                              ),
                            ),
                          ];
                          _showBreakdownDialog(title: adminTx(context, 'تفکیک پلن‌ها', 'By plan'), rows: rows);
                        },
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              if (byPlan.isEmpty)
                                ListTile(title: Text(adminTx(context, 'اشتراک فعالی نیست', 'No active subscriptions')))
                              else
                                ...byPlan.map((p) {
                                  final maxCnt = byPlan
                                      .map((e) => (e['count'] as num?)?.toDouble() ?? 0)
                                      .fold<double>(0, (a, b) => a > b ? a : b);
                                  final cnt = (p['count'] as num?)?.toDouble() ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                adminTx(context, '${p['plan_name']} · ${p['period_months']} ماهه', '${p['plan_name']} · ${p['period_months']} mo'),
                                                style: theme.textTheme.bodyMedium,
                                              ),
                                            ),
                                            Text(
                                              '${p['count']}',
                                              style: theme.textTheme.labelLarge?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(
                                          value: maxCnt <= 0 ? 0 : cnt / maxCnt,
                                          minHeight: 6,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              if (revenueByGw.isNotEmpty) ...[
                                const Divider(),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(adminTx(context, 'درآمد بر اساس درگاه', 'Revenue by gateway'), style: theme.textTheme.titleSmall),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: revenueByGw
                                      .map(
                                        (g) => Chip(
                                          avatar: const Icon(Icons.account_balance, size: 16),
                                          label: Text(
                                            '${g['gateway']}: ${_money(g['revenue'])} (${g['paid_count']})',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                              if (byStatus.isNotEmpty) ...[
                                const Divider(),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(adminTx(context, 'وضعیت صورت‌حساب‌ها در بازه', 'Invoice status in range'), style: theme.textTheme.titleSmall),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: byStatus.entries
                                      .map(
                                        (e) => FilterChip(
                                          label: Text('${_statusLabel(e.key)}: ${e.value}'),
                                          selected: _invoiceStatus == e.key,
                                          onSelected: (sel) {
                                            setState(() => _invoiceStatus = sel ? e.key : null);
                                            _load();
                                          },
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // CSAT و hybrid
                      _sectionTitle(adminTx(context, 'کیفیت و سهمیه', 'Quality and quota')),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 320,
                            child: Card(
                              child: ListTile(
                                leading: const Icon(Icons.star_rate_rounded),
                                title: Text(adminTx(context, 'میانگین CSAT مشترکان', 'Subscriber CSAT')),
                                subtitle: Text(
                                  csat['subscribers_avg'] == null
                                      ? adminTx(context, 'بدون امتیاز در بازه', 'No ratings in this range')
                                      : adminTx(context, '${csat['subscribers_avg']} از ۵ · ${csat['subscribers_count']} نظر', '${csat['subscribers_avg']} of 5 · ${csat['subscribers_count']} ratings'),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            child: Card(
                              child: ListTile(
                                leading: const Icon(Icons.star_outline),
                                title: Text(adminTx(context, 'میانگین CSAT غیرمشترک', 'Non-subscriber CSAT')),
                                subtitle: Text(
                                  csat['non_subscribers_avg'] == null
                                      ? adminTx(context, 'بدون امتیاز در بازه', 'No ratings in this range')
                                      : adminTx(context, '${csat['non_subscribers_avg']} از ۵ · ${csat['non_subscribers_count']} نظر', '${csat['non_subscribers_avg']} of 5 · ${csat['non_subscribers_count']} ratings'),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            child: Card(
                              child: ListTile(
                                leading: const Icon(Icons.data_usage),
                                title: Text(adminTx(context, 'سهمیه hybrid (${hybrid['billing_mode'] ?? '-'})', 'Hybrid quota (${hybrid['billing_mode'] ?? '-'})')),
                                subtitle: Text(
                                  adminTx(
                                    context,
                                    'دوره ${hybrid['period_key'] ?? '-'} · میانگین مصرف ${hybrid['avg_tickets_created'] ?? 0}${hybrid['free_quota_per_month'] != null ? ' از ' : ''}${hybrid['free_quota_per_month'] ?? ''}${hybrid['quota_utilization_pct'] != null ? ' · ' : ''}${hybrid['quota_utilization_pct'] ?? ''}${hybrid['quota_utilization_pct'] != null ? '%' : ''}',
                                    'Period ${hybrid['period_key'] ?? '-'} · avg usage ${hybrid['avg_tickets_created'] ?? 0}${hybrid['free_quota_per_month'] != null ? ' of ' : ''}${hybrid['free_quota_per_month'] ?? ''}${hybrid['quota_utilization_pct'] != null ? ' · ' : ''}${hybrid['quota_utilization_pct'] ?? ''}${hybrid['quota_utilization_pct'] != null ? '%' : ''}',
                                  ),
                                ),
                                onTap: () => _showBreakdownDialog(
                                  title: adminTx(context, 'جزئیات سهمیه hybrid', 'Hybrid quota details'),
                                  rows: [
                                    (adminTx(context, 'حالت صورتحساب', 'Billing mode'), '${hybrid['billing_mode'] ?? '—'}'),
                                    (adminTx(context, 'کلید دوره', 'Period key'), '${hybrid['period_key'] ?? '—'}'),
                                    (adminTx(context, 'سهمیه رایگان ماهانه', 'Free monthly quota'), '${hybrid['free_quota_per_month'] ?? '—'}'),
                                    (adminTx(context, 'کاربران دارای مصرف', 'Users with usage'), '${hybrid['users_with_usage'] ?? 0}'),
                                    (adminTx(context, 'میانگین تیکت ایجادشده', 'Average tickets created'), '${hybrid['avg_tickets_created'] ?? 0}'),
                                    (adminTx(context, 'حداکثر مصرف', 'Peak usage'), '${hybrid['max_tickets_created'] ?? 0}'),
                                    (
                                      adminTx(context, 'درصد مصرف میانگین', 'Average usage percent'),
                                      hybrid['quota_utilization_pct'] == null
                                          ? '—'
                                          : '${hybrid['quota_utilization_pct']}%',
                                    ),
                                    (
                                      adminTx(context, 'تیکت مشترکان در بازه', 'Subscriber tickets in range'),
                                      '${s?['tickets_by_subscribers_in_period'] ?? 0}',
                                    ),
                                    (adminTx(context, 'تعداد کاربران مشترک', 'Subscriber count'), '${s?['subscriber_user_count'] ?? 0}'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // صورت‌حساب‌ها
                      _sectionTitle(adminTx(context, 'صورت‌حساب‌ها ($_invoiceTotal)', 'Invoices ($_invoiceTotal)')),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _searchCtrl,
                                      decoration: InputDecoration(
                                        hintText: adminTx(context, 'جستجو با کد صورت‌حساب', 'Search by invoice code'),
                                        prefixIcon: const Icon(Icons.search),
                                        isDense: true,
                                        border: const OutlineInputBorder(),
                                        suffixIcon: _searchCtrl.text.isEmpty
                                            ? null
                                            : IconButton(
                                                icon: const Icon(Icons.clear),
                                                onPressed: () {
                                                  _searchCtrl.clear();
                                                  _load();
                                                },
                                              ),
                                      ),
                                      onSubmitted: (_) => _load(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: _load,
                                    child: Text(adminTx(context, 'اعمال', 'Apply')),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                children: [
                                  FilterChip(
                                    label: Text(adminTx(context, 'همه', 'All')),
                                    selected: _invoiceStatus == null,
                                    onSelected: (_) {
                                      setState(() => _invoiceStatus = null);
                                      _load();
                                    },
                                  ),
                                  for (final st in [
                                    'paid',
                                    'awaiting_payment',
                                    'failed',
                                    'expired',
                                    'void',
                                  ])
                                    FilterChip(
                                      label: Text(_statusLabel(st)),
                                      selected: _invoiceStatus == st,
                                      onSelected: (sel) {
                                        setState(() => _invoiceStatus = sel ? st : null);
                                        _load();
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_invoices.isEmpty)
                        Card(
                          child: ListTile(title: Text(adminTx(context, 'صورت‌حسابی یافت نشد', 'No invoices'))),
                        )
                      else
                        ..._invoices.map((inv) {
                          final status = inv['status']?.toString() ?? '';
                          final color = switch (status) {
                            'paid' => SemanticColorResolver.positive(context),
                            'failed' => theme.colorScheme.error,
                            'awaiting_payment' => SemanticColorResolver.warning(context),
                            'void' => Colors.grey,
                            'expired' => Colors.blueGrey,
                            _ => theme.colorScheme.primary,
                          };
                          final userLabel = inv['user_name']?.toString().trim().isNotEmpty == true
                              ? inv['user_name']
                              : adminTx(context, 'کاربر #${inv['user_id']}', 'User #${inv['user_id']}');
                          return Card(
                            child: ListTile(
                              onTap: () => _openInvoiceDetail(inv),
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.15),
                                child: Icon(Icons.receipt_long, color: color, size: 18),
                              ),
                              title: Text(inv['code']?.toString() ?? ''),
                              subtitle: Text(
                                '$userLabel · ${inv['plan_name'] ?? '-'} · ${adminTx(context, '${_money(inv['amount'])} ریال · ${_statusLabel(status)}', '${_money(inv['amount'])} IRR · ${_statusLabel(status)}')}',
                              ),
                              trailing: const Icon(Icons.chevron_left),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _RevenueTimeseriesChart extends StatelessWidget {
  final List<Map<String, dynamic>> points;
  final String Function(dynamic) money;

  const _RevenueTimeseriesChart({required this.points, required this.money});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(child: Text(adminTx(context, 'در این بازه درآمدی ثبت نشده است', 'No revenue in this range'))),
      );
    }

    final values = points
        .map((p) => (p['revenue'] is num) ? (p['revenue'] as num).toDouble() : double.tryParse('${p['revenue']}') ?? 0)
        .toList();
    final maxY = values.fold<double>(0, (a, b) => a > b ? a : b);
    final spots = List.generate(points.length, (i) => FlSpot(i.toDouble(), values[i]));

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: theme.colorScheme.outline.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text(
                  money(v),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: points.length <= 8 ? 1 : (points.length / 6).ceilToDouble(),
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  final date = '${points[i]['date'] ?? ''}';
                  final short = date.length >= 5 ? date.substring(5) : date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(short, style: theme.textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => touched.map((t) {
                final i = t.x.toInt();
                final date = (i >= 0 && i < points.length) ? '${points[i]['date']}' : '';
                return LineTooltipItem(
                  adminTx(context, '$date\n${money(t.y)} ریال', '$date\n${money(t.y)} IRR'),
                  TextStyle(color: theme.colorScheme.onInverseSurface, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              color: theme.colorScheme.primary,
              dotData: FlDotData(show: points.length <= 20),
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceDetailSheet extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String Function(dynamic) money;
  final String Function(dynamic) formatDate;
  final String Function(String?) statusLabel;
  final String Function(String?) invoiceTypeLabel;

  const _InvoiceDetailSheet({
    required this.invoice,
    required this.money,
    required this.formatDate,
    required this.statusLabel,
    required this.invoiceTypeLabel,
  });

  @override
  State<_InvoiceDetailSheet> createState() => _InvoiceDetailSheetState();
}

class _InvoiceDetailSheetState extends State<_InvoiceDetailSheet> {
  bool _voiding = false;

  Future<void> _voidInvoice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(adminTx(context, 'ابطال صورت‌حساب', 'Void invoice')),
        content: Text(
          adminTx(context, 'صورت‌حساب ${widget.invoice['code']} ابطال شود؟\nاین عمل برای صورت‌حساب‌های پرداخت‌شده مجاز نیست.', 'Void invoice ${widget.invoice['code']}?\nPaid invoices cannot be voided.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(adminTx(context, 'انصراف', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(adminTx(context, 'ابطال', 'Void')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _voiding = true);
    try {
      final id = widget.invoice['id'] as int;
      await AdminSupportBillingService(ApiClient()).voidInvoice(id);
      if (!mounted) return;
      Navigator.pop(context, 'voided');
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiding = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _row(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final theme = Theme.of(context);
    final status = inv['status']?.toString();
    final canVoid = status != null && status != 'paid' && status != 'void' && status != 'refunded';
    final userLabel = inv['user_name']?.toString().trim().isNotEmpty == true
        ? '${inv['user_name']} (#${inv['user_id']})'
        : adminTx(context, 'کاربر #${inv['user_id']}', 'User #${inv['user_id']}');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(inv['code']?.toString() ?? adminTx(context, 'صورت‌حساب', 'Invoice'), style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                widget.statusLabel(status),
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
              ),
              const Divider(height: 24),
              _row(adminTx(context, 'کاربر', 'User'), userLabel),
              if (inv['user_email'] != null) _row(adminTx(context, 'ایمیل', 'Email'), '${inv['user_email']}'),
              _row(adminTx(context, 'پلن', 'Plan'), '${inv['plan_name'] ?? '—'}'),
              if (inv['plan_code'] != null) _row(adminTx(context, 'کد پلن', 'Plan code'), '${inv['plan_code']}'),
              _row(adminTx(context, 'نوع', 'Type'), widget.invoiceTypeLabel(inv['invoice_type']?.toString())),
              _row(adminTx(context, 'مبلغ', 'Amount'), adminTx(context, '${widget.money(inv['amount'])} ریال', '${widget.money(inv['amount'])} IRR')),
              if ((inv['discount_amount'] is num) && (inv['discount_amount'] as num) > 0)
                _row(adminTx(context, 'تخفیف', 'Discount'), adminTx(context, '${widget.money(inv['discount_amount'])} ریال', '${widget.money(inv['discount_amount'])} IRR')),
              _row(adminTx(context, 'مدت', 'Term'), adminTx(context, '${inv['period_months'] ?? '—'} ماه', '${inv['period_months'] ?? '—'} mo')),
              _row(adminTx(context, 'صدور', 'Issued'), widget.formatDate(inv['issued_at'])),
              _row(adminTx(context, 'سررسید', 'Due'), widget.formatDate(inv['due_at'])),
              _row(adminTx(context, 'پرداخت', 'Paid'), widget.formatDate(inv['paid_at'])),
              _row(adminTx(context, 'شروع پوشش', 'Coverage start'), widget.formatDate(inv['coverage_starts_at'])),
              _row(adminTx(context, 'پایان پوشش', 'Coverage end'), widget.formatDate(inv['coverage_ends_at'])),
              _row(adminTx(context, 'درگاه', 'Gateway'), '${inv['gateway_provider'] ?? '—'}'),
              if (inv['gateway_ref'] != null) _row(adminTx(context, 'مرجع درگاه', 'Gateway reference'), '${inv['gateway_ref']}'),
              if (inv['gateway_trace'] != null) _row(adminTx(context, 'پیگیری', 'Tracking'), '${inv['gateway_trace']}'),
              if (inv['payment_session_id'] != null) _row(adminTx(context, 'نشست پرداخت', 'Payment session'), '#${inv['payment_session_id']}'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(adminTx(context, 'بستن', 'Close')),
                    ),
                  ),
                  if (canVoid) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _voiding ? null : _voidInvoice,
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                        ),
                        child: _voiding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(adminTx(context, 'ابطال', 'Void')),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
