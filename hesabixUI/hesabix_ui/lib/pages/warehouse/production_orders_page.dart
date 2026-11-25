import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../models/production_order_models.dart';
import '../../services/production_order_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/snackbar_helper.dart';
import '../../widgets/data_table/data_table.dart';
import 'production_order_form_dialog.dart';

class ProductionOrdersPage extends StatefulWidget {
  final int businessId;
  const ProductionOrdersPage({super.key, required this.businessId});

  @override
  State<ProductionOrdersPage> createState() => _ProductionOrdersPageState();
}

class _ProductionOrdersPageState extends State<ProductionOrdersPage> {
  final _svc = ProductionOrderService();
  CalendarController? get _calendar => ApiClient.getCalendarController();
  AuthStore? get _auth => ApiClient.getAuthStore();
  bool get _canWrite =>
      _auth?.hasBusinessPermission('inventory', 'write') ?? false;
  bool get _canRead => _auth?.canReadSection('inventory') ?? _canWrite;

  List<Map<String, dynamic>> _rows = const [];
  int _page = 1;
  int _pageSize = 20;
  int _total = 0;
  bool _loading = false;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  ProductionOrder _asOrder(dynamic item) {
    if (item is ProductionOrder) return item;
    return ProductionOrder.fromJson(Map<String, dynamic>.from(item as Map));
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.list(
        businessId: widget.businessId,
        status: _statusFilter,
        skip: (_page - 1) * _pageSize,
        take: _pageSize,
      );
      final items = List<Map<String, dynamic>>.from(
        (data['items'] as List?)?.map(
              (e) => Map<String, dynamic>.from(e as Map),
            ) ??
            const [],
      );
      if (!mounted) return;
      setState(() {
        _rows = items;
        _total = (data['total'] as num?)?.toInt() ?? items.length;
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            'خطا در بارگذاری سفارش‌ها: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductionOrderFormDialog(businessId: widget.businessId),
    );
    if (result == true) _refresh();
  }

  Future<void> _openMaterialPlan() async {
    try {
      final data = await _svc.getMaterialPlan(businessId: widget.businessId);
      if (!mounted) return;
      final rows = (data['items'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('برنامهٔ مواد سفارش‌های فعال'),
          content: SizedBox(
            width: 1050,
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'برای سفارش‌های آزادشده یا در حال اجرا نیازی ثبت نشده است.',
                    ),
                  )
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('ماده')),
                          DataColumn(label: Text('انبار')),
                          DataColumn(label: Text('نیاز باقی‌مانده')),
                          DataColumn(label: Text('رزروشده')),
                          DataColumn(label: Text('موجودی فیزیکی')),
                          DataColumn(label: Text('کسری تأمین')),
                          DataColumn(label: Text('پیشنهاد')),
                        ],
                        rows: rows.map((row) {
                          final shortage =
                              (row['shortage_quantity'] as num?)?.toDouble() ??
                              0;
                          final action =
                              row['suggested_action']?.toString() ?? 'none';
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  '${row['product_name'] ?? '-'}${row['product_code'] == null ? '' : ' (${row['product_code']})'}',
                                ),
                              ),
                              DataCell(
                                Text(row['warehouse_name']?.toString() ?? '-'),
                              ),
                              DataCell(
                                Text(
                                  formatWithThousands(row['required_quantity']),
                                ),
                              ),
                              DataCell(
                                Text(
                                  formatWithThousands(row['reserved_quantity']),
                                ),
                              ),
                              DataCell(
                                Text(
                                  formatWithThousands(
                                    row['physical_available_quantity'],
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  formatWithThousands(shortage),
                                  style: TextStyle(
                                    color: shortage > 0
                                        ? SemanticColorResolver.negative(
                                            context,
                                          )
                                        : null,
                                    fontWeight: shortage > 0
                                        ? FontWeight.w700
                                        : null,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(switch (action) {
                                  'manufacture' => 'تولید',
                                  'purchase' => 'خرید',
                                  _ => 'کافی',
                                }),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('بستن'),
            ),
          ],
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

  Future<void> _openLotTrace() async {
    final controller = TextEditingController();
    String? lotCode;
    try {
      lotCode = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ردیابی بچ/لات تولید'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 64,
            decoration: const InputDecoration(
              labelText: 'کد بچ/لات',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('جست‌وجو'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (lotCode == null || lotCode.isEmpty || !mounted) return;

    try {
      final data = await _svc.traceLot(
        businessId: widget.businessId,
        lotCode: lotCode,
      );
      if (!mounted) return;
      final orders = (data['orders'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('نتیجهٔ ردیابی: $lotCode'),
          content: SizedBox(
            width: 620,
            child: orders.isEmpty
                ? const Center(child: Text('سفارشی با این کد بچ/لات پیدا نشد.'))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final order = ProductionOrder.fromJson(orders[index]);
                      return ListTile(
                        title: Text(
                          '${order.code} · ${order.productName ?? '#${order.productId}'}',
                        ),
                        subtitle: Text(
                          '${productionOrderStatusLabel(order.status)} · '
                          '${formatWithThousands(order.producedQuantity)} از '
                          '${formatWithThousands(order.plannedQuantity)}',
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          _openDetails(order);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('بستن'),
            ),
          ],
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

  void _openDetails(ProductionOrder order) {
    context.push(
      context.businessPanelUrl(
        widget.businessId,
        'production-orders/${order.id}',
      ),
    );
  }

  Future<void> _runAction(
    ProductionOrder order,
    Future<ProductionOrder> Function() op,
    String success,
  ) async {
    try {
      await op();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: success);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Color? _statusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.blueGrey;
      case 'released':
        return Colors.indigo;
      case 'in_progress':
        return SemanticColorResolver.warning(context);
      case 'completed':
        return SemanticColorResolver.positive(context);
      case 'cancelled':
        return SemanticColorResolver.negative(context);
      default:
        return null;
    }
  }

  DataTableConfig<ProductionOrder> _buildTableConfig() {
    final actions = <DataTableAction>[
      DataTableAction(
        icon: Icons.visibility,
        label: 'مشاهده',
        onTap: (item) => _openDetails(_asOrder(item)),
      ),
      if (_canWrite)
        DataTableAction(
          icon: Icons.lock_open,
          label: 'آزادسازی',
          onTap: (item) {
            final o = _asOrder(item);
            _runAction(
              o,
              () => _svc.release(
                businessId: widget.businessId,
                orderId: o.id,
                version: o.version,
              ),
              'سفارش آزادسازی شد',
            );
          },
          enabled: (item) => _asOrder(item).isDraft,
        ),
      if (_canWrite)
        DataTableAction(
          icon: Icons.play_arrow,
          label: 'شروع',
          onTap: (item) {
            final o = _asOrder(item);
            _runAction(
              o,
              () => _svc.start(
                businessId: widget.businessId,
                orderId: o.id,
                version: o.version,
              ),
              'سفارش شروع شد',
            );
          },
          enabled: (item) => _asOrder(item).isReleased,
        ),
      if (_canWrite)
        DataTableAction(
          icon: Icons.check_circle_outline,
          label: 'تکمیل',
          onTap: (item) {
            final o = _asOrder(item);
            _runAction(
              o,
              () => _svc.complete(
                businessId: widget.businessId,
                orderId: o.id,
                version: o.version,
              ),
              'سفارش تکمیل شد',
            );
          },
          enabled: (item) {
            final order = _asOrder(item);
            return order.isInProgress &&
                order.outputs.every(
                  (o) => o.producedQuantity >= o.plannedQuantity,
                );
          },
        ),
      if (_canWrite)
        DataTableAction(
          icon: Icons.cancel_outlined,
          label: 'لغو',
          isDestructive: true,
          onTap: (item) {
            final o = _asOrder(item);
            _runAction(
              o,
              () => _svc.cancel(
                businessId: widget.businessId,
                orderId: o.id,
                version: o.version,
              ),
              'سفارش لغو شد',
            );
          },
          enabled: (item) {
            final o = _asOrder(item);
            return o.isDraft || o.isReleased || o.isInProgress;
          },
        ),
    ];

    final isJalali = _calendar?.isJalali ?? true;
    return DataTableConfig<ProductionOrder>(
      endpoint: 'local_production_orders',
      tableId: 'production_orders_table',
      title: 'سفارش‌های تولید',
      showSearch: false,
      showFilters: false,
      showColumnSearch: false,
      showExportButtons: false,
      showRowNumbers: true,
      enableSorting: false,
      enableGlobalSearch: false,
      enableHorizontalScroll: true,
      columns: [
        ActionColumn('actions', 'عملیات', actions: actions),
        TextColumn(
          'code',
          'کد',
          formatter: (item) => _asOrder(item).code,
          width: ColumnWidth.medium,
        ),
        CustomColumn(
          'status',
          'وضعیت',
          sortable: false,
          searchable: false,
          width: ColumnWidth.medium,
          builder: (item, index) {
            final o = _asOrder(item);
            final color = _statusColor(o.status);
            return Chip(
              label: Text(productionOrderStatusLabel(o.status)),
              backgroundColor: color?.withValues(alpha: 0.12),
              labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
              visualDensity: VisualDensity.compact,
            );
          },
        ),
        TextColumn(
          'product',
          'کالا',
          formatter: (item) {
            final o = _asOrder(item);
            return o.productName ?? '#${o.productId}';
          },
          width: ColumnWidth.large,
        ),
        NumberColumn(
          'planned',
          'برنامه',
          formatter: (item) =>
              formatWithThousands(_asOrder(item).plannedQuantity),
          width: ColumnWidth.small,
        ),
        NumberColumn(
          'produced',
          'تولیدشده',
          formatter: (item) =>
              formatWithThousands(_asOrder(item).producedQuantity),
          width: ColumnWidth.small,
        ),
        TextColumn(
          'priority',
          'اولویت',
          formatter: (item) => '${_asOrder(item).priority}',
          width: ColumnWidth.small,
        ),
        DateColumn(
          'due_date',
          'موعد',
          formatter: (item) => HesabixDateUtils.formatApiDateForDisplay(
            _asOrder(item).dueDate,
            isJalali,
            fallback: '-',
          ),
          showTime: false,
          width: ColumnWidth.small,
        ),
      ],
      onRowTap: (item) => _openDetails(_asOrder(item)),
      expandBodyHeightToFitRows: true,
      deferVerticalScrollToParent: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canRead) {
      return const Scaffold(
        body: Center(child: Text('دسترسی مشاهده موجودی/تولید را ندارید')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('سفارش‌های تولید'),
        actions: [
          IconButton(
            tooltip: 'ردیابی بچ/لات',
            onPressed: _loading ? null : _openLotTrace,
            icon: const Icon(Icons.qr_code_2),
          ),
          IconButton(
            tooltip: 'برنامهٔ مواد',
            onPressed: _loading ? null : _openMaterialPlan,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (_canWrite)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: FilledButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.add),
                label: const Text('سفارش جدید'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        value: _statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'وضعیت',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('همه')),
                          DropdownMenuItem(
                            value: 'draft',
                            child: Text('پیش‌نویس'),
                          ),
                          DropdownMenuItem(
                            value: 'released',
                            child: Text('آزادسازی‌شده'),
                          ),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('در حال اجرا'),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text('تکمیل‌شده'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('لغوشده'),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _statusFilter = v;
                            _page = 1;
                          });
                          _refresh();
                        },
                      ),
                    ),
                    Text('مجموع: $_total'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: DataTableWidget<ProductionOrder>(
                      key: ValueKey('mo_table_$_page'),
                      calendarController: _calendar,
                      config: _buildTableConfig(),
                      fromJson: (json) => ProductionOrder.fromJson(json),
                      localRawItems: _rows,
                      localTotalCount: _total,
                      localCurrentPage: _page,
                      localPageSize: _pageSize,
                      onLocalPageChange: (p) {
                        setState(() => _page = p);
                        _refresh();
                      },
                      onLocalPageSizeChange: (s) {
                        setState(() {
                          _pageSize = s.clamp(1, 100);
                          _page = 1;
                        });
                        _refresh();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
