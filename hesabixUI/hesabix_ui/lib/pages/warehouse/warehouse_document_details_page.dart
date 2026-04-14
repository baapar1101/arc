import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/warehouse_service.dart';
import '../../core/api_client.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/document/document_details_dialog.dart';
import '../../core/calendar_controller.dart';
import '../../utils/web/web_utils.dart' as web_utils;
import '../../core/date_utils.dart' show HesabixDateUtils;

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
  Map<String, dynamic>? _relatedDoc; // حواله مرتبط (اصلی یا کنسلی)
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _loadCalendarController();
    _load();
  }

  Future<void> _loadCalendarController() async {
    final c = await CalendarController.load();
    if (mounted) setState(() => _calendarController = c);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _relatedDoc = null; });
    try {
      final res = await _svc.getDoc(businessId: widget.businessId, docId: widget.documentId);
      final doc = Map<String, dynamic>.from(res['item'] ?? res);
      setState(() { _doc = doc; });
      
      // پیدا کردن حواله مرتبط
      await _loadRelatedDoc(doc);
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _loadRelatedDoc(Map<String, dynamic> doc) async {
    try {
      final extraInfo = doc['extra_info'] as Map<String, dynamic>?;
      final sourceType = doc['source_type'] as String?;
      final sourceDocumentId = doc['source_document_id'] as int?;
      final docId = doc['id'] as int?;
      
      int? relatedDocId;
      
      // اگر حواله کنسلی است (extra_info.cancels_warehouse_document_id دارد)
      if (extraInfo != null && extraInfo['cancels_warehouse_document_id'] != null) {
        relatedDocId = extraInfo['cancels_warehouse_document_id'] as int?;
      }
      // اگر حواله اصلی است و source_document_id دارد و source_type manual است
      else if (sourceType == 'manual' && sourceDocumentId != null) {
        relatedDocId = sourceDocumentId;
      }
      // اگر حواله اصلی است (status cancelled است)، باید حواله کنسلی را پیدا کنیم
      else if (doc['status'] == 'cancelled' && docId != null) {
        // جستجو برای پیدا کردن حواله کنسلی که cancels_warehouse_document_id آن برابر با این حواله است
        try {
          final searchResult = await _svc.search(
            businessId: widget.businessId,
            filters: {
              'source_document_id': docId,
              'source_type': 'manual',
            },
          );
          final items = searchResult['items'] as List<dynamic>?;
          if (items != null && items.isNotEmpty) {
            // پیدا کردن حواله‌ای که cancels_warehouse_document_id آن برابر با docId است
            for (final item in items) {
              final itemExtraInfo = item['extra_info'] as Map<String, dynamic>?;
              if (itemExtraInfo != null && itemExtraInfo['cancels_warehouse_document_id'] == docId) {
                relatedDocId = item['id'] as int?;
                break;
              }
            }
          }
        } catch (e) {
          // خطا را نادیده می‌گیریم
        }
      }
      
      if (relatedDocId != null) {
        try {
          final relatedRes = await _svc.getDoc(businessId: widget.businessId, docId: relatedDocId);
          final relatedDoc = Map<String, dynamic>.from(relatedRes['item'] ?? relatedRes);
          if (mounted) {
            setState(() { _relatedDoc = relatedDoc; });
          }
        } catch (e) {
          // اگر حواله مرتبط پیدا نشد، خطا را نادیده می‌گیریم
        }
      }
    } catch (e) {
      // خطا را نادیده می‌گیریم
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

  String _formatQuantity(num? q) {
    if (q == null) return '-';
    if (q == q.roundToDouble()) return '${q.toInt()}';
    return q.toString();
  }

  String _formatDocDateTime(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final cal = _calendarController;
    if (cal != null) {
      return HesabixDateUtils.formatForDisplay(dt, cal.isJalali);
    }
    final mm = dt.minute.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    return '${dt.year}/${dt.month}/${dt.day} $hh:$mm';
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
      case 'warehouse_door':
        return 'تحویل درب انبار';
      case 'post_regular':
        return 'پست عادی';
      case 'post_express':
        return 'پست پیشتاز';
      case 'freight':
        return 'باربری';
      case 'bus':
        return 'اتوبوس';
      case 'tipax':
        return 'تیپاکس';
      case 'courier':
        return 'پیک';
      default:
        return method ?? '-';
    }
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف حواله'),
        content: const Text('آیا از حذف این حواله مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('لغو حواله'),
        content: const Text('آیا از لغو این حواله مطمئن هستید؟ حواله معکوس ایجاد خواهد شد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('لغو'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final result = await _svc.cancelDoc(businessId: widget.businessId, docId: widget.documentId);
      if (!mounted) return;
      final cancelDocCode = result['code'] as String?;
      final message = cancelDocCode != null
          ? 'حواله لغو شد. حواله پیش‌نویس با کد $cancelDocCode ایجاد شد.'
          : 'حواله لغو شد و حواله معکوس ایجاد شد.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
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
    final theme = Theme.of(context);

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
                if (!mounted || !context.mounted) return;
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
                if (!mounted || !context.mounted) return;
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
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          Chip(
                            label: Text(_getStatusName(status)),
                            backgroundColor: _getStatusColor(status).withValues(alpha: 0.2),
                            labelStyle: TextStyle(color: _getStatusColor(status)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(theme, 'نوع حواله', _getDocTypeName(doc['doc_type'] as String?)),
                      if (doc['document_date'] != null && _calendarController != null)
                        _buildInfoRow(
                          theme,
                          'تاریخ حواله',
                          HesabixDateUtils.formatForDisplay(
                            DateTime.tryParse(doc['document_date'] as String),
                            _calendarController!.isJalali,
                          ),
                        )
                      else
                        _buildInfoRow(theme, 'تاریخ حواله', doc['document_date']?.toString() ?? '-'),
                      if (doc['fiscal_year_title'] != null)
                        _buildInfoRow(theme, 'سال مالی', doc['fiscal_year_title'].toString()),
                      if (doc['total_quantity'] != null)
                        _buildInfoRow(theme, 'جمع تعداد (طبق نوع حواله)', _formatQuantity(doc['total_quantity'] as num?)),
                      if (doc['doc_type'] == 'transfer') ...[
                        if (doc['warehouse_name_from'] != null || doc['warehouse_id_from'] != null)
                          _buildInfoRow(
                            theme,
                            'انبار مبدأ',
                            doc['warehouse_name_from']?.toString() ??
                                (doc['warehouse_id_from'] != null ? 'شناسه ${doc['warehouse_id_from']}' : '-'),
                          ),
                        if (doc['warehouse_name_to'] != null || doc['warehouse_id_to'] != null)
                          _buildInfoRow(
                            theme,
                            'انبار مقصد',
                            doc['warehouse_name_to']?.toString() ??
                                (doc['warehouse_id_to'] != null ? 'شناسه ${doc['warehouse_id_to']}' : '-'),
                          ),
                      ],
                      if (doc['created_by_name'] != null || doc['created_by_user_id'] != null)
                        _buildInfoRow(
                          theme,
                          'ایجادکننده',
                          doc['created_by_name']?.toString() ??
                              (doc['created_by_user_id'] != null ? 'کاربر ${doc['created_by_user_id']}' : '-'),
                        ),
                      if (doc['created_at'] != null)
                        _buildInfoRow(theme, 'زمان ایجاد', _formatDocDateTime(doc['created_at'] as String?)),
                      if (doc['updated_at'] != null)
                        _buildInfoRow(theme, 'آخرین به‌روزرسانی', _formatDocDateTime(doc['updated_at'] as String?)),
                      if (doc['accounting_document_id'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InkWell(
                            onTap: () async {
                              if (_calendarController == null) {
                                await _loadCalendarController();
                              }
                              if (!context.mounted || _calendarController == null) return;
                              final aid = doc['accounting_document_id'] is int
                                  ? doc['accounting_document_id'] as int
                                  : int.tryParse('${doc['accounting_document_id']}');
                              if (aid == null) return;
                              showDialog(
                                context: context,
                                builder: (_) => DocumentDetailsDialog(
                                  documentId: aid,
                                  calendarController: _calendarController!,
                                ),
                              );
                            },
                            child: Text(
                              'سند حسابداری مرتبط: ${doc['accounting_document_id']}',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      if (_relatedDoc != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => WarehouseDocumentDetailsPage(
                                    businessId: widget.businessId,
                                    documentId: _relatedDoc!['id'] as int,
                                  ),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'حواله مرتبط: ${_relatedDoc!['code'] ?? _relatedDoc!['id']} (${_getStatusName(_relatedDoc!['status'])})',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
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
                            Text('اطلاعات ارسال', style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (doc['description'] != null && (doc['description'] as String).isNotEmpty)
                          _buildInfoRow(theme, 'شرح/توضیحات', doc['description'] as String),
                        if (doc['delivery_method'] != null)
                          _buildInfoRow(theme, 'روش ارسال', _getDeliveryMethodName(doc['delivery_method'] as String?)),
                        if (doc['carrier_name'] != null && (doc['carrier_name'] as String).isNotEmpty)
                          _buildInfoRow(theme, 'نام باربری/حمل و نقل', doc['carrier_name'] as String),
                        if (doc['recipient_name'] != null && (doc['recipient_name'] as String).isNotEmpty)
                          _buildInfoRow(theme, 'تحویل گیرنده', doc['recipient_name'] as String),
                        if (doc['recipient_phone'] != null && (doc['recipient_phone'] as String).isNotEmpty)
                          _buildInfoRow(theme, 'تلفن تحویل گیرنده', doc['recipient_phone'] as String),
                        if (doc['tracking_number'] != null && (doc['tracking_number'] as String).isNotEmpty)
                          _buildInfoRow(theme, 'شماره پیگیری/بارنامه/قبض', doc['tracking_number'] as String),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('خطوط حواله', style: theme.textTheme.titleMedium),
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
                          final lineMap = Map<String, dynamic>.from(line as Map);
                          final lineId = lineMap['id'] as int?;
                          final productId = lineMap['product_id'] as int?;
                          final warehouseId = lineMap['warehouse_id'] as int?;
                          final movement = lineMap['movement'] as String?;
                          final quantity = lineMap['quantity'] as num?;

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
