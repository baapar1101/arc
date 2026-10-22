import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../core/hesabix_back.dart' show hesabixBackAppBarLeading;
import '../../models/production_order_models.dart';
import '../../services/production_order_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/snackbar_helper.dart';
import 'production_order_form_dialog.dart';

class ProductionOrderDetailsPage extends StatefulWidget {
  final int businessId;
  final int orderId;

  const ProductionOrderDetailsPage({
    super.key,
    required this.businessId,
    required this.orderId,
  });

  @override
  State<ProductionOrderDetailsPage> createState() =>
      _ProductionOrderDetailsPageState();
}

class _ProductionOrderDetailsPageState
    extends State<ProductionOrderDetailsPage> {
  final _svc = ProductionOrderService();
  CalendarController? get _calendar => ApiClient.getCalendarController();
  AuthStore? get _auth => ApiClient.getAuthStore();
  bool get _canWrite =>
      _auth?.hasBusinessPermission('inventory', 'write') ?? false;

  ProductionOrder? _order;
  Map<String, dynamic>? _costing;
  bool _loading = true;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final order = await _svc.getById(
        businessId: widget.businessId,
        orderId: widget.orderId,
      );
      Map<String, dynamic>? costing;
      try {
        costing = await _svc.getCosting(
          businessId: widget.businessId,
          orderId: widget.orderId,
        );
      } catch (_) {
        // Preserve access to the order when costing is unavailable to this user.
      }
      if (!mounted) return;
      setState(() {
        _order = order;
        _costing = costing;
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshCosting() async {
    setState(() => _acting = true);
    try {
      final data = await _svc.refreshCosting(
        businessId: widget.businessId,
        orderId: widget.orderId,
      );
      if (!mounted) return;
      setState(() => _costing = data);
      SnackBarHelper.showSuccess(
        context,
        message: 'بهای واقعی سفارش به‌روزرسانی شد',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _editLots(ProductionOrder order) async {
    final materialControllers = <int, TextEditingController>{
      for (final row in order.materials.where((row) => row.id != null))
        row.id!: TextEditingController(text: row.lotCode ?? ''),
    };
    final outputControllers = <int, TextEditingController>{
      for (final row in order.outputs.where((row) => row.id != null))
        row.id!: TextEditingController(text: row.lotCode ?? ''),
    };
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('کد لات مواد و خروجی‌ها'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'مواد مصرفی',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final row in order.materials.where(
                  (row) => row.id != null,
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: TextField(
                      controller: materialControllers[row.id],
                      maxLength: 64,
                      decoration: InputDecoration(
                        labelText:
                            '${row.productName ?? row.productId} · ردیف ${row.lineNo}',
                        counterText: '',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'خروجی‌ها',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final row in order.outputs.where((row) => row.id != null))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: TextField(
                      controller: outputControllers[row.id],
                      maxLength: 64,
                      decoration: InputDecoration(
                        labelText:
                            '${row.productName ?? row.productId} · ردیف ${row.lineNo}',
                        counterText: '',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      setState(() => _acting = true);
      try {
        final updated = await _svc.updateLots(
          businessId: widget.businessId,
          orderId: order.id,
          version: order.version,
          materials: materialControllers.entries
              .map(
                (entry) => <String, dynamic>{
                  'id': entry.key,
                  'lot_code': entry.value.text.trim(),
                },
              )
              .toList(),
          outputs: outputControllers.entries
              .map(
                (entry) => <String, dynamic>{
                  'id': entry.key,
                  'lot_code': entry.value.text.trim(),
                },
              )
              .toList(),
        );
        if (mounted) {
          setState(() => _order = updated);
          SnackBarHelper.showSuccess(context, message: 'کدهای لات ذخیره شدند');
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: ErrorExtractor.forContext(e, context),
          );
        }
      } finally {
        if (mounted) setState(() => _acting = false);
      }
    }
    for (final controller in materialControllers.values) {
      controller.dispose();
    }
    for (final controller in outputControllers.values) {
      controller.dispose();
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

  Future<void> _runAction(
    Future<ProductionOrder> Function() op,
    String success,
  ) async {
    setState(() => _acting = true);
    try {
      final updated = await op();
      if (!mounted) return;
      setState(() => _order = updated);
      SnackBarHelper.showSuccess(context, message: success);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لغو سفارش'),
        content: const Text(
          'آیا از لغو این سفارش مطمئن هستید؟ رزرو مواد آزاد می‌شود. '
          'اگر مواد صادر شده باشد، ابتدا باید حواله‌ها ابطال شوند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SemanticColorResolver.negative(context),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('لغو سفارش'),
          ),
        ],
      ),
    );
    if (ok != true || _order == null) return;
    await _runAction(
      () => _svc.cancel(
        businessId: widget.businessId,
        orderId: _order!.id,
        version: _order!.version,
      ),
      'سفارش لغو شد',
    );
  }

  Future<void> _completeOrder(ProductionOrder order) async {
    final shortfalls = order.outputs
        .where((o) => o.producedQuantity < o.plannedQuantity)
        .toList();
    String? reason;
    if (shortfalls.isNotEmpty) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('بستن سفارش با کسری تولید'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'این سفارش کمتر از مقدار برنامه تولید شده است. برای ثبت نهایی، علت بستن را وارد کنید.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'علت بستن سفارش',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                Navigator.pop(ctx, controller.text.trim());
              },
              child: const Text('ادامه و بستن'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null || reason.trim().isEmpty) return;
    }
    await _runAction(
      () => _svc.complete(
        businessId: widget.businessId,
        orderId: order.id,
        version: order.version,
        closeReason: reason,
      ),
      shortfalls.isEmpty ? 'سفارش تکمیل شد' : 'سفارش با علت ثبت‌شده بسته شد',
    );
  }

  Future<void> _edit() async {
    final order = _order;
    if (order == null || !order.isDraft) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductionOrderFormDialog(
        businessId: widget.businessId,
        order: order,
      ),
    );
    if (result == true) _load();
  }

  Widget _infoTile(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(value, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  String _costText(dynamic value) =>
      formatWithThousands(double.tryParse(value?.toString() ?? '0') ?? 0);

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final isJalali = _calendar?.isJalali ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(order == null ? 'سفارش تولید' : 'سفارش ${order.code}'),
        leading: hesabixBackAppBarLeading(
          context,
          businessId: widget.businessId,
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          if (_canWrite && order?.isDraft == true)
            IconButton(
              onPressed: _acting ? null : _edit,
              icon: const Icon(Icons.edit),
            ),
        ],
      ),
      body: _loading && order == null
          ? const Center(child: CircularProgressIndicator())
          : order == null
          ? const Center(child: Text('سفارش یافت نشد'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                              label: Text(
                                productionOrderStatusLabel(order.status),
                              ),
                              backgroundColor: _statusColor(
                                order.status,
                              )?.withValues(alpha: 0.12),
                              labelStyle: TextStyle(
                                color: _statusColor(order.status),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text('اولویت: ${order.priority}'),
                            Text('نسخه: ${order.version}'),
                          ],
                        ),
                        const Divider(),
                        Wrap(
                          children: [
                            SizedBox(
                              width: 260,
                              child: _infoTile(
                                'کالا',
                                '${order.productName ?? '-'} (${order.productCode ?? order.productId})',
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: _infoTile('فرمول', 'BOM #${order.bomId}'),
                            ),
                            SizedBox(
                              width: 200,
                              child: _infoTile(
                                'مقدار برنامه',
                                formatWithThousands(order.plannedQuantity),
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: _infoTile(
                                'مقدار تولیدشده',
                                formatWithThousands(order.producedQuantity),
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: _infoTile(
                                'انبار مواد',
                                '#${order.warehouseId}',
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: _infoTile(
                                'انبار محصول',
                                '#${order.outputWarehouseId}',
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: _infoTile(
                                'شروع برنامه',
                                HesabixDateUtils.formatApiDateForDisplay(
                                  order.plannedStartDate,
                                  isJalali,
                                  fallback: '-',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: _infoTile(
                                'موعد',
                                HesabixDateUtils.formatApiDateForDisplay(
                                  order.dueDate,
                                  isJalali,
                                  fallback: '-',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if ((order.notes ?? '').isNotEmpty) ...[
                          const Divider(),
                          Text(order.notes!),
                        ],
                        if (order.closedShort &&
                            (order.closeReason ?? '').isNotEmpty) ...[
                          const Divider(),
                          Text('علت بستن با کسری: ${order.closeReason}'),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_canWrite) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (order.isDraft)
                        FilledButton.icon(
                          onPressed: _acting
                              ? null
                              : () => _runAction(
                                  () => _svc.release(
                                    businessId: widget.businessId,
                                    orderId: order.id,
                                    version: order.version,
                                  ),
                                  'مواد رزرو و سفارش آزادسازی شد',
                                ),
                          icon: const Icon(Icons.lock_open),
                          label: const Text('آزادسازی و رزرو مواد'),
                        ),
                      if (order.isReleased)
                        FilledButton.icon(
                          onPressed: _acting
                              ? null
                              : () => _runAction(
                                  () => _svc.start(
                                    businessId: widget.businessId,
                                    orderId: order.id,
                                    version: order.version,
                                  ),
                                  'سفارش شروع شد',
                                ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('شروع اجرا'),
                        ),
                      if (order.isInProgress)
                        FilledButton.icon(
                          onPressed: _acting
                              ? null
                              : () => _completeOrder(order),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('تکمیل'),
                        ),
                      if (order.isDraft ||
                          order.isReleased ||
                          order.isInProgress)
                        OutlinedButton.icon(
                          onPressed: _acting ? null : _confirmCancel,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('لغو'),
                        ),
                      if (order.isInProgress)
                        OutlinedButton.icon(
                          onPressed: () {
                            context.go(
                              context.businessPanelUrl(
                                widget.businessId,
                                'invoice/new?production_order_id=${order.id}',
                              ),
                            );
                          },
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('صدور فاکتور تولید'),
                        ),
                    ],
                  ),
                ],
                if (_costing != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'بهای تمام‌شده',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (_canWrite &&
                          (order.isInProgress || order.isCompleted))
                        TextButton.icon(
                          onPressed: _acting ? null : _refreshCosting,
                          icon: const Icon(Icons.sync),
                          label: const Text('محاسبهٔ مجدد'),
                        ),
                    ],
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 12,
                        children: [
                          _infoTile(
                            'مواد استاندارد',
                            _costText(
                              (_costing!['standard']
                                  as Map?)?['materials_cost'],
                            ),
                          ),
                          _infoTile(
                            'عملیات استاندارد',
                            _costText(
                              (_costing!['standard']
                                  as Map?)?['operations_cost'],
                            ),
                          ),
                          _infoTile(
                            'کل استاندارد',
                            _costText(
                              (_costing!['standard'] as Map?)?['total_cost'],
                            ),
                          ),
                          _infoTile(
                            'مواد واقعی',
                            _costText(
                              (_costing!['actual'] as Map?)?['materials_cost'],
                            ),
                          ),
                          _infoTile(
                            'عملیات واقعی',
                            _costText(
                              (_costing!['actual'] as Map?)?['operations_cost'],
                            ),
                          ),
                          _infoTile(
                            'کل واقعی',
                            _costText(
                              (_costing!['actual'] as Map?)?['total_cost'],
                            ),
                          ),
                          _infoTile(
                            'انحراف کل',
                            _costText(
                              (_costing!['variance'] as Map?)?['total_cost'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'مواد مصرفی',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (_canWrite && !order.isCompleted && !order.isCancelled)
                      TextButton.icon(
                        onPressed: _acting ? null : () => _editLots(order),
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('ویرایش لات‌ها'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('#')),
                        DataColumn(label: Text('کالا')),
                        DataColumn(label: Text('برنامه')),
                        DataColumn(label: Text('رزرو')),
                        DataColumn(label: Text('صادر شده')),
                        DataColumn(label: Text('بهای استاندارد')),
                        DataColumn(label: Text('لات')),
                        DataColumn(label: Text('انبار')),
                        DataColumn(label: Text('مسیر BOM')),
                      ],
                      rows: order.materials
                          .map(
                            (m) => DataRow(
                              cells: [
                                DataCell(Text('${m.lineNo}')),
                                DataCell(
                                  Text(
                                    '${m.productName ?? m.productId}${m.isOptional ? ' (اختیاری)' : ''}',
                                  ),
                                ),
                                DataCell(
                                  Text(formatWithThousands(m.plannedQuantity)),
                                ),
                                DataCell(
                                  Text(formatWithThousands(m.reservedQuantity)),
                                ),
                                DataCell(
                                  Text(formatWithThousands(m.issuedQuantity)),
                                ),
                                DataCell(Text(_costText(m.standardTotalCost))),
                                DataCell(Text(m.lotCode ?? '-')),
                                DataCell(Text('#${m.warehouseId}')),
                                DataCell(Text(m.bomPath ?? '-')),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'خروجی‌ها',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('#')),
                        DataColumn(label: Text('کالا')),
                        DataColumn(label: Text('برنامه')),
                        DataColumn(label: Text('تولیدشده')),
                        DataColumn(label: Text('ضایعات')),
                        DataColumn(label: Text('بهای استاندارد')),
                        DataColumn(label: Text('بهای واقعی')),
                        DataColumn(label: Text('لات')),
                      ],
                      rows: order.outputs
                          .map(
                            (o) => DataRow(
                              cells: [
                                DataCell(Text('${o.lineNo}')),
                                DataCell(
                                  Text(o.productName ?? '#${o.productId}'),
                                ),
                                DataCell(
                                  Text(formatWithThousands(o.plannedQuantity)),
                                ),
                                DataCell(
                                  Text(formatWithThousands(o.producedQuantity)),
                                ),
                                DataCell(
                                  Text(formatWithThousands(o.scrapQuantity)),
                                ),
                                DataCell(Text(_costText(o.standardTotalCost))),
                                DataCell(Text(_costText(o.actualTotalCost))),
                                DataCell(Text(o.lotCode ?? '-')),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
