import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../../services/admin_wallet_payouts_service.dart';
import '../../utils/number_formatters.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/jalali_date_picker.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../core/calendar_controller.dart';

class WalletPayoutsAdminPage extends StatefulWidget {
  const WalletPayoutsAdminPage({super.key});

  @override
  State<WalletPayoutsAdminPage> createState() => _WalletPayoutsAdminPageState();
}

class _WalletPayoutsAdminPageState extends State<WalletPayoutsAdminPage> {
  late final AdminWalletPayoutsService _service;
  CalendarController? _calendarCtrl;
  Map<String, dynamic>? _stats;
  bool _loadingStats = true;
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();

  static const List<Map<String, String>> _statusOptions = [
    {'value': 'requested', 'label': 'در انتظار تایید', 'icon': 'pending'},
    {'value': 'approved', 'label': 'تایید شده', 'icon': 'check_circle'},
    {'value': 'processing', 'label': 'در حال پردازش', 'icon': 'sync'},
    {'value': 'settled', 'label': 'تسویه شده', 'icon': 'done'},
    {'value': 'canceled', 'label': 'لغو شده', 'icon': 'cancel'},
    {'value': 'failed', 'label': 'ناموفق', 'icon': 'error'},
  ];

  @override
  void initState() {
    super.initState();
    _service = AdminWalletPayoutsService(ApiClient());
    CalendarController.load().then((c) {
      if (mounted) setState(() => _calendarCtrl = c);
    });
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final stats = await _service.getStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingStats = false);
      }
    }
  }

  String _statusLabel(String raw, AppLocalizations t) {
    switch (raw.toLowerCase()) {
      case 'requested':
        return t.pending;
      case 'approved':
        return t.statusApproved;
      case 'processing':
        return t.statusProcessing;
      case 'settled':
        return t.walletTypePayoutSettlement;
      case 'failed':
        return t.statusFailed;
      case 'canceled':
        return t.statusCanceled;
      default:
        return t.unknown;
    }
  }

  Color _statusColor(String raw, ThemeData theme) {
    switch (raw.toLowerCase()) {
      case 'settled':
        return Colors.green.shade600;
      case 'failed':
        return Colors.red.shade600;
      case 'canceled':
        return Colors.orange.shade700;
      case 'approved':
        return Colors.blue.shade600;
      case 'processing':
        return Colors.teal.shade600;
      case 'requested':
        return Colors.amber.shade700;
      default:
        return theme.colorScheme.primary;
    }
  }

  IconData _statusIcon(String raw) {
    switch (raw.toLowerCase()) {
      case 'settled':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'canceled':
        return Icons.cancel;
      case 'approved':
        return Icons.verified;
      case 'processing':
        return Icons.sync;
      case 'requested':
        return Icons.pending;
      default:
        return Icons.help_outline;
    }
  }

  int _calculatePendingDays(String? createdAt) {
    if (createdAt == null) return 0;
    try {
      final created = DateTime.parse(createdAt);
      final now = DateTime.now();
      return now.difference(created).inDays;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openPayoutDetail(int payoutId) async {
    try {
      final payout = await _service.getById(payoutId);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _PayoutDetailSheet(
          payout: payout,
          statusLabelBuilder: (value) => _statusLabel(value, AppLocalizations.of(context)),
          statusColorBuilder: (value) => _statusColor(value, Theme.of(context)),
          onSettle: payout['status'] == 'settled'
              ? null
              : () => _showSettleDialog(payout),
          onRefresh: () {
            _loadStats();
            Navigator.of(ctx).pop();
          },
          calendarController: _calendarCtrl,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _showSettleDialog(Map<String, dynamic> payout) async {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final formKey = GlobalKey<FormState>();
    final trackingCtrl = TextEditingController(text: payout['bank_tracking_code']?.toString() ?? '');
    final feeCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: payout['settlement_note']?.toString() ?? '');
    DateTime selectedDate = DateTime.now();
    double? netAmount;
    
    try {
      final existingDate = payout['settlement_date'];
      if (existingDate is String) {
        final parsed = DateTime.tryParse(existingDate);
        if (parsed != null) {
          selectedDate = parsed;
        }
      }
    } catch (_) {}
    
    final grossAmount = (payout['gross_amount'] ?? 0) is num 
        ? (payout['gross_amount'] as num).toDouble() 
        : double.tryParse('${payout['gross_amount']}') ?? 0.0;

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              void _updateNetAmount() {
                final feeText = feeCtrl.text.trim().replaceAll(',', '');
                final feeValue = feeText.isEmpty ? 0.0 : (double.tryParse(feeText) ?? 0.0);
                final newNet = grossAmount - feeValue;
                setDialogState(() {
                  netAmount = newNet < 0 ? 0.0 : newNet;
                });
              }

              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.account_balance_wallet, color: theme.colorScheme.onPrimary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  t.walletPayoutsAdminSettleDialogTitle,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
                                onPressed: () => Navigator.of(ctx).pop(false),
                              ),
                            ],
                          ),
                        ),
                        // Summary Card
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Card(
                            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'خلاصه درخواست',
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('کسب‌وکار:', style: theme.textTheme.bodySmall),
                                      Text(
                                        '${payout['business_name'] ?? '-'} (#${payout['business_id']})',
                                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('مبلغ ناخالص:', style: theme.textTheme.bodySmall),
                                      Text(
                                        formatWithThousands(grossAmount),
                                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Form Fields
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: [
                                TextFormField(
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: t.walletPayoutsAdminSettlementDate,
                                    suffixIcon: const Icon(Icons.calendar_today),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                  ),
                                  controller: TextEditingController(
                                    text: HesabixDateUtils.formatForDisplay(
                                      selectedDate,
                                      _calendarCtrl?.isJalali ?? true,
                                    ),
                                  ),
                                  onTap: () async {
                                    final picked = await showAdaptiveDatePicker(
                                      context: ctx,
                                      calendarController: _calendarCtrl,
                                      initialDate: selectedDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now().add(const Duration(days: 1)),
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        selectedDate = picked;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: trackingCtrl,
                                  decoration: InputDecoration(
                                    labelText: t.bankTrackingCode,
                                    hintText: 'مثال: 1234567890',
                                    prefixIcon: const Icon(Icons.numbers),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return t.walletPayoutsAdminFormRequired;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: feeCtrl,
                                  decoration: InputDecoration(
                                    labelText: t.feeAmount,
                                    helperText: t.walletPayoutsAdminFeeHint,
                                    prefixIcon: const Icon(Icons.percent),
                                    suffixText: 'ریال',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                  ],
                                  onChanged: (_) => _updateNetAmount(),
                                ),
                                if (netAmount != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('مبلغ خالص:', style: theme.textTheme.bodySmall),
                                        Text(
                                          formatWithThousands(netAmount!),
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: noteCtrl,
                                  decoration: InputDecoration(
                                    labelText: t.descriptionOptional,
                                    prefixIcon: const Icon(Icons.note_outlined),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                  ),
                                  maxLines: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Actions
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: Text(t.cancel),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () async {
                                  if (formKey.currentState?.validate() != true) {
                                    return;
                                  }
                                  try {
                                    final feeText = feeCtrl.text.trim().replaceAll(',', '');
                                    final feeValue = feeText.isEmpty ? null : double.tryParse(feeText);
                                    await _service.settle(
                                      payoutId: payout['id'] as int,
                                      settlementDate: selectedDate,
                                      bankTrackingCode: trackingCtrl.text.trim(),
                                      feeAmount: feeValue,
                                      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                                    );
                                    if (!mounted) return;
                                    SnackBarHelper.show(context, message: t.walletPayoutsAdminSuccess);
                                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                                  } catch (e) {
                                    if (!mounted) return;
                                    SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
                                  }
                                },
                                icon: const Icon(Icons.check_circle_outline),
                                label: Text(t.walletPayoutsAdminSettleAction),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
      if (confirmed == true && mounted) {
        await _loadStats();
      }
    } finally {
      trackingCtrl.dispose();
      feeCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Widget _buildStatsCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final isJalali = _calendarCtrl?.isJalali ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.walletPayoutsAdminTitle),
        actions: [
          IconButton(
            tooltip: t.refresh,
            onPressed: () {
              _loadStats();
              _refreshKey.currentState?.show();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        key: _refreshKey,
        onRefresh: () async {
          await _loadStats();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats Dashboard
              if (_loadingStats)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_stats != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'آمار کلی',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.5,
                        children: [
                          _buildStatsCard(
                            title: 'کل درخواست‌ها',
                            value: '${_stats!['total_count'] ?? 0}',
                            icon: Icons.receipt_long,
                            color: theme.colorScheme.primary,
                          ),
                          _buildStatsCard(
                            title: 'در انتظار تسویه',
                            value: formatWithThousands((_stats!['pending_total'] ?? 0) is num 
                                ? (_stats!['pending_total'] as num).toDouble() 
                                : double.tryParse('${_stats!['pending_total']}') ?? 0),
                            icon: Icons.pending_actions,
                            color: Colors.amber.shade700,
                            subtitle: '${(_stats!['status_counts']?['requested'] ?? 0) + (_stats!['status_counts']?['approved'] ?? 0) + (_stats!['status_counts']?['processing'] ?? 0)} درخواست',
                          ),
                          _buildStatsCard(
                            title: 'تسویه شده (ماه جاری)',
                            value: formatWithThousands((_stats!['monthly_settled'] ?? 0) is num 
                                ? (_stats!['monthly_settled'] as num).toDouble() 
                                : double.tryParse('${_stats!['monthly_settled']}') ?? 0),
                            icon: Icons.check_circle,
                            color: Colors.green.shade600,
                          ),
                          _buildStatsCard(
                            title: 'کارمزد (ماه جاری)',
                            value: formatWithThousands((_stats!['monthly_fees'] ?? 0) is num 
                                ? (_stats!['monthly_fees'] as num).toDouble() 
                                : double.tryParse('${_stats!['monthly_fees']}') ?? 0),
                            icon: Icons.percent,
                            color: Colors.orange.shade700,
                          ),
                        ],
                      ),
                      if ((_stats!['old_pending_count'] ?? 0) > 0) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_stats!['old_pending_count']} درخواست قدیمی (> 7 روز) نیاز به بررسی دارد',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              // Quick Filters
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.walletPayoutsAdminSubtitle,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              // جدول؛ اسکرول عمودی با کل صفحه
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DataTableWidget<Map<String, dynamic>>(
                  config: DataTableConfig<Map<String, dynamic>>(
                    endpoint: '/admin/wallets/payouts/table',
                    title: t.walletPayoutsAdminTitle,
                    showTableIcon: true,
                    showSearch: true,
                    showActiveFilters: true,
                    showPagination: true,
                    defaultPageSize: 25,
                    pageSizeOptions: const [10, 25, 50, 100],
                    enableColumnSettings: true,
                    httpMethod: 'POST',
                    columns: [
                      TextColumn('business_name', t.business, 
                        width: ColumnWidth.large,
                        formatter: (it) {
                          final name = it['business_name']?.toString() ?? '-';
                          final id = it['business_id']?.toString() ?? '';
                          return '$name (#$id)';
                        },
                      ),
                      NumberColumn('gross_amount', t.moneyAmount, 
                        formatter: (it) {
                          final amount = it['gross_amount'];
                          final n = (amount is num) ? amount.toDouble() : double.tryParse('$amount') ?? 0;
                          return formatWithThousands(n);
                        },
                      ),
                      NumberColumn('fees', t.feeAmount, 
                        formatter: (it) {
                          final fee = it['fees'];
                          final n = (fee is num) ? fee.toDouble() : double.tryParse('$fee') ?? 0;
                          return formatWithThousands(n);
                        },
                      ),
                      NumberColumn('net_amount', 'مبلغ خالص', 
                        formatter: (it) {
                          final net = it['net_amount'];
                          final n = (net is num) ? net.toDouble() : double.tryParse('$net') ?? 0;
                          return formatWithThousands(n);
                        },
                      ),
                      CustomColumn('status', t.status,
                        filterType: ColumnFilterType.multiSelect,
                        filterOptions: _statusOptions.map((opt) => FilterOption(
                          value: opt['value']!,
                          label: opt['label']!,
                          icon: _statusIcon(opt['value']!) != Icons.help_outline 
                              ? _statusIcon(opt['value']!) 
                              : null,
                        )).toList(),
                        builder: (item, index) {
                          final status = item['status']?.toString() ?? '';
                          final color = _statusColor(status, theme);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_statusIcon(status), size: 16, color: color),
                                const SizedBox(width: 4),
                                Text(
                                  _statusLabel(status, t),
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      TextColumn('pending_days', 'روزهای انتظار',
                        formatter: (it) {
                          final days = _calculatePendingDays(it['created_at']?.toString());
                          if (days == 0) return '-';
                          final status = it['status']?.toString() ?? '';
                          if (status == 'settled') return '-';
                          return '$days روز';
                        },
                      ),
                      DateColumn('created_at', t.createdAt, 
                        filterType: ColumnFilterType.dateRange,
                        formatter: (it) {
                          final v = it['created_at'];
                          if (v == null) return '';
                          DateTime? date;
                          if (v is DateTime) {
                            date = v;
                          } else if (v is String) {
                            try {
                              date = DateTime.parse(v);
                            } catch (e) {
                              return v.toString();
                            }
                          } else {
                            return v.toString();
                          }
                          return HesabixDateUtils.formatForDisplay(date, isJalali);
                        },
                      ),
                      DateColumn('settlement_date', t.walletPayoutsAdminSettlementDate, 
                        formatter: (it) {
                          final v = it['settlement_date'];
                          if (v == null) return '-';
                          DateTime? date;
                          if (v is DateTime) {
                            date = v;
                          } else if (v is String) {
                            try {
                              date = DateTime.parse(v);
                            } catch (e) {
                              return v.toString();
                            }
                          } else {
                            return v.toString();
                          }
                          return HesabixDateUtils.formatForDisplay(date, isJalali);
                        },
                      ),
                      TextColumn('bank_tracking_code', t.bankTrackingCode, 
                        formatter: (it) {
                          return it['bank_tracking_code']?.toString() ?? '-';
                        },
                      ),
                      ActionColumn('actions', t.actions, actions: [
                        DataTableAction(
                          icon: Icons.visibility_outlined,
                          label: t.view,
                          onTap: (item) => _openPayoutDetail(item['id'] as int),
                        ),
                      ]),
                    ],
                    onRowTap: (row) => _openPayoutDetail(row['id'] as int),
                    rowColorBuilder: (item, index) {
                      final days = _calculatePendingDays(item['created_at']?.toString());
                      final status = item['status']?.toString() ?? '';
                      if (days > 7 && status != 'settled') {
                        return Colors.orange.shade50;
                      }
                      return null;
                    },
                    onRefresh: () => _loadStats(),
                  
        expandBodyHeightToFitRows: true,),
                  fromJson: (json) => Map<String, dynamic>.from(json),
                  calendarController: _calendarCtrl,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayoutDetailSheet extends StatelessWidget {
  final Map<String, dynamic> payout;
  final String Function(String) statusLabelBuilder;
  final Color Function(String) statusColorBuilder;
  final Future<void> Function()? onSettle;
  final VoidCallback? onRefresh;
  final CalendarController? calendarController;

  const _PayoutDetailSheet({
    required this.payout,
    required this.statusLabelBuilder,
    required this.statusColorBuilder,
    this.onSettle,
    this.onRefresh,
    this.calendarController,
  });

  String _formatDate(String? dateStr, bool isJalali) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return HesabixDateUtils.formatForDisplay(date, isJalali);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final isJalali = calendarController?.isJalali ?? false;
    final status = payout['status']?.toString() ?? '';
    final statusColor = statusColorBuilder(status);
    
    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.4,
      initialChildSize: 0.7,
      builder: (ctx, controller) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header with status badge
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(color: statusColor.withOpacity(0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getStatusIcon(status),
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t.walletPayoutsAdminTitle} #${payout['id']}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusLabelBuilder(status),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onSettle != null)
                      FilledButton.icon(
                        onPressed: onSettle,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(t.walletPayoutsAdminSettleAction),
                      ),
                  ],
                ),
              ),
              // Timeline
              if (payout['created_at'] != null || payout['settlement_date'] != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تاریخچه',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _TimelineItem(
                        icon: Icons.add_circle_outline,
                        title: 'ایجاد درخواست',
                        date: _formatDate(payout['created_at']?.toString(), isJalali),
                        color: Colors.blue,
                      ),
                      if (status == 'approved' || status == 'processing' || status == 'settled')
                        _TimelineItem(
                          icon: Icons.verified,
                          title: 'تایید شده',
                          date: _formatDate(payout['updated_at']?.toString(), isJalali),
                          color: Colors.green,
                        ),
                      if (status == 'settled' && payout['settlement_date'] != null)
                        _TimelineItem(
                          icon: Icons.check_circle,
                          title: 'تسویه شده',
                          date: _formatDate(payout['settlement_date']?.toString(), isJalali),
                          color: Colors.green.shade700,
                          isLast: true,
                        ),
                    ],
                  ),
                ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _InfoTile(
                            label: t.business,
                            value: '${payout['business_name'] ?? '-'} (#${payout['business_id']})',
                            icon: Icons.business,
                            onTap: () {
                              final businessId = payout['business_id'];
                              if (businessId != null) {
                                context.pushNamed(
                                  'business_dashboard',
                                  pathParameters: {'business_id': businessId.toString()},
                                );
                              }
                            },
                          ),
                          _InfoTile(
                            label: t.moneyAmount,
                            value: formatWithThousands(
                              (payout['gross_amount'] ?? 0) is num ? payout['gross_amount'] : double.tryParse('${payout['gross_amount']}') ?? 0,
                            ),
                            icon: Icons.payments_outlined,
                          ),
                          _InfoTile(
                            label: t.feeAmount,
                            value: formatWithThousands(
                              (payout['fees'] ?? 0) is num ? payout['fees'] : double.tryParse('${payout['fees']}') ?? 0,
                            ),
                            icon: Icons.percent,
                          ),
                          _InfoTile(
                            label: 'مبلغ خالص',
                            value: formatWithThousands(
                              (payout['net_amount'] ?? 0) is num ? payout['net_amount'] : double.tryParse('${payout['net_amount']}') ?? 0,
                            ),
                            icon: Icons.account_balance_wallet,
                          ),
                          _InfoTile(
                            label: t.bankTrackingCode,
                            value: payout['bank_tracking_code']?.toString() ?? '-',
                            icon: Icons.numbers,
                            onTap: payout['bank_tracking_code'] != null ? () {
                              Clipboard.setData(ClipboardData(text: payout['bank_tracking_code'].toString()));
                              SnackBarHelper.show(context, message: 'کد پیگیری کپی شد');
                            } : null,
                          ),
                          _InfoTile(
                            label: t.walletPayoutsAdminSettlementDate,
                            value: _formatDate(payout['settlement_date']?.toString(), isJalali),
                            icon: Icons.calendar_today,
                          ),
                          if (payout['document_id'] != null)
                            _InfoTile(
                              label: t.document,
                              value: '${payout['document_id']}',
                              icon: Icons.description_outlined,
                              onTap: () {
                                final businessId = payout['business_id'];
                                final docId = payout['document_id'];
                                if (businessId != null && docId != null) {
                                  context.pushNamed(
                                    'business_documents',
                                    pathParameters: {'business_id': businessId.toString()},
                                    extra: {'focus_document_id': docId},
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if ((payout['bank_account'] ?? const {}) is Map)
                        _BankAccountCard(bankAccount: Map<String, dynamic>.from(payout['bank_account'] as Map)),
                      if ((payout['settlement_note'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.note_outlined, size: 20, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      t.description,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(payout['settlement_note'].toString()),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'settled':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'canceled':
        return Icons.cancel;
      case 'approved':
        return Icons.verified;
      case 'processing':
        return Icons.sync;
      case 'requested':
        return Icons.pending;
      default:
        return Icons.help_outline;
    }
  }
}

class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String date;
  final Color color;
  final bool isLast;

  const _TimelineItem({
    required this.icon,
    required this.title,
    required this.date,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 30,
                color: color.withOpacity(0.3),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                date,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        elevation: onTap != null ? 2 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onTap != null)
                      Icon(Icons.arrow_forward_ios, size: 12, color: theme.colorScheme.primary),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BankAccountCard extends StatelessWidget {
  final Map<String, dynamic> bankAccount;

  const _BankAccountCard({required this.bankAccount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  t.bankAccounts,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _BankInfoRow(
              icon: Icons.person,
              label: 'صاحب حساب',
              value: bankAccount['owner_name']?.toString() ?? '-',
            ),
            const SizedBox(height: 8),
            _BankInfoRow(
              icon: Icons.account_balance,
              label: 'بانک',
              value: bankAccount['bank_name']?.toString() ?? '-',
            ),
            const SizedBox(height: 8),
            _BankInfoRow(
              icon: Icons.credit_card,
              label: 'شماره شبا',
              value: bankAccount['iban']?.toString() ?? '-',
              onCopy: bankAccount['iban'] != null ? () {
                Clipboard.setData(ClipboardData(text: bankAccount['iban'].toString()));
                SnackBarHelper.show(context, message: 'شماره شبا کپی شد');
              } : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BankInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _BankInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: onCopy,
            tooltip: 'کپی',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }
}
