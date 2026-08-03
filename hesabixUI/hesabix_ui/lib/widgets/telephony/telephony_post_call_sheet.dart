import 'package:flutter/material.dart';

import '../../services/telephony/telephony_session_controller.dart';

Future<void> showTelephonyPostCallSheet(
  BuildContext context, {
  required TelephonySessionController session,
}) async {
  final call = Map<String, dynamic>.from(session.activeCall ?? const {});
  final callId = int.tryParse('${call['id']}');
  if (callId == null) {
    session.clearPendingPostCall();
    return;
  }

  final note = TextEditingController(text: '${call['note'] ?? ''}');
  String category = '${call['category'] ?? 'support'}';
  String outcome = '${call['outcome'] ?? 'completed'}';

  final categories = {
    'sales': 'فروش',
    'support': 'پشتیبانی',
    'finance': 'مالی',
    'other': 'سایر',
  };
  final outcomes = {
    'completed': 'موفق',
    'callback': 'نیاز به تماس مجدد',
    'no_answer': 'بدون پاسخ',
    'wrong_number': 'شماره اشتباه',
    'other': 'سایر',
  };

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ثبت نتیجه تماس',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${call['from_number_normalized'] ?? call['to_number_normalized'] ?? ''} · ${call['status'] ?? ''}',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Text('دسته‌بندی', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in categories.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: category == e.key,
                          onSelected: (_) => setLocal(() => category = e.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('نتیجه', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in outcomes.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: outcome == e.key,
                          onSelected: (_) => setLocal(() => outcome = e.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: note,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'یادداشت',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await session.saveCallNote(
                        callId: callId,
                        note: note.text.trim(),
                        category: category,
                        outcome: outcome,
                      );
                      session.clearPendingPostCall();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('ذخیره و بستن'),
                  ),
                  TextButton(
                    onPressed: () {
                      session.clearPendingPostCall();
                      Navigator.pop(ctx);
                    },
                    child: const Text('بعداً'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  } finally {
    note.dispose();
    session.clearPendingPostCall();
  }
}
