import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
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

  final _storeUrlCtl = TextEditingController();
  final _tokenCtl = TextEditingController();
  final _searchCtl = TextEditingController();

  final _ordStatusCtl = TextEditingController();
  final _ordSearchCtl = TextEditingController();
  final _ordCustomerCtl = TextEditingController();
  final _ordAfterCtl = TextEditingController();
  final _ordBeforeCtl = TextEditingController();
  String _ordOrderby = 'date';
  String _ordOrder = 'DESC';

  bool _loadingSettings = true;
  bool _saving = false;
  bool _testing = false;
  bool _loadingList = false;

  int _listPage = 1;
  static const int _perPage = 20;
  List<Map<String, dynamic>> _rows = const [];
  int _total = 0;

  bool _canWooCommerceView() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'view');
  }

  bool _canWooCommerceManage() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'manage');
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(_onTabChanged);
    if (_canWooCommerceView()) {
      _loadSettings();
    } else {
      _loadingSettings = false;
    }
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) {
      _listPage = 1;
      if (_tabs.index == 2 || _tabs.index == 3) {
        _searchCtl.clear();
      }
      if (_tabs.index > 0) {
        _refreshList();
      }
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _storeUrlCtl.dispose();
    _tokenCtl.dispose();
    _searchCtl.dispose();
    _ordStatusCtl.dispose();
    _ordSearchCtl.dispose();
    _ordCustomerCtl.dispose();
    _ordAfterCtl.dispose();
    _ordBeforeCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (!_canWooCommerceView()) return;
    setState(() => _loadingSettings = true);
    try {
      final m = await _svc.getSettings(businessId: widget.businessId);
      _storeUrlCtl.text = (m['store_base_url'] ?? '').toString();
      final tok = (m['bridge_token'] ?? '').toString();
      _tokenCtl.text = tok == '***' ? '' : tok;
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_canWooCommerceManage()) return;
    setState(() => _saving = true);
    try {
      await _svc.updateSettings(
        businessId: widget.businessId,
        payload: <String, dynamic>{
          'store_base_url': _storeUrlCtl.text.trim(),
          'bridge_token': _tokenCtl.text.trim().isEmpty ? '***' : _tokenCtl.text.trim(),
        },
      );
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'تنظیمات ذخیره شد');
      }
      await _loadSettings();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testBridge() async {
    if (!_canWooCommerceView()) return;
    setState(() => _testing = true);
    try {
      await _svc.testBridge(businessId: widget.businessId);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'اتصال موفق');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
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
      if (idx == 1) {
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
      } else if (idx == 2) {
        raw = await _svc.listProducts(
          businessId: widget.businessId,
          page: _listPage,
          perPage: _perPage,
          search: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
        );
      } else if (idx == 3) {
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
    if (!_canWooCommerceView()) {
      return Scaffold(
        appBar: AppBar(
          leading: businessSubpageBackLeading(context, widget.businessId),
          title: const Text('ووکامرس'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('برای مشاهدهٔ این بخش به دسترسی «ووکامرس — مشاهده» نیاز دارید.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: businessSubpageBackLeading(context, widget.businessId),
        title: const Text('ووکامرس'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'تنظیمات'),
            Tab(text: 'سفارشات'),
            Tab(text: 'محصولات'),
            Tab(text: 'مشتریان'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildSettingsTab(),
          _buildOrdersTab(),
          _buildListTab(isProducts: true),
          _buildListTab(isProducts: false),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    if (_loadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }
    final canManage = _canWooCommerceManage();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!canManage)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'فقط مشاهده: برای ذخیرهٔ تنظیمات به دسترسی «مدیریت ووکامرس» نیاز است.',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        TextField(
          controller: _storeUrlCtl,
          readOnly: !canManage,
          decoration: const InputDecoration(
            labelText: 'آدرس فروشگاه (WordPress)',
            hintText: 'https://example.com',
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenCtl,
          readOnly: !canManage,
          decoration: const InputDecoration(
            labelText: 'توکن پل (از افزونه ArcWOC)',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 8),
        const Text(
          'اگر توکن را قبلاً ذخیره کرده‌اید، برای حفظ همان مقدار این فیلد را خالی بگذارید و ذخیره کنید.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: (!canManage || _saving) ? null : _saveSettings,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('ذخیره'),
            ),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testBridge,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('تست اتصال'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOrdersTab() {
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
                  const Text('فیلتر سفارشات', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ordStatusCtl,
                    decoration: const InputDecoration(
                      labelText: 'وضعیت (wc) یا چندتایی با کاما',
                      hintText: 'processing یا processing,completed',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ordCustomerCtl,
                    decoration: const InputDecoration(
                      labelText: 'شناسهٔ مشتری ووکامرس',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ordSearchCtl,
                    decoration: const InputDecoration(
                      labelText: 'جستجو در سفارش',
                      border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'از تاریخ (ISO)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _ordBeforeCtl,
                          decoration: const InputDecoration(
                            labelText: 'تا تاریخ (ISO)',
                            border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'مرتب‌سازی',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _ordOrderby,
                              items: const [
                                DropdownMenuItem(value: 'date', child: Text('تاریخ')),
                                DropdownMenuItem(value: 'modified', child: Text('ویرایش')),
                                DropdownMenuItem(value: 'id', child: Text('شناسه')),
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
                          decoration: const InputDecoration(
                            labelText: 'ترتیب',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _ordOrder,
                              items: const [
                                DropdownMenuItem(value: 'DESC', child: Text('نزولی')),
                                DropdownMenuItem(value: 'ASC', child: Text('صعودی')),
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
                      label: const Text('اعمال فیلتر'),
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
              : _buildDataTable(isOrders: true, isProducts: false),
        ),
        _buildPager(),
      ],
    );
  }

  Widget _buildListTab({required bool isProducts}) {
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
                    labelText: isProducts ? 'جستجوی محصول' : 'جستجوی مشتری',
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
              : _buildDataTable(isOrders: false, isProducts: isProducts),
        ),
        _buildPager(),
      ],
    );
  }

  Widget _buildDataTable({required bool isOrders, required bool isProducts}) {
    if (_rows.isEmpty) {
      return const Center(child: Text('داده‌ای نیست'));
    }
    if (isOrders) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('شناسه')),
            DataColumn(label: Text('شماره')),
            DataColumn(label: Text('وضعیت')),
            DataColumn(label: Text('مبلغ')),
            DataColumn(label: Text('ایمیل')),
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
          columns: const [
            DataColumn(label: Text('شناسه')),
            DataColumn(label: Text('نام')),
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('نوع')),
            DataColumn(label: Text('قیمت')),
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
        columns: const [
          DataColumn(label: Text('شناسه')),
          DataColumn(label: Text('ایمیل')),
          DataColumn(label: Text('نام')),
          DataColumn(label: Text('نام کاربری')),
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

  Widget _buildPager() {
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
          Text('صفحه $_listPage از $pages (مجموع $_total)'),
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
