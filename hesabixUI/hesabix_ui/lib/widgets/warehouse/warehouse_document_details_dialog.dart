import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/warehouse_service.dart';
import '../../core/api_client.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/document/document_details_dialog.dart';
import '../../core/calendar_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/web/web_utils.dart' as web_utils;
import '../../core/date_utils.dart' show HesabixDateUtils;

class WarehouseDocumentDetailsDialog extends StatefulWidget {
  final int businessId;
  final int documentId;

  const WarehouseDocumentDetailsDialog({
    super.key,
    required this.businessId,
    required this.documentId,
  });

  @override
  State<WarehouseDocumentDetailsDialog> createState() => _WarehouseDocumentDetailsDialogState();
}

class _WarehouseDocumentDetailsDialogState extends State<WarehouseDocumentDetailsDialog> {
  final _svc = WarehouseService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _doc;
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _loadCalendarController();
    _load();
  }

  Future<void> _loadCalendarController() async {
    final controller = await CalendarController.load();
    if (mounted) {
      setState(() => _calendarController = controller);
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _svc.getDoc(businessId: widget.businessId, docId: widget.documentId);
      setState(() { _doc = Map<String, dynamic>.from(res['item'] ?? res); });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  String _getDocTypeName(String? type, AppLocalizations t) {
    switch (type) {
      case 'receipt': return t.docTypeReceipt;
      case 'issue': return t.docTypeIssue;
      case 'transfer': return t.docTypeTransfer;
      case 'adjustment': return t.docTypeAdjustment;
      case 'production_in': return t.docTypeProductionIn;
      case 'production_out': return t.docTypeProductionOut;
      default: return type ?? '-';
    }
  }

  String _getStatusName(String? status, AppLocalizations t) {
    switch (status) {
      case 'draft': return t.statusDraft;
      case 'posted': return t.statusPosted;
      case 'cancelled': return t.statusCancelled;
      default: return status ?? '-';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'draft': return Colors.orange;
      case 'posted': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Future<void> _updateLineWarehouse(int lineId, int? warehouseId) async {
    try {
      await _svc.updateLine(
        businessId: widget.businessId,
        docId: widget.documentId,
        lineId: lineId,
        payload: {'warehouse_id': warehouseId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('انبار به‌روزرسانی شد')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e')),
      );
    }
  }

  Future<void> _postDoc() async {
    try {
      await _svc.postDoc(businessId: widget.businessId, docId: widget.documentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حواله پست شد')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در پست: $e')),
      );
    }
  }

  Future<void> _deleteDoc() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف حواله'),
        content: const Text('آیا از حذف این حواله مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final deleted = await _svc.deleteDoc(businessId: widget.businessId, docId: widget.documentId);
      if (!mounted) return;
      if (deleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حواله حذف شد')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e')),
      );
    }
  }

  Future<void> _cancelDoc() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('لغو حواله'),
        content: const Text('آیا از لغو این حواله مطمئن هستید؟ حواله معکوس ایجاد خواهد شد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('لغو'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.cancelDoc(businessId: widget.businessId, docId: widget.documentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حواله لغو شد و حواله معکوس ایجاد شد')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e')),
      );
    }
  }

  Future<void> _exportPdf() async {
    try {
      final api = ApiClient();
      final bytes = await api.downloadPdf(
        '/warehouse-docs/business/${widget.businessId}/${widget.documentId}/pdf',
      );
      if (!mounted) return;
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          bytes,
          'warehouse_doc_${widget.documentId}.pdf',
          mimeType: 'application/pdf',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('دانلود PDF در موبایل به زودی...')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در دانلود PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        child: Column(
          children: [
            _buildHeader(theme, t),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 48),
                              const SizedBox(height: 12),
                              Text(_error!),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _load,
                                child: const Text('تلاش مجدد'),
                              ),
                            ],
                          ),
                        )
                      : _doc == null
                          ? const Center(child: Text('حواله یافت نشد'))
                          : _buildContent(theme, t),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, AppLocalizations t) {
    final doc = _doc;
    final status = doc?['status'] as String?;
    final isDraft = status == 'draft';
    final isPosted = status == 'posted';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Icon(
              Icons.description,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc != null ? '${doc['code'] ?? '-'}' : 'حواله انبار',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (doc != null) ...[
                      _buildHeaderChip(
                        '${t.warehouseDocumentType}: ${_getDocTypeName(doc['doc_type'], t)}',
                        theme,
                      ),
                      _buildHeaderChip(
                        '${t.warehouseDocumentStatus}: ${_getStatusName(status, t)}',
                        theme,
                        icon: Icons.circle,
                        iconColor: _getStatusColor(status),
                      ),
                      if (doc['document_date'] != null && _calendarController != null)
                        _buildHeaderChip(
                          '${t.warehouseDocumentDate}: ${HesabixDateUtils.formatForDisplay(DateTime.tryParse(doc['document_date']), _calendarController!.isJalali)}',
                          theme,
                          icon: Icons.calendar_today,
                        ),
                    ],
                    if (_loading)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 6),
                          Text('در حال بارگذاری...'),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (doc != null) ...[
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _exportPdf,
              tooltip: t.printWarehouseDocument,
            ),
            if (isDraft) ...[
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteDoc,
                tooltip: t.deleteWarehouseDocument,
              ),
              IconButton(
                icon: const Icon(Icons.publish),
                onPressed: _postDoc,
                tooltip: t.postWarehouseDocument,
              ),
            ],
            if (isPosted)
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                onPressed: _cancelDoc,
                tooltip: t.cancelWarehouseDocument,
              ),
          ],
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(String text, ThemeData theme, {IconData? icon, Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor ?? theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, AppLocalizations t) {
    final doc = _doc!;
    final status = doc['status'] as String?;
    final isDraft = status == 'draft';
    final lines = List<dynamic>.from(doc['lines'] ?? const []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // اطلاعات اصلی
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.warehouseDocument,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(theme, 'کد', doc['code'] ?? '-'),
                  _buildInfoRow(theme, t.warehouseDocumentType, _getDocTypeName(doc['doc_type'], t)),
                  _buildInfoRow(theme, t.warehouseDocumentStatus, _getStatusName(status, t)),
                  if (doc['document_date'] != null && _calendarController != null)
                    _buildInfoRow(
                      theme,
                      t.warehouseDocumentDate,
                      HesabixDateUtils.formatForDisplay(DateTime.tryParse(doc['document_date']), _calendarController!.isJalali),
                    ),
                  if (doc['source_type'] == 'invoice' && doc['source_document_id'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: InkWell(
                        onTap: () async {
                          if (_calendarController == null) {
                            await _loadCalendarController();
                            if (_calendarController == null || !mounted) return;
                          }
                          if (!mounted) return;
                          showDialog(
                            context: context,
                            builder: (_) => DocumentDetailsDialog(
                              documentId: doc['source_document_id'] as int,
                              calendarController: _calendarController!,
                            ),
                          );
                        },
                        child: Text(
                          'فاکتور منبع: ${doc['source_document_id']}',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // اطلاعات ارسال (در صورت وجود)
          if (_hasDeliveryInfo(doc)) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_shipping, size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'اطلاعات ارسال',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (doc['description'] != null && (doc['description'] as String).isNotEmpty)
                      _buildInfoRow(theme, 'شرح/توضیحات', doc['description']),
                    if (doc['delivery_method'] != null)
                      _buildInfoRow(theme, 'روش ارسال', _getDeliveryMethodName(doc['delivery_method'])),
                    if (doc['carrier_name'] != null && (doc['carrier_name'] as String).isNotEmpty)
                      _buildInfoRow(theme, 'نام باربری/حمل و نقل', doc['carrier_name']),
                    if (doc['recipient_name'] != null && (doc['recipient_name'] as String).isNotEmpty)
                      _buildInfoRow(theme, 'تحویل گیرنده', doc['recipient_name']),
                    if (doc['recipient_phone'] != null && (doc['recipient_phone'] as String).isNotEmpty)
                      _buildInfoRow(theme, 'تلفن تحویل گیرنده', doc['recipient_phone']),
                    if (doc['tracking_number'] != null && (doc['tracking_number'] as String).isNotEmpty)
                      _buildInfoRow(theme, 'شماره پیگیری/بارنامه/قبض', doc['tracking_number']),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // خطوط حواله
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'خطوط حواله',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('خطی وجود ندارد')),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('محصول')),
                        DataColumn(label: Text('انبار')),
                        DataColumn(label: Text('نوع حرکت')),
                        DataColumn(label: Text('تعداد')),
                      ],
                      rows: lines.map<DataRow>((line) {
                        final lineId = line['id'] as int?;
                        final productId = line['product_id'] as int?;
                        final warehouseId = line['warehouse_id'] as int?;
                        final movement = line['movement'] as String?;
                        final quantity = line['quantity'] as num?;

                        return DataRow(
                          cells: [
                            DataCell(Text('${productId ?? '-'}')),
                            DataCell(
                              isDraft && lineId != null
                                  ? SizedBox(
                                      width: 150,
                                      child: WarehouseComboboxWidget(
                                        businessId: widget.businessId,
                                        selectedWarehouseId: warehouseId,
                                        onChanged: (wid) {
                                          _updateLineWarehouse(lineId, wid);
                                        },
                                      ),
                                    )
                                  : Text(warehouseId?.toString() ?? '-'),
                            ),
                            DataCell(Text(movement == 'in' ? 'ورود' : 'خروج')),
                            DataCell(Text(quantity?.toString() ?? '-')),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _hasDeliveryInfo(Map<String, dynamic> doc) {
    return (doc['description'] != null && (doc['description'] as String).isNotEmpty) ||
           doc['delivery_method'] != null ||
           (doc['carrier_name'] != null && (doc['carrier_name'] as String).isNotEmpty) ||
           (doc['recipient_name'] != null && (doc['recipient_name'] as String).isNotEmpty) ||
           (doc['recipient_phone'] != null && (doc['recipient_phone'] as String).isNotEmpty) ||
           (doc['tracking_number'] != null && (doc['tracking_number'] as String).isNotEmpty);
  }

  String _getDeliveryMethodName(String? method) {
    switch (method) {
      case 'warehouse_door': return 'تحویل درب انبار';
      case 'post_regular': return 'پست عادی';
      case 'post_express': return 'پست پیشتاز';
      case 'freight': return 'باربری';
      case 'bus': return 'اتوبوس';
      case 'tipax': return 'تیپاکس';
      case 'courier': return 'پیک';
      default: return method ?? '-';
    }
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

