import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as Hd;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/business_user_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_form_helpers.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';

/// پنل عملیات تجاری پخش: سفارش پیش‌فروش، تحویل، بارگیری، پروموشن، پورسانت.
class DistributionCommercialPanel extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final CalendarController calendarController;
  final bool canManage;
  final bool canOperate;

  const DistributionCommercialPanel({
    super.key,
    required this.businessId,
    required this.service,
    required this.calendarController,
    required this.canManage,
    required this.canOperate,
  });

  @override
  State<DistributionCommercialPanel> createState() => _DistributionCommercialPanelState();
}

class _DistributionCommercialPanelState extends State<DistributionCommercialPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = false;
  List<dynamic> _orders = [];
  List<dynamic> _trips = [];
  List<dynamic> _plans = [];
  List<dynamic> _promos = [];
  List<dynamic> _commRuns = [];
  List<dynamic> _commRules = [];
  List<dynamic> _assets = [];
  List<dynamic> _shelfAudits = [];
  Map<String, dynamic>? _kpi;
  DateTime _day = DateTime.now();

  bool get _jalali => widget.calendarController.isJalali;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _load();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      switch (_tabs.index) {
        case 0:
          _orders = await widget.service.listOrders(businessId: widget.businessId);
          break;
        case 1:
          _trips = await widget.service.listDeliveryTrips(
            businessId: widget.businessId,
            tripDate: _iso(_day),
          );
          break;
        case 2:
          _plans = await widget.service.listLoadPlans(
            businessId: widget.businessId,
            planDate: _iso(_day),
          );
          break;
        case 3:
          if (widget.canManage) {
            _promos = await widget.service.listPromotions(businessId: widget.businessId, all: true);
          }
          break;
        case 4:
          final now = DateTime.now();
          final from = DateTime(now.year, now.month, 1);
          _kpi = await widget.service.getCommercialKpi(
            businessId: widget.businessId,
            fromDate: _iso(from),
            toDate: _iso(now),
          );
          if (widget.canManage) {
            _commRuns = await widget.service.listCommissionRuns(businessId: widget.businessId);
            _commRules = await widget.service.listCommissionRules(businessId: widget.businessId);
          }
          break;
        case 5:
          _assets = await widget.service.listCustomerAssets(businessId: widget.businessId);
          _shelfAudits = await widget.service.listShelfAudits(businessId: widget.businessId);
          break;
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmOrder(int id) async {
    try {
      await widget.service.confirmOrder(businessId: widget.businessId, orderId: id);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).distributionOrderConfirmed);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _buildLoadPlan() async {
    final t = AppLocalizations.of(context);
    List<dynamic> vans = const [];
    try {
      vans = await widget.service.listVans(businessId: widget.businessId);
    } catch (_) {}
    if (!mounted) return;
    int? vanId;
    int? whId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionBuildLoadPlan),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int?>(
                  value: vanId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.distributionSelectVan,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text('—')),
                    ...vans.map((raw) {
                      final m = Map<String, dynamic>.from(raw as Map);
                      return DropdownMenuItem<int?>(
                        value: int.tryParse('${m['id']}'),
                        child: Text('${m['name'] ?? m['code'] ?? m['id']}'),
                      );
                    }),
                  ],
                  onChanged: (v) => setD(() => vanId = v),
                ),
                const SizedBox(height: 8),
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: whId,
                    label: t.distributionSelectWarehouse,
                    selectDefaultWhenUnset: true,
                    onChanged: (id) => setD(() => whId = id),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.createLoadPlan(
        businessId: widget.businessId,
        payload: {
          'plan_date': _iso(_day),
          if (vanId != null) 'van_id': vanId,
          if (whId != null) 'warehouse_id': whId,
        },
      );
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: t.distributionLoadPlanCreated);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _confirmPlan(int id) async {
    try {
      await widget.service.confirmLoadPlan(businessId: widget.businessId, planId: id);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).distributionLoadPlanConfirmed);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _createTripFromConfirmedOrders() async {
    final confirmed = _orders
        .where((o) => o is Map && (o['status'] == 'confirmed' || o['status'] == 'loaded' || o['status'] == 'picking'))
        .map((o) => int.tryParse('${(o as Map)['id']}') ?? 0)
        .where((id) => id > 0)
        .toList();
    if (confirmed.isEmpty) {
      SnackBarHelper.showError(context, message: AppLocalizations.of(context).distributionNoOrdersForTrip);
      return;
    }
    try {
      await widget.service.createDeliveryTrip(
        businessId: widget.businessId,
        payload: {'trip_date': _iso(_day), 'order_ids': confirmed},
      );
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).distributionTripCreated);
      }
      _tabs.animateTo(1);
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _completeStopUi(Map stop) async {
    final t = AppLocalizations.of(context);
    final nameCtl = TextEditingController();
    final noteCtl = TextEditingController();
    var ok = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.distributionDeliveryPodTitle, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                stop['person_name']?.toString() ?? '#${stop['person_id']}',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(
                  labelText: t.distributionPodSignerName,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: t.distributionPodNote,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  if (nameCtl.text.trim().length < 2) {
                    SnackBarHelper.showError(ctx, message: t.distributionPodSignerRequired);
                    return;
                  }
                  ok = true;
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.check_circle_outline),
                label: Text(t.distributionMarkDelivered),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  ok = false;
                  Navigator.pop(ctx);
                  final sid = int.tryParse('${stop['id']}');
                  if (sid == null) return;
                  try {
                    await widget.service.completeDeliveryStop(
                      businessId: widget.businessId,
                      stopId: sid,
                      payload: {
                        'status': 'failed',
                        'failure_reason': 'customer_unavailable',
                      },
                    );
                    await _load();
                  } catch (e) {
                    if (mounted) {
                      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                    }
                  }
                },
                child: Text(t.distributionMarkFailed),
              ),
            ],
          ),
        );
      },
    );
    if (!ok) return;
    final sid = int.tryParse('${stop['id']}');
    if (sid == null) return;
    try {
      await widget.service.completeDeliveryStop(
        businessId: widget.businessId,
        stopId: sid,
        payload: {
          'status': 'delivered',
          'pod_confirmed': true,
          'pod_signer_name': nameCtl.text.trim(),
          if (noteCtl.text.trim().isNotEmpty) 'pod_note': noteCtl.text.trim(),
        },
      );
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: t.distributionDeliveredOk);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _addPromoDialog({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final nameCtl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final cfg = existing?['config'] is Map ? Map<String, dynamic>.from(existing!['config'] as Map) : <String, dynamic>{};
    final pctCtl = TextEditingController(text: '${cfg['percent'] ?? 5}');
    final editing = existing != null;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.distributionPromoCreate),
        content: distributionFormColumn(
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: InputDecoration(labelText: t.distributionPromoName, border: const OutlineInputBorder()),
            ),
            TextField(
              controller: pctCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t.distributionPromoPercent, border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(
            onPressed: () async {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await widget.service.upsertPromotion(
                  businessId: widget.businessId,
                  promoId: editing ? int.tryParse('${existing['id']}') : null,
                  payload: {
                    'code': editing
                        ? '${existing['code']}'
                        : nextDistributionCode('PR', _promos),
                    'name': name,
                    'mechanic': 'percent_off',
                    'config': {'percent': double.tryParse(pctCtl.text.trim()) ?? 5},
                    'valid_from': _iso(DateTime.now()),
                    'is_active': true,
                  },
                );
                await _load();
              } catch (e) {
                if (mounted) {
                  SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                }
              }
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        Material(
          color: cs.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: [
              Tab(text: t.distributionTabOrders),
              Tab(text: t.distributionTabDelivery),
              Tab(text: t.distributionTabLoadPlan),
              Tab(text: t.distributionTabPromos),
              Tab(text: t.distributionTabKpiCommission),
              Tab(text: t.distributionTabShelfAssets),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ordersTab(t, theme, cs),
              _deliveryTab(t, theme, cs),
              _loadTab(t, theme, cs),
              _promoTab(t, theme, cs),
              _kpiTab(t, theme, cs),
              _shelfAssetsTab(t, theme, cs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ordersTab(AppLocalizations t, ThemeData theme, ColorScheme cs) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.distributionPresellOrdersHint, style: theme.textTheme.bodySmall),
              ),
              if (widget.canOperate)
                FilledButton.tonalIcon(
                  onPressed: _createTripFromConfirmedOrders,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: Text(t.distributionCreateTripFromOrders),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_orders.isEmpty)
            _emptyState(cs, Icons.receipt_long_outlined, t.distributionNoOrders)
          else
            ..._orders.map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              final status = '${m['status']}';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    m['person_name']?.toString() ?? '#${m['person_id']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${t.distributionOrderStatus}: $status · ${t.distributionNetTotal}: ${m['net_total'] ?? 0}'
                    '${m['document_id'] != null ? ' · #${m['document_id']}' : ''}',
                  ),
                  trailing: status == 'draft' && widget.canOperate
                      ? FilledButton(
                          onPressed: () => _confirmOrder(int.parse('${m['id']}')),
                          child: Text(t.distributionConfirmOrder),
                        )
                      : Chip(
                          label: Text(status),
                          visualDensity: VisualDensity.compact,
                        ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _deliveryTab(AppLocalizations t, ThemeData theme, ColorScheme cs) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showAdaptiveDatePicker(
                      context: context,
                      calendarController: widget.calendarController,
                      initialDate: _day,
                    );
                    if (picked != null) {
                      setState(() => _day = picked);
                      await _load();
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: t.distributionSelectDate,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(Hd.HesabixDateUtils.formatForDisplay(_day, _jalali)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 12),
          if (_trips.isEmpty)
            _emptyState(cs, Icons.route_outlined, t.distributionNoTrips)
          else
            ..._trips.map((raw) {
              final trip = Map<String, dynamic>.from(raw as Map);
              final stops = (trip['stops'] is List) ? trip['stops'] as List : const [];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(
                    '${t.distributionTrip} #${trip['id']} · ${trip['status']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(trip['driver_name']?.toString() ?? ''),
                  trailing: trip['status'] == 'draft' && widget.canOperate
                      ? TextButton(
                          onPressed: () async {
                            try {
                              await widget.service.startDeliveryTrip(
                                businessId: widget.businessId,
                                tripId: int.parse('${trip['id']}'),
                              );
                              await _load();
                            } catch (e) {
                              if (mounted) {
                                SnackBarHelper.showError(
                                  context,
                                  message: ErrorExtractor.forContext(e, context),
                                );
                              }
                            }
                          },
                          child: Text(t.distributionStartTrip),
                        )
                      : null,
                  children: stops.map((sraw) {
                    final s = Map<String, dynamic>.from(sraw as Map);
                    final pending = s['status'] == 'pending';
                    return ListTile(
                      leading: Icon(
                        pending ? Icons.radio_button_unchecked : Icons.check_circle,
                        color: pending ? cs.outline : cs.primary,
                      ),
                      title: Text(s['person_name']?.toString() ?? '#${s['person_id']}'),
                      subtitle: Text('${s['status']}'),
                      trailing: pending && widget.canOperate
                          ? FilledButton.tonal(
                              onPressed: () => _completeStopUi(s),
                              child: Text(t.distributionDeliver),
                            )
                          : null,
                    );
                  }).toList(),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _loadTab(AppLocalizations t, ThemeData theme, ColorScheme cs) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.canManage)
            FilledButton.icon(
              onPressed: _buildLoadPlan,
              icon: const Icon(Icons.playlist_add_check_outlined),
              label: Text(t.distributionBuildLoadPlan),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          const SizedBox(height: 8),
          Text(t.distributionLoadPlanHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          if (_plans.isEmpty)
            _emptyState(cs, Icons.inventory_2_outlined, t.distributionNoLoadPlans)
          else
            ..._plans.map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              final lines = (m['lines'] is List) ? m['lines'] as List : const [];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: ExpansionTile(
                  title: Text('${t.distributionLoadPlan} #${m['id']} · ${m['status']}'),
                  subtitle: Text('${lines.length} ${t.distributionSkuLines}'),
                  trailing: m['status'] == 'draft' && widget.canManage
                      ? FilledButton(
                          onPressed: () => _confirmPlan(int.parse('${m['id']}')),
                          child: Text(t.distributionConfirmLoad),
                        )
                      : null,
                  children: lines.map((ln) {
                    final l = Map<String, dynamic>.from(ln as Map);
                    return ListTile(
                      dense: true,
                      title: Text(l['product_name']?.toString() ?? '#${l['product_id']}'),
                      trailing: Text('${l['quantity']}'),
                    );
                  }).toList(),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _promoTab(AppLocalizations t, ThemeData theme, ColorScheme cs) {
    if (!widget.canManage) {
      return Center(child: Text(t.distributionManageOnly));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _addPromoDialog,
            icon: const Icon(Icons.local_offer_outlined),
            label: Text(t.distributionPromoCreate),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
          if (_promos.isEmpty)
            _emptyState(cs, Icons.discount_outlined, t.distributionNoPromos)
          else
            ..._promos.map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              final cfg = m['config'] is Map ? m['config'] as Map : {};
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: ListTile(
                  leading: Icon(Icons.sell_outlined, color: cs.primary),
                  title: Text('${m['name']}'),
                  subtitle: Text('${m['mechanic']} · ${cfg['percent'] ?? cfg['amount'] ?? ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _addPromoDialog(existing: m),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirmDistributionDelete(
                            context: context,
                            title: t.distributionPromoCreate,
                            message: t.distributionDeletePromoConfirm,
                          );
                          if (!ok) return;
                          try {
                            await widget.service.deletePromotion(
                              businessId: widget.businessId,
                              promoId: int.parse('${m['id']}'),
                            );
                            await _load();
                          } catch (e) {
                            if (mounted) {
                              SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _kpiTab(AppLocalizations t, ThemeData theme, ColorScheme cs) {
    final kpi = _kpi?['kpi'] is Map ? Map<String, dynamic>.from(_kpi!['kpi'] as Map) : <String, dynamic>{};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.distributionKpiPackTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _kpiChip(cs, t.distributionKpiCoverage, '${kpi['coverage_percent'] ?? '—'}%'),
              _kpiChip(cs, t.distributionKpiStrike, '${kpi['strike_rate_percent'] ?? '—'}%'),
              _kpiChip(cs, t.distributionKpiDropSize, '${kpi['drop_size'] ?? '—'}'),
              _kpiChip(cs, t.distributionKpiPresell, '${kpi['presell_orders'] ?? 0}'),
              _kpiChip(cs, t.distributionKpiSales, '${kpi['sales_linked_net_total'] ?? 0}'),
              _kpiChip(cs, t.distributionKpiShelf, '${kpi['shelf_audit_avg_score'] ?? '—'}'),
            ],
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.distributionCommissionRulesTitle,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _addCommissionRuleDialog,
                  icon: const Icon(Icons.rule),
                  label: Text(t.distributionCommissionRuleCreate),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_commRules.isEmpty)
              Text(t.distributionNoCommissionRules, style: theme.textTheme.bodySmall)
            else
              ..._commRules.map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                final cfg = m['config'] is Map ? m['config'] as Map : {};
                return ListTile(
                  dense: true,
                  title: Text('${m['name']}'),
                  subtitle: Text('${m['rule_type']} · ${cfg['percent'] ?? ''}%'),
                  trailing: m['is_active'] == true
                      ? Icon(Icons.check_circle, color: cs.primary, size: 18)
                      : Icon(Icons.pause_circle_outline, color: cs.outline, size: 18),
                );
              }),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.distributionCommissionTitle,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _computeCommissionDialog,
                  icon: const Icon(Icons.calculate_outlined),
                  label: Text(t.distributionCommissionCompute),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_commRuns.isEmpty)
              Text(t.distributionNoCommissionRuns, style: theme.textTheme.bodySmall)
            else
              ..._commRuns.take(10).map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                return ListTile(
                  title: Text(m['user_name']?.toString() ?? '#${m['user_id']}'),
                  subtitle: Text('${m['period_start']} → ${m['period_end']}'),
                  trailing: Text(
                    '${m['commission_amount']}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  Future<void> _addCommissionRuleDialog() async {
    final t = AppLocalizations.of(context);
    final nameCtl = TextEditingController();
    final pctCtl = TextEditingController(text: '1');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.distributionCommissionRuleCreate),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(labelText: t.distributionPromoName, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pctCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t.distributionCommissionPercent, border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.service.upsertCommissionRule(
                  businessId: widget.businessId,
                  payload: {
                    'name': nameCtl.text.trim().isEmpty ? 'default' : nameCtl.text.trim(),
                    'rule_type': 'percent_of_sales',
                    'config': {'percent': double.tryParse(pctCtl.text.trim()) ?? 1},
                    'is_active': true,
                  },
                );
                await _load();
              } catch (e) {
                if (mounted) {
                  SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                }
              }
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
  }

  Future<void> _computeCommissionDialog() async {
    final t = AppLocalizations.of(context);
    List<BusinessUser> users = const [];
    try {
      users = (await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId)).users;
    } catch (_) {}
    if (!mounted) return;
    int? userId;
    int? ruleId = _commRules.isNotEmpty ? int.tryParse('${(_commRules.first as Map)['id']}') : null;
    final now = DateTime.now();
    DateTime from = DateTime(now.year, now.month, 1);
    DateTime to = now;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionCommissionCompute),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: userId,
                  decoration: InputDecoration(
                    labelText: t.distributionSelectVisitor,
                    border: const OutlineInputBorder(),
                  ),
                  items: users
                      .map(
                        (u) => DropdownMenuItem(
                          value: u.userId,
                          child: Text(u.userName.isNotEmpty ? u.userName : '${u.userId}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => userId = v),
                ),
                if (_commRules.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: ruleId,
                    decoration: InputDecoration(
                      labelText: t.distributionCommissionRulesTitle,
                      border: const OutlineInputBorder(),
                    ),
                    items: _commRules.map((raw) {
                      final m = Map<String, dynamic>.from(raw as Map);
                      return DropdownMenuItem(
                        value: int.tryParse('${m['id']}'),
                        child: Text('${m['name']}'),
                      );
                    }).toList(),
                    onChanged: (v) => setD(() => ruleId = v),
                  ),
                ],
                ListTile(
                  title: Text('${Hd.HesabixDateUtils.formatForDisplay(from, _jalali)} → ${Hd.HesabixDateUtils.formatForDisplay(to, _jalali)}'),
                  subtitle: Text(t.distributionSelectDate),
                  onTap: () async {
                    final a = await showAdaptiveDatePicker(
                      context: context,
                      calendarController: widget.calendarController,
                      initialDate: from,
                    );
                    if (a == null) return;
                    final b = await showAdaptiveDatePicker(
                      context: context,
                      calendarController: widget.calendarController,
                      initialDate: to,
                    );
                    if (b == null) return;
                    setD(() {
                      from = a;
                      to = b;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    if (ok != true || userId == null) return;
    try {
      await widget.service.computeCommissionRun(
        businessId: widget.businessId,
        payload: {
          'user_id': userId,
          'period_start': _iso(from),
          'period_end': _iso(to),
          if (ruleId != null) 'rule_id': ruleId,
        },
      );
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: t.distributionCommissionComputed);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Widget _shelfAssetsTab(AppLocalizations t, ThemeData theme, ColorScheme cs) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.canOperate)
            FilledButton.tonalIcon(
              onPressed: _addAssetDialog,
              icon: const Icon(Icons.add_box_outlined),
              label: Text(t.distributionAssetCreate),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          const SizedBox(height: 12),
          Text(t.distributionAssetsTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_assets.isEmpty)
            _emptyState(cs, Icons.kitchen_outlined, t.distributionNoAssets)
          else
            ..._assets.map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: ListTile(
                  title: Text(m['asset_type']?.toString() ?? t.distributionAssetType),
                  subtitle: Text(
                    '${m['person_name'] ?? m['person_id']}'
                    '${m['status'] != null ? ' · ${m['status']}' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _addAssetDialog(existing: m),
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
          Text(t.distributionShelfAuditTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_shelfAudits.isEmpty)
            Text(t.distributionNoShelfAudits, style: theme.textTheme.bodySmall)
          else
            ..._shelfAudits.take(30).map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              return ListTile(
                dense: true,
                title: Text(m['person_name']?.toString() ?? '#${m['person_id']}'),
                subtitle: Text('${m['created_at'] ?? ''}'),
                trailing: Text(
                  '${m['score'] ?? '—'}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _addAssetDialog({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final types = <String, String>{
      'cooler': t.distributionAssetTypeCooler,
      'freezer': t.distributionAssetTypeFreezer,
      'shelf': t.distributionAssetTypeShelf,
      'other': t.distributionAssetTypeOther,
    };
    var type = existing?['asset_type']?.toString() ?? 'cooler';
    if (!types.containsKey(type)) type = 'other';
    Person? person;
    final pid = int.tryParse('${existing?['person_id'] ?? ''}');
    if (pid != null) {
      person = distributionPersonStub(
        businessId: widget.businessId,
        id: pid,
        name: existing?['person_name']?.toString() ?? '$pid',
      );
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionAssetCreate),
          content: distributionFormColumn(
            children: [
              PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: person,
                label: t.distributionSelectPerson,
                hintText: t.distributionSelectPerson,
                isRequired: true,
                onChanged: (p) => setD(() => person = p),
              ),
              DropdownButtonFormField<String>(
                value: type,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionAssetType,
                  border: const OutlineInputBorder(),
                ),
                items: types.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setD(() => type = v ?? 'cooler'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                if (person == null) return;
                Navigator.pop(ctx);
                try {
                  await widget.service.upsertCustomerAsset(
                    businessId: widget.businessId,
                    assetId: existing != null ? int.tryParse('${existing['id']}') : null,
                    payload: {
                      'person_id': person!.id,
                      'asset_type': type,
                      'asset_code': existing != null
                          ? '${existing['asset_code'] ?? nextDistributionCode('AST', _assets)}'
                          : nextDistributionCode('AST', _assets),
                      'status': 'active',
                    },
                  );
                  await _load();
                } catch (e) {
                  if (mounted) {
                    SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                  }
                }
              },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiChip(ColorScheme cs, String label, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _emptyState(ColorScheme cs, IconData icon, String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
