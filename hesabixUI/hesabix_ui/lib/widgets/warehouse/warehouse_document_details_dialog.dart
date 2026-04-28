import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import '../../services/warehouse_service.dart';
import '../../core/api_client.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/document/document_details_dialog.dart';
import '../../widgets/warehouse/warehouse_document_form_dialog.dart';
import '../../core/calendar_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/snackbar_helper.dart';

import '../../utils/web/web_utils.dart' as web_utils;
import '../../core/date_utils.dart' show HesabixDateUtils;
import 'warehouse_postal_label_print_dialog.dart';
import '../../utils/error_extractor.dart';

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
  Map<String, dynamic>? _relatedDoc; // حواله مرتبط (اصلی یا کنسلی)

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
    setState(() { _loading = true; _error = null; _relatedDoc = null; });
    try {
      final res = await _svc.getDoc(businessId: widget.businessId, docId: widget.documentId);
      final doc = Map<String, dynamic>.from(res['item'] ?? res);
      setState(() { _doc = doc; });
      
      // پیدا کردن حواله مرتبط
      await _loadRelatedDoc(doc);
    } catch (e) {
      setState(() { _error = ErrorExtractor.forContext(e, context); });
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
      // این یعنی این حواله کنسلی است و باید حواله اصلی را نشان دهیم
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

  String _movementNarrativeText(Map<String, dynamic> doc) {
    final docType = doc['doc_type'] as String? ?? '';
    final wf = doc['warehouse_name_from'] as String?;
    final wt = doc['warehouse_name_to'] as String?;
    final party = doc['source_invoice_party_name'] as String?;
    final invLabel = doc['source_invoice_type_label_fa'] as String?;
    final invCode = doc['source_document_code'] as String?;
    final st = doc['source_type'] as String?;
    final srcFa = doc['source_type_label_fa'] as String?;

    if (docType == 'transfer') {
      final from = wf ?? '';
      final to = wt ?? '';
      if (from.isEmpty && to.isEmpty) return '';
      return 'انتقال موجودی از «${from.isEmpty ? '—' : from}» به «${to.isEmpty ? '—' : to}».';
    }
    if (docType == 'issue' || docType == 'production_out') {
      final w = wf ?? wt;
      final parts = <String>['خروج کالا'];
      if (w != null && w.isNotEmpty) parts.add('از انبار «$w»');
      if (st == 'invoice') {
        final bits = <String>[];
        if (invLabel != null && invLabel.isNotEmpty) bits.add(invLabel);
        if (invCode != null && invCode.isNotEmpty) bits.add(invCode);
        if (bits.isNotEmpty) parts.add(bits.join(' '));
        if (party != null && party.isNotEmpty) parts.add('طرف: $party');
      } else {
        parts.add('منشأ: ${srcFa ?? st ?? '—'}');
      }
      return parts.join(' — ');
    }
    if (docType == 'receipt' || docType == 'production_in') {
      final w = wt ?? wf;
      final parts = <String>['ورود کالا'];
      if (w != null && w.isNotEmpty) parts.add('به انبار «$w»');
      if (st == 'invoice') {
        final bits = <String>[];
        if (invLabel != null && invLabel.isNotEmpty) bits.add(invLabel);
        if (invCode != null && invCode.isNotEmpty) bits.add(invCode);
        if (bits.isNotEmpty) parts.add(bits.join(' '));
        if (party != null && party.isNotEmpty) parts.add('طرف: $party');
      } else {
        parts.add('منشأ: ${srcFa ?? st ?? '—'}');
      }
      return parts.join(' — ');
    }
    return '';
  }

  void _openSourceInvoice(Map<String, dynamic> doc) {
    final sid = doc['source_document_id'];
    if (sid == null) return;
    final id = sid is int ? sid : int.tryParse('$sid');
    if (id == null) return;
    context.push('/business/${widget.businessId}/invoice/$id/edit');
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
      SnackBarHelper.show(context, message: 'انبار به‌روزرسانی شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _postDoc() async {
    try {
      await _svc.postDoc(businessId: widget.businessId, docId: widget.documentId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'حواله پست شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'خطا در پست: ${ErrorExtractor.forContext(e, context)}',
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
        SnackBarHelper.show(context, message: 'حواله حذف شد');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
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
      final result = await _svc.cancelDoc(businessId: widget.businessId, docId: widget.documentId);
      if (!mounted) return;
      final cancelDocCode = result['code'] as String?;
      final message = cancelDocCode != null
          ? 'حواله لغو شد. حواله پیش‌نویس با کد $cancelDocCode ایجاد شد.'
          : 'حواله لغو شد و حواله معکوس ایجاد شد.';
      SnackBarHelper.show(context, message: message);
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _editDoc() async {
    if (_doc == null || _doc!['status'] != 'draft') return;
    
    Navigator.of(context).pop(); // بستن دیالوگ جزئیات
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WarehouseDocumentFormDialog(
        businessId: widget.businessId,
        documentId: widget.documentId,
        calendarController: _calendarController,
      ),
    );

    if (result == true && mounted) {
      // اگر دیالوگ جزئیات هنوز باز است، داده‌ها را بارگذاری مجدد کن
      // در غیر این صورت، نیازی به بارگذاری نیست چون دیالوگ بسته شده
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
        SnackBarHelper.show(context, message: 'دانلود PDF در موبایل به زودی...');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'خطا در دانلود PDF: ${ErrorExtractor.forContext(e, context)}',
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
            IconButton(
              icon: const Icon(Icons.local_shipping_outlined),
              onPressed: () => showWarehousePostalLabelPrintDialog(
                context: context,
                businessId: widget.businessId,
                documentId: widget.documentId,
              ),
              tooltip: t.warehousePostalLabelTooltip,
            ),
            if (isDraft) ...[
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _editDoc,
                tooltip: 'ویرایش',
              ),
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
                  _buildInfoRow(theme, 'کد', doc['code']?.toString() ?? '-'),
                  _buildInfoRow(theme, t.warehouseDocumentType, _getDocTypeName(doc['doc_type'], t)),
                  _buildInfoRow(theme, t.warehouseDocumentStatus, _getStatusName(status, t)),
                  if (doc['document_date'] != null && _calendarController != null)
                    _buildInfoRow(
                      theme,
                      t.warehouseDocumentDate,
                      HesabixDateUtils.formatForDisplay(DateTime.tryParse(doc['document_date'] as String), _calendarController!.isJalali),
                    ),
                  if (doc['fiscal_year_title'] != null)
                    _buildInfoRow(theme, 'سال مالی', doc['fiscal_year_title'].toString()),
                  if (doc['total_quantity'] != null)
                    _buildInfoRow(theme, 'جمع تعداد (طبق نوع حواله)', _formatQuantity(doc['total_quantity'] as num?)),
                  if (doc['source_type'] != null || doc['source_type_label_fa'] != null)
                    _buildInfoRow(
                      theme,
                      'منشأ',
                      '${doc['source_type_label_fa'] ?? doc['source_type'] ?? '—'}',
                    ),
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
                  ] else ...[
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
                            if (_calendarController == null || !mounted) return;
                          }
                          if (!mounted) return;
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
                  // نمایش حواله مرتبط (اصلی یا کنسلی)
                  if (_relatedDoc != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop(); // بستن دیالوگ فعلی
                          showDialog(
                            context: context,
                            builder: (_) => WarehouseDocumentDetailsDialog(
                              businessId: widget.businessId,
                              documentId: _relatedDoc!['id'] as int,
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.link,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'حواله مرتبط: ${_relatedDoc!['code'] ?? _relatedDoc!['id']} (${_getStatusName(_relatedDoc!['status'], t)})',
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
          if (_movementNarrativeText(doc).isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.alt_route, color: theme.colorScheme.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'خلاصهٔ مسیر و طرف',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _movementNarrativeText(doc),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (doc['source_type'] == 'invoice' && doc['source_document_id'] != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'فاکتور مرتبط',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(theme, 'کد فاکتور', doc['source_document_code']?.toString() ?? '—'),
                    _buildInfoRow(theme, 'نوع فاکتور', doc['source_invoice_type_label_fa']?.toString() ?? '—'),
                    if ((doc['source_invoice_party_name'] as String?)?.isNotEmpty == true)
                      _buildInfoRow(theme, 'طرف حساب', doc['source_invoice_party_name'].toString()),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => _openSourceInvoice(doc),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('باز کردن فاکتور'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final productColW =
                          _warehouseLinesProductColumnWidth(lines, constraints.maxWidth);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: DataTable(
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('کالا / دسته')),
                              DataColumn(label: Text('واحد')),
                              DataColumn(label: Text('انبار')),
                              DataColumn(label: Text('نوع حرکت')),
                              DataColumn(label: Text('تعداد')),
                              DataColumn(label: Text('یونیک / سریال')),
                              DataColumn(label: Text('سایر')),
                            ],
                            rows: lines.map<DataRow>((line) {
                              final lineMap = Map<String, dynamic>.from(line as Map);
                              final lineId = lineMap['id'] as int?;
                              final productId = lineMap['product_id'] as int?;
                              final warehouseId = lineMap['warehouse_id'] as int?;
                              final warehouseName = lineMap['warehouse_name'] as String?;
                              final movement = lineMap['movement'] as String?;
                              final quantity = lineMap['quantity'] as num?;
                              final productName = lineMap['product_name'] as String?;
                              final productCode = lineMap['product_code'] as String?;
                              final productCategoryName = lineMap['product_category_name'] as String?;
                              final unit = lineMap['product_main_unit'] as String?;
                              final instanceSummary = _instanceSummaryText(lineMap['instance_data']);

                              return DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: productColW,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            productName ?? (productId != null ? 'شناسه $productId' : '-'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (productCode != null && productCode.isNotEmpty)
                                            Text(
                                              'کد: $productCode',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          if (productCategoryName != null && productCategoryName.isNotEmpty)
                                            Text(
                                              'دسته: $productCategoryName',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(unit?.isNotEmpty == true ? unit! : '-')),
                                  DataCell(
                                    isDraft && lineId != null
                                        ? SizedBox(
                                            width: 160,
                                            child: WarehouseComboboxWidget(
                                              businessId: widget.businessId,
                                              selectedWarehouseId: warehouseId,
                                              onChanged: (wid) {
                                                _updateLineWarehouse(lineId, wid);
                                              },
                                              selectDefaultWhenUnset: true,
                                            ),
                                          )
                                        : ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 160),
                                            child: Text(
                                              warehouseName ??
                                                  (warehouseId != null ? 'شناسه $warehouseId' : '-'),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                  ),
                                  DataCell(Text(movement == 'in' ? 'ورود' : 'خروج')),
                                  DataCell(Text(_formatQuantity(quantity))),
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 200),
                                      child: Text(
                                        instanceSummary,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    _lineExtraSnippet(lineMap['extra_info']) == null
                                        ? const Text('—')
                                        : Tooltip(
                                            message: _lineExtraSnippet(lineMap['extra_info'])!,
                                            child: const Icon(Icons.info_outline, size: 20),
                                          ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// عرض ستون «کالا»: در عرض عادی باقیماندهٔ ویو را می‌گیرد؛ برای نام‌های خیلی بلند
  /// عرض را زیاد می‌کند تا جدول از `SingleChildScrollView` افقی اسکرول بخورد.
  double _warehouseLinesProductColumnWidth(List<dynamic> lines, double viewportWidth) {
    const otherColumnsReserve = 440.0;
    final base = math.max(200.0, viewportWidth - otherColumnsReserve);
    double result = base;
    double approxLineWidth(String s) => math.max(40.0, s.runes.length * 8.5);
    for (final line in lines) {
      final m = Map<String, dynamic>.from(line as Map);
      final productId = m['product_id'] as int?;
      final name = m['product_name'] as String?;
      final display = (name != null && name.isNotEmpty)
          ? name
          : (productId != null ? 'شناسه $productId' : '-');
      final code = m['product_code'] as String?;
      final cat = m['product_category_name'] as String?;
      var w = approxLineWidth(display);
      if (code != null && code.isNotEmpty) {
        w = math.max(w, approxLineWidth('کد: $code'));
      }
      if (cat != null && cat.isNotEmpty) {
        w = math.max(w, approxLineWidth('دسته: $cat'));
      }
      w = (w + 28).clamp(base, 1600.0);
      result = math.max(result, w);
    }
    return result;
  }

  bool _hasDeliveryInfo(Map<String, dynamic> doc) {
    return (doc['description'] != null && (doc['description'] as String).isNotEmpty) ||
           doc['delivery_method'] != null ||
           (doc['carrier_name'] != null && (doc['carrier_name'] as String).isNotEmpty) ||
           (doc['recipient_name'] != null && (doc['recipient_name'] as String).isNotEmpty) ||
           (doc['recipient_phone'] != null && (doc['recipient_phone'] as String).isNotEmpty) ||
           (doc['tracking_number'] != null && (doc['tracking_number'] as String).isNotEmpty);
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

  String _instanceSummaryText(dynamic raw) {
    if (raw is! List || raw.isEmpty) return '—';
    final parts = <String>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final serial = m['serial_number']?.toString();
      final barcode = m['barcode']?.toString();
      if (serial != null && serial.isNotEmpty) {
        parts.add(serial);
      } else if (barcode != null && barcode.isNotEmpty) {
        parts.add(barcode);
      } else {
        parts.add('شناسه ${m['id'] ?? ''}');
      }
      if (parts.length >= 10) break;
    }
    if (parts.isEmpty) return '—';
    return parts.join('، ');
  }

  String? _lineExtraSnippet(dynamic extra) {
    if (extra is! Map || extra.isEmpty) return null;
    final m = Map<String, dynamic>.from(extra);
    final keys = m.keys.map((k) => k.toString()).toList()..sort();
    final buf = StringBuffer();
    var n = 0;
    for (final k in keys) {
      buf.write('$k: ${m[k]}');
      n++;
      if (n >= 8) {
        buf.write(' …');
        break;
      }
      buf.write('\n');
    }
    return buf.toString().trim();
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

