import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/auth_store.dart';
import '../../../services/procurement_api.dart';

class ProcurementPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ProcurementPage({super.key, required this.businessId, required this.authStore});

  @override
  State<ProcurementPage> createState() => _ProcurementPageState();
}

class _ProcurementPageState extends State<ProcurementPage> with SingleTickerProviderStateMixin {
  final _api = ProcurementApi();
  late final TabController _tabs;
  final _query = TextEditingController();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _dashboard = {};
  List<Map<String, dynamic>> _requisitions = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _budgets = [];
  List<Map<String, dynamic>> _budgetMovements = [];
  List<Map<String, dynamic>> _contracts = [];
  List<Map<String, dynamic>> _reorder = [];
  List<Map<String, dynamic>> _costCenters = [];
  List<Map<String, dynamic>> _sourcing = [];
  Map<String, dynamic> _settings = {};
  Map<String, dynamic>? _event;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _t(String fa, String en) => _fa ? fa : en;
  bool _can(String action) {
    if (widget.authStore.hasBusinessPermission('procurement', 'admin')) return true;
    if (widget.authStore.hasBusinessPermission('procurement', action)) return true;
    if (action == 'view') {
      return widget.authStore.hasBusinessPermission('procurement', 'operate') ||
          widget.authStore.hasBusinessPermission('procurement', 'approve') ||
          widget.authStore.hasBusinessPermission('procurement', 'manage');
    }
    return false;
  }

  bool get _canPurchaseInvoice =>
      widget.authStore.hasBusinessPermission('invoices', 'add') ||
      widget.authStore.hasBusinessPermission('invoice_types', 'purchase');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 9, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _api.dashboard(widget.businessId),
        _api.listRequisitions(widget.businessId),
        _api.listOrders(widget.businessId),
        _api.listSuppliers(widget.businessId),
        _api.listBudgets(widget.businessId),
        _api.listPendingBudgetMovements(widget.businessId),
        _api.listContracts(widget.businessId),
        _api.listReorder(widget.businessId),
        _api.getSettings(widget.businessId),
        _api.listCostCenters(widget.businessId),
        _api.listSourcing(widget.businessId),
      ]);
      if (!mounted) return;
      Map<String, dynamic>? openEvent = _event;
      if (openEvent != null && openEvent['id'] is int) {
        try {
          openEvent = await _api.getSourcing(widget.businessId, openEvent['id'] as int);
        } catch (_) {
          openEvent = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _dashboard = Map<String, dynamic>.from(results[0] as Map);
        _requisitions = _maps((results[1] as Map)['items']);
        _orders = _maps((results[2] as Map)['items']);
        _suppliers = _maps((results[3] as Map)['items']);
        _budgets = _maps((results[4] as Map)['items']);
        _budgetMovements = List<Map<String, dynamic>>.from(results[5] as List);
        _contracts = _maps((results[6] as Map)['items']);
        _reorder = _maps((results[7] as Map)['items']);
        _settings = Map<String, dynamic>.from(results[8] as Map);
        _costCenters = List<Map<String, dynamic>>.from(results[9] as List);
        _sourcing = _maps((results[10] as Map)['items']);
        _event = openEvent;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = procurementErrorText(error);
      });
    }
  }

  List<Map<String, dynamic>> _maps(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  bool _tenderBidsScored(Map<String, dynamic> event) {
    final bids = _maps(event['invites']).map((invite) => invite['bid']).whereType<Map>().toList();
    if (bids.isEmpty) return false;
    return bids.every((bid) => bid['technical_score'] != null);
  }

  double _asNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  double _payableUnit(Map<String, dynamic> order, Map<String, dynamic> line) {
    double ownOf(Map item) {
      final gross = _asNum(item['qty']) * _asNum(item['unit_price']) - _asNum(item['discount']);
      return gross > 0 ? gross : 0;
    }

    final own = ownOf(line);
    final base = _maps(order['lines']).fold<double>(0, (sum, item) => sum + ownOf(item));
    final share = base <= 0 ? 0.0 : _asNum(order['header_discount']) * own / base;
    final net = own - share;
    final qty = _asNum(line['qty']);
    if (qty <= 0) return _asNum(line['unit_price']);
    return (((net < 0 ? 0 : net) / qty) * 100).round() / 100;
  }

  int? _optionalId(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  String _itemKind(String? raw) => raw == 'service' ? 'service' : 'goods';

  List<_Field> _catalogInputs(Map? line) => [
        _Field('product_id', _t('شناسه کالا، برای رسید و فاکتور', 'Product id, for receipt and invoice'), number: true, initial: '${line?['product_id'] ?? ''}'),
        _Field('warehouse_id', _t('شناسه انبار', 'Warehouse id'), number: true, initial: '${line?['warehouse_id'] ?? ''}'),
        _Field('item_kind', _t('goods یا service', 'goods or service'), initial: '${line?['item_kind'] ?? 'goods'}'),
      ];

  Map<String, dynamic> _catalogFields(Map<String, String> values) {
    final productId = _optionalId(values['product_id']);
    final warehouseId = _optionalId(values['warehouse_id']);
    return {
      'item_kind': _itemKind(values['item_kind']),
      if (productId != null) 'product_id': productId,
      if (warehouseId != null) 'warehouse_id': warehouseId,
    };
  }

  Map<String, dynamic> _keptOrderLine(
    Map line, {
    String? description,
    num? qty,
    num? price,
    num? discount,
    num? tax,
    String? itemKind,
    int? productId,
    int? warehouseId,
    bool replaceCatalog = false,
  }) {
    final product = replaceCatalog ? productId : line['product_id'];
    final warehouse = replaceCatalog ? warehouseId : line['warehouse_id'];
    return {
      'description': description ?? line['description'],
      'qty': qty ?? line['qty'],
      'unit_price': price ?? line['unit_price'] ?? 0,
      'discount': discount ?? line['discount'] ?? 0,
      'tax': tax ?? line['tax'] ?? 0,
      'item_kind': itemKind ?? line['item_kind'] ?? 'goods',
      if (product != null) 'product_id': product,
      if (warehouse != null) 'warehouse_id': warehouse,
      if (line['requisition_line_id'] != null) 'requisition_line_id': line['requisition_line_id'],
    };
  }

  Map<String, dynamic> _needLine(Map line, {Map<String, String>? values}) {
    if (values == null) {
      return {
        'description': line['description'],
        'qty': line['qty'],
        'unit_price': line['unit_price_estimate'] ?? line['unit_price'] ?? 0,
        'item_kind': line['item_kind'] ?? 'goods',
        if (line['product_id'] != null) 'product_id': line['product_id'],
        if (line['warehouse_id'] != null) 'warehouse_id': line['warehouse_id'],
      };
    }
    return {
      'description': values['description'],
      'qty': num.parse(values['qty']!),
      'unit_price': num.tryParse(values['price'] ?? '') ?? 0,
      ..._catalogFields(values),
    };
  }

  bool _orderClosable(Map<String, dynamic> row) {
    if (['draft', 'pending_approval', 'cancelled', 'closed'].contains(row['status'])) return false;
    final lines = _maps(row['lines']);
    if (lines.isEmpty) return false;
    var kept = false;
    for (final line in lines) {
      final ordered = _asNum(line['qty']) - _asNum(line['cancelled_qty']);
      if (ordered <= 0) continue;
      kept = true;
      if (_asNum(line['received_qty']) + 0.0001 < ordered || _asNum(line['invoiced_qty']) + 0.0001 < _asNum(line['accepted_qty'])) {
        return false;
      }
    }
    if (!kept) return false;
    return !_maps(row['invoices']).any((invoice) => invoice['match_status'] == 'exception');
  }

  bool _lineReceivable(Map<String, dynamic> order, Map<String, dynamic> line) {
    return ['approved', 'sent', 'partial', 'received'].contains(order['status']) && _asNum(line['open_qty']) > 0.0001;
  }

  bool _lineReturnable(Map<String, dynamic> order, Map<String, dynamic> line) {
    if (['draft', 'pending_approval', 'cancelled', 'closed'].contains(order['status'])) return false;
    return _asNum(line['accepted_qty']) - _asNum(line['invoiced_qty']) > 0.0001;
  }

  bool _orderBillable(Map<String, dynamic> row) {
    if (['draft', 'pending_approval', 'closed'].contains(row['status'])) return false;
    return _maps(row['lines']).any((line) => line['product_id'] != null && _asNum(line['accepted_qty']) > _asNum(line['invoiced_qty']) + 0.0001);
  }

  bool _matches(Map<String, dynamic> row) {
    final q = _query.text.trim();
    if (q.isEmpty) return true;
    return row.values.map((value) => '$value').join(' ').contains(q);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('انجام شد', 'Done'))));
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<Map<String, String>?> _form(String title, List<_Field> fields) async {
    final controllers = {for (final field in fields) field.key: TextEditingController(text: field.initial)};
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: controllers[field.key],
                    keyboardType: field.number ? TextInputType.number : TextInputType.text,
                    inputFormatters: field.number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
                    decoration: InputDecoration(labelText: field.label, helperText: field.help),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('انصراف', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final missing = fields.where((field) => field.required && controllers[field.key]!.text.trim().isEmpty);
              if (missing.isNotEmpty) return;
              Navigator.pop(context, {for (final field in fields) field.key: controllers[field.key]!.text.trim()});
            },
            child: Text(_t('ثبت', 'Save')),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('خرید و تدارکات', 'Procurement')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: _t('داشبورد', 'Dashboard')),
            Tab(text: _t('درخواست‌ها', 'Needs')),
            Tab(text: _t('سفارش‌ها', 'Orders')),
            Tab(text: _t('استعلام', 'Sourcing')),
            Tab(text: _t('تأمین‌کنندگان', 'Suppliers')),
            Tab(text: _t('بودجه', 'Budgets')),
            Tab(text: _t('قراردادها', 'Contracts')),
            Tab(text: _t('نقطه سفارش', 'Reorder')),
            Tab(text: _t('تنظیمات', 'Settings')),
          ],
        ),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _t('جست‌وجو در فهرست همین صفحه', 'Search the loaded lists'),
                isDense: true,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  TextButton(onPressed: _reload, child: Text(_t('تلاش دوباره', 'Retry'))),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _dashboardTab(),
                      _requisitionsTab(),
                      _ordersTab(),
                      _sourcingTab(),
                      _suppliersTab(),
                      _budgetsTab(),
                      _contractsTab(),
                      _reorderTab(),
                      _settingsTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardTab() {
    final cards = [
      [_t('درخواست در انتظار تأیید', 'Requisitions awaiting approval'), '${_dashboard['pending_requisitions'] ?? 0}'],
      [_t('سفارش باز', 'Open orders'), '${_dashboard['open_orders'] ?? 0}'],
      [_t('مغایرت فاکتور', 'Invoice exceptions'), '${_dashboard['invoice_exceptions'] ?? 0}'],
      [_t('پیشنهاد خرید', 'Reorder suggestions'), '${_dashboard['reorder_open'] ?? 0}'],
    ];
    final expiring = _maps(_dashboard['expiring_contracts']);
    final warnings = _maps(_dashboard['budget_warnings']);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(
                width: 220,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(card[0]), const SizedBox(height: 8), Text(card[1], style: Theme.of(context).textTheme.headlineSmall)]),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(_t('قراردادهای رو به انقضا', 'Contracts ending within 30 days'), style: Theme.of(context).textTheme.titleMedium),
        if (expiring.isEmpty) _empty(_t('قرارداد رو به انقضایی نیست.', 'No contracts are ending soon.')),
        for (final row in expiring.where(_matches)) ListTile(title: Text('${row['code']} ${row['title'] ?? ''}'), subtitle: Text('${row['end_date'] ?? ''}')),
        Text(_t('هشدار بودجه', 'Budget warnings'), style: Theme.of(context).textTheme.titleMedium),
        if (warnings.isEmpty) _empty(_t('بودجه‌ای به آستانه مصرف نرسیده است.', 'No budget has reached its warning threshold.')),
        for (final row in warnings.where(_matches)) ListTile(title: Text('${row['name']}'), subtitle: Text(_t('مانده ${row['available']}', 'Available ${row['available']}'))),
      ],
    );
  }

  Widget _requisitionsTab() {
    final rows = _requisitions.where(_matches).toList();
    return _list(
      onAdd: _can('operate') ? _createRequisition : null,
      empty: _t('درخواستی ثبت نشده است.', 'No purchase needs yet.'),
      children: [
        for (final row in rows)
          ExpansionTile(
            title: Text('${row['code']}'),
            subtitle: Text('${row['reason'] ?? ''} ${row['org_unit_name'] ?? ''}'),
            trailing: Chip(label: Text('${row['status']}')),
            children: [
              if (_can('operate') && (row['status'] == 'draft' || row['status'] == 'returned')) ...[
                TextButton(onPressed: () => _editRequisition(row), child: Text(_t('ویرایش', 'Edit'))),
                TextButton(onPressed: () => _addNeedLine(row), child: Text(_t('قلم جدید', 'Add line'))),
                TextButton(onPressed: () => _submitRequisition(row['id'] as int), child: Text(_t('ارسال برای تأیید', 'Submit'))),
              ],
              if (_can('approve') && row['status'] == 'pending_approval') ...[
                TextButton(onPressed: () => _run(() => _api.decide(widget.businessId, 'requisition', row['id'] as int, 'approve')), child: Text(_t('تأیید', 'Approve'))),
                TextButton(onPressed: () => _reject('requisition', row['id'] as int, action: 'return'), child: Text(_t('برگشت', 'Return'))),
                TextButton(onPressed: () => _reject('requisition', row['id'] as int), child: Text(_t('رد', 'Reject'))),
              ],
              if (_can('operate') && row['status'] == 'approved') ...[
                TextButton(onPressed: () => _orderFromNeed(row), child: Text(_t('تبدیل به سفارش', 'Create order'))),
                TextButton(onPressed: () => _sourceFromNeed(row), child: Text(_t('استعلام', 'Request quotes'))),
              ],
              if (row['file_ids'] is List && (row['file_ids'] as List).isNotEmpty)
                ListTile(title: Text(_t('پیوست', 'Attachments')), subtitle: Text('${row['file_ids']}')),
              for (final step in _maps(row['approvals']))
                ListTile(
                  title: Text(_t('گام ${step['step_no']}', 'Step ${step['step_no']}')),
                  subtitle: Text(_t('کاربر ${step['approver_user_id'] ?? 'هر دارنده مجوز'} — ${step['status']}', 'User ${step['approver_user_id'] ?? 'anyone with permission'} — ${step['status']}')),
                ),
              for (final line in _maps(row['lines']))
                ListTile(
                  title: Text('${line['description']}'),
                  subtitle: Text(_t(
                    'مقدار ${line['qty']} — برآورد ${line['unit_price_estimate'] ?? 0}${line['product_id'] != null ? ' — کالا ' : ''}${line['product_id'] ?? ''}',
                    'Qty ${line['qty']} — estimate ${line['unit_price_estimate'] ?? 0}${line['product_id'] != null ? ' — product ' : ''}${line['product_id'] ?? ''}',
                  )),
                ),
            ],
          ),
      ],
    );
  }

  Widget _ordersTab() {
    final rows = _orders.where(_matches).toList();
    return _list(
      onAdd: _can('operate') ? _createOrder : null,
      empty: _t('سفارشی ثبت نشده است.', 'No purchase orders yet.'),
      children: [
        for (final row in rows)
          ExpansionTile(
            title: Text('${row['code']}'),
            subtitle: Text(_t(
              'شخص ${row['person_id']} — جمع ${row['total']}${row['cost_center_id'] == null ? '' : ' — مرکز '}${row['cost_center_id'] ?? ''}${row['delivery_date'] == null ? '' : ' — تحویل '}${row['delivery_date'] ?? ''}',
              'Person ${row['person_id']} — total ${row['total']}${row['cost_center_id'] == null ? '' : ' — cost center '}${row['cost_center_id'] ?? ''}${row['delivery_date'] == null ? '' : ' — delivery '}${row['delivery_date'] ?? ''}',
            )),
            trailing: Chip(label: Text('${row['status']}')),
            children: [
              if (_can('operate') && row['status'] == 'draft') ...[
                TextButton(onPressed: () => _editOrder(row), child: Text(_t('ویرایش', 'Edit'))),
                TextButton(onPressed: () => _addOrderLine(row), child: Text(_t('قلم جدید', 'Add line'))),
                TextButton(onPressed: () => _submitOrder(row['id'] as int), child: Text(_t('ارسال برای تأیید', 'Submit'))),
              ],
              if (_can('approve') && row['status'] == 'pending_approval') ...[
                TextButton(onPressed: () => _run(() => _api.decide(widget.businessId, 'order', row['id'] as int, 'approve')), child: Text(_t('تأیید و ثبت تعهد', 'Approve and commit'))),
                TextButton(onPressed: () => _reject('order', row['id'] as int, action: 'return'), child: Text(_t('برگشت', 'Return'))),
                TextButton(onPressed: () => _reject('order', row['id'] as int), child: Text(_t('رد', 'Reject'))),
              ],
              if (_can('operate') && row['status'] == 'approved')
                TextButton(onPressed: () => _run(() => _api.sendOrder(widget.businessId, row['id'] as int)), child: Text(_t('ارسال برای تأمین‌کننده', 'Send to supplier'))),
              if (_can('operate') && !['closed', 'cancelled', 'draft'].contains(row['status']))
                TextButton(onPressed: () => _run(() => _api.cancelOrder(widget.businessId, row['id'] as int)), child: Text(_t('لغو مقدار باز', 'Cancel open quantity'))),
              if (_can('operate') && _orderClosable(row))
                TextButton(onPressed: () => _run(() => _api.closeOrder(widget.businessId, row['id'] as int)), child: Text(_t('بستن', 'Close'))),
              if (_can('operate') && !['cancelled', 'closed'].contains(row['status']))
                TextButton(onPressed: () => _prepay(row), child: Text(_t('پیش‌پرداخت', 'Prepayment'))),
              if (_can('operate') && _canPurchaseInvoice && _orderBillable(row))
                TextButton(onPressed: () => _invoice(row), child: Text(_t('فاکتور خرید', 'Supplier invoice'))),
              if (_can('operate') && !['draft', 'pending_approval', 'cancelled'].contains(row['status']))
                TextButton(onPressed: () => _share(row), child: Text(_t('لینک تأمین‌کننده', 'Supplier link'))),
              for (final link in _maps(row['share_links']))
                if (link['revoked'] != true && _can('operate'))
                  TextButton(onPressed: () => _run(() => _api.revokeShare(widget.businessId, link['id'] as int)), child: Text(_t('ابطال لینک ${link['kind']}', 'Revoke ${link['kind']} link'))),
              if (row['file_ids'] is List && (row['file_ids'] as List).isNotEmpty)
                ListTile(title: Text(_t('پیوست', 'Attachments')), subtitle: Text('${row['file_ids']}')),
              for (final step in _maps(row['approvals']))
                ListTile(
                  title: Text(_t('گام ${step['step_no']}', 'Step ${step['step_no']}')),
                  subtitle: Text(_t('کاربر ${step['approver_user_id'] ?? 'هر دارنده مجوز'} — ${step['status']}', 'User ${step['approver_user_id'] ?? 'anyone with permission'} — ${step['status']}')),
                ),
              for (final receipt in _maps(row['receipts'])) ...[
                ListTile(
                  title: Text(receipt['note'] == 'supplier_return' ? _t('برگشت ${receipt['received_on'] ?? ''}', 'Return ${receipt['received_on'] ?? ''}') : _t('رسید ${receipt['received_on'] ?? ''}', 'Receipt ${receipt['received_on'] ?? ''}')),
                  subtitle: Text(_t('حواله ${receipt['warehouse_document_ids'] is List && (receipt['warehouse_document_ids'] as List).isNotEmpty ? (receipt['warehouse_document_ids'] as List).join('، ') : (receipt['warehouse_document_id'] ?? '—')}', 'Warehouse document ${receipt['warehouse_document_ids'] is List && (receipt['warehouse_document_ids'] as List).isNotEmpty ? (receipt['warehouse_document_ids'] as List).join(', ') : (receipt['warehouse_document_id'] ?? '—')}')),
                ),
                for (final item in _maps(receipt['lines']))
                  ListTile(
                    title: Text(_t('قلم ${item['order_line_id']}', 'Line ${item['order_line_id']}')),
                    subtitle: Text(_t('پذیرفته ${item['qty']}، مردود ${item['rejected_qty']}، کیفیت ${item['qc_status']}', 'Accepted ${item['qty']}, rejected ${item['rejected_qty']}, QC ${item['qc_status']}')),
                  ),
              ],
              for (final invoice in _maps(row['invoices']))
                ListTile(
                  title: Text(_t('فاکتور سند ${invoice['document_id']}', 'Invoice document ${invoice['document_id']}')),
                  subtitle: Text(_t('تطبیق ${invoice['match_status']}${invoice['price_variance_accepted'] == true ? ' — اختلاف قیمت پذیرفته شده' : ''}', 'Match ${invoice['match_status']}${invoice['price_variance_accepted'] == true ? ' — price difference accepted' : ''}')),
                ),
              for (final notice in _maps(row['portal_invoices']))
                ListTile(title: Text(_t('اعلام فاکتور ${notice['reference']}', 'Invoice notice ${notice['reference']}')), subtitle: Text(_t('مبلغ ${notice['amount']}. این اعلام سند حسابداری نیست.', 'Amount ${notice['amount']}. This notice is not an accounting document.'))),
              for (final payment in _maps(row['prepayments']))
                ListTile(title: Text(_t('پیش‌پرداخت', 'Prepayment')), subtitle: Text(_t('سند ${payment['document_id']} — مبلغ ${payment['amount']}', 'Document ${payment['document_id']} — amount ${payment['amount']}'))),
              for (final line in _maps(row['lines']))
                ListTile(
                  title: Text('${line['description']}${line['product_id'] != null ? ' · ' : ''}${line['product_id'] ?? ''}'),
                  subtitle: Text(_t(
                    'سفارش ${line['qty']}، قیمت ${line['unit_price']}، تخفیف ${line['discount'] ?? 0}، مالیات ${line['tax'] ?? 0}، پذیرفته ${line['accepted_qty']}، فاکتور ${line['invoiced_qty']}${line['requisition_line_id'] == null ? '' : '، قلم درخواست '}${line['requisition_line_id'] ?? ''}',
                    'Ordered ${line['qty']}, price ${line['unit_price']}, discount ${line['discount'] ?? 0}, tax ${line['tax'] ?? 0}, accepted ${line['accepted_qty']}, invoiced ${line['invoiced_qty']}${line['requisition_line_id'] == null ? '' : ', requisition line '}${line['requisition_line_id'] ?? ''}',
                  )),
                  trailing: _can('operate') && (_lineReceivable(row, line) || _lineReturnable(row, line))
                      ? Wrap(
                          spacing: 4,
                          children: [
                            if (_lineReceivable(row, line)) TextButton(onPressed: () => _receive(row, line), child: Text(_t('رسید', 'Receive'))),
                            if (_lineReturnable(row, line)) TextButton(onPressed: () => _returnLine(row, line), child: Text(_t('برگشت', 'Return'))),
                          ],
                        )
                      : null,
                ),
            ],
          ),
      ],
    );
  }

  Widget _sourcingTab() {
    final event = _event;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_can('operate'))
          FilledButton(onPressed: _createSourcing, child: Text(_t('استعلام یا مناقصه جدید', 'New RFQ or tender'))),
        if (event == null && _sourcing.where(_matches).isEmpty) _empty(_t('رویداد منبع‌یابی ثبت نشده است.', 'No sourcing event yet.')),
        if (event == null)
          for (final row in _sourcing.where(_matches))
            ListTile(
              title: Text('${row['code']} ${row['title']}'),
              subtitle: Text('${row['event_type']} — ${row['status']}'),
              onTap: () => _openSourcing(row['id'] as int),
            ),
        if (event != null) ...[
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: () => setState(() => _event = null), child: Text(_t('بازگشت به فهرست', 'Back to the list')))),
          ListTile(title: Text('${event['code']} ${event['title']}'), subtitle: Text('${event['event_type']} — ${event['status']}')),
          if (_can('operate') && (event['status'] == 'draft' || event['status'] == 'open')) ...[
            TextButton(onPressed: _invite, child: Text(_t('دعوت تأمین‌کننده', 'Invite suppliers'))),
            if (!(event['event_type'] == 'tender' && event['technical_opened_at'] != null))
              TextButton(onPressed: _internalBid, child: Text(_t('ثبت پیشنهاد داخلی', 'Record a bid'))),
            if (event['requisition_id'] == null && !_maps(event['invites']).any((invite) => invite['bid'] != null))
              TextButton(onPressed: _addSourcingLine, child: Text(_t('قلم جدید', 'Add line'))),
            TextButton(onPressed: _cancelSourcing, child: Text(_t('لغو رویداد', 'Cancel event'))),
          ],
          for (final line in _maps(event['lines']))
            ListTile(
              title: Text('${line['description']}'),
              subtitle: Text(_t(
                'مقدار ${line['qty']}${line['product_id'] == null ? '' : ' — کالا '}${line['product_id'] ?? ''}${line['warehouse_id'] == null ? '' : ' — انبار '}${line['warehouse_id'] ?? ''}',
                'Qty ${line['qty']}${line['product_id'] == null ? '' : ' — product '}${line['product_id'] ?? ''}${line['warehouse_id'] == null ? '' : ' — warehouse '}${line['warehouse_id'] ?? ''}',
              )),
            ),
          if (_can('approve') && event['status'] != 'cancelled' && event['status'] != 'awarded') TextButton(onPressed: _technicalScore, child: Text(_t('امتیاز فنی', 'Technical score'))),
          if (event['event_type'] == 'tender' && _can('approve') && event['status'] != 'cancelled' && event['status'] != 'awarded') ...[
            if (event['technical_opened_at'] == null)
              TextButton(onPressed: () => _run(() async { _event = await _api.openTechnical(widget.businessId, event['id'] as int); }), child: Text(_t('بازگشایی فنی', 'Open technical'))),
            if (event['technical_opened_at'] != null && event['financial_opened_at'] == null && _tenderBidsScored(event))
              TextButton(onPressed: () => _run(() async { _event = await _api.openFinancial(widget.businessId, event['id'] as int); }), child: Text(_t('بازگشایی مالی', 'Open financial'))),
            TextButton(onPressed: _minutes, child: Text(_t('ثبت صورت‌جلسه', 'Record minutes'))),
          ],
          if (_can('view') || _can('approve')) TextButton(onPressed: _compare, child: Text(_t('مقایسه وزنی', 'Weighted comparison'))),
          for (final invite in _maps(event['invites']))
            ListTile(
              title: Text(_t('شخص ${invite['person_id']}', 'Person ${invite['person_id']}')),
              subtitle: Text('${invite['status']} ${invite['bid'] == null ? '' : invite['bid']['total'] ?? _t('قیمت پنهان', 'price sealed')}'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  if (_can('operate') && (event['status'] == 'draft' || event['status'] == 'open')) TextButton(onPressed: () => _shareInvite(invite), child: Text(_t('لینک پیشنهاد', 'Quote link'))),
                  for (final link in _maps(invite['share_links']))
                    if (link['revoked'] != true && _can('operate'))
                      TextButton(onPressed: () => _run(() => _api.revokeShare(widget.businessId, link['id'] as int)), child: Text(_t('ابطال لینک', 'Revoke link'))),
                  if (_can('approve') && (event['status'] == 'draft' || event['status'] == 'open') && invite['status'] == 'responded') TextButton(onPressed: () => _award(event, invite['id'] as int), child: Text(_t('انتخاب', 'Award'))),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _suppliersTab() {
    final rows = _suppliers.where(_matches).toList();
    return _list(
      onAdd: _can('manage') ? _saveSupplier : null,
      empty: _t('پرونده تأمین‌کننده‌ای نیست. هویت در اشخاص می‌ماند و اینجا فقط وضعیت مجاز ساخته می‌شود.', 'No supplier profile yet. The person record stays in People; this list only stores approval status.'),
      children: [
        for (final row in rows)
          ListTile(
            title: Text('${row['person_id']}'),
            subtitle: Text('${row['category'] ?? ''}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                Chip(label: Text('${row['status']}')),
                TextButton(onPressed: () => _supplierDocuments(row), child: Text(_t('مدارک', 'Documents'))),
                if (_can('manage')) TextButton(onPressed: () => _score(row), child: Text(_t('امتیاز', 'Score'))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _budgetsTab() {
    final rows = _budgets.where(_matches).toList();
    return _list(
      onAdd: _can('manage') ? _createBudget : null,
      addLabel: _t('ردیف بودجه', 'Budget line'),
      empty: _t('ردیف بودجه‌ای تعریف نشده است.', 'No procurement budget yet.'),
      children: [
        if (_budgetMovements.any((row) => row['status'] != 'returned')) Text(_t('در انتظار تأیید', 'Awaiting approval'), style: Theme.of(context).textTheme.titleMedium),
        for (final movement in _budgetMovements.where((row) => row['status'] != 'returned' && _matches(row)))
          ListTile(
            title: Text(movement['kind'] == 'increase'
                ? _t('افزایش ${movement['budget_name'] ?? movement['budget_id']}', 'Increase ${movement['budget_name'] ?? movement['budget_id']}')
                : _t('انتقال از ${movement['budget_name'] ?? movement['budget_id']} به ${movement['counter_budget_name'] ?? movement['counter_budget_id']}', 'Transfer from ${movement['budget_name'] ?? movement['budget_id']} to ${movement['counter_budget_name'] ?? movement['counter_budget_id']}')),
            subtitle: Text(_t('مبلغ ${movement['amount']} — ${movement['reason'] ?? ''}', 'Amount ${movement['amount']} — ${movement['reason'] ?? ''}')),
            trailing: _can('approve')
                ? Wrap(
                    spacing: 4,
                    children: [
                      IconButton(tooltip: _t('تأیید', 'Approve'), onPressed: () => _run(() => _api.decide(widget.businessId, 'budget_movement', movement['id'] as int, 'approve')), icon: const Icon(Icons.check)),
                      IconButton(tooltip: _t('برگشت', 'Return'), onPressed: () => _reject('budget_movement', movement['id'] as int, action: 'return'), icon: const Icon(Icons.undo)),
                      IconButton(tooltip: _t('رد', 'Reject'), onPressed: () => _reject('budget_movement', movement['id'] as int), icon: const Icon(Icons.close)),
                    ],
                  )
                : null,
          ),
        if (_budgetMovements.any((row) => row['status'] == 'returned')) Text(_t('برگشت‌خورده', 'Returned'), style: Theme.of(context).textTheme.titleMedium),
        for (final movement in _budgetMovements.where((row) => row['status'] == 'returned' && _matches(row)))
          ListTile(
            title: Text(movement['kind'] == 'increase'
                ? _t('افزایش ${movement['budget_name'] ?? movement['budget_id']}', 'Increase ${movement['budget_name'] ?? movement['budget_id']}')
                : _t('انتقال از ${movement['budget_name'] ?? movement['budget_id']} به ${movement['counter_budget_name'] ?? movement['counter_budget_id']}', 'Transfer from ${movement['budget_name'] ?? movement['budget_id']} to ${movement['counter_budget_name'] ?? movement['counter_budget_id']}')),
            subtitle: Text(_t('مبلغ ${movement['amount']} — ${movement['reason'] ?? ''}', 'Amount ${movement['amount']} — ${movement['reason'] ?? ''}')),
            trailing: _can('operate') ? TextButton(onPressed: () => _resubmitBudget(movement), child: Text(_t('ارسال دوباره', 'Resubmit'))) : null,
          ),
        if (_can('operate') && _budgets.length >= 2)
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: _transferBudget, child: Text(_t('انتقال بین ردیف‌ها', 'Transfer between lines')))),
        for (final row in rows)
          ListTile(
            title: Text('${row['name']} ${row['period_key']}'),
            subtitle: Text(_t('اصل ${row['amount']} — مانده ${row['available']} — رزرو انتقال ${row['pending_transfers'] ?? 0} — تعهد ${row['open_commitments']} — واحد ${row['org_unit_name'] ?? '—'} — پروژه ${row['project_id'] ?? '—'} — مرکز ${row['cost_center_id'] ?? '—'}', 'Original ${row['amount']} — available ${row['available']} — transfer hold ${row['pending_transfers'] ?? 0} — committed ${row['open_commitments']} — unit ${row['org_unit_name'] ?? '—'} — project ${row['project_id'] ?? '—'} — cost center ${row['cost_center_id'] ?? '—'}')),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (row['warn'] == true) Chip(label: Text(_t('هشدار', 'Warning'))),
                if (_can('operate')) TextButton(onPressed: () => _increaseBudget(row), child: Text(_t('افزایش', 'Increase'))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _contractsTab() {
    final rows = _contracts.where(_matches).toList();
    return _list(
      onAdd: _can('manage') ? _createContract : null,
      empty: _t('قراردادی ثبت نشده است.', 'No contracts yet.'),
      children: [
        for (final row in rows)
          ListTile(
            title: Text('${row['code']} ${row['title'] ?? ''}'),
            subtitle: Text(_t(
              'پایان ${row['end_date'] ?? '—'} — سقف ${row['ceiling_amount'] ?? '—'} — آزادشده ${row['released_amount'] ?? 0}${_maps(row['lines']).isEmpty || _asNum(_maps(row['lines']).first['discount_percent']) == 0 ? '' : ' — تخفیف '}${_maps(row['lines']).isEmpty || _asNum(_maps(row['lines']).first['discount_percent']) == 0 ? '' : _maps(row['lines']).first['discount_percent']}${_maps(row['lines']).isEmpty || _asNum(_maps(row['lines']).first['discount_percent']) == 0 ? '' : '٪'}${_maps(row['lines']).isEmpty || _maps(row['lines']).first['warehouse_id'] == null ? '' : ' — انبار '}${_maps(row['lines']).isEmpty || _maps(row['lines']).first['warehouse_id'] == null ? '' : _maps(row['lines']).first['warehouse_id']}',
              'Ends ${row['end_date'] ?? '—'} — ceiling ${row['ceiling_amount'] ?? '—'} — released ${row['released_amount'] ?? 0}${_maps(row['lines']).isEmpty || _asNum(_maps(row['lines']).first['discount_percent']) == 0 ? '' : ' — discount '}${_maps(row['lines']).isEmpty || _asNum(_maps(row['lines']).first['discount_percent']) == 0 ? '' : _maps(row['lines']).first['discount_percent']}${_maps(row['lines']).isEmpty || _asNum(_maps(row['lines']).first['discount_percent']) == 0 ? '' : '%'}${_maps(row['lines']).isEmpty || _maps(row['lines']).first['warehouse_id'] == null ? '' : ' — warehouse '}${_maps(row['lines']).isEmpty || _maps(row['lines']).first['warehouse_id'] == null ? '' : _maps(row['lines']).first['warehouse_id']}',
            )),
            trailing: Wrap(spacing: 4, children: [
              Chip(label: Text('${row['status']}')),
              if (_can('manage') && row['status'] == 'draft')
                IconButton(tooltip: _t('فعال‌سازی', 'Activate'), onPressed: () => _run(() => _api.activateContract(widget.businessId, row['id'] as int)), icon: const Icon(Icons.play_arrow)),
              if (_can('operate') && row['status'] == 'active')
                IconButton(tooltip: _t('آزادسازی سفارش', 'Release order'), onPressed: () => _releaseContract(row), icon: const Icon(Icons.output)),
              if (_can('manage'))
                IconButton(tooltip: _t('ضمانت', 'Guarantee'), onPressed: () => _guarantee(row), icon: const Icon(Icons.verified_user_outlined)),
            ]),
          ),
      ],
    );
  }

  Widget _reorderTab() {
    final rows = _reorder.where(_matches).toList();
    return _list(
      onAdd: _can('operate') ? () => _run(() => _api.refreshReorder(widget.businessId)) : null,
      addLabel: _t('به‌روزرسانی از نقطه سفارش', 'Refresh from reorder point'),
      empty: _t('پیشنهاد بازی نیست. به‌روزرسانی فقط پیش‌نویس نیاز می‌سازد، نه سفارش.', 'No open suggestion. Refresh creates a draft need only after you convert it, never an order.'),
      children: [
        TextButton(onPressed: _lookupSources, child: Text(_t('منابع داخلی کالا', 'Internal product sources'))),
        for (final row in rows)
          ListTile(
            title: Text(_t('کالا ${row['product_id']}', 'Product ${row['product_id']}')),
            subtitle: Text(_t('پیشنهاد ${row['suggested_qty']} — موجودی ${row['on_hand']} — سفارش باز ${row['open_qty']} — مدت تأمین ${row['lead_time_days'] ?? '—'} روز — منبع ${row['source_name'] ?? '—'} — آخرین قیمت ${row['last_price'] ?? '—'}. نقطه سفارش برای کل کالا است، نه هر انبار.', 'Suggested ${row['suggested_qty']} — on hand ${row['on_hand']} — open PO ${row['open_qty']} — lead time ${row['lead_time_days'] ?? '—'} days — source ${row['source_name'] ?? '—'} — last price ${row['last_price'] ?? '—'}. The reorder point is for the whole product, not each warehouse.')),
            trailing: _can('operate') ? TextButton(onPressed: () => _run(() => _api.convertReorder(widget.businessId, row['id'] as int)), child: Text(_t('ساخت درخواست', 'Create need'))) : null,
          ),
      ],
    );
  }

  Widget _list({required List<Widget> children, required String empty, VoidCallback? onAdd, String? addLabel}) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (onAdd != null) Align(alignment: AlignmentDirectional.centerStart, child: FilledButton(onPressed: onAdd, child: Text(addLabel ?? _t('مورد جدید', 'New')))),
        if (children.isEmpty) _empty(empty),
        ...children,
      ],
    );
  }

  Widget _empty(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(text));

  List<String> _ids(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  }

  Widget _settingsTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(title: Text(_t('حالت', 'Mode')), subtitle: Text('${_settings['mode'] ?? ''}')),
        ListTile(title: Text(_t('رواداری مقدار / قیمت', 'Quantity / price tolerance')), subtitle: Text('${_settings['qty_tolerance_pct'] ?? 0} / ${_settings['price_tolerance'] ?? 0}')),
        ListTile(title: Text(_t('بودجه اجباری', 'Budget required')), subtitle: Text('${_settings['budget_required'] == true}')),
        ListTile(title: Text(_t('سفارش مستقیم', 'Direct purchase order')), subtitle: Text('${_settings['allow_direct_po'] == true}')),
        if (_can('manage'))
          FilledButton(onPressed: _editSettings, child: Text(_t('ویرایش تنظیمات', 'Edit settings'))),
        const SizedBox(height: 16),
        Text(_t('مراکز هزینه', 'Cost centers'), style: Theme.of(context).textTheme.titleMedium),
        if (_costCenters.isEmpty) _empty(_t('مرکز هزینه‌ای نیست.', 'No cost center yet.')),
        for (final row in _costCenters) ListTile(title: Text('${row['code']} ${row['name']}')),
        if (_can('manage')) TextButton(onPressed: _addCostCenter, child: Text(_t('مرکز هزینه جدید', 'New cost center'))),
        if (_can('manage')) TextButton(onPressed: _addDelegation, child: Text(_t('جانشین تأییدکننده', 'Approval delegate'))),
      ],
    );
  }

  Future<void> _createRequisition() async {
    final values = await _form(_t('درخواست خرید', 'Purchase need'), [
      _Field('description', _t('شرح', 'Description'), required: true),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '1'),
      _Field('price', _t('برآورد قیمت', 'Estimated price'), number: true, initial: '0'),
      ..._catalogInputs(null),
      _Field('reason', _t('دلیل', 'Reason')),
      _Field('org_unit_name', _t('واحد سازمانی، متنی اگر اتوماسیون خاموش است', 'Org unit name when office automation is off')),
      _Field('file_ids', _t('شناسه فایل‌ها با ویرگول', 'File ids, comma separated')),
    ]);
    if (values == null) return;
    final payload = <String, dynamic>{
      'reason': values['reason'],
      'org_unit_name': values['org_unit_name'],
      'file_ids': _ids(values['file_ids']),
      'lines': [
        _needLine(const {}, values: values),
      ],
    };
    await _saveNeed((body) => _api.createRequisition(widget.businessId, body), payload);
  }

  Future<void> _saveNeed(Future<void> Function(Map<String, dynamic> payload) send, Map<String, dynamic> payload) async {
    try {
      await send(payload);
    } catch (error) {
      if (procurementErrorCode(error) != 'DUPLICATE_BUY_RISK' || !mounted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
        return;
      }
      final accept = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('نیاز پوشیده شده است', 'Demand is already covered')),
          content: Text(_t('موجودی و سفارش باز این مقدار را می‌پوشاند. باز هم ثبت شود؟', 'Stock and open orders already cover this quantity. Save it anyway?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('انصراف', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t('ثبت شود', 'Save anyway'))),
          ],
        ),
      );
      if (accept != true) return;
      payload['acknowledge_duplicate'] = true;
      try {
        await send(payload);
      } catch (retry) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(retry))));
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('انجام شد', 'Done'))));
    await _reload();
  }

  Future<void> _editRequisition(Map<String, dynamic> row) async {
    final lines = _maps(row['lines']);
    final first = lines.isEmpty ? <String, dynamic>{} : lines.first;
    final values = await _form(_t('ویرایش درخواست', 'Edit purchase need'), [
      _Field('description', _t('شرح', 'Description'), required: true, initial: '${first['description'] ?? ''}'),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '${first['qty'] ?? 1}'),
      _Field('price', _t('برآورد قیمت', 'Estimated price'), number: true, initial: '${first['unit_price_estimate'] ?? 0}'),
      ..._catalogInputs(first),
      _Field('reason', _t('دلیل', 'Reason'), initial: '${row['reason'] ?? ''}'),
      _Field('org_unit_name', _t('واحد سازمانی', 'Org unit'), initial: '${row['org_unit_name'] ?? ''}'),
      _Field('file_ids', _t('شناسه فایل‌ها با ویرگول', 'File ids, comma separated'), initial: row['file_ids'] is List ? (row['file_ids'] as List).join(', ') : ''),
    ]);
    if (values == null) return;
    await _saveNeed(
      (body) => _api.updateRequisition(widget.businessId, row['id'] as int, body),
      {
        'reason': values['reason'],
        'org_unit_name': values['org_unit_name'],
        'file_ids': _ids(values['file_ids']),
        'lines': [
          _needLine(first, values: values),
          for (final line in lines.skip(1)) _needLine(line),
        ],
      },
    );
  }

  Future<void> _addNeedLine(Map<String, dynamic> row) async {
    final values = await _form(_t('قلم جدید', 'New line'), [
      _Field('description', _t('شرح', 'Description'), required: true),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '1'),
      _Field('price', _t('برآورد قیمت', 'Estimated price'), number: true, initial: '0'),
      ..._catalogInputs(null),
    ]);
    if (values == null) return;
    await _saveNeed(
      (body) => _api.updateRequisition(widget.businessId, row['id'] as int, body),
      {
        'lines': [
          for (final line in _maps(row['lines'])) _needLine(line),
          _needLine(const {}, values: values),
        ],
      },
    );
  }

  Future<void> _createOrder() async {
    final values = await _form(_t('سفارش مستقیم', 'Direct order'), [
      _Field('person_id', _t('شناسه شخص تأمین‌کننده', 'Supplier person id'), number: true, required: true),
      _Field('description', _t('شرح', 'Description'), required: true),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '1'),
      _Field('price', _t('قیمت واحد', 'Unit price'), number: true, required: true),
      _Field('discount', _t('تخفیف قلم', 'Line discount'), number: true, initial: '0'),
      _Field('tax', _t('مالیات قلم', 'Line tax'), number: true, initial: '0'),
      ..._catalogInputs(null),
      _Field('header_discount', _t('تخفیف سربرگ', 'Header discount'), number: true, initial: '0'),
      _Field('currency_id', _t('شناسه ارز', 'Currency id'), number: true, required: true, help: _t('برای فاکتور بعدی لازم است.', 'Required before invoicing.')),
      _Field('budget_id', _t('شناسه بودجه، اگر اجباری است', 'Budget id if required'), number: true),
      _Field('cost_center_id', _t('شناسه مرکز هزینه', 'Cost center id'), number: true),
      _Field('file_ids', _t('شناسه فایل‌ها با ویرگول', 'File ids, comma separated')),
    ]);
    if (values == null) return;
    await _run(() => _api.createOrder(widget.businessId, {
          'person_id': int.parse(values['person_id']!),
          'currency_id': int.parse(values['currency_id']!),
          'header_discount': num.tryParse(values['header_discount'] ?? '') ?? 0,
          if ((values['budget_id'] ?? '').isNotEmpty) 'budget_id': int.parse(values['budget_id']!),
          if ((values['cost_center_id'] ?? '').isNotEmpty) 'cost_center_id': int.parse(values['cost_center_id']!),
          'file_ids': _ids(values['file_ids']),
          'lines': [
            {
              'description': values['description'],
              'qty': num.parse(values['qty']!),
              'unit_price': num.parse(values['price']!),
              'discount': num.tryParse(values['discount'] ?? '') ?? 0,
              'tax': num.tryParse(values['tax'] ?? '') ?? 0,
              ..._catalogFields(values),
            }
          ],
        }));
  }

  Future<void> _editOrder(Map<String, dynamic> row) async {
    final lines = _maps(row['lines']);
    final first = lines.isEmpty ? <String, dynamic>{} : lines.first;
    final values = await _form(_t('ویرایش سفارش', 'Edit order'), [
      _Field('description', _t('شرح', 'Description'), required: true, initial: '${first['description'] ?? ''}'),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '${first['qty'] ?? 1}'),
      _Field('price', _t('قیمت واحد', 'Unit price'), number: true, required: true, initial: '${first['unit_price'] ?? 0}'),
      _Field('discount', _t('تخفیف قلم', 'Line discount'), number: true, initial: '${first['discount'] ?? 0}'),
      _Field('tax', _t('مالیات قلم', 'Line tax'), number: true, initial: '${first['tax'] ?? 0}'),
      ..._catalogInputs(first),
      _Field('currency_id', _t('شناسه ارز', 'Currency id'), number: true, required: true, initial: '${row['currency_id'] ?? ''}'),
      _Field('budget_id', _t('شناسه بودجه', 'Budget id'), number: true, initial: '${row['budget_id'] ?? ''}'),
      _Field('cost_center_id', _t('شناسه مرکز هزینه', 'Cost center id'), number: true, initial: '${row['cost_center_id'] ?? ''}'),
      _Field('freight', _t('کرایه', 'Freight'), number: true, initial: '${row['freight'] ?? 0}'),
      _Field('header_discount', _t('تخفیف سربرگ', 'Header discount'), number: true, initial: '${row['header_discount'] ?? 0}'),
      _Field('file_ids', _t('شناسه فایل‌ها با ویرگول', 'File ids, comma separated'), initial: row['file_ids'] is List ? (row['file_ids'] as List).join(', ') : ''),
    ]);
    if (values == null) return;
    final edited = _keptOrderLine(
      first,
      description: values['description'],
      qty: num.parse(values['qty']!),
      price: num.parse(values['price']!),
      discount: num.tryParse(values['discount'] ?? '') ?? 0,
      tax: num.tryParse(values['tax'] ?? '') ?? 0,
      itemKind: _itemKind(values['item_kind']),
      productId: _optionalId(values['product_id']),
      warehouseId: _optionalId(values['warehouse_id']),
      replaceCatalog: true,
    );
    await _run(() => _api.updateOrder(widget.businessId, row['id'] as int, {
          'currency_id': int.parse(values['currency_id']!),
          if ((values['budget_id'] ?? '').isNotEmpty) 'budget_id': int.parse(values['budget_id']!),
          if ((values['cost_center_id'] ?? '').isNotEmpty) 'cost_center_id': int.parse(values['cost_center_id']!),
          'freight': num.tryParse(values['freight'] ?? '') ?? 0,
          'header_discount': num.tryParse(values['header_discount'] ?? '') ?? 0,
          'file_ids': _ids(values['file_ids']),
          'lines': [
            edited,
            for (final line in lines.skip(1)) _keptOrderLine(line),
          ],
        }));
  }

  Future<void> _addOrderLine(Map<String, dynamic> row) async {
    final values = await _form(_t('قلم جدید', 'New line'), [
      _Field('description', _t('شرح', 'Description'), required: true),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '1'),
      _Field('price', _t('قیمت واحد', 'Unit price'), number: true, required: true),
      _Field('discount', _t('تخفیف قلم', 'Line discount'), number: true, initial: '0'),
      _Field('tax', _t('مالیات قلم', 'Line tax'), number: true, initial: '0'),
      ..._catalogInputs(null),
    ]);
    if (values == null) return;
    await _run(() => _api.updateOrder(widget.businessId, row['id'] as int, {
          'lines': [
            for (final line in _maps(row['lines'])) _keptOrderLine(line),
            {
              'description': values['description'],
              'qty': num.parse(values['qty']!),
              'unit_price': num.parse(values['price']!),
              'discount': num.tryParse(values['discount'] ?? '') ?? 0,
              'tax': num.tryParse(values['tax'] ?? '') ?? 0,
              ..._catalogFields(values),
            },
          ],
        }));
  }

  Future<void> _invoice(Map<String, dynamic> order) async {
    final lines = _maps(order['lines']).where((line) => line['product_id'] != null && _asNum(line['accepted_qty']) > _asNum(line['invoiced_qty']) + 0.0001).toList();
    if (lines.isEmpty) return;
    final values = await _form(_t('فاکتور خرید', 'Supplier invoice'), [
      for (final line in lines) ...[
        _Field('qty_${line['id']}', _t('مقدار ${line['description']}', 'Quantity ${line['description']}'), number: true, initial: '${_asNum(line['accepted_qty']) - _asNum(line['invoiced_qty'])}'),
        _Field('price_${line['id']}', _t('قیمت پس از تخفیف ${line['description']}', 'Price after discount ${line['description']}'), number: true, initial: '${_payableUnit(order, line)}'),
      ],
      if (_can('approve')) _Field('accept', _t('۱ برای پذیرش اختلاف قیمت', '1 to accept a price difference'), initial: '0'),
    ]);
    if (values == null) return;
    final selected = <Map<String, dynamic>>[];
    for (final line in lines) {
      final qty = num.tryParse(values['qty_${line['id']}'] ?? '') ?? 0;
      final price = num.tryParse(values['price_${line['id']}'] ?? '');
      if (qty <= 0) continue;
      if (price == null) return;
      selected.add({'order_line_id': line['id'], 'qty': qty, 'unit_price': price});
    }
    if (selected.isEmpty) return;
    await _run(() => _api.invoice(widget.businessId, order['id'] as int, {
          'accept_price_variance': _can('approve') && values['accept'] == '1',
          'lines': selected,
        }));
  }

  Future<void> _showToken(Map<String, dynamic> link) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('لینک یک‌بار نمایش', 'Token shown once')),
        content: SelectableText('/public/procurement/${link['token']}'),
        actions: [
          if (link['id'] != null)
            TextButton(
              onPressed: () async {
                try {
                  await _api.revokeShare(widget.businessId, link['id'] as int);
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
                }
              },
              child: Text(_t('ابطال', 'Revoke')),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('بستن', 'Close'))),
        ],
      ),
    );
  }

  Future<void> _openSourcing(int id) async {
    await _run(() async {
      _event = await _api.getSourcing(widget.businessId, id);
    });
  }

  Future<void> _shareInvite(Map<String, dynamic> invite) async {
    try {
      final link = await _api.share(widget.businessId, {
        'kind': 'rfq',
        'entity_id': invite['id'],
        'person_id': invite['person_id'],
      });
      await _showToken(link);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<void> _share(Map<String, dynamic> order) async {
    final values = await _form(_t('لینک تأمین‌کننده', 'Supplier link'), [
      _Field('kind', _t('order یا invoice', 'order or invoice'), initial: 'order', required: true),
    ]);
    if (values == null) return;
    try {
      final link = await _api.share(widget.businessId, {
        'kind': values['kind'] == 'invoice' ? 'invoice' : 'order',
        'entity_id': order['id'],
        'person_id': order['person_id'],
      });
      await _showToken(link);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<void> _receive(Map<String, dynamic> order, Map<String, dynamic> line) async {
    final values = await _form(_t('رسید', 'Receipt'), [
      _Field('qty', _t('مقدار پذیرفته', 'Accepted quantity'), number: true, required: true, initial: '${line['open_qty'] ?? ''}'),
      _Field('rejected', _t('مقدار مردود', 'Rejected quantity'), number: true, initial: '0'),
      _Field('warehouse_id', _t('انبار، برای کالای شناسه‌دار', 'Warehouse for a stocked product'), number: true),
      _Field('qc', _t('accept، conditional یا reject', 'accept, conditional, or reject'), initial: 'accept', required: true),
    ]);
    if (values == null) return;
    await _run(() => _api.receive(widget.businessId, order['id'] as int, {
          'lines': [
            {
              'order_line_id': line['id'],
              'qty': num.parse(values['qty']!),
              'rejected_qty': num.tryParse(values['rejected'] ?? '') ?? 0,
              if ((values['warehouse_id'] ?? '').isNotEmpty) 'warehouse_id': int.parse(values['warehouse_id']!),
              'qc_status': (values['qc'] == 'reject' || values['qc'] == 'conditional') ? values['qc'] : 'accept',
            }
          ],
        }));
  }

  Future<void> _reject(String entityType, int id, {String action = 'reject'}) async {
    final values = await _form(action == 'return' ? _t('دلیل برگشت', 'Return reason') : _t('دلیل رد', 'Rejection reason'), [_Field('note', _t('دلیل', 'Reason'), required: true)]);
    if (values == null) return;
    await _run(() => _api.decide(widget.businessId, entityType, id, action, note: values['note']));
  }

  Future<List<int>?> _askApprovers() async {
    final values = await _form(_t('مسیر تأیید', 'Approval path'), [
      _Field('approvers', _t('شناسه تأییدکنندگان به ترتیب، با ویرگول. خالی یعنی تأییدکننده پیش‌فرض یا هر دارنده مجوز', 'Approver user ids in order, comma separated. Empty uses the default approver, or anyone with permission')),
    ]);
    if (values == null) return null;
    return (values['approvers'] ?? '').split(',').map((item) => int.tryParse(item.trim())).whereType<int>().toList();
  }

  Future<void> _submitRequisition(int id) async {
    final ids = await _askApprovers();
    if (ids == null) return;
    await _run(() => _api.submitRequisition(widget.businessId, id, approverIds: ids));
  }

  Future<void> _submitOrder(int id) async {
    final ids = await _askApprovers();
    if (ids == null) return;
    await _run(() => _api.submitOrder(widget.businessId, id, approverIds: ids));
  }

  Future<void> _orderFromNeed(Map<String, dynamic> row) async {
    final values = await _form(_t('سفارش از درخواست', 'Order from need'), [
      _Field('person_id', _t('شناسه شخص تأمین‌کننده', 'Supplier person id'), number: true, required: true),
      _Field('currency_id', _t('شناسه ارز', 'Currency id'), number: true, required: true),
      _Field('budget_id', _t('شناسه بودجه', 'Budget id'), number: true),
    ]);
    if (values == null) return;
    await _run(() => _api.orderFromRequisition(widget.businessId, row['id'] as int, {
          'person_id': int.parse(values['person_id']!),
          'currency_id': int.parse(values['currency_id']!),
          if ((values['budget_id'] ?? '').isNotEmpty) 'budget_id': int.parse(values['budget_id']!),
        }));
  }

  Future<void> _sourceFromNeed(Map<String, dynamic> row) async {
    final values = await _form(_t('استعلام از درخواست', 'Quotes from this need'), [
      _Field('title', _t('عنوان', 'Title'), required: true, initial: '${row['code'] ?? ''}'),
      _Field('event_type', _t('rfq یا tender', 'rfq or tender'), initial: 'rfq', required: true),
    ]);
    if (values == null) return;
    await _run(() async {
      _event = await _api.createSourcing(widget.businessId, {
        'event_type': values['event_type'] == 'tender' ? 'tender' : 'rfq',
        'title': values['title'],
        'requisition_id': row['id'],
      });
      _tabs.animateTo(3);
    });
  }

  Future<void> _returnLine(Map<String, dynamic> order, Map<String, dynamic> line) async {
    final values = await _form(_t('برگشت به تأمین‌کننده', 'Return to supplier'), [
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '${_asNum(line['accepted_qty']) - _asNum(line['invoiced_qty'])}'),
      _Field('warehouse_id', _t('انبار خروج', 'Issue warehouse'), number: true),
    ]);
    if (values == null) return;
    await _run(() => _api.returnOrder(widget.businessId, order['id'] as int, {
          'lines': [
            {
              'order_line_id': line['id'],
              'qty': num.parse(values['qty']!),
              if ((values['warehouse_id'] ?? '').isNotEmpty) 'warehouse_id': int.parse(values['warehouse_id']!),
            }
          ],
        }));
  }

  Future<void> _prepay(Map<String, dynamic> order) async {
    final values = await _form(_t('اتصال پیش‌پرداخت', 'Link prepayment'), [
      _Field('document_id', _t('شناسه سند پرداخت هسته', 'Core payment document id'), number: true, required: true),
      _Field('amount', _t('مبلغ', 'Amount'), number: true, required: true),
    ]);
    if (values == null) return;
    await _run(() => _api.prepay(widget.businessId, order['id'] as int, {
          'document_id': int.parse(values['document_id']!),
          'amount': num.parse(values['amount']!),
        }));
  }

  Future<void> _resubmitBudget(Map<String, dynamic> movement) async {
    final values = await _form(_t('ارسال دوباره', 'Resubmit'), [
      _Field('amount', _t('مبلغ', 'Amount'), number: true, required: true, initial: '${movement['amount'] ?? ''}'),
      _Field('reason', _t('دلیل', 'Reason'), required: true, initial: '${movement['reason'] ?? ''}'),
      _Field('approvers', _t('شناسه تأییدکنندگان، با ویرگول', 'Approver user ids, comma separated')),
    ]);
    if (values == null) return;
    final approvers = (values['approvers'] ?? '').split(',').map((item) => int.tryParse(item.trim())).whereType<int>().toList();
    await _run(() => _api.resubmitBudgetMovement(widget.businessId, movement['id'] as int, {
          'amount': num.parse(values['amount']!),
          'reason': values['reason'],
          'approver_user_ids': approvers,
        }));
  }

  Future<void> _increaseBudget(Map<String, dynamic> row) async {
    final values = await _form(_t('افزایش بودجه', 'Budget increase'), [
      _Field('amount', _t('مبلغ', 'Amount'), number: true, required: true),
      _Field('reason', _t('دلیل', 'Reason'), required: true),
      _Field('approvers', _t('شناسه تأییدکنندگان، با ویرگول', 'Approver user ids, comma separated')),
    ]);
    if (values == null) return;
    final approvers = (values['approvers'] ?? '').split(',').map((item) => int.tryParse(item.trim())).whereType<int>().toList();
    try {
      final created = await _api.increaseBudget(widget.businessId, row['id'] as int, {
        'amount': num.parse(values['amount']!),
        'reason': values['reason'],
        'approver_user_ids': approvers,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('درخواست ثبت شد', 'Request saved')),
          content: Text(_t('اگر الان تأیید نکنید، درخواست در فهرست «در انتظار تأیید» می‌ماند.', 'If you do not approve it now, the request stays under Awaiting approval.')),
          actions: [
            if (_can('approve'))
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _run(() => _api.decide(widget.businessId, 'budget_movement', created['id'] as int, 'approve'));
                },
                child: Text(_t('تأیید همین حالا', 'Approve now')),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('بستن', 'Close'))),
          ],
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<void> _transferBudget() async {
    final values = await _form(_t('انتقال بودجه', 'Budget transfer'), [
      _Field('from_budget_id', _t('شناسه مبدأ', 'Source budget id'), number: true, required: true),
      _Field('to_budget_id', _t('شناسه مقصد', 'Target budget id'), number: true, required: true),
      _Field('amount', _t('مبلغ', 'Amount'), number: true, required: true),
      _Field('reason', _t('دلیل', 'Reason'), required: true),
      _Field('approvers', _t('شناسه تأییدکنندگان، با ویرگول', 'Approver user ids, comma separated')),
    ]);
    if (values == null) return;
    final approvers = (values['approvers'] ?? '').split(',').map((item) => int.tryParse(item.trim())).whereType<int>().toList();
    try {
      final created = await _api.transferBudget(widget.businessId, {
        'from_budget_id': int.parse(values['from_budget_id']!),
        'to_budget_id': int.parse(values['to_budget_id']!),
        'amount': num.parse(values['amount']!),
        'reason': values['reason'],
        'approver_user_ids': approvers,
      });
      if (!mounted) return;
      final movementId = created['transfer_out_id'] as int;
      final approve = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('انتقال در انتظار تأیید', 'Transfer awaits approval')),
          content: Text(_t('اگر بعداً بگذارید، خروج انتقال در فهرست «در انتظار تأیید» می‌ماند.', 'Choosing later keeps the outgoing transfer under Awaiting approval.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('بعداً', 'Later'))),
            if (_can('approve')) FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t('تأیید', 'Approve'))),
          ],
        ),
      );
      if (approve == true) {
        await _run(() => _api.decide(widget.businessId, 'budget_movement', movementId, 'approve'));
      } else {
        await _reload();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<void> _releaseContract(Map<String, dynamic> row) async {
    final lines = _maps(row['lines']);
    if (lines.isEmpty) return;
    final values = await _form(_t('آزادسازی قرارداد', 'Release contract'), [
      _Field('contract_line_id', _t('شناسه قلم', 'Contract line id'), number: true, required: true, initial: '${lines.first['id']}'),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '1'),
      _Field('currency_id', _t('شناسه ارز، اگر قرارداد ارز ندارد', 'Currency id if the contract has none'), number: true),
    ]);
    if (values == null) return;
    await _run(() => _api.releaseContract(widget.businessId, row['id'] as int, {
          if ((values['currency_id'] ?? '').isNotEmpty) 'currency_id': int.parse(values['currency_id']!),
          'lines': [
            {'contract_line_id': int.parse(values['contract_line_id']!), 'qty': num.parse(values['qty']!)}
          ],
        }));
  }

  Future<void> _guarantee(Map<String, dynamic> row) async {
    final values = await _form(_t('ضمانت قرارداد', 'Contract guarantee'), [
      _Field('amount', _t('مبلغ', 'Amount'), number: true, required: true),
      _Field('kind', _t('نوع', 'Kind'), initial: 'performance'),
    ]);
    if (values == null) return;
    await _run(() => _api.addGuarantee(widget.businessId, {
          'contract_id': row['id'],
          'amount': num.parse(values['amount']!),
          'kind': values['kind'],
        }));
  }

  Future<void> _editSettings() async {
    final values = await _form(_t('تنظیمات تدارکات', 'Procurement settings'), [
      _Field('mode', _t('small، standard یا enterprise', 'small, standard, or enterprise'), initial: '${_settings['mode'] ?? 'standard'}', required: true),
      _Field('qty_tolerance_pct', _t('رواداری مقدار درصد', 'Quantity tolerance percent'), number: true, initial: '${_settings['qty_tolerance_pct'] ?? 0}'),
      _Field('price_tolerance', _t('رواداری قیمت', 'Price tolerance'), number: true, initial: '${_settings['price_tolerance'] ?? 0}'),
      _Field('budget_required', _t('۱ اگر بودجه اجباری است', '1 if a budget is required'), initial: _settings['budget_required'] == true ? '1' : '0'),
      _Field('allow_direct_po', _t('۱ اگر سفارش مستقیم مجاز است', '1 if a direct order is allowed'), initial: _settings['allow_direct_po'] == true ? '1' : '0'),
      _Field('require_approved_supplier', _t('۱ اگر تأمین‌کننده باید تأییدشده باشد', '1 if the supplier must be approved'), initial: _settings['require_approved_supplier'] == true ? '1' : '0'),
      _Field('default_approver_user_id', _t('شناسه تأییدکننده پیش‌فرض', 'Default approver user id'), number: true, initial: '${_settings['default_approver_user_id'] ?? ''}'),
    ]);
    if (values == null) return;
    final mode = values['mode'];
    await _run(() => _api.updateSettings(widget.businessId, {
          if (mode == 'small' || mode == 'standard' || mode == 'enterprise') 'mode': mode,
          'qty_tolerance_pct': num.tryParse(values['qty_tolerance_pct'] ?? '') ?? 0,
          'price_tolerance': num.tryParse(values['price_tolerance'] ?? '') ?? 0,
          'budget_required': values['budget_required'] == '1',
          'allow_direct_po': values['allow_direct_po'] == '1',
          'require_approved_supplier': values['require_approved_supplier'] == '1',
          'default_approver_user_id': int.tryParse(values['default_approver_user_id'] ?? ''),
        }));
  }

  Future<void> _addCostCenter() async {
    final values = await _form(_t('مرکز هزینه', 'Cost center'), [
      _Field('code', _t('کد', 'Code'), required: true),
      _Field('name', _t('نام', 'Name'), required: true),
    ]);
    if (values == null) return;
    await _run(() => _api.createCostCenter(widget.businessId, {'code': values['code'], 'name': values['name']}));
  }

  Future<void> _addDelegation() async {
    final values = await _form(_t('جانشینی', 'Delegation'), [
      _Field('user_id', _t('شناسه تأییدکننده اصلی', 'Original approver user id'), number: true, required: true),
      _Field('delegate_user_id', _t('شناسه جانشین', 'Delegate user id'), number: true, required: true),
    ]);
    if (values == null) return;
    await _run(() => _api.createDelegation(widget.businessId, {
          'user_id': int.parse(values['user_id']!),
          'delegate_user_id': int.parse(values['delegate_user_id']!),
        }));
  }

  Future<void> _supplierDocuments(Map<String, dynamic> row) async {
    try {
      final data = await _api.listSupplierDocuments(widget.businessId, row['id'] as int);
      if (!mounted) return;
      final items = _maps(data['items']);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('مدارک تأمین‌کننده', 'Supplier documents')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (items.isEmpty) Text(_t('مدرکی ثبت نشده است.', 'No documents yet.')),
                for (final item in items)
                  ListTile(
                    title: Text('${item['title']}'),
                    subtitle: Text(_t('انقضا ${item['expires_on'] ?? '—'}${item['expires_on'] is String && (item['expires_on'] as String).compareTo(DateTime.now().toIso8601String().substring(0, 10)) < 0 ? ' — منقضی' : ''} — فایل ${item['file_id'] ?? '—'}', 'Expires ${item['expires_on'] ?? '—'}${item['expires_on'] is String && (item['expires_on'] as String).compareTo(DateTime.now().toIso8601String().substring(0, 10)) < 0 ? ' — expired' : ''} — file ${item['file_id'] ?? '—'}')),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('بستن', 'Close'))),
            if (_can('manage'))
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _supplierDocument(row);
                },
                child: Text(_t('مدرک جدید', 'Add document')),
              ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<void> _supplierDocument(Map<String, dynamic> row) async {
    final values = await _form(_t('مدرک تأمین‌کننده', 'Supplier document'), [
      _Field('title', _t('عنوان', 'Title'), required: true),
      _Field('file_id', _t('شناسه فایل', 'File id')),
      _Field('expires_on', _t('تاریخ انقضا', 'Expiry date')),
    ]);
    if (values == null) return;
    await _run(() => _api.addSupplierDocument(widget.businessId, row['id'] as int, {
          'title': values['title'],
          if ((values['file_id'] ?? '').isNotEmpty) 'file_id': values['file_id'],
          if ((values['expires_on'] ?? '').isNotEmpty) 'expires_on': values['expires_on'],
        }));
  }

  Future<void> _score(Map<String, dynamic> row) async {
    final now = DateTime.now();
    final values = await _form(_t('امتیاز دوره', 'Period score'), [
      _Field('period_key', _t('دوره، مثل 2026-11', 'Period, such as 2026-11'), required: true, initial: '${now.year}-${now.month.toString().padLeft(2, '0')}'),
    ]);
    if (values == null) return;
    try {
      final scored = await _api.scoreSupplier(widget.businessId, row['person_id'] as int, periodKey: values['period_key']);
      if (!mounted) return;
      final metrics = scored['metrics'] is Map ? Map<String, dynamic>.from(scored['metrics'] as Map) : <String, dynamic>{};
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('امتیاز ${scored['period_key']}', 'Score ${scored['period_key']}')),
          content: Text(_t('${scored['grade']} — ${scored['total']}\nکیفیت ${metrics['quality'] ?? '—'}، تحویل ${metrics['delivery'] ?? '—'}، قیمت ${metrics['price'] ?? '—'}', '${scored['grade']} — ${scored['total']}\nQuality ${metrics['quality'] ?? '—'}, delivery ${metrics['delivery'] ?? '—'}, price ${metrics['price'] ?? '—'}')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('بستن', 'Close')))],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<void> _internalBid() async {
    final event = _event;
    if (event == null) return;
    final invites = _maps(event['invites']);
    final lines = _maps(event['lines']);
    if (invites.isEmpty || lines.isEmpty) return;
    final values = await _form(_t('پیشنهاد', 'Bid'), [
      _Field('invite_id', _t('شناسه دعوت', 'Invite id'), number: true, required: true, initial: '${invites.first['id']}'),
      for (final line in lines)
        _Field('price_${line['id']}', _t('قیمت ${line['description']} × ${line['qty']}', 'Price ${line['description']} × ${line['qty']}'), number: true, required: true),
      _Field('freight', _t('کرایه', 'Freight'), number: true, initial: '0'),
      _Field('tax', _t('مالیات', 'Tax'), number: true, initial: '0'),
      _Field('discount', _t('تخفیف', 'Discount'), number: true, initial: '0'),
      _Field('warranty', _t('ضمانت', 'Warranty')),
      _Field('delivery_days', _t('روز تحویل', 'Delivery days'), number: true, initial: '7'),
      _Field('payment_days', _t('مهلت پرداخت', 'Payment days'), number: true, initial: '30'),
    ]);
    if (values == null) return;
    await _run(() async {
      await _api.submitBid(widget.businessId, int.parse(values['invite_id']!), {
        'delivery_days': int.tryParse(values['delivery_days'] ?? '') ?? 0,
        'payment_days': int.tryParse(values['payment_days'] ?? '') ?? 0,
        'freight': num.tryParse(values['freight'] ?? '') ?? 0,
        'tax': num.tryParse(values['tax'] ?? '') ?? 0,
        'discount': num.tryParse(values['discount'] ?? '') ?? 0,
        if ((values['warranty'] ?? '').isNotEmpty) 'warranty': values['warranty'],
        'lines': [
          for (final line in lines) {'sourcing_line_id': line['id'], 'unit_price': num.parse(values['price_${line['id']}']!)}
        ],
      });
      _event = await _api.getSourcing(widget.businessId, event['id'] as int);
    });
  }

  Future<void> _technicalScore() async {
    final event = _event;
    if (event == null) return;
    final values = await _form(_t('امتیاز فنی', 'Technical score'), [
      _Field('invite_id', _t('شناسه دعوت', 'Invite id'), number: true, required: true),
      _Field('technical_score', _t('امتیاز ۰ تا ۱۰۰', 'Score from 0 to 100'), number: true, required: true),
    ]);
    if (values == null) return;
    await _run(() async {
      _event = await _api.technicalScores(widget.businessId, event['id'] as int, {
        'scores': [
          {'invite_id': int.parse(values['invite_id']!), 'technical_score': num.parse(values['technical_score']!)}
        ],
      });
    });
  }

  Future<void> _lookupSources() async {
    final values = await _form(_t('منابع کالا', 'Product sources'), [_Field('product_id', _t('شناسه کالا', 'Product id'), number: true, required: true)]);
    if (values == null) return;
    try {
      final result = await _api.productSources(widget.businessId, int.parse(values['product_id']!));
      if (!mounted) return;
      final items = _maps(result['items']);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('تأمین‌کنندگان همین کسب‌وکار', 'Suppliers already in this business')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (items.isEmpty) Text(_t('منبع ترجیحی یا قیمت سفارش قبلی نیست.', 'There is no preferred source or previous order price.')),
              for (final item in items) ListTile(title: Text('${item['name'] ?? item['person_id']}'), subtitle: Text(_t('آخرین قیمت ${item['last_price'] ?? '—'}', 'Last price ${item['last_price'] ?? '—'}'))),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('بستن', 'Close')))],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<void> _createSourcing() async {
    final values = await _form(_t('رویداد خرید', 'Sourcing event'), [
      _Field('title', _t('عنوان', 'Title'), required: true),
      _Field('event_type', _t('rfq یا tender', 'rfq or tender'), initial: 'rfq', required: true),
      _Field('description', _t('شرح قلم', 'Line description'), required: true),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '1'),
      ..._catalogInputs(null),
    ]);
    if (values == null) return;
    final type = values['event_type'] == 'tender' ? 'tender' : 'rfq';
    await _run(() async {
      _event = await _api.createSourcing(widget.businessId, {
        'event_type': type,
        'title': values['title'],
        'lines': [
          {'description': values['description'], 'qty': num.parse(values['qty']!), ..._catalogFields(values)}
        ],
      });
    });
  }

  Future<void> _addSourcingLine() async {
    final event = _event;
    if (event == null) return;
    final values = await _form(_t('قلم جدید', 'New line'), [
      _Field('description', _t('شرح', 'Description'), required: true),
      _Field('qty', _t('مقدار', 'Quantity'), number: true, required: true, initial: '1'),
      ..._catalogInputs(null),
    ]);
    if (values == null) return;
    await _run(() async {
      _event = await _api.addSourcingLines(widget.businessId, event['id'] as int, [
        {'description': values['description'], 'qty': num.parse(values['qty']!), ..._catalogFields(values)},
      ]);
    });
  }

  Future<void> _cancelSourcing() async {
    final event = _event;
    if (event == null) return;
    final values = await _form(_t('لغو رویداد', 'Cancel event'), [_Field('reason', _t('دلیل', 'Reason'), required: true)]);
    if (values == null) return;
    await _run(() async {
      _event = await _api.cancelSourcing(widget.businessId, event['id'] as int, reason: values['reason']);
    });
  }

  Future<void> _invite() async {
    final event = _event;
    if (event == null) return;
    final values = await _form(_t('دعوت', 'Invite'), [_Field('ids', _t('شناسه اشخاص، با ویرگول', 'Person ids, comma separated'), required: true)]);
    if (values == null) return;
    final ids = values['ids']!.split(',').map((item) => int.tryParse(item.trim())).whereType<int>().toList();
    if (ids.isEmpty) return;
    await _run(() async {
      _event = await _api.invite(widget.businessId, event['id'] as int, ids);
    });
  }

  Future<void> _compare() async {
    final event = _event;
    if (event == null) return;
    try {
      final result = await _api.compare(widget.businessId, event['id'] as int);
      if (!mounted) return;
      final ranking = _maps(result['ranking']);
      final invites = _maps((result['matrix'] as Map?)?['invites']);
      final people = {for (final invite in invites) invite['id']: invite['person_id']};
      String label(String key) {
        switch (key) {
          case 'price':
            return _t('قیمت', 'Price');
          case 'delivery':
            return _t('تحویل', 'Delivery');
          case 'payment':
            return _t('پرداخت', 'Payment');
          case 'quality':
            return _t('کیفیت', 'Quality');
          case 'risk':
            return _t('ریسک', 'Risk');
          default:
            return key;
        }
      }
      Map<String, dynamic> asMap(dynamic raw) => raw is Map ? Map<String, dynamic>.from(raw) : {};
      final weights = ranking.isEmpty ? <String, dynamic>{} : asMap(ranking.first['weights']);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('رتبه‌بندی وزنی', 'Weighted ranking')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (result['quality_period'] != null)
                    Text(_t('کیفیت از امتیاز دوره ${result['quality_period']}', 'Quality uses the score for ${result['quality_period']}')),
                  if (weights.isNotEmpty)
                    Text('${_t('وزن مؤثر', 'Applied weight')}: ${weights.entries.map((item) => '${label(item.key)} ${item.value}').join(' · ')}'),
                  for (final row in ranking)
                    ListTile(
                      title: Text(_t('رتبه ${row['rank']} · شخص ${people[row['invite_id']] ?? row['invite_id']}', 'Rank ${row['rank']} · person ${people[row['invite_id']] ?? row['invite_id']}')),
                      trailing: Text('${row['total']}'),
                      subtitle: Text(asMap(row['parts']).entries.map((item) => '${label(item.key)} ${item.value}').join(' · ')),
                    ),
                  if (ranking.isEmpty) Text(_t('پیشنهادی برای مقایسه نیست.', 'There is no bid to compare.')),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('بستن', 'Close')))],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Future<void> _minutes() async {
    final event = _event;
    if (event == null) return;
    final values = await _form(_t('صورت‌جلسه', 'Minutes'), [_Field('minutes', _t('متن جلسه', 'Committee notes'), required: true)]);
    if (values == null) return;
    await _run(() async {
      _event = await _api.minutes(widget.businessId, event['id'] as int, values['minutes']!);
    });
  }

  Future<void> _award(Map<String, dynamic> event, int inviteId) async {
    final values = await _form(_t('انتخاب برنده', 'Award'), [
      _Field('reason', _t('دلیل انتخاب', 'Award reason'), required: true),
      _Field('currency_id', _t('شناسه ارز سفارش', 'Order currency id'), number: true, required: true),
    ]);
    if (values == null) return;
    await _run(() async {
      final result = await _api.award(widget.businessId, event['id'] as int, {
        'invite_id': inviteId,
        'reason': values['reason'],
        'currency_id': int.parse(values['currency_id']!),
      });
      _event = result['event'] is Map ? Map<String, dynamic>.from(result['event'] as Map) : _event;
    });
  }

  Future<void> _saveSupplier() async {
    final values = await _form(_t('پرونده تأمین‌کننده', 'Supplier profile'), [
      _Field('person_id', _t('شناسه شخص', 'Person id'), number: true, required: true),
      _Field('status', _t('prospective، review، approved، suspended یا ended', 'prospective, review, approved, suspended, or ended'), initial: 'approved', required: true),
      _Field('category', _t('دسته', 'Category')),
    ]);
    if (values == null) return;
    await _run(() => _api.saveSupplier(widget.businessId, {
          'person_id': int.parse(values['person_id']!),
          'status': values['status'],
          'category': values['category'],
        }));
  }

  Future<void> _createBudget() async {
    final values = await _form(_t('بودجه خرید', 'Purchase budget'), [
      _Field('name', _t('نام', 'Name'), required: true),
      _Field('amount', _t('مبلغ', 'Amount'), number: true, required: true),
      _Field('period_key', _t('دوره، مثل 2026-11', 'Period, such as 2026-11'), required: true),
      _Field('org_unit_name', _t('واحد سازمانی', 'Org unit')),
      _Field('project_id', _t('شناسه پروژه', 'Project id'), number: true),
      _Field('cost_center_id', _t('شناسه مرکز هزینه', 'Cost center id'), number: true),
    ]);
    if (values == null) return;
    await _run(() => _api.createBudget(widget.businessId, {
          'name': values['name'],
          'amount': num.parse(values['amount']!),
          'period_key': values['period_key'],
          if ((values['org_unit_name'] ?? '').isNotEmpty) 'org_unit_name': values['org_unit_name'],
          if ((values['project_id'] ?? '').isNotEmpty) 'project_id': int.parse(values['project_id']!),
          if ((values['cost_center_id'] ?? '').isNotEmpty) 'cost_center_id': int.parse(values['cost_center_id']!),
        }));
  }

  Future<void> _createContract() async {
    final values = await _form(_t('قرارداد', 'Contract'), [
      _Field('title', _t('عنوان', 'Title'), required: true),
      _Field('person_id', _t('شناسه شخص', 'Person id'), number: true, required: true),
      _Field('qty', _t('سقف مقدار', 'Quantity ceiling'), number: true, required: true, initial: '1'),
      _Field('unit_price', _t('قیمت واحد', 'Unit price'), number: true, required: true),
      _Field('discount_percent', _t('درصد تخفیف قلم', 'Line discount percent'), number: true, initial: '0'),
      _Field('product_id', _t('شناسه کالا، برای رسید آزادسازی', 'Product id, for a stocked release'), number: true),
      _Field('warehouse_id', _t('شناسه انبار', 'Warehouse id'), number: true),
      _Field('ceiling_amount', _t('سقف ریالی، اگر هست', 'Money ceiling, if any'), number: true),
      _Field('end_date', _t('تاریخ پایان میلادی', 'End date, YYYY-MM-DD')),
    ]);
    if (values == null) return;
    await _run(() => _api.createContract(widget.businessId, {
          'title': values['title'],
          'person_id': int.parse(values['person_id']!),
          if ((values['ceiling_amount'] ?? '').isNotEmpty) 'ceiling_amount': num.parse(values['ceiling_amount']!),
          if ((values['end_date'] ?? '').isNotEmpty) 'end_date': values['end_date'],
          'lines': [
            {
              'description': values['title'],
              'qty': num.parse(values['qty']!),
              'unit_price': num.parse(values['unit_price']!),
              'discount_percent': num.tryParse(values['discount_percent'] ?? '') ?? 0,
              if (_optionalId(values['product_id']) != null) 'product_id': _optionalId(values['product_id']),
              if (_optionalId(values['warehouse_id']) != null) 'warehouse_id': _optionalId(values['warehouse_id']),
            }
          ],
        }));
  }
}

class _Field {
  final String key;
  final String label;
  final bool required;
  final bool number;
  final String? initial;
  final String? help;

  _Field(this.key, this.label, {this.required = false, this.number = false, this.initial, this.help});
}
