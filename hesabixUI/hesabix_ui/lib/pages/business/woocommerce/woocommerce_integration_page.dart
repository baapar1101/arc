import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/woocommerce_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../pages/business/woocommerce/woocommerce_l10n_format.dart';
import '../../../widgets/data_table/data_table_config.dart';
import '../../../widgets/data_table/data_table_widget.dart';

class WoocommerceIntegrationPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const WoocommerceIntegrationPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<WoocommerceIntegrationPage> createState() => _WoocommerceIntegrationPageState();
}

class _WoocommerceIntegrationPageState extends State<WoocommerceIntegrationPage>
    with SingleTickerProviderStateMixin {
  final WoocommerceIntegrationService _svc = WoocommerceIntegrationService();
  late TabController _tabs;

  final _searchCtl = TextEditingController();

  final _ordStatusCtl = TextEditingController();
  final _ordSearchCtl = TextEditingController();
  final _ordCustomerCtl = TextEditingController();
  final _ordAfterCtl = TextEditingController();
  final _ordBeforeCtl = TextEditingController();
  String _ordOrderby = 'date';
  String _ordOrder = 'DESC';

  bool _loadingList = false;

  int _listPage = 1;
  int _perPage = 20;
  List<Map<String, dynamic>> _rows = const [];
  int _total = 0;
  int _hubTableEpoch = 0;

  bool _controlLoading = false;
  Map<String, dynamic> _syncStats = const {};
  Map<String, dynamic> _settingsSummary = const {};
  Map<String, dynamic> _connection = const {};
  Map<String, dynamic> _pluginInfo = const {};
  Map<String, dynamic> _queueSnapshot = const {};
  final _bulkIdsCtl = TextEditingController();

  List<Map<String, dynamic>> _logRows = const [];
  int _logTotal = 0;
  int _logPage = 1;
  int _logPerPage = 15;
  int _logEpoch = 0;

  bool _canWooCommerceManage() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'manage');
  }

  bool _canWooCommerceView() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'view');
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(_onTabChanged);
    if (_canWooCommerceView()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshList());
    }
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) {
      if (_tabs.index == 3) {
        _loadControlPanel();
      } else {
        _listPage = 1;
        if (_tabs.index == 1 || _tabs.index == 2) {
          _searchCtl.clear();
        }
        _refreshList();
      }
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchCtl.dispose();
    _ordStatusCtl.dispose();
    _ordSearchCtl.dispose();
    _ordCustomerCtl.dispose();
    _ordAfterCtl.dispose();
    _ordBeforeCtl.dispose();
    _bulkIdsCtl.dispose();
    super.dispose();
  }

  int? _parsePositiveInt(String s) {
    final v = int.tryParse(s.trim());
    if (v == null || v <= 0) return null;
    return v;
  }

  List<int> _parseCommaSeparatedIds(String raw) {
    final parts = raw.split(RegExp(r'[\s,،]+'));
    final out = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v != null && v > 0) {
        out.add(v);
      }
    }
    return out;
  }

  String _prettyJson(Object? value) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return '$value';
    }
  }

  Future<bool> _confirmSyncAction(
    BuildContext context,
    AppLocalizations t, {
    required String title,
    required String body,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.woocommerceHubSyncColumnLabel)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _loadControlPanel({bool logsOnly = false}) async {
    if (!_canWooCommerceView()) return;
    setState(() => _controlLoading = true);
    try {
      if (!logsOnly) {
        final results = await Future.wait([
          _svc.controlSyncStats(businessId: widget.businessId),
          _svc.controlSettingsSummary(businessId: widget.businessId),
          _svc.controlConnection(businessId: widget.businessId),
          _svc.controlPlugin(businessId: widget.businessId),
          _svc.controlQueueSnapshot(businessId: widget.businessId),
        ]);
        if (!mounted) return;
        setState(() {
          final stats = results[0];
          final sm = stats['stats'];
          _syncStats = sm is Map ? Map<String, dynamic>.from(sm) : const {};
          _settingsSummary = Map<String, dynamic>.from(results[1] as Map);
          _connection = Map<String, dynamic>.from(results[2] as Map);
          _pluginInfo = Map<String, dynamic>.from(results[3] as Map);
          _queueSnapshot = Map<String, dynamic>.from(results[4] as Map);
        });
      }
      final lr = await _svc.controlLogs(
        businessId: widget.businessId,
        page: _logPage,
        perPage: _logPerPage,
      );
      if (!mounted) return;
      final items = lr['items'];
      setState(() {
        _logRows = items is List
            ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : const [];
        _logTotal = int.tryParse('${lr['total'] ?? 0}') ?? 0;
        _logEpoch++;
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _controlLoading = false);
    }
  }

  Future<void> _onSyncOrderPressed(BuildContext context, AppLocalizations t, int orderId) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(context, message: t.woocommerceControlManageRequiredHint);
      return;
    }
    final ok = await _confirmSyncAction(context, t, title: t.woocommerceHubSyncOrderConfirmTitle, body: t.woocommerceHubSyncOrderConfirmBody);
    if (!ok || !context.mounted) return;
    try {
      final r = await _svc.postControlSyncOrders(businessId: widget.businessId, orderIds: [orderId]);
      if (!context.mounted) return;
      final results = r['results'];
      String? msg;
      if (results is List && results.isNotEmpty) {
        final first = results.first;
        if (first is Map) {
          msg = '${first['message'] ?? ''}';
        }
      }
      final summary = r['summary'];
      if (summary is Map && (int.tryParse('${summary['failed'] ?? 0}') ?? 0) > 0) {
        SnackBarHelper.showError(context, message: (msg != null && msg.isNotEmpty) ? msg : t.woocommerceControlConnectionFail);
      } else {
        SnackBarHelper.showSuccess(context, message: (msg != null && msg.isNotEmpty) ? msg : t.woocommerceSyncDone);
      }
      await _refreshList();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _onSyncProductPressed(BuildContext context, AppLocalizations t, int productId) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(context, message: t.woocommerceControlManageRequiredHint);
      return;
    }
    final ok = await _confirmSyncAction(context, t, title: t.woocommerceHubSyncProductConfirmTitle, body: t.woocommerceHubSyncProductConfirmBody);
    if (!ok || !context.mounted) return;
    try {
      final r = await _svc.postControlSyncProduct(businessId: widget.businessId, productId: productId);
      if (!context.mounted) return;
      final success = r['success'] == true;
      final m = '${r['message'] ?? ''}'.trim();
      if (success) {
        SnackBarHelper.showSuccess(context, message: m.isNotEmpty ? m : t.woocommerceSyncDone);
      } else {
        SnackBarHelper.showError(context, message: m.isNotEmpty ? m : t.woocommerceControlConnectionFail);
      }
      await _refreshList();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _onSyncCustomerPressed(BuildContext context, AppLocalizations t, int customerId) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(context, message: t.woocommerceControlManageRequiredHint);
      return;
    }
    final ok = await _confirmSyncAction(context, t, title: t.woocommerceHubSyncCustomerConfirmTitle, body: t.woocommerceHubSyncCustomerConfirmBody);
    if (!ok || !context.mounted) return;
    try {
      final r = await _svc.postControlSyncCustomers(businessId: widget.businessId, customerIds: [customerId]);
      if (!context.mounted) return;
      final results = r['results'];
      if (results is List && results.isNotEmpty) {
        final first = results.first;
        if (first is Map && first['success'] == true) {
          SnackBarHelper.showSuccess(context, message: t.woocommerceSyncDone);
        } else if (first is Map) {
          SnackBarHelper.showError(context, message: '${first['message'] ?? t.woocommerceControlConnectionFail}');
        }
      } else {
        SnackBarHelper.showSuccess(context, message: t.woocommerceSyncDone);
      }
      await _refreshList();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _runBulkSync(BuildContext context, AppLocalizations t, String kind) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(context, message: t.woocommerceControlManageRequiredHint);
      return;
    }
    final ids = _parseCommaSeparatedIds(_bulkIdsCtl.text);
    if (ids.isEmpty) {
      SnackBarHelper.showError(context, message: t.woocommerceControlBulkIdsHint);
      return;
    }
    try {
      if (kind == 'orders') {
        await _svc.postControlSyncOrders(businessId: widget.businessId, orderIds: ids);
      } else if (kind == 'products') {
        await _svc.postControlSyncProducts(businessId: widget.businessId, productIds: ids);
      } else {
        await _svc.postControlSyncCustomers(businessId: widget.businessId, customerIds: ids);
      }
      if (!context.mounted) return;
      SnackBarHelper.showSuccess(context, message: t.woocommerceSyncDone);
      await _loadControlPanel();
      if (_tabs.index < 3) {
        await _refreshList();
      }
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _onProcessQueueOnce(BuildContext context, AppLocalizations t) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(context, message: t.woocommerceControlManageRequiredHint);
      return;
    }
    try {
      final r = await _svc.postControlQueueProcessOnce(businessId: widget.businessId);
      if (!context.mounted) return;
      final d = int.tryParse('${r['pending_delta'] ?? 0}') ?? 0;
      SnackBarHelper.showSuccess(
        context,
        message: t.woocommerceControlQueueProcessDone('$d'),
      );
      await _loadControlPanel();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _onPluginForceUpdateCheck(BuildContext context, AppLocalizations t) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(context, message: t.woocommerceControlManageRequiredHint);
      return;
    }
    try {
      await _svc.postControlPluginUpdateCheck(businessId: widget.businessId, force: true);
      if (!context.mounted) return;
      SnackBarHelper.showSuccess(context, message: t.woocommerceControlPluginCheckDone);
      await _loadControlPanel();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _onDebugModeChanged(BuildContext context, AppLocalizations t, bool value) async {
    if (!_canWooCommerceManage()) return;
    try {
      await _svc.postControlSettingsPatch(
        businessId: widget.businessId,
        payload: <String, dynamic>{'hesabix_v2_debug_mode': value},
      );
      if (!context.mounted) return;
      setState(() {
        _settingsSummary = Map<String, dynamic>.from(_settingsSummary)..['hesabix_v2_debug_mode'] = value;
      });
      SnackBarHelper.showSuccess(context, message: t.woocommerceControlSettingsApplied);
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _refreshList() async {
    if (!_canWooCommerceView()) return;
    if (_tabs.index == 3) return;
    setState(() => _loadingList = true);
    try {
      Map<String, dynamic> raw;
      final idx = _tabs.index;
      if (idx == 0) {
        raw = await _svc.listOrders(
          businessId: widget.businessId,
          page: _listPage,
          perPage: _perPage,
          status: _ordStatusCtl.text.trim().isEmpty ? null : _ordStatusCtl.text.trim(),
          after: _ordAfterCtl.text.trim().isEmpty ? null : _ordAfterCtl.text.trim(),
          before: _ordBeforeCtl.text.trim().isEmpty ? null : _ordBeforeCtl.text.trim(),
          customerId: _parsePositiveInt(_ordCustomerCtl.text),
          search: _ordSearchCtl.text.trim().isEmpty ? null : _ordSearchCtl.text.trim(),
          orderby: _ordOrderby,
          order: _ordOrder,
        );
      } else if (idx == 1) {
        raw = await _svc.listProducts(
          businessId: widget.businessId,
          page: _listPage,
          perPage: _perPage,
          search: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
        );
      } else if (idx == 2) {
        raw = await _svc.listCustomers(
          businessId: widget.businessId,
          page: _listPage,
          perPage: _perPage,
          search: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
        );
      } else {
        raw = const {};
      }
      final items = raw['items'];
      setState(() {
        _rows = items is List
            ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : const [];
        _total = int.tryParse('${raw['total'] ?? 0}') ?? 0;
        _hubTableEpoch++;
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canWooCommerceView()) {
      return Scaffold(
        appBar: AppBar(
          leading: businessSubpageBackLeading(context, widget.businessId),
          title: Text(t.woocommercePermissionDeniedTitle),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.woocommercePermissionDeniedBody, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: businessSubpageBackLeading(context, widget.businessId),
        title: Text(t.woocommerceIntegrationMenuTitle),
        actions: [
          IconButton(
            tooltip: t.woocommerceGoToSettingsTooltip,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(
                  context.businessPanelUrl(widget.businessId, 'settings/woocommerce'),
                ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: t.woocommerceHubOrdersTab),
            Tab(text: t.woocommerceHubProductsTab),
            Tab(text: t.woocommerceHubCustomersTab),
            Tab(text: t.woocommerceHubControlTab),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Card(
              child: ListTile(
                leading: Icon(
                  Icons.settings_suggest_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(t.woocommerceHubSettingsPromoTitle),
                subtitle: Text(t.woocommerceHubSettingsPromoSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                      context.businessPanelUrl(widget.businessId, 'settings/woocommerce'),
                    ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildOrdersTab(context, t),
                _buildListTab(context, t, tabIndex: 1, isProducts: true),
                _buildListTab(context, t, tabIndex: 2, isProducts: false),
                _buildControlTab(context, t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.woocommerceOrdersFiltersTitle, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ordStatusCtl,
                    decoration: InputDecoration(
                      labelText: t.woocommerceOrderStatusLabel,
                      hintText: t.woocommerceOrderStatusHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ordCustomerCtl,
                    decoration: InputDecoration(
                      labelText: t.woocommerceOrderCustomerIdLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ordSearchCtl,
                    decoration: InputDecoration(
                      labelText: t.woocommerceOrderSearchLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ordAfterCtl,
                          decoration: InputDecoration(
                            labelText: t.woocommerceOrderDateAfterLabel,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _ordBeforeCtl,
                          decoration: InputDecoration(
                            labelText: t.woocommerceOrderDateBeforeLabel,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: t.woocommerceOrderSortByLabel,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _ordOrderby,
                              items: [
                                DropdownMenuItem(value: 'date', child: Text(t.woocommerceOrderSortByDate)),
                                DropdownMenuItem(
                                    value: 'modified', child: Text(t.woocommerceOrderSortByModified)),
                                DropdownMenuItem(value: 'id', child: Text(t.woocommerceOrderSortById)),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _ordOrderby = v);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: t.woocommerceOrderSortOrderLabel,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _ordOrder,
                              items: [
                                DropdownMenuItem(value: 'DESC', child: Text(t.woocommerceSortDesc)),
                                DropdownMenuItem(value: 'ASC', child: Text(t.woocommerceSortAsc)),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _ordOrder = v);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      onPressed: _loadingList
                          ? null
                          : () {
                              _listPage = 1;
                              _refreshList();
                            },
                      icon: const Icon(Icons.filter_alt),
                      label: Text(t.woocommerceApplyFiltersButton),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                onPressed: _loadingList ? null : _refreshList,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _tabs.index == 0
              ? (_loadingList
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                      child: DataTableWidget<Map<String, dynamic>>(
                        key: ValueKey('woo_hub_o_${_listPage}_$_hubTableEpoch'),
                        config: _hubOrdersTableConfig(context, t),
                        fromJson: (json) => Map<String, dynamic>.from(json as Map),
                        localRawItems: _rows,
                        localTotalCount: _total,
                        localCurrentPage: _listPage,
                        localPageSize: _perPage,
                        onLocalPageChange: (p) {
                          setState(() => _listPage = p);
                          _refreshList();
                        },
                        onLocalPageSizeChange: (s) {
                          setState(() {
                            _perPage = s.clamp(1, 50);
                            _listPage = 1;
                          });
                          _refreshList();
                        },
                      ),
                    ))
              : const ColoredBox(color: Colors.transparent, child: SizedBox.expand()),
        ),
      ],
    );
  }

  Widget _buildControlTab(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t.woocommerceControlIntroTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: t.woocommerceControlRefreshTooltip,
                onPressed: _controlLoading ? null : () => _loadControlPanel(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_controlLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadControlPanel(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(t.woocommerceControlIntroSubtitle),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _controlCard(context, t, title: t.woocommerceControlStatsTitle, child: SelectionArea(child: Text(_prettyJson(_syncStats), style: _monoStyle(context)))),
                  _controlCard(context, t, title: t.woocommerceControlConnectionTitle, child: _connectionSummary(context, t)),
                  _controlCard(context, t, title: t.woocommerceControlQueueTitle, child: _queueSnapshotSection(context, t)),
                  _controlCard(
                    context,
                    t,
                    title: t.woocommerceControlPluginTitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _pluginSummary(context, t),
                        if (_canWooCommerceManage()) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _controlLoading ? null : () => _onPluginForceUpdateCheck(context, t),
                            icon: const Icon(Icons.system_update_alt_outlined, size: 20),
                            label: Text(t.woocommerceControlPluginForceCheckButton),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _controlCard(
                    context,
                    t,
                    title: t.woocommerceControlSettingsTitle,
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(_prettyJson(_settingsSummary), style: _monoStyle(context)),
                      ),
                    ),
                  ),
                  if (_canWooCommerceManage())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: SwitchListTile(
                          title: Text(t.woocommerceControlDebugModeTitle),
                          subtitle: Text(t.woocommerceControlDebugModeSubtitle),
                          value: _settingsSummary['hesabix_v2_debug_mode'] == true,
                          onChanged: _controlLoading
                              ? null
                              : (v) {
                                  _onDebugModeChanged(context, t, v);
                                },
                        ),
                      ),
                    ),
                  if (_canWooCommerceManage()) ...[
                    const SizedBox(height: 8),
                    _bulkSyncCard(context, t),
                  ] else ...[
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(t.woocommerceControlManageRequiredHint),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(t.woocommerceControlLogsTitle, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 440,
                    child: DataTableWidget<Map<String, dynamic>>(
                      key: ValueKey('woo_logs_${_logPage}_${_logPerPage}_$_logEpoch'),
                      config: _controlLogsTableConfig(t),
                      fromJson: (json) => Map<String, dynamic>.from(json as Map),
                      localRawItems: _logRows,
                      localTotalCount: _logTotal,
                      localCurrentPage: _logPage,
                      localPageSize: _logPerPage,
                      onLocalPageChange: (p) {
                        setState(() => _logPage = p);
                        _loadControlPanel(logsOnly: true);
                      },
                      onLocalPageSizeChange: (s) {
                        setState(() {
                          _logPerPage = s.clamp(1, 100);
                          _logPage = 1;
                        });
                        _loadControlPanel(logsOnly: true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _monoStyle(BuildContext context) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.35,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  Widget _controlCard(BuildContext context, AppLocalizations t, {required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionSummary(BuildContext context, AppLocalizations t) {
    final ok = _connection['ok'] == true;
    final msg = '${_connection['message'] ?? ''}'.trim();
    final payload = _connection['payload'];
    String? userLine;
    if (payload is Map && payload['user'] is Map) {
      final u = Map<String, dynamic>.from(payload['user'] as Map);
      final em = '${u['email'] ?? ''}'.trim();
      if (em.isNotEmpty) {
        userLine = em;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              color: ok ? Colors.green : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(ok ? t.woocommerceControlConnectionOk : t.woocommerceControlConnectionFail),
          ],
        ),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg)),
        if (userLine != null && userLine.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(userLine, textDirection: TextDirection.ltr)),
      ],
    );
  }

  Widget _queueSnapshotSection(BuildContext context, AppLocalizations t) {
    final by = _queueSnapshot['by_status'];
    final batch = '${_queueSnapshot['batch_size'] ?? '—'}';
    final buf = StringBuffer();
    if (by is Map && by.isNotEmpty) {
      by.forEach((k, v) {
        buf.writeln('$k: $v');
      });
    } else {
      buf.write('—');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.woocommerceControlQueueBatchHint(batch)),
        const SizedBox(height: 8),
        SelectionArea(child: Text(buf.toString().trim(), style: _monoStyle(context))),
        if (_canWooCommerceManage()) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _controlLoading ? null : () => _onProcessQueueOnce(context, t),
            icon: const Icon(Icons.play_circle_outline, size: 22),
            label: Text(t.woocommerceControlQueueProcessOnceButton),
          ),
        ],
      ],
    );
  }

  Widget _pluginSummary(BuildContext context, AppLocalizations t) {
    final cur = '${_pluginInfo['current_version'] ?? ''}'.trim();
    final up = _pluginInfo['updater'];
    String remote = '';
    bool updateAvail = false;
    if (up is Map) {
      remote = '${up['remote_version'] ?? ''}'.trim();
      updateAvail = up['update_available'] == true;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${t.woocommerceControlCurrentVersion}: ${cur.isEmpty ? '—' : cur}'),
        const SizedBox(height: 6),
        Text('${t.woocommerceControlRemoteVersion}: ${remote.isEmpty ? '—' : remote}', textDirection: TextDirection.ltr),
        const SizedBox(height: 6),
        Text('${t.woocommerceControlUpdateAvailable}: ${updateAvail ? t.woocommerceControlConnectionOk : '—'}'),
      ],
    );
  }

  Widget _bulkSyncCard(BuildContext context, AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.woocommerceControlBulkTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            TextField(
              controller: _bulkIdsCtl,
              decoration: InputDecoration(
                labelText: t.woocommerceControlBulkIdsHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              children: [
                FilledButton(
                  onPressed: _controlLoading ? null : () => _runBulkSync(context, t, 'orders'),
                  child: Text(t.woocommerceControlSyncOrdersButton),
                ),
                FilledButton.tonal(
                  onPressed: _controlLoading ? null : () => _runBulkSync(context, t, 'products'),
                  child: Text(t.woocommerceControlSyncProductsButton),
                ),
                OutlinedButton(
                  onPressed: _controlLoading ? null : () => _runBulkSync(context, t, 'customers'),
                  child: Text(t.woocommerceControlSyncCustomersButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DataTableConfig<Map<String, dynamic>> _controlLogsTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/_local/woocommerce/control/logs',
      tableId: 'woo_control_logs',
      title: t.woocommerceControlLogsTitle,
      columns: [
        TextColumn('id', t.woocommerceControlColumnLogId),
        TextColumn('entity_type', t.woocommerceControlColumnEntityType),
        TextColumn('entity_id', t.woocommerceControlColumnEntityId),
        TextColumn('action', t.woocommerceControlColumnAction),
        TextColumn('status', t.woocommerceControlColumnStatus),
        TextColumn('created_at', t.woocommerceControlColumnCreatedAt),
        TextColumn('error_message', t.woocommerceControlColumnError),
      ],
      searchFields: const ['id', 'entity_type', 'entity_id', 'action', 'status', 'error_message'],
      showFilters: false,
      showPagination: true,
      persistPageSize: false,
      pageSizeOptions: const [10, 15, 25, 50],
      showRefreshButton: false,
      showClearFiltersButton: false,
      enableDateRangeFilter: false,
      defaultPageSize: _logPerPage,
      enableColumnSettings: true,
      showColumnSearch: false,
      enableGlobalSearch: false,
      enableSorting: false,
      showSearch: false,
      showTableIcon: false,
      showActiveFilters: false,
      emptyStateMessage: t.woocommerceNoData,
      minTableWidth: 960,
    );
  }

  Widget _buildListTab(
    BuildContext context,
    AppLocalizations t, {
    required int tabIndex,
    required bool isProducts,
  }) {
    final active = _tabs.index == tabIndex;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  decoration: InputDecoration(
                    labelText: isProducts ? t.woocommerceSearchProductsLabel : t.woocommerceSearchCustomersLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    _listPage = 1;
                    _refreshList();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _loadingList
                    ? null
                    : () {
                        _listPage = 1;
                        _refreshList();
                      },
                icon: const Icon(Icons.search),
              ),
              IconButton(
                onPressed: _loadingList ? null : _refreshList,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: active
              ? (_loadingList
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                      child: DataTableWidget<Map<String, dynamic>>(
                        key: ValueKey('woo_hub_${isProducts ? 'p' : 'c'}_${_listPage}_$_hubTableEpoch'),
                        config: isProducts
                            ? _hubProductsTableConfig(context, t)
                            : _hubCustomersTableConfig(context, t),
                        fromJson: (json) => Map<String, dynamic>.from(json as Map),
                        localRawItems: _rows,
                        localTotalCount: _total,
                        localCurrentPage: _listPage,
                        localPageSize: _perPage,
                        onLocalPageChange: (p) {
                          setState(() => _listPage = p);
                          _refreshList();
                        },
                        onLocalPageSizeChange: (s) {
                          setState(() {
                            _perPage = s.clamp(1, 50);
                            _listPage = 1;
                          });
                          _refreshList();
                        },
                      ),
                    ))
              : const ColoredBox(color: Colors.transparent, child: SizedBox.expand()),
        ),
      ],
    );
  }

  DataTableConfig<Map<String, dynamic>> _hubOrdersTableConfig(BuildContext context, AppLocalizations t) {
    final cols = <DataTableColumn>[
      TextColumn('id', t.woocommerceColumnOrderId),
      TextColumn('number', t.woocommerceColumnOrderNumber),
      TextColumn(
        'type',
        t.woocommerceColumnOrderType,
        sortable: false,
        formatter: (item) => item is Map<String, dynamic> ? wooOrderTypeLabel(t, item['type'] as String?) : null,
      ),
      TextColumn(
        'status',
        t.woocommerceColumnOrderStatus,
        formatter: (item) => item is Map<String, dynamic> ? wooOrderStatusLabel(t, item['status'] as String?) : null,
      ),
      NumberColumn(
        'total',
        t.woocommerceColumnOrderTotal,
        sortable: false,
        textAlign: TextAlign.end,
        formatter: (item) => item is Map<String, dynamic> ? formatOrderTotalDisplay(context, item) : null,
      ),
      TextColumn('billing_email', t.woocommerceColumnBillingEmail),
      TextColumn(
        'hesabix_id',
        t.woocommerceColumnHesabixId,
        sortable: false,
        formatter: (item) {
          if (item is! Map<String, dynamic>) return null;
          final v = item['hesabix_id'];
          if (v == null) return '-';
          return formatWooInteger(context, v);
        },
      ),
      CustomColumn(
        'sync_status',
        t.woocommerceColumnSyncStatus,
        sortable: false,
        searchable: true,
        builder: (item, index) => wooReportSyncStatusCell(t, item),
      ),
    ];
    if (_canWooCommerceManage()) {
      cols.add(
        CustomColumn(
          '_sync',
          t.woocommerceHubSyncColumnLabel,
          sortable: false,
          searchable: false,
          width: ColumnWidth.small,
          builder: (item, index) {
            final m = item is Map<String, dynamic> ? item : null;
            final id = int.tryParse('${m?['id'] ?? ''}') ?? 0;
            return IconButton(
              tooltip: t.woocommerceHubSyncRowTooltip,
              icon: const Icon(Icons.cloud_upload_outlined, size: 20),
              onPressed: id < 1 ? null : () => _onSyncOrderPressed(context, t, id),
            );
          },
        ),
      );
    }
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/_local/woocommerce/hub/orders',
      tableId: 'woo_hub_orders',
      title: t.woocommerceHubOrdersTab,
      columns: cols,
      searchFields: _canWooCommerceManage()
          ? const ['id', 'number', 'type', 'status', 'billing_email', 'hesabix_id', 'sync_status', '_sync']
          : const ['id', 'number', 'type', 'status', 'billing_email', 'hesabix_id', 'sync_status'],
      showFilters: false,
      showPagination: true,
      persistPageSize: false,
      pageSizeOptions: const [10, 20, 50],
      showRefreshButton: false,
      showClearFiltersButton: false,
      enableDateRangeFilter: false,
      defaultPageSize: _perPage,
      enableColumnSettings: true,
      showColumnSearch: false,
      enableGlobalSearch: false,
      enableSorting: false,
      showSearch: false,
      showTableIcon: false,
      showActiveFilters: false,
      emptyStateMessage: t.woocommerceNoData,
      minTableWidth: 980,
    );
  }

  DataTableConfig<Map<String, dynamic>> _hubProductsTableConfig(BuildContext context, AppLocalizations t) {
    final cols = <DataTableColumn>[
      TextColumn('id', t.woocommerceColumnProductId),
      TextColumn('name', t.woocommerceColumnProductName),
      TextColumn('sku', t.woocommerceColumnSku),
      TextColumn(
        'type',
        t.woocommerceColumnProductType,
        formatter: (item) => item is Map<String, dynamic> ? wooProductTypeLabel(t, item['type'] as String?) : null,
      ),
      NumberColumn(
        'price',
        t.woocommerceColumnPrice,
        sortable: false,
        textAlign: TextAlign.end,
        formatter: (item) => item is Map<String, dynamic> ? formatProductPriceDisplay(context, item) : null,
      ),
      TextColumn(
        'hesabix_id',
        t.woocommerceColumnHesabixId,
        sortable: false,
        formatter: (item) {
          if (item is! Map<String, dynamic>) return null;
          final v = item['hesabix_id'];
          if (v == null) return '-';
          return formatWooInteger(context, v);
        },
      ),
      CustomColumn(
        'sync_status',
        t.woocommerceColumnSyncStatus,
        sortable: false,
        searchable: true,
        builder: (item, index) => wooReportSyncStatusCell(t, item),
      ),
    ];
    if (_canWooCommerceManage()) {
      cols.add(
        CustomColumn(
          '_sync',
          t.woocommerceHubSyncColumnLabel,
          sortable: false,
          searchable: false,
          width: ColumnWidth.small,
          builder: (item, index) {
            final m = item is Map<String, dynamic> ? item : null;
            final id = int.tryParse('${m?['id'] ?? ''}') ?? 0;
            return IconButton(
              tooltip: t.woocommerceHubSyncRowTooltip,
              icon: const Icon(Icons.cloud_upload_outlined, size: 20),
              onPressed: id < 1 ? null : () => _onSyncProductPressed(context, t, id),
            );
          },
        ),
      );
    }
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/_local/woocommerce/hub/products',
      tableId: 'woo_hub_products',
      title: t.woocommerceHubProductsTab,
      columns: cols,
      searchFields: _canWooCommerceManage()
          ? const ['id', 'name', 'sku', 'type', 'price', 'hesabix_id', 'sync_status', '_sync']
          : const ['id', 'name', 'sku', 'type', 'price', 'hesabix_id', 'sync_status'],
      showFilters: false,
      showPagination: true,
      persistPageSize: false,
      pageSizeOptions: const [10, 20, 50],
      showRefreshButton: false,
      showClearFiltersButton: false,
      enableDateRangeFilter: false,
      defaultPageSize: _perPage,
      enableColumnSettings: true,
      showColumnSearch: false,
      enableGlobalSearch: false,
      enableSorting: false,
      showSearch: false,
      showTableIcon: false,
      showActiveFilters: false,
      emptyStateMessage: t.woocommerceNoData,
      minTableWidth: 900,
    );
  }

  DataTableConfig<Map<String, dynamic>> _hubCustomersTableConfig(BuildContext context, AppLocalizations t) {
    final cols = <DataTableColumn>[
      TextColumn('id', t.woocommerceColumnCustomerId),
      TextColumn('email', t.woocommerceColumnCustomerEmail),
      TextColumn(
        'name',
        t.woocommerceColumnCustomerName,
        sortable: false,
        formatter: (item) {
          if (item is! Map<String, dynamic>) return null;
          return '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim();
        },
      ),
      TextColumn('username', t.woocommerceColumnUsername),
      TextColumn(
        'hesabix_id',
        t.woocommerceColumnHesabixId,
        sortable: false,
        formatter: (item) {
          if (item is! Map<String, dynamic>) return null;
          final v = item['hesabix_id'];
          if (v == null) return '-';
          return formatWooInteger(context, v);
        },
      ),
      CustomColumn(
        'sync_status',
        t.woocommerceColumnSyncStatus,
        sortable: false,
        searchable: true,
        builder: (item, index) => wooReportSyncStatusCell(t, item),
      ),
    ];
    if (_canWooCommerceManage()) {
      cols.add(
        CustomColumn(
          '_sync',
          t.woocommerceHubSyncColumnLabel,
          sortable: false,
          searchable: false,
          width: ColumnWidth.small,
          builder: (item, index) {
            final m = item is Map<String, dynamic> ? item : null;
            final id = int.tryParse('${m?['id'] ?? ''}') ?? 0;
            return IconButton(
              tooltip: t.woocommerceHubSyncRowTooltip,
              icon: const Icon(Icons.cloud_upload_outlined, size: 20),
              onPressed: id < 1 ? null : () => _onSyncCustomerPressed(context, t, id),
            );
          },
        ),
      );
    }
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/_local/woocommerce/hub/customers',
      tableId: 'woo_hub_customers',
      title: t.woocommerceHubCustomersTab,
      columns: cols,
      searchFields: _canWooCommerceManage()
          ? const ['id', 'email', 'username', 'first_name', 'last_name', 'hesabix_id', 'sync_status', '_sync']
          : const ['id', 'email', 'username', 'first_name', 'last_name', 'hesabix_id', 'sync_status'],
      showFilters: false,
      showPagination: true,
      persistPageSize: false,
      pageSizeOptions: const [10, 20, 50],
      showRefreshButton: false,
      showClearFiltersButton: false,
      enableDateRangeFilter: false,
      defaultPageSize: _perPage,
      enableColumnSettings: true,
      showColumnSearch: false,
      enableGlobalSearch: false,
      enableSorting: false,
      showSearch: false,
      showTableIcon: false,
      showActiveFilters: false,
      emptyStateMessage: t.woocommerceNoData,
      minTableWidth: 800,
    );
  }
}
