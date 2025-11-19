import 'package:flutter/material.dart';
import '../../services/production_settings_service.dart';

class ProductionSettingsDialog extends StatefulWidget {
  final int businessId;
  const ProductionSettingsDialog({super.key, required this.businessId});

  @override
  State<ProductionSettingsDialog> createState() => _ProductionSettingsDialogState();
}

class _ProductionSettingsDialogState extends State<ProductionSettingsDialog> {
  final _service = ProductionSettingsService();
  final _invCtrl = TextEditingController();
  final _wipCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (inv, wip) = await _service.getDefaultAccounts(widget.businessId);
    if (!mounted) return;
    setState(() {
      _invCtrl.text = inv ?? '10102';
      _wipCtrl.text = wip ?? '10106';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _invCtrl.dispose();
    _wipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تنظیمات حساب‌های تولید', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (_loading) const Center(child: CircularProgressIndicator()) else ...[
                TextField(
                  controller: _invCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'کد حساب موجودی کالا (مصرف مواد)'
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _wipCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'کد حساب کالای در جریان ساخت/محصول تولیدی'
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        if (!context.mounted) return;
                        final ctx = context;
                        await _service.saveDefaultAccounts(
                          businessId: widget.businessId,
                          inventoryCode: _invCtrl.text.trim(),
                          wipCode: _wipCtrl.text.trim(),
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('ذخیره'),
                    ),
                  ],
                )
              ],
            ],
          ),
        ),
      ),
    );
  }
}


