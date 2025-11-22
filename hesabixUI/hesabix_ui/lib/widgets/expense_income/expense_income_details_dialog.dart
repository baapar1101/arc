import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/expense_income_document.dart';
import 'package:hesabix_ui/services/expense_income_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import '../../utils/snackbar_helper.dart';

/// دیالوگ مشاهده جزئیات سند هزینه/درآمد
class ExpenseIncomeDetailsDialog extends StatefulWidget {
  final ExpenseIncomeDocument document;
  final CalendarController calendarController;
  final int businessId;
  final ApiClient apiClient;

  const ExpenseIncomeDetailsDialog({
    super.key,
    required this.document,
    required this.calendarController,
    required this.businessId,
    required this.apiClient,
  });

  @override
  State<ExpenseIncomeDetailsDialog> createState() => _ExpenseIncomeDetailsDialogState();
}

class _ExpenseIncomeDetailsDialogState extends State<ExpenseIncomeDetailsDialog> {
  bool _isGeneratingPdf = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final doc = widget.document;
    
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // هدر دیالوگ
            _buildHeader(t, doc),
            
            // محتوای اصلی
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اطلاعات کلی سند
                    _buildDocumentInfo(t, doc),
                    
                    const SizedBox(height: 24),
                    
                    // خطوط حساب‌ها
                    _buildItemLines(t, doc),
                    
                    const SizedBox(height: 24),
                    
                    // خطوط طرف‌حساب‌ها
                    _buildCounterpartyLines(t, doc),
                  ],
                ),
              ),
            ),
            
            // دکمه‌های پایین
            _buildFooter(t),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, ExpenseIncomeDocument doc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'جزئیات سند ${doc.documentTypeName}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'کد سند: ${doc.code}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: 'بستن',
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentInfo(AppLocalizations t, ExpenseIncomeDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات کلی سند',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildInfoRow('نوع سند', doc.documentTypeName),
            _buildInfoRow('تاریخ سند', HesabixDateUtils.formatForDisplay(doc.documentDate, widget.calendarController.isJalali)),
            _buildInfoRow('تاریخ ثبت', HesabixDateUtils.formatForDisplay(doc.registeredAt, widget.calendarController.isJalali)),
            _buildInfoRow('ارز', doc.currencyCode ?? 'نامشخص'),
            _buildInfoRow('ایجادکننده', doc.createdByName ?? 'نامشخص'),
            _buildInfoRow('مبلغ کل', '${formatWithThousands(doc.totalAmount)} ریال'),
            if (doc.description != null && doc.description!.isNotEmpty)
              _buildInfoRow('توضیحات', doc.description!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemLines(AppLocalizations t, ExpenseIncomeDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطوط حساب‌ها (${doc.itemLinesCount})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (doc.itemLines.isEmpty)
              const Text('هیچ خط حسابی یافت نشد')
            else
              ...doc.itemLines.map((line) => _buildItemLineItem(line)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemLineItem(ItemLine line) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.accountName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'کد: ${line.accountCode}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (line.description != null && line.description!.isNotEmpty)
                  Text(
                    line.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            '${formatWithThousands(line.amount)} ریال',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCounterpartyLines(AppLocalizations t, ExpenseIncomeDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطوط طرف‌حساب‌ها (${doc.counterpartyLinesCount})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (doc.counterpartyLines.isEmpty)
              const Text('هیچ خط طرف‌حسابی یافت نشد')
            else
              ...doc.counterpartyLines.map((line) => _buildCounterpartyLineItem(line)),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterpartyLineItem(CounterpartyLine line) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.displayName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'نوع: ${line.transactionTypeName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'تاریخ: ${HesabixDateUtils.formatForDisplay(line.transactionDate, widget.calendarController.isJalali)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatWithThousands(line.amount)} ریال',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (line.commission != null && line.commission! > 0)
                    Text(
                      'کارمزد: ${formatWithThousands(line.commission!)} ریال',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (line.description != null && line.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              line.description!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isGeneratingPdf ? null : _generatePdf,
            icon: _isGeneratingPdf 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf),
            label: Text(_isGeneratingPdf ? 'در حال تولید...' : 'خروجی PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      // ایجاد PDF از سند
      final service = ExpenseIncomeService(widget.apiClient);
      final pdfBytes = await service.generatePdf(widget.document.id);

      // ذخیره فایل
      await _savePdfFile(pdfBytes, widget.document.code);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فایل PDF با موفقیت تولید شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در تولید PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  Future<void> _savePdfFile(List<int> bytes, String filename) async {
    if (kIsWeb) {
      await web_utils.saveBytesAsFileWeb(
        bytes,
        filename.endsWith('.pdf') ? filename : '$filename.pdf',
        mimeType: 'application/pdf',
      );
    } else {
      throw UnsupportedError('دانلود فایل فقط در نسخه وب پشتیبانی می‌شود');
    }
  }
}
