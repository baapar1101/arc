import 'package:flutter/material.dart';

class TransferDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> document;
  const TransferDetailsDialog({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final lines = List<Map<String, dynamic>>.from(document['account_lines'] as List? ?? const []);
    final code = document['code'] as String? ?? '';
    final date = document['document_date'] as String? ?? '';
    final total = (document['total_amount'] as num?)?.toStringAsFixed(0) ?? '0';
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
              child: Row(
                children: [
                  Chip(label: Text('تاریخ: $date')),
                  const SizedBox(width: 8),
                  Chip(label: Text('مبلغ کل: $total')),
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
                  return ListTile(
                    leading: Icon(isCommission ? Icons.receipt_long : Icons.account_balance_wallet),
                    title: Text(name),
                    subtitle: Text('کد: $code • سمت: ${isCommission ? 'کارمزد' : side}'),
                    trailing: Text(amount),
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
