import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/document_monetization_service.dart';
import '../../services/errors/api_error.dart';
import '../../utils/number_formatters.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../utils/snackbar_helper.dart';

class DocumentMonetizationBusinessPage extends StatefulWidget {
  final int businessId;
  const DocumentMonetizationBusinessPage({super.key, required this.businessId});

  @override
  State<DocumentMonetizationBusinessPage> createState() => _DocumentMonetizationBusinessPageState();
}

class _DocumentMonetizationBusinessPageState extends State<DocumentMonetizationBusinessPage> {
  late final DocumentMonetizationService _service;
  CalendarController? _calendarController;
  bool _loading = true;
  String? _error;
  final GlobalKey _chargesTableKey = GlobalKey();

  List<Map<String, dynamic>> _policies = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _plans = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _currentSubscription;
  int? _activatingPlanId;

  @override
  void initState() {
    super.initState();
    _service = DocumentMonetizationService(ApiClient());
    _initCalendarController();
    _load();
  }

  Future<void> _initCalendarController() async {
    final cc = await CalendarController.load();
    if (mounted) {
      setState(() => _calendarController = cc);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overviewFuture = _service.getBusinessOverview(widget.businessId);
      final plansFuture = _service.listBusinessPlans(widget.businessId);

      final overview = await overviewFuture;
      final plansResponse = await plansFuture;

      setState(() {
        _policies = (overview['policies'] as List<dynamic>? ?? const [])
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final planItems = plansResponse['plans'];
        if (planItems is List) {
          _plans = planItems.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          _plans = const <Map<String, dynamic>>[];
        }
        final current = plansResponse['current_subscription'];
        _currentSubscription = current is Map ? Map<String, dynamic>.from(current) : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _payCharge(int chargeId) async {
    final t = AppLocalizations.of(context);
    try {
      await _service.payBusinessCharge(widget.businessId, chargeId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.paymentSuccess);
      // فقط جدول charges را refresh کنیم، نه کل صفحه
      final state = _chargesTableKey.currentState;
      if (state != null) {
        try {
          // ignore: avoid_dynamic_calls
          (state as dynamic).refresh();
        } catch (_) {}
      }
    } catch (e) {
      _showErrorFromException(e, fallback: t.paymentError);
    }
  }

  Future<void> _finalizeVolume() async {
    final t = AppLocalizations.of(context);
    try {
      await _service.finalizeVolume(widget.businessId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.volumeFinalized);
      _load();
    } catch (e) {
      _showErrorFromException(e, fallback: t.volumeFinalizeError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final isJalali = _calendarController?.isJalali ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.documentMonetizationTitle),
        actions: [
          IconButton(
            tooltip: t.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ),
                    _buildSubscriptionCard(theme, t, isJalali),
                    const SizedBox(height: 16),
                    _buildPoliciesCard(theme, t),
                    const SizedBox(height: 16),
                    _buildChargesCard(theme, t, isJalali),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _finalizeVolume,
        icon: const Icon(Icons.calculate),
        label: Text(t.finalizeVolume),
      ),
    );
  }

  Widget _buildSubscriptionCard(ThemeData theme, AppLocalizations t, bool isJalali) {
    final current = _currentSubscription;
    final planWidgets = _plans.isEmpty
        ? [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t.noPackageAvailable),
            ),
          ]
        : _plans.map((plan) => _buildPlanTile(plan, theme, t)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.subscriptionPackages,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (current == null)
              Text(t.noActivePackage)
            else
              _buildCurrentSubscriptionInfo(current, theme, t, isJalali),
            const SizedBox(height: 16),
            ...planWidgets,
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSubscriptionInfo(Map<String, dynamic> current, ThemeData theme, AppLocalizations t, bool isJalali) {
    final endsAtRaw = current['ends_at'];
    DateTime? endsAt;
    if (endsAtRaw is String) {
      endsAt = DateTime.tryParse(endsAtRaw);
    }
    final planName = current['plan_name'] as String? ?? t.activePackage;
    final statusRaw = current['status'] as String? ?? '';
    final status = _translateStatus(statusRaw, t);
    final autoRenew = current['auto_renew'] == true;
    final currencyCode = current['currency_code'] as String?;
    final planPrice = current['plan_price'];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planName,
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 4),
          Text(
            '${t.status}: $status${autoRenew ? " | ${t.autoRenewActive}" : ""}',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
          ),
          if (planPrice != null)
            Text(
              '${t.periodAmount}: ${formatWithThousands(planPrice)} ${currencyCode ?? ""}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
          if (endsAt != null)
            Text(
              '${t.expiryDate}: ${HesabixDateUtils.formatForDisplay(endsAt, isJalali)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanTile(Map<String, dynamic> plan, ThemeData theme, AppLocalizations t) {
    final planId = plan['id'] as int?;
    final isActive = _currentSubscription != null &&
        _currentSubscription!['plan_id'] == planId &&
        (_currentSubscription!['status'] == 'active' || _currentSubscription!['status'] == 'pending');
    final priceValue = plan['price'];
    final currencyCode = plan['currency_code'] as String?;
    final duration = plan['period_months'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan['name'] as String? ?? '-', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(plan['description'] as String? ?? '', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('${t.duration}: ${duration ?? '-'} ${t.month} | ${t.amount}: ${formatWithThousands(priceValue)}${currencyCode != null && currencyCode.isNotEmpty ? ' $currencyCode' : ''}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (isActive)
              Chip(
                label: Text(t.active),
                backgroundColor: theme.colorScheme.secondaryContainer,
              )
            else
              FilledButton(
                onPressed: (_activatingPlanId == planId) ? null : () => _confirmAndActivatePlan(plan),
                child: _activatingPlanId == planId
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t.activate),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndActivatePlan(Map<String, dynamic> plan) async {
    final t = AppLocalizations.of(context);
    bool dialogAutoRenew = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(t.activatePackage(plan['name'] ?? '')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${t.packageDuration}: ${plan['period_months'] ?? '-'} ${t.month}'),
                  Text('${t.packagePrice}: ${formatWithThousands(plan['price'] ?? 0)} ${plan['currency_code'] ?? ""}'),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: dialogAutoRenew,
                    title: Text(t.autoRenewAtEnd),
                    onChanged: (value) {
                      setStateDialog(() => dialogAutoRenew = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(t.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(t.confirmAndActivate),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (!context.mounted) return;
    final ctx = context;
    final planId = plan['id'] as int?;
    if (planId == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.invalidPackageId)));
      return;
    }

    setState(() {
      _activatingPlanId = planId;
    });

    try {
      await _service.activateBusinessSubscription(
        widget.businessId,
        planId: planId,
        autoRenew: dialogAutoRenew,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.packageActivatedSuccess);
      await _load();
    } catch (e) {
      _showErrorFromException(e, fallback: t.packageActivationError);
    } finally {
      if (mounted) {
        setState(() {
          _activatingPlanId = null;
        });
      }
    }
  }

  String _translateStatus(String status, AppLocalizations t) {
    switch (status.toLowerCase()) {
      case 'active':
        return t.statusActive;
      case 'pending':
        return t.statusPending;
      case 'expired':
        return t.statusExpired;
      case 'cancelled':
        return t.statusCancelled;
      case 'awaiting_payment':
        return t.statusAwaitingPayment;
      case 'paid':
        return t.statusPaid;
      case 'invoiced':
        return t.statusInvoiced;
      default:
        return status;
    }
  }

  String _translateChargeType(String chargeType, AppLocalizations t) {
    switch (chargeType.toLowerCase()) {
      case 'per_document':
        return t.chargeTypePerDocument;
      case 'volume_cycle':
        return t.chargeTypeVolumeCycle;
      case 'subscription_fee':
        return t.chargeTypeSubscriptionFee;
      default:
        return chargeType;
    }
  }

  String _translatePolicyType(String policyType, AppLocalizations t) {
    switch (policyType.toLowerCase()) {
      case 'free':
        return t.policyTypeFree;
      case 'subscription':
        return t.policyTypeSubscription;
      case 'volume':
        return t.policyTypeVolume;
      case 'per_document':
        return t.policyTypePerDocument;
      case 'hybrid':
        return t.policyTypeHybrid;
      default:
        return policyType;
    }
  }

  void _showErrorFromException(Object error, {required String fallback}) {
    String message = fallback;
    if (error is ApiErrorDetails) {
      message = error.message ?? fallback;
      if (error.code != null && error.code!.isNotEmpty) {
        message = '$message (کد: ${error.code})';
      }
    } else {
      final errorStr = error.toString();
      if (errorStr.isNotEmpty && errorStr != 'Exception') {
        message = errorStr;
      }
    }
    if (!mounted) return;
    SnackBarHelper.show(context, message: message);
  }

  Widget _buildPoliciesCard(ThemeData theme, AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.activePolicies,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_policies.isEmpty)
              Text(t.noPolicyDefined)
            else
              Column(
                children: _policies
                    .map(
                      (policy) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          policy['is_active'] == true ? Icons.verified : Icons.pause_circle,
                          color: policy['is_active'] == true ? theme.colorScheme.primary : theme.colorScheme.outline,
                        ),
                        title: Text(policy['title'] as String? ?? '-'),
                        subtitle: Text('${t.type}: ${_translatePolicyType(policy['policy_type'] as String? ?? '', t)} | ${t.priority}: ${policy['priority']}'),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChargesCard(ThemeData theme, AppLocalizations t, bool isJalali) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.invoices,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 400,
              child: DataTableWidget<Map<String, dynamic>>(
                key: _chargesTableKey,
                config: DataTableConfig<Map<String, dynamic>>(
                  endpoint: '/api/v1/business/${widget.businessId}/document-monetization/charges/table',
                  showTableIcon: false,
                  showSearch: true,
                  showFilters: true,
                  showPagination: true,
                  defaultPageSize: 20,
                  pageSizeOptions: const [10, 20, 50, 100],
                  enableColumnSettings: true,
                  columns: [
                    TextColumn('description', t.description, searchable: true),
                    TextColumn('charge_type', t.type, 
                      formatter: (it) {
                        final chargeTypeRaw = it['charge_type'] as String? ?? '';
                        return _translateChargeType(chargeTypeRaw, t);
                      },
                      filterType: ColumnFilterType.multiSelect,
                      filterOptions: [
                        FilterOption(value: 'per_document', label: t.chargeTypePerDocument),
                        FilterOption(value: 'volume_cycle', label: t.chargeTypeVolumeCycle),
                        FilterOption(value: 'subscription_fee', label: t.chargeTypeSubscriptionFee),
                      ],
                    ),
                    TextColumn('status', t.status,
                      formatter: (it) {
                        final statusRaw = it['status'] as String? ?? '';
                        return _translateStatus(statusRaw, t);
                      },
                      filterType: ColumnFilterType.multiSelect,
                      filterOptions: [
                        FilterOption(value: 'awaiting_payment', label: t.statusAwaitingPayment),
                        FilterOption(value: 'paid', label: t.statusPaid),
                        FilterOption(value: 'invoiced', label: t.statusInvoiced),
                      ],
                    ),
                    NumberColumn('amount', t.amount,
                      formatter: (it) {
                        final amount = it['amount'];
                        final n = (amount is num) ? amount.toDouble() : double.tryParse('$amount') ?? 0;
                        return formatWithThousands(n);
                      },
                    ),
                    DateColumn('paid_at', t.paymentSuccess,
                      formatter: (it) {
                        final paidAtRaw = it['paid_at'];
                        if (paidAtRaw == null) return '';
                        DateTime? paidAt;
                        if (paidAtRaw is String) {
                          paidAt = DateTime.tryParse(paidAtRaw);
                        } else if (paidAtRaw is DateTime) {
                          paidAt = paidAtRaw;
                        }
                        if (paidAt == null) return '';
                        return HesabixDateUtils.formatForDisplay(paidAt, isJalali);
                      },
                    ),
                    DateColumn('created_at', t.createdAt,
                      formatter: (it) {
                        final createdAtRaw = it['created_at'];
                        if (createdAtRaw == null) return '';
                        DateTime? createdAt;
                        if (createdAtRaw is String) {
                          createdAt = DateTime.tryParse(createdAtRaw);
                        } else if (createdAtRaw is DateTime) {
                          createdAt = createdAtRaw;
                        }
                        if (createdAt == null) return '';
                        return HesabixDateUtils.formatForDisplay(createdAt, isJalali);
                      },
                    ),
                    ActionColumn('actions', t.actions, actions: [
                      DataTableAction(
                        icon: Icons.payment,
                        label: t.pay,
                        onTap: (charge) {
                          final status = charge['status'] as String? ?? '';
                          if (status == 'awaiting_payment') {
                            _payCharge(charge['id'] as int);
                          }
                        },
                      ),
                    ]),
                  ],
                  defaultSortBy: 'created_at',
                  defaultSortDesc: true,
                ),
                fromJson: (json) => Map<String, dynamic>.from(json),
                calendarController: _calendarController,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

