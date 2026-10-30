import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;
import '../../../services/repair_shop_service.dart';
import '../../../services/business_storage_service.dart';
import '../../../models/repair_order_model.dart';
import '../../../models/repair_technician_model.dart';
import '../../../core/api_client.dart';
import '../../../core/calendar_controller.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/error_extractor.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/invoice/product_combobox_widget.dart';
import '../../../widgets/invoice/warehouse_combobox_widget.dart';
import 'repair_shop_calendar_utils.dart';
import 'repair_shop_status.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class RepairOrderDetailPage extends StatefulWidget {
  final int businessId;
  final int orderId;
  final CalendarController calendarController;

  const RepairOrderDetailPage({
    super.key,
    required this.businessId,
    required this.orderId,
    required this.calendarController,
  });

  @override
  State<RepairOrderDetailPage> createState() => _RepairOrderDetailPageState();
}

class _RepairOrderDetailPageState extends State<RepairOrderDetailPage> {
  late final RepairShopService _service;
  late final BusinessStorageService _storage;

  bool _isLoading = true;
  bool _busy = false;
  RepairOrder? _order;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _service = RepairShopService(api);
    _storage = BusinessStorageService(api);
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
      if (!mounted) return;
      setState(() {
        _order = order;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'خطا در بارگذاری سفارش: ${ErrorExtractor.forContext(e, context)}';
        _isLoading = false;
      });
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showStatusMenu() async {
    final newStatus = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('انتخاب وضعیت جدید'),
        children: RepairShopStatus.labels.entries.map((entry) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, entry.key),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: RepairShopStatus.color(context, entry.key),
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
      await _updateStatus(newStatus);
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
              backgroundColor: SemanticColorResolver.negative(context),
            ),
            child: const Text('بله، لغو کن'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _runAction(() async {
      try {
        await _service.deleteOrder(
          businessId: widget.businessId,
          orderId: widget.orderId,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        SnackBarHelper.show(context, message: 'سفارش لغو شد');
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _assignTechnician() async {
    List<RepairTechnician> technicians;
    try {
      technicians = await _service.listTechnicians(
        businessId: widget.businessId,
        onlyActive: true,
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        );
      }
      return;
    }

    if (!mounted) return;
    if (technicians.isEmpty) {
      SnackBarHelper.show(context, message: 'ابتدا یک تعمیرکار فعال تعریف کنید');
      return;
    }

    final selected = await showDialog<RepairTechnician>(
      context: context,
      builder: (context) => _TechnicianPickDialog(technicians: technicians),
    );

    if (selected == null) return;

    await _runAction(() async {
      try {
        await _service.assignTechnician(
          businessId: widget.businessId,
          orderId: widget.orderId,
          technicianId: selected.id,
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'تعمیرکار اختصاص یافت');
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _updateStatus(String newStatus) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => _NotesDialog(
        title: 'تغییر وضعیت به ${RepairShopStatus.label(newStatus)}',
      ),
    );

    if (notes == null) return;

    await _runAction(() async {
      try {
        await _service.updateStatus(
          businessId: widget.businessId,
          orderId: widget.orderId,
          status: newStatus,
          notes: notes.isNotEmpty ? notes : null,
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'وضعیت با موفقیت تغییر کرد');
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
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

    await _runAction(() async {
      try {
        await _service.completeRepair(
          businessId: widget.businessId,
          orderId: widget.orderId,
          isFixed: isFixed,
          notes: notes.isNotEmpty ? notes : null,
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'تعمیر تکمیل شد');
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _deliverRepair() async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => const _NotesDialog(
        title: 'تحویل کالا به مشتری',
        hint: 'یادداشت تحویل (اختیاری)',
      ),
    );
    if (notes == null) return;

    await _runAction(() async {
      try {
        await _service.deliverRepair(
          businessId: widget.businessId,
          orderId: widget.orderId,
          notes: notes.isNotEmpty ? notes : null,
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'کالا تحویل داده شد');
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _createInvoice() async {
    final order = _order;
    if (order == null) return;
    if (order.laborCost <= 0 && order.parts.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'قبل از صدور فاکتور، دستمزد یا قطعه را ثبت کنید',
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('صدور فاکتور'),
        content: Text(
          'فاکتور فروش برای ${order.formattedFinalCost} صادر می‌شود. ادامه می‌دهید؟',
        ),
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

    await _runAction(() async {
      try {
        final result = await _service.createInvoice(
          businessId: widget.businessId,
          orderId: widget.orderId,
        );
        if (mounted) {
          final code = result['code'] ??
              (result['document'] is Map ? result['document']['code'] : null);
          SnackBarHelper.show(
            context,
            message: code != null
                ? 'فاکتور $code صادر شد'
                : 'فاکتور با موفقیت صادر شد',
          );
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _openAddPartDialog() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddPartDialog(businessId: widget.businessId),
    );
    if (payload == null) return;

    await _runAction(() async {
      try {
        await _service.addParts(
          businessId: widget.businessId,
          orderId: widget.orderId,
          parts: [payload],
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'قطعه اضافه شد');
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _removePart(RepairOrderPart part) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف قطعه'),
        content: Text('قطعه «${part.productName}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('خیر'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _runAction(() async {
      try {
        await _service.removePart(
          businessId: widget.businessId,
          orderId: widget.orderId,
          partId: part.id,
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'قطعه حذف شد');
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _setLaborCost() async {
    final order = _order;
    if (order == null) return;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => _LaborCostDialog(initial: order.laborCost),
    );
    if (result == null) return;

    await _runAction(() async {
      try {
        await _service.calculateCosts(
          businessId: widget.businessId,
          orderId: widget.orderId,
          laborCost: result,
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'دستمزد ثبت شد');
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _addAttachment() async {
    final attachmentType = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('نوع ضمیمه'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'before_repair'),
            child: const Text('قبل از تعمیر'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'during_repair'),
            child: const Text('حین تعمیر'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'after_repair'),
            child: const Text('بعد از تعمیر'),
          ),
        ],
      ),
    );
    if (attachmentType == null) return;

    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;

    await _runAction(() async {
      try {
        final uploaded = await _storage.uploadFile(
          businessId: widget.businessId,
          fileBytes: file.bytes!,
          filename: file.name,
          moduleContext: 'repair_shop',
          contextId: widget.orderId.toString(),
        );
        final fileId = uploaded['id']?.toString() ??
            uploaded['file_id']?.toString();
        if (fileId == null) {
          throw Exception('شناسه فایل پس از آپلود دریافت نشد');
        }
        final name = file.name.toLowerCase();
        final fileType = name.endsWith('.mp4') || name.endsWith('.mov')
            ? 'video'
            : (name.endsWith('.png') ||
                    name.endsWith('.jpg') ||
                    name.endsWith('.jpeg') ||
                    name.endsWith('.webp')
                ? 'image'
                : 'document');
        await _service.addAttachment(
          businessId: widget.businessId,
          orderId: widget.orderId,
          fileStorageId: fileId,
          fileType: fileType,
          attachmentType: attachmentType,
          description: file.name,
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'ضمیمه اضافه شد');
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _deleteAttachment(RepairOrderAttachment attachment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف ضمیمه'),
        content: Text('«${attachment.description ?? attachment.fileStorageId}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('خیر'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _runAction(() async {
      try {
        await _service.deleteAttachment(
          businessId: widget.businessId,
          orderId: widget.orderId,
          attachmentId: attachment.id,
        );
        if (mounted) {
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    });
  }

  Future<void> _editOrder() async {
    final result = await context.push(
      '/business/${widget.businessId}/repair-shop/${widget.orderId}/edit',
    );
    if (result == true) {
      await _loadOrder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.calendarController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(_order?.code ?? 'جزئیات سفارش'),
            leading:
                hesabixBackAppBarLeading(context, businessId: widget.businessId),
            actions: [
              if (_order != null && RepairShopStatus.isEditable(_order!.status))
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'ویرایش سفارش',
                  onPressed: _editOrder,
                ),
              if (_order != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'status') {
                      _showStatusMenu();
                    } else if (value == 'delete') {
                      _deleteOrder();
                    } else if (value == 'edit') {
                      _editOrder();
                    }
                  },
                  itemBuilder: (context) => [
                    if (RepairShopStatus.isEditable(_order!.status))
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit),
                            SizedBox(width: 8),
                            Text('ویرایش سفارش'),
                          ],
                        ),
                      ),
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
                    if (RepairShopStatus.isEditable(_order!.status))
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete,
                                color: SemanticColorResolver.negative(context)),
                            const SizedBox(width: 8),
                            Text(
                              'لغو سفارش',
                              style: TextStyle(
                                color: SemanticColorResolver.negative(context),
                              ),
                            ),
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
          bottomNavigationBar:
              _order == null || _isLoading ? null : _buildActionBar(colorScheme),
        );
      },
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme colorScheme) {
    final order = _order!;
    final isJalali = widget.calendarController.isJalali;
    String fmt(DateTime dt) =>
        RepairShopCalendarUtils.formatDateTime(dt, isJalali);
    String fmtOptional(DateTime? dt) =>
        dt == null ? '-' : RepairShopCalendarUtils.formatDateTime(dt, isJalali);
    final formatter = intl.NumberFormat('#,###');

    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: RepairShopStatus.color(context, order.status)
                    .withValues(alpha: 0.1),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: RepairShopStatus.color(context, order.status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        RepairShopStatus.label(order.status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (order.hasInvoice) ...[
                      const SizedBox(height: 8),
                      Chip(
                        avatar: const Icon(Icons.receipt_long, size: 16),
                        label: Text(
                          order.invoiceCode != null
                              ? 'فاکتور ${order.invoiceCode}'
                              : 'فاکتور صادر شده',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
              _buildSection(
                'اطلاعات کالا',
                Icons.devices,
                colorScheme,
                [
                  _buildInfoRow('نام کالا', order.productName),
                  if (order.productSerial != null)
                    _buildInfoRow('سریال', order.productSerial!),
                  if (order.warrantyCodeId != null)
                    _buildInfoRow(
                        'کد گارانتی', order.warrantyCodeId.toString()),
                ],
              ),
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
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('یادداشت مشتری:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(order.customerNotes!),
                    ),
                  ],
                  if (order.technicianNotes != null) ...[
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('یادداشت تعمیرکار:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(order.technicianNotes!),
                    ),
                  ],
                ],
              ),
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
              _buildSection(
                'هزینه‌ها',
                Icons.attach_money,
                colorScheme,
                [
                  _buildInfoRow('دستمزد', order.formattedLaborCost),
                  _buildInfoRow('قطعات', order.formattedPartsCost),
                  _buildInfoRow(
                      'حق‌الزحمه تعمیرکار', order.formattedCommission),
                  const Divider(),
                  _buildInfoRow('جمع کل', order.formattedFinalCost, bold: true),
                ],
              ),
              _buildSection(
                'ضمائم',
                Icons.attach_file,
                colorScheme,
                [
                  if (order.attachments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('ضمیمه‌ای ثبت نشده است'),
                    )
                  else
                    ...order.attachments.map((att) {
                      return ListTile(
                        leading: Icon(
                          att.fileType == 'image'
                              ? Icons.image
                              : att.fileType == 'video'
                                  ? Icons.videocam
                                  : Icons.insert_drive_file,
                        ),
                        title: Text(att.description ?? att.fileStorageId),
                        subtitle: Text(att.typeLabel),
                        trailing: RepairShopStatus.isEditable(order.status)
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteAttachment(att),
                              )
                            : null,
                      );
                    }),
                  if (RepairShopStatus.isEditable(order.status))
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: OutlinedButton.icon(
                        onPressed: _addAttachment,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('افزودن عکس یا فایل'),
                      ),
                    ),
                ],
              ),
              _buildSection(
                'قطعات استفاده شده',
                Icons.inventory,
                colorScheme,
                [
                  if (order.parts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('قطعه‌ای ثبت نشده است'),
                    )
                  else
                    ...order.parts.map((part) {
                      return ListTile(
                        title: Text(part.productName),
                        subtitle: Text(
                          'تعداد: ${part.quantity} × ${formatter.format(part.unitPrice)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${formatter.format(part.totalPrice)} ${order.currencySymbol}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (RepairShopStatus.canAddParts(order.status))
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removePart(part),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
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
                          color:
                              RepairShopStatus.color(context, status.status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(RepairShopStatus.label(status.status)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fmt(status.createdAt)),
                          if (status.notes != null) Text(status.notes!),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              _buildSection(
                'تاریخ‌ها',
                Icons.calendar_today,
                colorScheme,
                [
                  _buildInfoRow('دریافت', fmt(order.receivedAt)),
                  if (order.estimatedDeliveryAt != null)
                    _buildInfoRow(
                        'تحویل تقریبی', fmtOptional(order.estimatedDeliveryAt)),
                  if (order.completedAt != null)
                    _buildInfoRow(
                        'تکمیل تعمیر', fmtOptional(order.completedAt)),
                  if (order.deliveredAt != null)
                    _buildInfoRow('تحویل شده', fmtOptional(order.deliveredAt)),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget? _buildActionBar(ColorScheme colorScheme) {
    final order = _order!;
    final status = order.status;
    final actions = <Widget>[];

    if (RepairShopStatus.canAssign(status)) {
      actions.add(_ActionChip(
        icon: Icons.engineering,
        label: order.assignedTechnicianId == null
            ? 'اختصاص تعمیرکار'
            : 'تغییر تعمیرکار',
        onPressed: _assignTechnician,
      ));
    }
    if (status == 'assigned') {
      actions.add(_ActionChip(
        icon: Icons.play_arrow,
        label: 'شروع تعمیر',
        onPressed: () => _updateStatus('in_progress'),
      ));
    }
    if (RepairShopStatus.canAddParts(status)) {
      actions.add(_ActionChip(
        icon: Icons.add_box_outlined,
        label: 'افزودن قطعه',
        onPressed: _openAddPartDialog,
      ));
    }
    if (RepairShopStatus.canSetLabor(status)) {
      actions.add(_ActionChip(
        icon: Icons.handyman_outlined,
        label: 'ثبت دستمزد',
        onPressed: _setLaborCost,
      ));
    }
    if (status == 'in_progress') {
      actions.add(_ActionChip(
        icon: Icons.hourglass_empty,
        label: 'منتظر قطعه',
        onPressed: () => _updateStatus('waiting_parts'),
      ));
      actions.add(_ActionChip(
        icon: Icons.science_outlined,
        label: 'تست',
        onPressed: () => _updateStatus('testing'),
      ));
    }
    if (status == 'waiting_parts') {
      actions.add(_ActionChip(
        icon: Icons.play_arrow,
        label: 'ادامه تعمیر',
        onPressed: () => _updateStatus('in_progress'),
      ));
    }
    if (RepairShopStatus.canComplete(status)) {
      actions.add(_ActionChip(
        icon: Icons.check_circle,
        label: 'تعمیر موفق',
        filled: true,
        onPressed: () => _completeRepair(true),
      ));
      actions.add(_ActionChip(
        icon: Icons.cancel_outlined,
        label: 'غیرقابل تعمیر',
        onPressed: () => _completeRepair(false),
      ));
    }
    if (RepairShopStatus.canInvoice(status) && !order.hasInvoice) {
      actions.add(_ActionChip(
        icon: Icons.receipt_long,
        label: 'صدور فاکتور',
        filled: true,
        onPressed: _createInvoice,
      ));
    }
    if (status == 'completed_fixed') {
      actions.add(_ActionChip(
        icon: Icons.storefront_outlined,
        label: 'آماده تحویل',
        onPressed: () => _updateStatus('ready_for_pickup'),
      ));
    }
    if (RepairShopStatus.canDeliver(status)) {
      actions.add(_ActionChip(
        icon: Icons.handshake_outlined,
        label: 'تحویل به مشتری',
        filled: status != 'completed_fixed' || order.hasInvoice,
        onPressed: _deliverRepair,
      ));
    }

    if (actions.isEmpty) return null;

    return Material(
      elevation: 8,
      color: colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: actions),
          ),
        ),
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
          Text('$label:', style: const TextStyle(color: Colors.grey)),
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
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: filled
          ? FilledButton(onPressed: onPressed, child: child)
          : OutlinedButton(onPressed: onPressed, child: child),
    );
  }
}

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

class _TechnicianPickDialog extends StatefulWidget {
  final List<RepairTechnician> technicians;

  const _TechnicianPickDialog({required this.technicians});

  @override
  State<_TechnicianPickDialog> createState() => _TechnicianPickDialogState();
}

class _TechnicianPickDialogState extends State<_TechnicianPickDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.technicians.where((t) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim();
      return t.personName.contains(q) || t.code.contains(q);
    }).toList();

    return AlertDialog(
      title: const Text('انتخاب تعمیرکار'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'جستجو نام یا کد...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('تعمیرکاری یافت نشد'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final tech = filtered[index];
                        return ListTile(
                          title: Text(tech.personName),
                          subtitle: Text(
                            '${tech.code} · ${tech.formattedCommission()}',
                          ),
                          onTap: () => Navigator.pop(context, tech),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
      ],
    );
  }
}

class _LaborCostDialog extends StatefulWidget {
  final double initial;
  const _LaborCostDialog({required this.initial});

  @override
  State<_LaborCostDialog> createState() => _LaborCostDialogState();
}

class _LaborCostDialogState extends State<_LaborCostDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial > 0 ? widget.initial.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('دستمزد تعمیر'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'مبلغ دستمزد',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        ElevatedButton(
          onPressed: () {
            final value = double.tryParse(
              _controller.text.replaceAll(',', '').trim(),
            );
            if (value == null || value < 0) {
              SnackBarHelper.show(context, message: 'مبلغ معتبر وارد کنید');
              return;
            }
            Navigator.pop(context, value);
          },
          child: const Text('ثبت'),
        ),
      ],
    );
  }
}

class _AddPartDialog extends StatefulWidget {
  final int businessId;
  const _AddPartDialog({required this.businessId});

  @override
  State<_AddPartDialog> createState() => _AddPartDialogState();
}

class _AddPartDialogState extends State<_AddPartDialog> {
  Map<String, dynamic>? _product;
  int? _warehouseId;
  final _qtyController = TextEditingController(text: '1');
  final _priceController = TextEditingController();

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('افزودن قطعه'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProductComboboxWidget(
                businessId: widget.businessId,
                productsOnly: true,
                selectedProduct: _product,
                label: 'قطعه',
                hintText: 'جست‌وجو و انتخاب قطعه',
                onChanged: (product) {
                  setState(() {
                    _product = product;
                    final price = product?['base_sales_price'];
                    if (price != null) {
                      _priceController.text = price.toString();
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              WarehouseComboboxWidget(
                businessId: widget.businessId,
                selectedWarehouseId: _warehouseId,
                selectDefaultWhenUnset: true,
                isRequired: false,
                onChanged: (id) => setState(() => _warehouseId = id),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'تعداد',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'قیمت واحد',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        ElevatedButton(
          onPressed: () {
            final productId = _product?['id'];
            final qty = double.tryParse(_qtyController.text.trim());
            final price = double.tryParse(
              _priceController.text.replaceAll(',', '').trim(),
            );
            if (productId == null) {
              SnackBarHelper.show(context, message: 'قطعه را انتخاب کنید');
              return;
            }
            if (qty == null || qty <= 0) {
              SnackBarHelper.show(context, message: 'تعداد معتبر وارد کنید');
              return;
            }
            Navigator.pop(context, {
              'product_id': productId,
              'quantity': qty,
              'unit_price': ?price,
              'warehouse_id': ?_warehouseId,
            });
          },
          child: const Text('افزودن'),
        ),
      ],
    );
  }
}
