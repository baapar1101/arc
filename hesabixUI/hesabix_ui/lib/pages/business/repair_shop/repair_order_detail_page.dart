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
import 'package:hesabix_ui/l10n/app_localizations.dart';
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
            AppLocalizations.of(context).repairShopLoadOrderError(
          ErrorExtractor.forContext(e, context),
        );
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
        title: Text(AppLocalizations.of(context).repairShopSelectNewStatus),
        children: RepairShopStatus.codes.map((code) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, code),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: RepairShopStatus.color(context, code),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(RepairShopStatus.label(code, AppLocalizations.of(context))),
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
        title: Text(AppLocalizations.of(context).repairShopCancelOrder),
        content: Text(AppLocalizations.of(context).repairShopCancelOrderConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SemanticColorResolver.negative(context),
            ),
            child: Text(AppLocalizations.of(context).repairShopCancelYes),
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
        SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopOrderCancelled);
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
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
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    if (technicians.isEmpty) {
      SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopNeedActiveTechnician);
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
          SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopTechnicianAssigned);
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
          );
        }
      }
    });
  }

  Future<void> _updateStatus(String newStatus) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => _NotesDialog(
        title: AppLocalizations.of(context).repairShopChangeStatusTo(RepairShopStatus.label(newStatus, AppLocalizations.of(context))),
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
          SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopStatusChanged);
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
          );
        }
      }
    });
  }

  Future<void> _completeRepair(bool isFixed) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => _NotesDialog(
        title: isFixed ? AppLocalizations.of(context).repairShopCompleteFixedTitle : AppLocalizations.of(context).repairShopCompleteUnfixableTitle,
        hint: AppLocalizations.of(context).repairShopNotesHint,
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
          SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopRepairCompleted);
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
          );
        }
      }
    });
  }

  Future<void> _deliverRepair() async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => _NotesDialog(
        title: AppLocalizations.of(context).repairShopDeliverToCustomer,
        hint: AppLocalizations.of(context).repairShopDeliveryNotesHint,
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
          SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopItemDelivered);
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
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
        message: AppLocalizations.of(context).repairShopInvoiceRequiresCost,
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).repairShopIssueInvoice),
        content: Text(
          AppLocalizations.of(context).repairShopIssueInvoiceConfirm(order.formattedFinalCost),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).repairShopIssueInvoiceYes),
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
                ? AppLocalizations.of(context).repairShopInvoiceIssuedWithCode(code)
                : AppLocalizations.of(context).repairShopInvoiceIssued,
          );
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
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
          SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopPartAdded);
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
          );
        }
      }
    });
  }

  Future<void> _removePart(RepairOrderPart part) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).repairShopDeletePart),
        content: Text(AppLocalizations.of(context).repairShopDeletePartConfirm(part.productName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).delete),
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
          SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopPartDeleted);
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
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
          SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopLaborSaved);
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
          );
        }
      }
    });
  }

  Future<void> _addAttachment() async {
    final attachmentType = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).repairShopAttachmentType),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'before_repair'),
            child: Text(AppLocalizations.of(context).repairShopAttachmentBefore),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'during_repair'),
            child: Text(AppLocalizations.of(context).repairShopAttachmentDuring),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'after_repair'),
            child: Text(AppLocalizations.of(context).repairShopAttachmentAfter),
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
          throw Exception(AppLocalizations.of(context).repairShopFileIdMissing);
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
          SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopAttachmentAdded);
          await _loadOrder();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
          );
        }
      }
    });
  }

  Future<void> _deleteAttachment(RepairOrderAttachment attachment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).repairShopDeleteAttachment),
        content: Text(AppLocalizations.of(context).repairShopDeleteAttachmentConfirm(attachment.description ?? attachment.fileStorageId)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).delete),
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
            message: AppLocalizations.of(context).repairShopErrorWithDetails(
            ErrorExtractor.forContext(e, context),
          ),
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
            title: Text(_order?.code ?? AppLocalizations.of(context).repairShopOrderDetails),
            leading:
                hesabixBackAppBarLeading(context, businessId: widget.businessId),
            actions: [
              if (_order != null && RepairShopStatus.isEditable(_order!.status))
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: AppLocalizations.of(context).repairShopEditOrder,
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
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(Icons.edit),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context).repairShopEditOrder),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'status',
                      child: Row(
                        children: [
                          const Icon(Icons.swap_horiz),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context).repairShopChangeStatus),
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
                              AppLocalizations.of(context).repairShopCancelOrder,
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
                            child: Text(AppLocalizations.of(context).retry),
                          ),
                        ],
                      ),
                    )
                  : _order == null
                      ? Center(child: Text(AppLocalizations.of(context).repairShopOrderNotFound))
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
                        RepairShopStatus.label(order.status, AppLocalizations.of(context)),
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
                              ? AppLocalizations.of(context).repairShopInvoiceWithCode(order.invoiceCode!)
                              : AppLocalizations.of(context).repairShopInvoiceIssuedLabel,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _buildSection(
                AppLocalizations.of(context).repairShopCustomerInfo,
                Icons.person,
                colorScheme,
                [
                  _buildInfoRow(AppLocalizations.of(context).repairShopName, order.customerName),
                  if (order.customerPhone != null)
                    _buildInfoRow(AppLocalizations.of(context).phone, order.customerPhone!),
                  if (order.customerEmail != null)
                    _buildInfoRow(AppLocalizations.of(context).email, order.customerEmail!),
                ],
              ),
              _buildSection(
                AppLocalizations.of(context).repairShopProductInfo,
                Icons.devices,
                colorScheme,
                [
                  _buildInfoRow(AppLocalizations.of(context).repairShopProductNameLabel, order.productName),
                  if (order.productSerial != null)
                    _buildInfoRow(AppLocalizations.of(context).repairShopSerial, order.productSerial!),
                  if (order.warrantyCodeId != null)
                    _buildInfoRow(
                        AppLocalizations.of(context).repairShopWarrantyCode, order.warrantyCodeId.toString()),
                ],
              ),
              _buildSection(
                AppLocalizations.of(context).repairShopProblemSection,
                Icons.report_problem,
                colorScheme,
                [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(order.problemDescription),
                  ),
                  if (order.customerNotes != null) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(AppLocalizations.of(context).repairShopCustomerNotesLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(order.customerNotes!),
                    ),
                  ],
                  if (order.technicianNotes != null) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(AppLocalizations.of(context).repairShopTechnicianNotesLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(order.technicianNotes!),
                    ),
                  ],
                ],
              ),
              _buildSection(
                AppLocalizations.of(context).repairShopTechnician,
                Icons.engineering,
                colorScheme,
                [
                  if (order.technicianName != null)
                    _buildInfoRow(AppLocalizations.of(context).repairShopTechnician, order.technicianName!)
                  else
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(AppLocalizations.of(context).repairShopNoTechnicianAssigned),
                    ),
                ],
              ),
              _buildSection(
                AppLocalizations.of(context).repairShopCosts,
                Icons.attach_money,
                colorScheme,
                [
                  _buildInfoRow(AppLocalizations.of(context).repairShopLabor, order.formattedLaborCost),
                  _buildInfoRow(AppLocalizations.of(context).repairShopParts, order.formattedPartsCost),
                  _buildInfoRow(
                      AppLocalizations.of(context).repairShopTechnicianCommission, order.formattedCommission),
                  const Divider(),
                  _buildInfoRow(AppLocalizations.of(context).repairShopGrandTotal, order.formattedFinalCost, bold: true),
                ],
              ),
              _buildSection(
                AppLocalizations.of(context).repairShopAttachments,
                Icons.attach_file,
                colorScheme,
                [
                  if (order.attachments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(AppLocalizations.of(context).repairShopNoAttachments),
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
                        subtitle: Text(att.typeLabel(AppLocalizations.of(context))),
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
                        label: Text(AppLocalizations.of(context).repairShopAddPhotoOrFile),
                      ),
                    ),
                ],
              ),
              _buildSection(
                AppLocalizations.of(context).repairShopUsedParts,
                Icons.inventory,
                colorScheme,
                [
                  if (order.parts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(AppLocalizations.of(context).repairShopNoParts),
                    )
                  else
                    ...order.parts.map((part) {
                      return ListTile(
                        title: Text(part.productName),
                        subtitle: Text(
                          AppLocalizations.of(context).repairShopPartQtyPrice(part.quantity.toString(), formatter.format(part.unitPrice)),
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
                  AppLocalizations.of(context).repairShopStatusHistory,
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
                      title: Text(RepairShopStatus.label(status.status, AppLocalizations.of(context))),
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
                AppLocalizations.of(context).repairShopDates,
                Icons.calendar_today,
                colorScheme,
                [
                  _buildInfoRow(AppLocalizations.of(context).repairShopReceived, fmt(order.receivedAt)),
                  if (order.estimatedDeliveryAt != null)
                    _buildInfoRow(
                        AppLocalizations.of(context).repairShopEstimatedDelivery, fmtOptional(order.estimatedDeliveryAt)),
                  if (order.completedAt != null)
                    _buildInfoRow(
                        AppLocalizations.of(context).repairShopCompletedAt, fmtOptional(order.completedAt)),
                  if (order.deliveredAt != null)
                    _buildInfoRow(AppLocalizations.of(context).repairShopDeliveredAt, fmtOptional(order.deliveredAt)),
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
            ? AppLocalizations.of(context).repairShopAssignTechnician
            : AppLocalizations.of(context).repairShopChangeTechnician,
        onPressed: _assignTechnician,
      ));
    }
    if (status == 'assigned') {
      actions.add(_ActionChip(
        icon: Icons.play_arrow,
        label: AppLocalizations.of(context).repairShopStartRepair,
        onPressed: () => _updateStatus('in_progress'),
      ));
    }
    if (RepairShopStatus.canAddParts(status)) {
      actions.add(_ActionChip(
        icon: Icons.add_box_outlined,
        label: AppLocalizations.of(context).repairShopAddPart,
        onPressed: _openAddPartDialog,
      ));
    }
    if (RepairShopStatus.canSetLabor(status)) {
      actions.add(_ActionChip(
        icon: Icons.handyman_outlined,
        label: AppLocalizations.of(context).repairShopSetLabor,
        onPressed: _setLaborCost,
      ));
    }
    if (status == 'in_progress') {
      actions.add(_ActionChip(
        icon: Icons.hourglass_empty,
        label: AppLocalizations.of(context).repairShopWaitingPart,
        onPressed: () => _updateStatus('waiting_parts'),
      ));
      actions.add(_ActionChip(
        icon: Icons.science_outlined,
        label: AppLocalizations.of(context).repairShopTest,
        onPressed: () => _updateStatus('testing'),
      ));
    }
    if (status == 'waiting_parts') {
      actions.add(_ActionChip(
        icon: Icons.play_arrow,
        label: AppLocalizations.of(context).repairShopContinueRepair,
        onPressed: () => _updateStatus('in_progress'),
      ));
    }
    if (RepairShopStatus.canComplete(status)) {
      actions.add(_ActionChip(
        icon: Icons.check_circle,
        label: AppLocalizations.of(context).repairShopStatusCompletedFixed,
        filled: true,
        onPressed: () => _completeRepair(true),
      ));
      actions.add(_ActionChip(
        icon: Icons.cancel_outlined,
        label: AppLocalizations.of(context).repairShopStatusCompletedUnfixable,
        onPressed: () => _completeRepair(false),
      ));
    }
    if (RepairShopStatus.canInvoice(status) && !order.hasInvoice) {
      actions.add(_ActionChip(
        icon: Icons.receipt_long,
        label: AppLocalizations.of(context).repairShopIssueInvoice,
        filled: true,
        onPressed: _createInvoice,
      ));
    }
    if (status == 'completed_fixed') {
      actions.add(_ActionChip(
        icon: Icons.storefront_outlined,
        label: AppLocalizations.of(context).repairShopReadyForPickupAction,
        onPressed: () => _updateStatus('ready_for_pickup'),
      ));
    }
    if (RepairShopStatus.canDeliver(status)) {
      actions.add(_ActionChip(
        icon: Icons.handshake_outlined,
        label: AppLocalizations.of(context).repairShopDeliverToCustomerAction,
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
  final String? hint;

  const _NotesDialog({
    required this.title,
    this.hint,
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
          hintText: widget.hint ?? AppLocalizations.of(context).repairShopOptionalNoteHint,
          border: const OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(AppLocalizations.of(context).confirm),
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
      title: Text(AppLocalizations.of(context).repairShopSelectTechnician),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).repairShopSearchNameOrCode,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(AppLocalizations.of(context).repairShopNoTechnicianFound),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final tech = filtered[index];
                        return ListTile(
                          title: Text(tech.personName),
                          subtitle: Text(
                            '${tech.code} · ${tech.formattedCommission(AppLocalizations.of(context))}',
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
          child: Text(AppLocalizations.of(context).cancel),
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
      title: Text(AppLocalizations.of(context).repairShopLaborTitle),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).repairShopLaborAmount,
          border: const OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        ElevatedButton(
          onPressed: () {
            final value = double.tryParse(
              _controller.text.replaceAll(',', '').trim(),
            );
            if (value == null || value < 0) {
              SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopEnterValidAmount);
              return;
            }
            Navigator.pop(context, value);
          },
          child: Text(AppLocalizations.of(context).repairShopRegister),
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
      title: Text(AppLocalizations.of(context).repairShopAddPartTitle),
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
                label: AppLocalizations.of(context).repairShopPart,
                hintText: AppLocalizations.of(context).repairShopSearchSelectPart,
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
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).quantity,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).repairShopUnitPrice,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        ElevatedButton(
          onPressed: () {
            final productId = _product?['id'];
            final qty = double.tryParse(_qtyController.text.trim());
            final price = double.tryParse(
              _priceController.text.replaceAll(',', '').trim(),
            );
            if (productId == null) {
              SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopSelectPart);
              return;
            }
            if (qty == null || qty <= 0) {
              SnackBarHelper.show(context, message: AppLocalizations.of(context).repairShopEnterValidQty);
              return;
            }
            Navigator.pop(context, {
              'product_id': productId,
              'quantity': qty,
              'unit_price': ?price,
              'warehouse_id': ?_warehouseId,
            });
          },
          child: Text(AppLocalizations.of(context).add),
        ),
      ],
    );
  }
}
