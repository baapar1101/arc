import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

/// CSAT (1–5 stars) dialog after ticket closure.
class TicketCsatDialog extends StatefulWidget {
  final int ticketId;

  const TicketCsatDialog({super.key, required this.ticketId});

  static Future<bool?> show(BuildContext context, int ticketId) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TicketCsatDialog(ticketId: ticketId),
    );
  }

  @override
  State<TicketCsatDialog> createState() => _TicketCsatDialogState();
}

class _TicketCsatDialogState extends State<TicketCsatDialog> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) return;
    setState(() => _submitting = true);
    try {
      await SupportService(ApiClient()).submitTicketCsat(
        widget.ticketId,
        rating: _rating,
        comment: _comment.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('رضایت از پشتیبانی'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'از پاسخگویی تیم پشتیبانی چقدر راضی بودید؟',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return IconButton(
                  onPressed: () => setState(() => _rating = star),
                  icon: Icon(
                    star <= _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber.shade700,
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              decoration: const InputDecoration(
                labelText: 'نظر (اختیاری)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context, false), child: const Text('بعداً')),
        FilledButton(
          onPressed: _submitting || _rating < 1 ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ثبت'),
        ),
      ],
    );
  }
}
