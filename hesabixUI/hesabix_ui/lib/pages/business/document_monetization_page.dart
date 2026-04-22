import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/document_monetization_service.dart';
import '../../services/wallet_service.dart';
import '../../services/errors/api_error.dart';
import '../../utils/number_formatters.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';

class DocumentMonetizationBusinessPage extends StatefulWidget {
  final int businessId;
  const DocumentMonetizationBusinessPage({super.key, required this.businessId});

  @override
  State<DocumentMonetizationBusinessPage> createState() => _DocumentMonetizationBusinessPageState();
}

class _DocumentMonetizationBusinessPageState extends State<DocumentMonetizationBusinessPage> {
  late final DocumentMonetizationService _service;
  late final WalletService _walletService;
  CalendarController? _calendarController;
  bool _loading = true;
  String? _error;
  final GlobalKey _chargesTableKey = GlobalKey();

  List<Map<String, dynamic>> _policies = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _plans = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _currentSubscription;
  Map<String, dynamic>? _walletOverview;
  int? _activatingPlanId;
  bool _finalizingVolume = false;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _service = DocumentMonetizationService(api);
    _walletService = WalletService(api);
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
      final walletFuture = _walletService.getOverview(businessId: widget.businessId);

      final overview = await overviewFuture;
      final plansResponse = await plansFuture;
      final walletOverview = await walletFuture;

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
        _walletOverview = walletOverview;
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
      // Refresh wallet و جدول charges
      await _refreshAfterPayment();
    } catch (e) {
      if (!mounted) return;
      // بررسی خطای INSUFFICIENT_FUNDS
      String errorMessage = '';
      bool isInsufficientFunds = false;
      if (e is ApiErrorDetails) {
        errorMessage = e.message ?? t.paymentError;
        if (e.code == 'INSUFFICIENT_FUNDS' || errorMessage.contains('موجودی کافی') || errorMessage.contains('insufficient')) {
          isInsufficientFunds = true;
        }
      } else {
        final errorStr = e.toString();
        if (errorStr.contains('INSUFFICIENT_FUNDS') || errorStr.contains('موجودی کافی') || errorStr.contains('insufficient')) {
          isInsufficientFunds = true;
          errorMessage = 'موجودی کیف‌پول کافی نیست';
        } else {
          errorMessage = errorStr.isNotEmpty && errorStr != 'Exception' ? errorStr : t.paymentError;
        }
      }
      
      if (isInsufficientFunds) {
        final shouldCharge = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('موجودی کافی نیست'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage),
                const SizedBox(height: 16),
                const Text('آیا می‌خواهید کیف‌پول را شارژ کنید؟'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('شارژ کیف‌پول'),
              ),
            ],
          ),
        );
        if (shouldCharge == true && mounted) {
          context.go('/business/${widget.businessId}/wallet');
        }
      } else {
        SnackBarHelper.show(context, message: errorMessage);
      }
    }
  }

  Future<void> _refreshAfterPayment() async {
    // Refresh wallet
    try {
      final walletOverview = await _walletService.getOverview(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _walletOverview = walletOverview;
        });
      }
    } catch (_) {}
    
    // Refresh جدول charges
    final state = _chargesTableKey.currentState;
    if (state != null) {
      try {
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
      } catch (_) {}
    }
    
    // Refresh subscription status
    try {
      final plansResponse = await _service.listBusinessPlans(widget.businessId);
      if (mounted) {
        setState(() {
          final current = plansResponse['current_subscription'];
          _currentSubscription = current is Map ? Map<String, dynamic>.from(current) : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _finalizeVolume() async {
    final t = AppLocalizations.of(context);
    if (_finalizingVolume) return;
    
    setState(() {
      _finalizingVolume = true;
    });
    
    try {
      final result = await _service.finalizeVolume(widget.businessId);
      if (!mounted) return;
      
      final finalizedCount = result['finalized'] as int? ?? 0;
      
      String message = t.volumeFinalized;
      if (finalizedCount > 0) {
        message = 'نتیجه: $finalizedCount دوره نهایی شد';
      }
      
      SnackBarHelper.show(context, message: message);
      await _load();
    } catch (e) {
      _showErrorFromException(e, fallback: t.volumeFinalizeError);
    } finally {
      if (mounted) {
        setState(() {
          _finalizingVolume = false;
        });
      }
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
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          IconButton(
            tooltip: t.viewWallet,
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () {
              context.go('/business/${widget.businessId}/wallet');
            },
          ),
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
                    _buildWalletBalanceCard(theme, t),
                    const SizedBox(height: 16),
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
        onPressed: _finalizingVolume ? null : _finalizeVolume,
        icon: _finalizingVolume
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.calculate),
        label: Text(t.finalizeVolume),
      ),
    );
  }

  Widget _buildWalletBalanceCard(ThemeData theme, AppLocalizations t) {
    final balance = _walletOverview?['available_balance'] as num?;
    final currencyCode = _walletOverview?['currency_code'] as String? ?? '';
    final currencySymbol = _walletOverview?['currency_symbol'] as String? ?? currencyCode;
    
    if (balance == null) return const SizedBox.shrink();
    
    final balanceValue = balance.toDouble();
    final isLow = balanceValue < 100000; // کمتر از 100K
    
    return Card(
      color: isLow ? theme.colorScheme.errorContainer.withOpacity(0.3) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.account_balance_wallet,
              color: isLow ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.wallet}: ${formatWithThousands(balanceValue)} $currencySymbol',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isLow ? theme.colorScheme.error : null,
                    ),
                  ),
                  if (isLow)
                    Text(
                      'موجودی کم است. لطفاً کیف‌پول را شارژ کنید.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                context.go('/business/${widget.businessId}/wallet');
              },
              icon: const Icon(Icons.arrow_forward),
              label: Text(t.viewWallet),
            ),
          ],
        ),
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
    final currencySymbol = current['currency_symbol'] as String? ?? currencyCode ?? '';
    final planPrice = current['plan_price'];

    // محاسبه روزهای باقی‌مانده تا انقضا
    int? daysUntilExpiry;
    bool isExpiringSoon = false;
    bool isExpired = false;
    if (endsAt != null) {
      final now = DateTime.now();
      daysUntilExpiry = endsAt.difference(now).inDays;
      isExpiringSoon = daysUntilExpiry <= 7 && daysUntilExpiry > 0;
      isExpired = daysUntilExpiry < 0;
    }

    return Container(
      decoration: BoxDecoration(
        color: isExpired 
            ? theme.colorScheme.errorContainer.withOpacity(0.5)
            : isExpiringSoon
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: isExpiringSoon || isExpired
            ? Border.all(
                color: isExpired ? theme.colorScheme.error : theme.colorScheme.tertiary,
                width: 2,
              )
            : null,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  planName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isExpired 
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              if (isExpiringSoon || isExpired)
                Chip(
                  label: Text(isExpired ? 'منقضی شده' : 'به زودی منقضی می‌شود'),
                  backgroundColor: isExpired 
                      ? theme.colorScheme.error
                      : theme.colorScheme.tertiary,
                  labelStyle: TextStyle(
                    color: isExpired
                        ? theme.colorScheme.onError
                        : theme.colorScheme.onTertiary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${t.status}: $status${autoRenew ? " | ${t.autoRenewActive}" : ""}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isExpired 
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
          if (planPrice != null)
            Text(
              '${t.periodAmount}: ${formatWithThousands(planPrice)} $currencySymbol',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isExpired 
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
          if (endsAt != null) ...[
            Text(
              '${t.expiryDate}: ${HesabixDateUtils.formatForDisplay(endsAt, isJalali)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isExpired 
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
            if (daysUntilExpiry != null && daysUntilExpiry > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$daysUntilExpiry روز تا انقضا',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isExpiringSoon 
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onPrimaryContainer,
                    fontWeight: isExpiringSoon ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
          ],
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
      SnackBarHelper.show(ctx, message: t.invalidPackageId);
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
                      (policy) {
                        final policyType = policy['policy_type'] as String? ?? '';
                        final config = policy['config'] as Map<String, dynamic>? ?? {};
                        final title = policy['title'] as String? ?? '-';
                        final priority = policy['priority'] as int? ?? 0;
                        
                        String configText = '';
                        if (policyType == 'per_document') {
                          final fee = config['fee_amount'] as num? ?? 0;
                          final autoCharge = config['auto_charge_wallet'] == true;
                          configText = 'هزینه هر سند: ${formatWithThousands(fee.toDouble())} | کسر خودکار: ${autoCharge ? "بله" : "خیر"}';
                        } else if (policyType == 'volume') {
                          final cycle = config['cycle'] as String? ?? '';
                          final tierAmount = config['tier_amount'] as num? ?? 0;
                          final pricePerTier = config['price_per_tier'] as num? ?? 0;
                          final freeThreshold = config['free_threshold_amount'] as num? ?? 0;
                          final cycleText = cycle == 'monthly' ? 'ماهانه' : cycle == 'weekly' ? 'هفتگی' : cycle == 'yearly' ? 'سالانه' : cycle;
                          configText = 'دوره: $cycleText | هر ${formatWithThousands(tierAmount.toDouble())}: ${formatWithThousands(pricePerTier.toDouble())}';
                          if (freeThreshold > 0) {
                            configText += ' | رایگان تا: ${formatWithThousands(freeThreshold.toDouble())}';
                          }
                        } else if (policyType == 'subscription') {
                          configText = 'پکیج نامحدود';
                        } else if (policyType == 'free') {
                          configText = 'رایگان';
                        }
                        
                        return ExpansionTile(
                          leading: Icon(
                            policy['is_active'] == true ? Icons.verified : Icons.pause_circle,
                            color: policy['is_active'] == true ? theme.colorScheme.primary : theme.colorScheme.outline,
                          ),
                          title: Text(title),
                          subtitle: Text('${t.type}: ${_translatePolicyType(policyType, t)} | ${t.priority}: $priority'),
                          children: [
                            if (configText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        configText,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
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
            DataTableWidget<Map<String, dynamic>>(
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
                        final status = _translateStatus(statusRaw, t);
                        // اضافه کردن علامت برای شناسایی آسان‌تر
                        if (statusRaw == 'paid') {
                          return '✓ $status';
                        } else if (statusRaw == 'awaiting_payment') {
                          return '⚠ $status';
                        } else if (statusRaw == 'invoiced') {
                          return '📄 $status';
                        }
                        return status;
                      },
                      filterType: ColumnFilterType.multiSelect,
                      filterOptions: [
                        FilterOption(
                          value: 'awaiting_payment',
                          label: t.statusAwaitingPayment,
                          color: Colors.orange,
                        ),
                        FilterOption(
                          value: 'paid',
                          label: t.statusPaid,
                          color: Colors.green,
                        ),
                        FilterOption(
                          value: 'invoiced',
                          label: t.statusInvoiced,
                          color: Colors.blue,
                        ),
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
                    TextColumn('document_id', 'سند حسابداری',
                      formatter: (it) {
                        final docId = it['document_id'];
                        if (docId == null) return '-';
                        return '#$docId';
                      },
                      searchable: false,
                    ),
                    TextColumn('period_key', 'دوره/متعلق',
                      formatter: (it) {
                        final chargeType = it['charge_type'] as String? ?? '';
                        final periodKey = it['period_key'] as String?;
                        final metrics = it['metrics'] as Map<String, dynamic>? ?? {};
                        
                        if (chargeType == 'volume_cycle' && periodKey != null) {
                          final periodText = periodKey.replaceAll('monthly-', '').replaceAll('weekly-', '').replaceAll('yearly-', '');
                          final docsCount = metrics['documents_count'] as int?;
                          if (docsCount != null) {
                            return '$periodText ($docsCount سند)';
                          }
                          return periodText;
                        } else if (chargeType == 'per_document') {
                          final docCode = metrics['document_code'] as String?;
                          if (docCode != null) {
                            return docCode;
                          }
                        }
                        return periodKey ?? '-';
                      },
                      searchable: false,
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
                        icon: Icons.receipt_long,
                        label: 'مشاهده سند حسابداری',
                        onTap: (charge) {
                          final docId = charge['document_id'] as int?;
                          if (docId != null) {
                            context.go('/business/${widget.businessId}/documents?document_id=$docId');
                          }
                        },
                        enabled: (charge) => charge['document_id'] != null,
                      ),
                      DataTableAction(
                        icon: Icons.payment,
                        label: t.pay,
                        onTap: (charge) {
                          final status = charge['status'] as String? ?? '';
                          if (status == 'awaiting_payment') {
                            _payCharge(charge['id'] as int);
                          }
                        },
                        enabled: (charge) => charge['status'] == 'awaiting_payment',
                      ),
                    ]),
                  ],
                  defaultSortBy: 'created_at',
                  defaultSortDesc: true,
                
        expandBodyHeightToFitRows: true,),
                fromJson: (json) => Map<String, dynamic>.from(json),
                calendarController: _calendarController,
              ),
          ],
        ),
      ),
    );
  }
}

