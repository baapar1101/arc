import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/warehouse_service.dart';
import '../../core/api_client.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/document/document_details_dialog.dart';
import '../../core/calendar_controller.dart';
import '../../utils/web/web_utils.dart' as web_utils;

class WarehouseDocumentDetailsPage extends StatefulWidget {
  final int businessId;
  final int documentId;
  const WarehouseDocumentDetailsPage({
    super.key,
    required this.businessId,
    required this.documentId,
  });

  @override
  State<WarehouseDocumentDetailsPage> createState() => _WarehouseDocumentDetailsPageState();
}

class _WarehouseDocumentDetailsPageState extends State<WarehouseDocumentDetailsPage> {
  final _svc = WarehouseService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _doc;

  @override
  void initState() {
    super.initState();
    _load();
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

  String _getDocTypeName(String? type) {
    switch (type) {
      case 'receipt': return 'حواله ورود';
      case 'issue': return 'حواله خروج';
      case 'transfer': return 'انتقال بین انبارها';
      case 'adjustment': return 'تعدیل موجودی';
      case 'production_in': return 'ورود تولید';
      case 'production_out': return 'خروج تولید';
      default: return type ?? '-';
    }
  }

  String _getStatusName(String? status) {
    switch (status) {
      case 'draft': return 'پیش‌نویس';
      case 'posted': return 'پست شده';
      case 'cancelled': return 'لغو شده';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('جزئیات حواله')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('جزئیات حواله')),
        body: Center(child: Text('خطا: $_error')),
      );
    }
    if (_doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('جزئیات حواله')),
        body: const Center(child: Text('حواله یافت نشد')),
      );
    }

    final doc = _doc!;
    final status = doc['status'] as String?;
    final isDraft = status == 'draft';
    final isPosted = status == 'posted';
    final lines = List<dynamic>.from(doc['lines'] ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('جزئیات حواله'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () async {
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
            },
            tooltip: 'چاپ PDF',
          ),
          if (isDraft) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteDoc,
              tooltip: 'حذف',
            ),
            IconButton(
              icon: const Icon(Icons.publish),
              onPressed: _postDoc,
              tooltip: 'پست',
            ),
          ],
          if (isPosted)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              onPressed: _cancelDoc,
              tooltip: 'لغو',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'کد: ${doc['code'] ?? '-'}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Chip(
                            label: Text(_getStatusName(status)),
                            backgroundColor: _getStatusColor(status).withOpacity(0.2),
                            labelStyle: TextStyle(color: _getStatusColor(status)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('نوع: ${_getDocTypeName(doc['doc_type'])}'),
                      const SizedBox(height: 4),
                      Text('تاریخ: ${doc['document_date'] ?? '-'}'),
                      if (doc['source_type'] == 'invoice' && doc['source_document_id'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InkWell(
                            onTap: () async {
                              final calendarController = await CalendarController.load();
                              if (!mounted) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DocumentDetailsDialog(
                                    documentId: doc['source_document_id'] as int,
                                    calendarController: calendarController,
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              'فاکتور منبع: ${doc['source_document_id']}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
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
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('خطی وجود ندارد')),
                      )
                    else
                      DataTable(
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
