import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../../../services/repair_shop_service.dart';
import '../../../models/repair_order_model.dart';
import '../../../models/repair_technician_model.dart';
import '../../../core/api_client.dart';
import '../../../utils/snackbar_helper.dart';


/// صفحه جزئیات و عملیات سفارش تعمیر
class RepairOrderDetailPage extends StatefulWidget {
  final int businessId;
  final int orderId;

  const RepairOrderDetailPage({
    super.key,
    required this.businessId,
    required this.orderId,
  });

  @override
  State<RepairOrderDetailPage> createState() => _RepairOrderDetailPageState();
}

class _RepairOrderDetailPageState extends State<RepairOrderDetailPage> {
  late final RepairShopService _service;

  bool _isLoading = true;
  RepairOrder? _order;
  String? _errorMessage;

  // وضعیت‌ها و رنگ‌ها
  final Map<String, String> _statusLabels = {
    'received': 'دریافت شده',
    'assigned': 'اختصاص داده شده',
    'in_progress': 'در حال تعمیر',
    'waiting_parts': 'منتظر قطعات',
    'testing': 'در حال تست',
    'completed_fixed': 'تعمیر موفق',
    'completed_unfixable': 'غیرقابل تعمیر',
    'ready_for_pickup': 'آماده تحویل',
    'delivered': 'تحویل داده شده',
    'cancelled': 'لغو شده',
  };

  final Map<String, Color> _statusColors = {
    'received': Colors.blue,
    'assigned': Colors.purple,
    'in_progress': Colors.orange,
    'waiting_parts': Colors.amber,
    'testing': Colors.cyan,
    'completed_fixed': Colors.green,
    'completed_unfixable': Colors.red,
    'ready_for_pickup': Colors.teal,
    'delivered': Colors.grey,
    'cancelled': Colors.black54,
  };

  @override
  void initState() {
    super.initState();
    _service = RepairShopService(ApiClient());
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final order = await _service.getOrder(
        businessId: widget.businessId,
        orderId: widget.orderId,
      );

      setState(() {
        _order = order;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطا در بارگذاری سفارش: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _showStatusMenu() async {
    // نمایش منوی انتخاب وضعیت
    final newStatus = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('انتخاب وضعیت جدید'),
        children: _statusLabels.entries.map((entry) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, entry.key),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _statusColors[entry.key],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(entry.value),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (newStatus != null) {
      _updateStatus(newStatus);
    }
  }

  Future<void> _deleteOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('لغو سفارش'),
        content: const Text('آیا مطمئن هستید که می‌خواهید این سفارش را لغو کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('خیر'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('بله، لغو کن'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteOrder(
        businessId: widget.businessId,
        orderId: widget.orderId,
      );

      if (mounted) {
        Navigator.of(context).pop(); // بازگشت به لیست
        SnackBarHelper.show(context, message: 'سفارش لغو شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
    }
  }

  Future<void> _assignTechnician() async {
    // دیالوگ انتخاب تعمیرکار
    final technicians = await _service.listTechnicians(
      businessId: widget.businessId,
      onlyActive: true,
    );

    if (!mounted) return;

    final selected = await showDialog<RepairTechnician>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('انتخاب تعمیرکار'),
        children: technicians.map((tech) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, tech),
            child: ListTile(
              title: Text(tech.personName),
              subtitle: Text(tech.code),
            ),
          );
        }).toList(),
      ),
    );

    if (selected == null) return;

    try {
      await _service.assignTechnician(
        businessId: widget.businessId,
        orderId: widget.orderId,
        technicianId: selected.id,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'تعمیرکار با موفقیت اختصاص یافت');
        _loadOrder();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => _NotesDialog(
        title: 'تغییر وضعیت به ${_statusLabels[newStatus]}',
      ),
    );

    if (notes == null) return; // کنسل شد

    try {
      await _service.updateStatus(
        businessId: widget.businessId,
        orderId: widget.orderId,
        status: newStatus,
        notes: notes.isNotEmpty ? notes : null,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'وضعیت با موفقیت تغییر کرد');
        _loadOrder();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
    }
  }

  Future<void> _completeRepair(bool isFixed) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => _NotesDialog(
        title: isFixed ? 'تکمیل تعمیر موفق' : 'تعمیر ناموفق',
        hint: 'توضیحات...',
      ),
    );

    if (notes == null) return;

    try {
      await _service.completeRepair(
        businessId: widget.businessId,
        orderId: widget.orderId,
        isFixed: isFixed,
        notes: notes.isNotEmpty ? notes : null,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'تعمیر با موفقیت تکمیل شد');
        _loadOrder();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
    }
  }

  Future<void> _createInvoice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('صدور فاکتور'),
        content: const Text('آیا می‌خواهید فاکتور این سفارش را صادر کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('خیر'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بله، صدور فاکتور'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.createInvoice(
        businessId: widget.businessId,
        orderId: widget.orderId,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'فاکتور با موفقیت صادر شد');
        _loadOrder();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_order?.code ?? 'جزئیات سفارش'),
        actions: [
          if (_order != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'status') {
                  _showStatusMenu();
                } else if (value == 'delete') {
                  _deleteOrder();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'status',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz),
                      SizedBox(width: 8),
                      Text('تغییر وضعیت'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('لغو سفارش', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrder,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadOrder,
                        child: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : _order == null
                  ? const Center(child: Text('سفارش یافت نشد'))
                  : _buildContent(theme, colorScheme),
      floatingActionButton: _floatingActionButton,
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme colorScheme) {
    final order = _order!;
    final dateFormat = intl.DateFormat('yyyy/MM/dd HH:mm', 'fa');

    return SingleChildScrollView(
      child: Column(
        children: [
          // هدر با وضعیت
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _statusColors[order.status]?.withValues(alpha: 0.1),
            child: Column(
              children: [
                Text(
                  order.code,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _statusColors[order.status],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabels[order.status] ?? order.status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // اطلاعات مشتری
          _buildSection(
            'اطلاعات مشتری',
            Icons.person,
            colorScheme,
            [
              _buildInfoRow('نام', order.customerName),
              if (order.customerPhone != null)
                _buildInfoRow('تلفن', order.customerPhone!),
              if (order.customerEmail != null)
                _buildInfoRow('ایمیل', order.customerEmail!),
            ],
          ),

          // اطلاعات کالا
          _buildSection(
            'اطلاعات کالا',
            Icons.devices,
            colorScheme,
            [
              _buildInfoRow('نام کالا', order.productName),
              if (order.productSerial != null)
                _buildInfoRow('سریال', order.productSerial!),
            ],
          ),

          // مشکل و یادداشت‌ها
          _buildSection(
            'شرح مشکل',
            Icons.report_problem,
            colorScheme,
            [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(order.problemDescription),
              ),
              if (order.customerNotes != null) ...[
                const Divider(),
                const Text('یادداشت مشتری:', style: TextStyle(fontWeight: FontWeight.bold)),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(order.customerNotes!),
                ),
              ],
              if (order.technicianNotes != null) ...[
                const Divider(),
                const Text('یادداشت تعمیرکار:', style: TextStyle(fontWeight: FontWeight.bold)),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(order.technicianNotes!),
                ),
              ],
            ],
          ),

          // تعمیرکار
          _buildSection(
            'تعمیرکار',
            Icons.engineering,
            colorScheme,
            [
              if (order.technicianName != null)
                _buildInfoRow('تعمیرکار', order.technicianName!)
              else
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('هنوز تعمیرکاری اختصاص نیافته'),
                ),
            ],
          ),

          // هزینه‌ها
          _buildSection(
            'هزینه‌ها',
            Icons.attach_money,
            colorScheme,
            [
              _buildInfoRow(
                'دستمزد',
                order.formattedLaborCost,
              ),
              _buildInfoRow(
                'قطعات',
                order.formattedPartsCost,
              ),
              _buildInfoRow(
                'حق‌الزحمه تعمیرکار',
                order.formattedCommission,
              ),
              const Divider(),
              _buildInfoRow(
                'جمع کل',
                order.formattedFinalCost,
                bold: true,
              ),
            ],
          ),

          // قطعات
          if (order.parts.isNotEmpty)
            _buildSection(
              'قطعات استفاده شده',
              Icons.inventory,
              colorScheme,
              order.parts.map((part) {
                final formatter = intl.NumberFormat('#,###');
                return ListTile(
                  title: Text(part.productName),
                  subtitle: Text('تعداد: ${part.quantity} × ${formatter.format(part.unitPrice)}'),
                  trailing: Text(
                    '${formatter.format(part.totalPrice)} ${order.currencySymbol}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
            ),

          // Timeline وضعیت‌ها
          if (order.statusHistory.isNotEmpty)
            _buildSection(
              'تاریخچه وضعیت‌ها',
              Icons.timeline,
              colorScheme,
              order.statusHistory.map((status) {
                return ListTile(
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _statusColors[status.status],
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(_statusLabels[status.status] ?? status.status),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateFormat.format(status.createdAt)),
                      if (status.notes != null) Text(status.notes!),
                    ],
                  ),
                );
              }).toList(),
            ),

          // تاریخ‌ها
          _buildSection(
            'تاریخ‌ها',
            Icons.calendar_today,
            colorScheme,
            [
              _buildInfoRow('دریافت', dateFormat.format(order.receivedAt)),
              if (order.estimatedDeliveryAt != null)
                _buildInfoRow('تحویل تقریبی', dateFormat.format(order.estimatedDeliveryAt!)),
              if (order.completedAt != null)
                _buildInfoRow('تکمیل تعمیر', dateFormat.format(order.completedAt!)),
              if (order.deliveredAt != null)
                _buildInfoRow('تحویل شده', dateFormat.format(order.deliveredAt!)),
            ],
          ),

          const SizedBox(height: 100), // فضا برای دکمه‌های شناور
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    IconData icon,
    ColorScheme colorScheme,
    List<Widget> children,
  ) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(color: Colors.grey),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? get _floatingActionButton {
    if (_order == null) return null;

    final status = _order!.status;

    // دکمه‌های عملیات بر اساس وضعیت
    if (status == 'received') {
      return FloatingActionButton.extended(
        onPressed: _assignTechnician,
        icon: const Icon(Icons.person_add),
        label: const Text('اختصاص تعمیرکار'),
      );
    } else if (status == 'in_progress') {
      return FloatingActionButton.extended(
        onPressed: () => _completeRepair(true),
        icon: const Icon(Icons.check_circle),
        label: const Text('تکمیل تعمیر'),
      );
    } else if (status == 'completed_fixed') {
      return FloatingActionButton.extended(
        onPressed: _createInvoice,
        icon: const Icon(Icons.receipt),
        label: const Text('صدور فاکتور'),
      );
    }

    return null;
  }
}

/// دیالوگ ورود یادداشت
class _NotesDialog extends StatefulWidget {
  final String title;
  final String hint;

  const _NotesDialog({
    required this.title,
    this.hint = 'یادداشت (اختیاری)',
  });

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('تایید'),
        ),
      ],
    );
  }
}

