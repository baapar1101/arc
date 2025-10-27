import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/services/document_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;

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

  @override
  void initState() {
    super.initState();
    _service = DocumentService(ApiClient());
    _loadDocument();
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
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
          ],
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
            onPressed: () {
              // TODO: پیاده‌سازی چاپ PDF
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('چاپ PDF در حال پیاده‌سازی است')),
              );
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('چاپ PDF'),
          ),
          const SizedBox(width: 12),
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

