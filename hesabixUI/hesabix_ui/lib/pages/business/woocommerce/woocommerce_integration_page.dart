import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/date_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/woocommerce_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/jalali_date_picker.dart';
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
  State<WoocommerceIntegrationPage> createState() =>
      _WoocommerceIntegrationPageState();
}

class _WoocommerceIntegrationPageState extends State<WoocommerceIntegrationPage>
    with SingleTickerProviderStateMixin {
  final WoocommerceIntegrationService _svc = WoocommerceIntegrationService();
  late TabController _tabs;

  final _searchCtl = TextEditingController();

  final _ordSearchCtl = TextEditingController();
  final _ordCustomerCtl = TextEditingController();
  String _ordOrderby = 'date';
  String _ordOrder = 'DESC';

  static const List<String> _wooOrderStatusSlugs = [
    'pending',
    'processing',
    'on-hold',
    'completed',
    'cancelled',
    'refunded',
    'failed',
    'draft',
  ];
  final Set<String> _selectedOrderStatuses = {};
  DateTime? _orderFilterDateAfter;
  DateTime? _orderFilterDateBefore;

  bool _loadingList = false;

  int _listPage = 1;
  int _perPage = 20;
  List<Map<String, dynamic>> _rows = const [];
  int _total = 0;
  int _hubTableEpoch = 0;

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
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChanged);
    if (_canWooCommerceView()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshList());
    }
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) {
      _listPage = 1;
      if (_tabs.index == 1 || _tabs.index == 2) {
        _searchCtl.clear();
      }
      _refreshList();
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchCtl.dispose();
    _ordSearchCtl.dispose();
    _ordCustomerCtl.dispose();
    super.dispose();
  }

  int? _parsePositiveInt(String s) {
    final v = int.tryParse(s.trim());
    if (v == null || v <= 0) return null;
    return v;
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.woocommerceHubSyncColumnLabel),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _onSyncOrderPressed(
    BuildContext context,
    AppLocalizations t,
    int orderId,
  ) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceControlManageRequiredHint,
      );
      return;
    }
    final ok = await _confirmSyncAction(
      context,
      t,
      title: t.woocommerceHubSyncOrderConfirmTitle,
      body: t.woocommerceHubSyncOrderConfirmBody,
    );
    if (!ok || !context.mounted) return;
    try {
      final r = await _svc.postControlSyncOrders(
        businessId: widget.businessId,
        orderIds: [orderId],
      );
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
      if (summary is Map &&
          (int.tryParse('${summary['failed'] ?? 0}') ?? 0) > 0) {
        SnackBarHelper.showError(
          context,
          message: (msg != null && msg.isNotEmpty)
              ? msg
              : t.woocommerceControlConnectionFail,
        );
      } else {
        SnackBarHelper.showSuccess(
          context,
          message: (msg != null && msg.isNotEmpty)
              ? msg
              : t.woocommerceSyncDone,
        );
      }
      await _refreshList();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _onSyncProductPressed(
    BuildContext context,
    AppLocalizations t,
    int productId,
  ) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceControlManageRequiredHint,
      );
      return;
    }
    final ok = await _confirmSyncAction(
      context,
      t,
      title: t.woocommerceHubSyncProductConfirmTitle,
      body: t.woocommerceHubSyncProductConfirmBody,
    );
    if (!ok || !context.mounted) return;
    try {
      final r = await _svc.postControlSyncProduct(
        businessId: widget.businessId,
        productId: productId,
      );
      if (!context.mounted) return;
      final success = r['success'] == true;
      final m = '${r['message'] ?? ''}'.trim();
      if (success) {
        SnackBarHelper.showSuccess(
          context,
          message: m.isNotEmpty ? m : t.woocommerceSyncDone,
        );
      } else {
        SnackBarHelper.showError(
          context,
          message: m.isNotEmpty ? m : t.woocommerceControlConnectionFail,
        );
      }
      await _refreshList();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _onSyncCustomerPressed(
    BuildContext context,
    AppLocalizations t,
    int customerId,
  ) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceControlManageRequiredHint,
      );
      return;
    }
    final ok = await _confirmSyncAction(
      context,
      t,
      title: t.woocommerceHubSyncCustomerConfirmTitle,
      body: t.woocommerceHubSyncCustomerConfirmBody,
    );
    if (!ok || !context.mounted) return;
    try {
      final r = await _svc.postControlSyncCustomers(
        businessId: widget.businessId,
        customerIds: [customerId],
      );
      if (!context.mounted) return;
      final results = r['results'];
      if (results is List && results.isNotEmpty) {
        final first = results.first;
        if (first is Map && first['success'] == true) {
          SnackBarHelper.showSuccess(context, message: t.woocommerceSyncDone);
        } else if (first is Map) {
          SnackBarHelper.showError(
            context,
            message:
                '${first['message'] ?? t.woocommerceControlConnectionFail}',
          );
        }
      } else {
        SnackBarHelper.showSuccess(context, message: t.woocommerceSyncDone);
      }
      await _refreshList();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  String? _wooIsoDayStartUtc(DateTime d) {
    final localMidnight = DateTime(d.year, d.month, d.day);
    return localMidnight.toUtc().toIso8601String();
  }

  String? _wooIsoDayEndUtc(DateTime d) {
    final end = DateTime(d.year, d.month, d.day, 23, 59, 59);
    return end.toUtc().toIso8601String();
  }

  Future<void> _pickOrderDate(
    BuildContext context, {
    required bool isAfter,
  }) async {
    final cal = ApiClient.getCalendarController();
    final initial = isAfter
        ? (_orderFilterDateAfter ?? DateTime.now())
        : (_orderFilterDateBefore ?? DateTime.now());
    final picked = await showAdaptiveDatePicker(
      context: context,
      calendarController: cal,
      initialDate: initial,
      firstDate: DateTime(2018),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isAfter) {
          _orderFilterDateAfter = picked;
        } else {
          _orderFilterDateBefore = picked;
        }
      });
    }
  }

  void _clearOrderFilters() {
    setState(() {
      _selectedOrderStatuses.clear();
      _orderFilterDateAfter = null;
      _orderFilterDateBefore = null;
      _ordSearchCtl.clear();
      _ordCustomerCtl.clear();
      _ordOrderby = 'date';
      _ordOrder = 'DESC';
    });
  }

  Future<void> _refreshList() async {
    if (!_canWooCommerceView()) return;
    setState(() => _loadingList = true);
    try {
      Map<String, dynamic> raw;
      final idx = _tabs.index;
      if (idx == 0) {
        raw = await _svc.listOrders(
          businessId: widget.businessId,
          page: _listPage,
          perPage: _perPage,
          status: _selectedOrderStatuses.isEmpty
              ? null
              : _selectedOrderStatuses.join(','),
          after: _orderFilterDateAfter == null
              ? null
              : _wooIsoDayStartUtc(_orderFilterDateAfter!),
          before: _orderFilterDateBefore == null
              ? null
              : _wooIsoDayEndUtc(_orderFilterDateBefore!),
          customerId: _parsePositiveInt(_ordCustomerCtl.text),
          search: _ordSearchCtl.text.trim().isEmpty
              ? null
              : _ordSearchCtl.text.trim(),
          orderby: _ordOrderby,
          order: _ordOrder,
        );
      } else if (idx == 1) {
        raw = await _svc.listProducts(
          businessId: widget.businessId,
          page: _listPage,
          perPage: _perPage,
          search: _searchCtl.text.trim().isEmpty
              ? null
              : _searchCtl.text.trim(),
        );
      } else if (idx == 2) {
        raw = await _svc.listCustomers(
          businessId: widget.businessId,
          page: _listPage,
          perPage: _perPage,
          search: _searchCtl.text.trim().isEmpty
              ? null
              : _searchCtl.text.trim(),
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
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
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
            child: Text(
              t.woocommercePermissionDeniedBody,
              textAlign: TextAlign.center,
            ),
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
              context.businessPanelUrl(
                widget.businessId,
                'settings/woocommerce',
              ),
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
                  Icons.tune,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(t.woocommerceHubArcwocSettingsBannerTitle),
                subtitle: Text(t.woocommerceHubArcwocSettingsBannerSubtitle),
                trailing: FilledButton.tonal(
                  onPressed: () => context.push(
                    context.businessPanelUrl(
                      widget.businessId,
                      'settings/woocommerce',
                    ),
                  ),
                  child: Text(t.woocommerceHubOpenWooSettingsButton),
                ),
                isThreeLine: true,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab(BuildContext context, AppLocalizations t) {
    final isJalali = ApiClient.getCalendarController()?.isJalali ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Card(
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(t.woocommerceOrdersFilterExpandTitle),
              subtitle: Text(t.woocommerceOrdersFiltersTitle),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                Text(
                  t.woocommerceOrderStatusQuickTitle,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _wooOrderStatusSlugs.map((slug) {
                    return FilterChip(
                      label: Text(wooOrderStatusLabel(t, slug)),
                      selected: _selectedOrderStatuses.contains(slug),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _selectedOrderStatuses.add(slug);
                          } else {
                            _selectedOrderStatuses.remove(slug);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        t.woocommerceOrderDateAfterLabel,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      TextButton(
                        onPressed: () => _pickOrderDate(context, isAfter: true),
                        child: Text(
                          _orderFilterDateAfter == null
                              ? t.woocommerceOrderDatePickFrom
                              : HesabixDateUtils.formatForDisplay(
                                  _orderFilterDateAfter,
                                  isJalali,
                                ),
                        ),
                      ),
                      Text(
                        t.woocommerceOrderDateBeforeLabel,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      TextButton(
                        onPressed: () =>
                            _pickOrderDate(context, isAfter: false),
                        child: Text(
                          _orderFilterDateBefore == null
                              ? t.woocommerceOrderDatePickTo
                              : HesabixDateUtils.formatForDisplay(
                                  _orderFilterDateBefore,
                                  isJalali,
                                ),
                        ),
                      ),
                      if (_orderFilterDateAfter != null ||
                          _orderFilterDateBefore != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _orderFilterDateAfter = null;
                            _orderFilterDateBefore = null;
                          }),
                          child: Text(t.woocommerceOrderDateClear),
                        ),
                    ],
                  ),
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
                              DropdownMenuItem(
                                value: 'date',
                                child: Text(t.woocommerceOrderSortByDate),
                              ),
                              DropdownMenuItem(
                                value: 'modified',
                                child: Text(t.woocommerceOrderSortByModified),
                              ),
                              DropdownMenuItem(
                                value: 'id',
                                child: Text(t.woocommerceOrderSortById),
                              ),
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
                              DropdownMenuItem(
                                value: 'DESC',
                                child: Text(t.woocommerceSortDesc),
                              ),
                              DropdownMenuItem(
                                value: 'ASC',
                                child: Text(t.woocommerceSortAsc),
                              ),
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
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _loadingList
                            ? null
                            : () {
                                _clearOrderFilters();
                                _listPage = 1;
                                _refreshList();
                              },
                        child: Text(t.woocommerceClearOrderFilters),
                      ),
                      FilledButton.icon(
                        onPressed: _loadingList
                            ? null
                            : () {
                                _listPage = 1;
                                _refreshList();
                              },
                        icon: const Icon(Icons.filter_alt),
                        label: Text(t.woocommerceApplyFiltersButton),
                      ),
                    ],
                  ),
                ),
              ],
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
                          key: ValueKey(
                            'woo_hub_o_${_listPage}_$_hubTableEpoch',
                          ),
                          config: _hubOrdersTableConfig(context, t),
                          fromJson: (json) =>
                              Map<String, dynamic>.from(json as Map),
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
              : const ColoredBox(
                  color: Colors.transparent,
                  child: SizedBox.expand(),
                ),
        ),
      ],
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
                    labelText: isProducts
                        ? t.woocommerceSearchProductsLabel
                        : t.woocommerceSearchCustomersLabel,
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
                          key: ValueKey(
                            'woo_hub_${isProducts ? 'p' : 'c'}_${_listPage}_$_hubTableEpoch',
                          ),
                          config: isProducts
                              ? _hubProductsTableConfig(context, t)
                              : _hubCustomersTableConfig(context, t),
                          fromJson: (json) =>
                              Map<String, dynamic>.from(json as Map),
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
              : const ColoredBox(
                  color: Colors.transparent,
                  child: SizedBox.expand(),
                ),
        ),
      ],
    );
  }

  DataTableConfig<Map<String, dynamic>> _hubOrdersTableConfig(
    BuildContext context,
    AppLocalizations t,
  ) {
    final cols = <DataTableColumn>[
      TextColumn('id', t.woocommerceColumnOrderId),
      TextColumn('number', t.woocommerceColumnOrderNumber),
      TextColumn(
        'type',
        t.woocommerceColumnOrderType,
        sortable: false,
        formatter: (item) => item is Map<String, dynamic>
            ? wooOrderTypeLabel(t, item['type'] as String?)
            : null,
      ),
      TextColumn(
        'status',
        t.woocommerceColumnOrderStatus,
        formatter: (item) => item is Map<String, dynamic>
            ? wooOrderStatusLabel(t, item['status'] as String?)
            : null,
      ),
      NumberColumn(
        'total',
        t.woocommerceColumnOrderTotal,
        sortable: false,
        textAlign: TextAlign.end,
        formatter: (item) => item is Map<String, dynamic>
            ? formatOrderTotalDisplay(context, item)
            : null,
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
              onPressed: id < 1
                  ? null
                  : () => _onSyncOrderPressed(context, t, id),
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
          ? const [
              'id',
              'number',
              'type',
              'status',
              'billing_email',
              'hesabix_id',
              'sync_status',
              '_sync',
            ]
          : const [
              'id',
              'number',
              'type',
              'status',
              'billing_email',
              'hesabix_id',
              'sync_status',
            ],
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

  DataTableConfig<Map<String, dynamic>> _hubProductsTableConfig(
    BuildContext context,
    AppLocalizations t,
  ) {
    final cols = <DataTableColumn>[
      TextColumn('id', t.woocommerceColumnProductId),
      TextColumn('name', t.woocommerceColumnProductName),
      TextColumn('sku', t.woocommerceColumnSku),
      TextColumn(
        'type',
        t.woocommerceColumnProductType,
        formatter: (item) => item is Map<String, dynamic>
            ? wooProductTypeLabel(t, item['type'] as String?)
            : null,
      ),
      NumberColumn(
        'price',
        t.woocommerceColumnPrice,
        sortable: false,
        textAlign: TextAlign.end,
        formatter: (item) => item is Map<String, dynamic>
            ? formatProductPriceDisplay(context, item)
            : null,
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
              onPressed: id < 1
                  ? null
                  : () => _onSyncProductPressed(context, t, id),
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
          ? const [
              'id',
              'name',
              'sku',
              'type',
              'price',
              'hesabix_id',
              'sync_status',
              '_sync',
            ]
          : const [
              'id',
              'name',
              'sku',
              'type',
              'price',
              'hesabix_id',
              'sync_status',
            ],
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

  DataTableConfig<Map<String, dynamic>> _hubCustomersTableConfig(
    BuildContext context,
    AppLocalizations t,
  ) {
    final cols = <DataTableColumn>[
      TextColumn('id', t.woocommerceColumnCustomerId),
      TextColumn('email', t.woocommerceColumnCustomerEmail),
      TextColumn(
        'name',
        t.woocommerceColumnCustomerName,
        sortable: false,
        formatter: (item) {
          if (item is! Map<String, dynamic>) return null;
          return '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'
              .trim();
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
              onPressed: id < 1
                  ? null
                  : () => _onSyncCustomerPressed(context, t, id),
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
          ? const [
              'id',
              'email',
              'username',
              'first_name',
              'last_name',
              'hesabix_id',
              'sync_status',
              '_sync',
            ]
          : const [
              'id',
              'email',
              'username',
              'first_name',
              'last_name',
              'hesabix_id',
              'sync_status',
            ],
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
