import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/date_utils.dart';
import '../../core/calendar_controller.dart';
import '../../core/api_client.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import '../../utils/snackbar_helper.dart';

class TransferDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> document;
  final CalendarController calendarController;
  const TransferDetailsDialog({
    super.key, 
    required this.document,
    required this.calendarController,
  });

  @override
  State<TransferDetailsDialog> createState() => _TransferDetailsDialogState();
}

class _TransferDetailsDialogState extends State<TransferDetailsDialog> {
  bool _isGeneratingPdf = false;

  String _typeFa(String? t) {
    switch (t) {
      case 'bank':
        return 'بانک';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواه';
      default:
        return t ?? '';
    }
  }

  String _formatSourceDestination(String? type, String? name) {
    final typeFa = _typeFa(type);
    final nameStr = name ?? '';
    if (typeFa.isEmpty && nameStr.isEmpty) return '';
    return '$typeFa $nameStr'.trim();
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      final api = ApiClient();
      final documentId = widget.document['id'] as int?;
      if (documentId == null) {
        throw Exception('شناسه سند یافت نشد');
      }
      
      final path = '/transfers/$documentId/pdf';
      final bytes = await api.downloadPdf(path);
      await _savePdfFile(bytes, widget.document['code'] as String? ?? 'transfer');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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

  @override
  Widget build(BuildContext context) {
    final lines = List<Map<String, dynamic>>.from(widget.document['account_lines'] as List? ?? const []);
    final code = widget.document['code'] as String? ?? '';
    final dateStr = widget.document['document_date'] as String? ?? '';
    final date = DateTime.tryParse(dateStr);
    final total = (widget.document['total_amount'] as num?)?.toStringAsFixed(0) ?? '0';
    final currencyCode = widget.document['currency_code'] as String? ?? 'ریال';
    
    // Get source and destination info
    final sourceType = widget.document['source_type'] as String?;
    final sourceName = widget.document['source_name'] as String?;
    final destinationType = widget.document['destination_type'] as String?;
    final destinationName = widget.document['destination_name'] as String?;
    
    final sourceText = _formatSourceDestination(sourceType, sourceName);
    final destinationText = _formatSourceDestination(destinationType, destinationName);
    
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz),
                  const SizedBox(width: 8),
                  Expanded(child: Text('سند انتقال $code')),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(label: Text('تاریخ: ${HesabixDateUtils.formatForDisplay(date, widget.calendarController.isJalali)}')),
                      const SizedBox(width: 8),
                      Chip(label: Text('مبلغ کل: $total $currencyCode')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (sourceText.isNotEmpty || destinationText.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('مبدا', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(sourceText.isNotEmpty ? sourceText : 'نامشخص'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('مقصد', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(destinationText.isNotEmpty ? destinationText : 'نامشخص'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: lines.length,
                separatorBuilder: (_, separatorIndex) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final l = lines[i];
                  final name = (l['account_name'] as String?) ?? '';
                  final code = (l['account_code'] as String?) ?? '';
                  final side = (l['side'] as String?) ?? '';
                  final isCommission = (l['is_commission_line'] as bool?) ?? false;
                  final amount = (l['amount'] as num?)?.toStringAsFixed(0) ?? '';
                  
                  String sideText = '';
                  if (isCommission) {
                    sideText = 'کارمزد';
                  } else {
                    switch (side) {
                      case 'source':
                        sideText = 'مبدا';
                        break;
                      case 'destination':
                        sideText = 'مقصد';
                        break;
                      default:
                        sideText = side;
                    }
                  }
                  
                  return ListTile(
                    leading: Icon(isCommission ? Icons.receipt_long : Icons.account_balance_wallet),
                    title: Text(name),
                    subtitle: Text('کد: $code • سمت: $sideText'),
                    trailing: Text('$amount $currencyCode'),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
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
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('بستن'),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
