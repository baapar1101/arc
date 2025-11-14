import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/services/document_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/services/warehouse_service.dart';
import 'dart:html' as html;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/report_template_service.dart';

/// دیالوگ نمایش جزئیات کامل سند حسابداری
class DocumentDetailsDialog extends StatefulWidget {
  final int documentId;
  final CalendarController calendarController;

  const DocumentDetailsDialog({
    super.key,
    required this.documentId,
    required this.calendarController,
  });

  @override
  State<DocumentDetailsDialog> createState() => _DocumentDetailsDialogState();
}

class _DocumentDetailsDialogState extends State<DocumentDetailsDialog> {
  late DocumentService _service;
  DocumentModel? _document;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isGeneratingPdf = false;
  final _warehouseService = WarehouseService();
  List<dynamic> _relatedWhDocs = const [];
  final ReportTemplateService _templateService = ReportTemplateService(ApiClient());
  List<Map<String, dynamic>> _invoiceTemplates = const [];
  bool _loadingInvoiceTemplates = false;
  int? _selectedInvoiceTemplateId;

  @override
  void initState() {
    super.initState();
    _service = DocumentService(ApiClient());
    _loadDocument();
  }

  Future<void> _generatePdf() async {
    if (_document == null) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final api = ApiClient();
      final doc = _document!;
      String path;
      // اگر فاکتور است، از endpoint اختصاصی فاکتور استفاده کنیم تا قالب invoices/detail اعمال شود
      if (doc.documentType.startsWith('invoice')) {
        path = '/invoices/business/${doc.businessId}/${doc.id}/pdf';
      } else {
        // سایر اسناد: endpoint عمومی با قالب documents/detail
        path = '/documents/${doc.id}/pdf';
      }
      final query = <String, dynamic>{};
      if (doc.documentType.startsWith('invoice') && _selectedInvoiceTemplateId != null) {
        query['template_id'] = _selectedInvoiceTemplateId;
      }
      final bytes = await api.downloadPdf(path, query: query.isNotEmpty ? query : null);
      await _savePdfFile(bytes, doc.code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).pdfSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context).pdfError}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _savePdfFile(List<int> bytes, String filename) async {
    try {
      final name = filename.endsWith('.pdf') ? filename : '$filename.pdf';
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', name)
        ..click();
      html.Url.revokeObjectUrl(url);
      // ignore: avoid_print
      print('✅ PDF downloaded successfully: $name');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error downloading PDF: $e');
    }
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final doc = await _service.getDocument(widget.documentId);
      if (mounted) {
        setState(() {
          _document = doc;
          _isLoading = false;
        });
      }
      // اگر سند از نوع فاکتور باشد، قالب‌های چاپ فاکتور را بارگذاری کن
      try {
        if (doc.documentType.startsWith('invoice')) {
          await _loadInvoiceTemplates(doc.businessId);
        }
      } catch (_) {
        // خطای بارگذاری قالب‌ها نباید نمایش سند را متوقف کند
      }
      // load related warehouse docs
      try {
        final data = await _warehouseService.search(
          businessId: doc.businessId,
          limit: 50,
          filters: {
            'source_type': 'invoice',
            'source_document_id': widget.documentId,
          },
        );
        if (mounted) {
          setState(() {
            _relatedWhDocs = List<dynamic>.from(data['items'] ?? const []);
          });
        }
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadInvoiceTemplates(int businessId) async {
    setState(() {
      _loadingInvoiceTemplates = true;
    });
    try {
      final items = await _templateService.listTemplates(
        businessId: businessId,
        moduleKey: 'invoices',
        subtype: 'detail',
        status: 'published',
      );
      if (!mounted) return;
      setState(() {
        _invoiceTemplates = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _invoiceTemplates = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingInvoiceTemplates = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))
              : _errorMessage != null
                  ? SizedBox(height: 240, child: Center(child: Text(_errorMessage!)))
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // هدر
                          _buildHeader(theme),

                          // محتوای اصلی
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _errorMessage != null
                                    ? _buildError()
                                    : _buildContent(theme),
                          ),

                          // فوتر
                          _buildFooter(),
                          const SizedBox(height: 16),
                          if (_relatedWhDocs.isNotEmpty) ...[
                            Text('حواله‌های مرتبط', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Card(
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _relatedWhDocs.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final it = _relatedWhDocs[index] as Map<String, dynamic>;
                                  return ListTile(
                                    dense: true,
                                    title: Text('${it['code'] ?? '-'} • ${it['doc_type'] ?? ''} • ${it['status'] ?? ''}'),
                                    subtitle: Text(it['document_date'] ?? ''),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.publish),
                                      onPressed: (it['status'] == 'draft') ? () async {
                                        try {
                                          await _warehouseService.postDoc(
                                            businessId: _document!.businessId,
                                            docId: it['id'],
                                          );
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('حواله پست شد')),
                                          );
                                          _loadDocument();
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('خطا در پست حواله: $e')),
                                          );
                                        }
                                      } : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  /// ساخت هدر دیالوگ
  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description,
            size: 28,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'جزئیات سند ${_document?.code ?? ''}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                if (_document != null)
                  Text(
                    _document!.getDocumentTypeName(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }

  /// ساخت پیام خطا
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'خطا در بارگذاری سند',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'خطای نامشخص',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadDocument,
            icon: const Icon(Icons.refresh),
            label: const Text('تلاش مجدد'),
          ),
        ],
      ),
    );
  }

  /// ساخت محتوای اصلی
  Widget _buildContent(ThemeData theme) {
    if (_document == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // اطلاعات هدر سند
          _buildDocumentHeader(theme),

          const SizedBox(height: 24),

          // جدول سطرهای سند
          _buildLinesTable(theme),

          const SizedBox(height: 16),

          // جمع کل
          _buildTotals(theme),
        ],
      ),
    );
  }

  /// ساخت اطلاعات هدر سند
  Widget _buildDocumentHeader(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات سند',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            _buildInfoRow('شماره سند:', _document!.code),
            _buildInfoRow('نوع سند:', _document!.getDocumentTypeName()),
            _buildInfoRow('تاریخ سند:', _document!.documentDateRaw ?? '-'),
            _buildInfoRow('سال مالی:', _document!.fiscalYearTitle ?? '-'),
            _buildInfoRow('ارز:', _document!.currencyCode ?? '-'),
            _buildInfoRow('وضعیت:', _document!.statusText),
            _buildInfoRow('ایجادکننده:', _document!.createdByName ?? '-'),
            if (_document!.description != null && _document!.description!.isNotEmpty)
              _buildInfoRow('توضیحات:', _document!.description!),
          ],
        ),
      ),
    );
  }

  /// ساخت یک ردیف اطلاعات
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// ساخت جدول سطرهای سند
  Widget _buildLinesTable(ThemeData theme) {
    final lines = _document!.lines ?? [];

    if (lines.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'هیچ سطری برای این سند ثبت نشده است',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'سطرهای سند',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child:             DataTable(
              headingRowColor: WidgetStateProperty.all(
                theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              ),
              columns: const [
                DataColumn(label: Text('ردیف', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('حساب', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('طرف‌حساب', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('بدهکار', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('بستانکار', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('توضیحات', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: lines.asMap().entries.map((entry) {
                final index = entry.key;
                final line = entry.value;
                return DataRow(
                  cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          line.fullAccountName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 150,
                        child: Text(
                          line.counterpartyName ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        line.debit > 0 ? formatWithThousands(line.debit.toInt()) : '-',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.red,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    DataCell(
                      Text(
                        line.credit > 0 ? formatWithThousands(line.credit.toInt()) : '-',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.green,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          line.description ?? '-',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// ساخت بخش جمع کل
  Widget _buildTotals(ThemeData theme) {
    return Card(
      elevation: 2,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildTotalItem(
              'جمع بدهکار',
              formatWithThousands(_document!.totalDebit.toInt()),
              Colors.red,
            ),
            Container(
              width: 2,
              height: 40,
              color: theme.dividerColor,
            ),
            _buildTotalItem(
              'جمع بستانکار',
              formatWithThousands(_document!.totalCredit.toInt()),
              Colors.green,
            ),
            Container(
              width: 2,
              height: 40,
              color: theme.dividerColor,
            ),
            _buildTotalItem(
              'تعداد سطرها',
              '${_document!.linesCount}',
              theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  /// ساخت یک آیتم از جمع کل
  Widget _buildTotalItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
            fontFamily: 'monospace',
          ),
          textDirection: TextDirection.ltr,
        ),
      ],
    );
  }

  /// ساخت فوتر دیالوگ
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // دکمه چاپ PDF
          OutlinedButton.icon(
            onPressed: _isGeneratingPdf ? null : _generatePdf,
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            label: Text(_isGeneratingPdf ? AppLocalizations.of(context).generating : AppLocalizations.of(context).printPdf),
          ),
          const SizedBox(width: 12),
          if (_document != null &&
              _document!.documentType.startsWith('invoice') &&
              !_loadingInvoiceTemplates &&
              _invoiceTemplates.isNotEmpty) ...[
            DropdownButton<int?>(
              value: _selectedInvoiceTemplateId,
              hint: Text(AppLocalizations.of(context).printTemplatePublished),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(AppLocalizations.of(context).noCustomTemplate),
                ),
                ..._invoiceTemplates.map((tpl) {
                  final id = (tpl['id'] as num).toInt();
                  final name = (tpl['name'] ?? 'Template').toString();
                  final isDefault = tpl['is_default'] == true;
                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Row(
                      children: [
                        if (isDefault) const Icon(Icons.star, size: 16),
                        if (isDefault) const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedInvoiceTemplateId = value;
                });
              },
            ),
            const SizedBox(width: 12),
          ],
          // دکمه بستن
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }
}

