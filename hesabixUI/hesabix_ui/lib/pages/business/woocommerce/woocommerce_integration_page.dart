import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/woocommerce_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';

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
  static const int _perPage = 20;
  List<Map<String, dynamic>> _rows = const [];
  int _total = 0;

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
    _ordStatusCtl.dispose();
    _ordSearchCtl.dispose();
    _ordCustomerCtl.dispose();
    _ordAfterCtl.dispose();
    _ordBeforeCtl.dispose();
    super.dispose();
  }

  int? _parsePositiveInt(String s) {
    final v = int.tryParse(s.trim());
    if (v == null || v <= 0) return null;
    return v;
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
                _buildListTab(context, t, isProducts: true),
                _buildListTab(context, t, isProducts: false),
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
          child: _loadingList
              ? const Center(child: CircularProgressIndicator())
              : _buildDataTable(context, t, isOrders: true, isProducts: false),
        ),
        _buildPager(context, t),
      ],
    );
  }

  Widget _buildListTab(BuildContext context, AppLocalizations t, {required bool isProducts}) {
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
          child: _loadingList
              ? const Center(child: CircularProgressIndicator())
              : _buildDataTable(context, t, isOrders: false, isProducts: isProducts),
        ),
        _buildPager(context, t),
      ],
    );
  }

  Widget _buildDataTable(
    BuildContext context,
    AppLocalizations t, {
    required bool isOrders,
    required bool isProducts,
  }) {
    if (_rows.isEmpty) {
      return Center(child: Text(t.woocommerceNoData));
    }
    if (isOrders) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(t.woocommerceColumnOrderId)),
            DataColumn(label: Text(t.woocommerceColumnOrderNumber)),
            DataColumn(label: Text(t.woocommerceColumnOrderStatus)),
            DataColumn(label: Text(t.woocommerceColumnOrderTotal)),
            DataColumn(label: Text(t.woocommerceColumnBillingEmail)),
          ],
          rows: _rows
              .map(
                (r) => DataRow(
                  cells: [
                    DataCell(Text('${r['id'] ?? ''}')),
                    DataCell(Text('${r['number'] ?? ''}')),
                    DataCell(Text('${r['status'] ?? ''}')),
                    DataCell(Text('${r['total'] ?? ''}')),
                    DataCell(Text('${r['billing_email'] ?? ''}')),
                  ],
                ),
              )
              .toList(),
        ),
      );
    }
    if (isProducts) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(t.woocommerceColumnProductId)),
            DataColumn(label: Text(t.woocommerceColumnProductName)),
            DataColumn(label: Text(t.woocommerceColumnSku)),
            DataColumn(label: Text(t.woocommerceColumnProductType)),
            DataColumn(label: Text(t.woocommerceColumnPrice)),
          ],
          rows: _rows
              .map(
                (r) => DataRow(
                  cells: [
                    DataCell(Text('${r['id'] ?? ''}')),
                    DataCell(Text('${r['name'] ?? ''}')),
                    DataCell(Text('${r['sku'] ?? ''}')),
                    DataCell(Text('${r['type'] ?? ''}')),
                    DataCell(Text('${r['price'] ?? ''}')),
                  ],
                ),
              )
              .toList(),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text(t.woocommerceColumnCustomerId)),
          DataColumn(label: Text(t.woocommerceColumnCustomerEmail)),
          DataColumn(label: Text(t.woocommerceColumnCustomerName)),
          DataColumn(label: Text(t.woocommerceColumnUsername)),
        ],
        rows: _rows
            .map(
              (r) => DataRow(
                cells: [
                  DataCell(Text('${r['id'] ?? ''}')),
                  DataCell(Text('${r['email'] ?? ''}')),
                  DataCell(Text('${r['first_name'] ?? ''} ${r['last_name'] ?? ''}')),
                  DataCell(Text('${r['username'] ?? ''}')),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildPager(BuildContext context, AppLocalizations t) {
    final pages = (_total / _perPage).ceil().clamp(1, 999999);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _listPage <= 1 || _loadingList
                ? null
                : () {
                    _listPage--;
                    _refreshList();
                  },
            icon: const Icon(Icons.chevron_right),
          ),
          Text(t.woocommercePagerLine(_listPage, pages, _total)),
          IconButton(
            onPressed: _listPage >= pages || _loadingList
                ? null
                : () {
                    _listPage++;
                    _refreshList();
                  },
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    );
  }
}
