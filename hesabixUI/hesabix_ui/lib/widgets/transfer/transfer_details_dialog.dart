import 'package:flutter/material.dart';
import '../../core/date_utils.dart';
import '../../core/calendar_controller.dart';

class TransferDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> document;
  final CalendarController calendarController;
  const TransferDetailsDialog({
    super.key, 
    required this.document,
    required this.calendarController,
  });

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

  @override
  Widget build(BuildContext context) {
    final lines = List<Map<String, dynamic>>.from(document['account_lines'] as List? ?? const []);
    final code = document['code'] as String? ?? '';
    final dateStr = document['document_date'] as String? ?? '';
    final date = DateTime.tryParse(dateStr);
    final total = (document['total_amount'] as num?)?.toStringAsFixed(0) ?? '0';
    
    // Get source and destination info
    final sourceType = document['source_type'] as String?;
    final sourceName = document['source_name'] as String?;
    final destinationType = document['destination_type'] as String?;
    final destinationName = document['destination_name'] as String?;
    
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
                      Chip(label: Text('تاریخ: ${HesabixDateUtils.formatForDisplay(date, calendarController.isJalali)}')),
                      const SizedBox(width: 8),
                      Chip(label: Text('مبلغ کل: $total ریال')),
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
                separatorBuilder: (_, __) => const Divider(height: 1),
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
                    trailing: Text('$amount ریال'),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('بستن'),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
