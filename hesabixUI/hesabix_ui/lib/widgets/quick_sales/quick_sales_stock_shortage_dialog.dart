import 'package:flutter/material.dart';

/// Scrollable on phones, including when a sale contains many shortage lines.
class QuickSalesStockShortageDialog extends StatelessWidget {
  final List<Map<String, dynamic>> shortages;
  final String? saleLabel;
  final bool workflowEnabled;
  final bool canOverride;
  final bool canCorrect;
  final bool correctionAlreadyApplied;
  final VoidCallback onCancel;
  final VoidCallback onPark;
  final VoidCallback onCorrect;
  final VoidCallback onOverride;

  const QuickSalesStockShortageDialog({
    super.key,
    required this.shortages,
    this.saleLabel,
    required this.workflowEnabled,
    required this.canOverride,
    required this.canCorrect,
    this.correctionAlreadyApplied = false,
    required this.onCancel,
    required this.onPark,
    required this.onCorrect,
    required this.onOverride,
  });

  bool get _hasUnique => shortages.any(
    (item) =>
        item['inventory_mode']?.toString().trim().toLowerCase() == 'unique',
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('کسری موجودی'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (saleLabel != null)
              Text(
                'فروش: $saleLabel',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const Text('موجودی سیستمی کالاهای زیر برای ثبت فاکتور کافی نیست:'),
            const SizedBox(height: 12),
            for (final item in shortages)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${item['product_name'] ?? 'کالا'}'),
                subtitle: Text(
                  '${item['warehouse_name'] ?? 'انبار'} — موجودی: ${item['available_quantity'] ?? 0}، موردنیاز: ${item['requested_quantity'] ?? 0}، کسری: ${item['shortage_quantity'] ?? '—'}',
                ),
              ),
            if (!workflowEnabled)
              const Text(
                'گردش‌کار کسری موجودی در تنظیمات فروش سریع فعال نیست.',
              ),
            if (_hasUnique)
              const Text(
                'ثبت موجودی منفی برای کالای یونیک/سریالی مجاز نیست؛ سریال و گردش واقعی انبار را بررسی کنید.',
              ),
            if (workflowEnabled && !canOverride && !_hasUnique)
              const Text(
                'برای ثبت یک‌باره موجودی منفی، مجوز مربوط به موجودی منفی لازم است.',
              ),
            if (workflowEnabled && !canCorrect)
              const Text(
                'اصلاح موجودی به مجوز ایجاد و قطعی‌کردن سند کالای درآمدشده نیاز دارد.',
              ),
            if (correctionAlreadyApplied)
              const Text(
                'اصلاح موجودی این فروش قبلاً ثبت شده است؛ برای جلوگیری از ثبت سند تکراری، اصلاح دوباره در دسترس نیست.',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: onCancel, child: const Text('انصراف')),
        TextButton(onPressed: onPark, child: const Text('پارک فروش')),
        if (workflowEnabled && canCorrect && !correctionAlreadyApplied)
          OutlinedButton(
            onPressed: onCorrect,
            child: const Text('اصلاح موجودی'),
          ),
        if (workflowEnabled && canOverride && !_hasUnique)
          FilledButton(
            onPressed: onOverride,
            child: const Text('ثبت با موجودی منفی'),
          ),
      ],
    );
  }
}
