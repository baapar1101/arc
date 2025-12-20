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
  final _formKey = GlobalKey<FormState>();
  final _invCtrl = TextEditingController();
  final _wipCtrl = TextEditingController();
  final _overheadCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (inv, wip, overhead) = await _service.getDefaultAccounts(widget.businessId);
    if (!mounted) return;
    setState(() {
      _invCtrl.text = inv ?? '10102';
      _wipCtrl.text = wip ?? '10106';
      _overheadCtrl.text = overhead ?? '70408';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _invCtrl.dispose();
    _wipCtrl.dispose();
    _overheadCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _service.saveDefaultAccounts(
        businessId: widget.businessId,
        inventoryCode: _invCtrl.text.trim(),
        wipCode: _wipCtrl.text.trim(),
        overheadCode: _overheadCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'خطا در ذخیره تنظیمات: $e';
      });
    }
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
                Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _invCtrl,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'کد حساب موجودی کالا (مصرف مواد)',
                          helperText: 'کد حساب برای مصرف مواد اولیه در تولید',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'لطفاً کد حساب را وارد کنید';
                          }
                          if (value.trim().length < 3) {
                            return 'کد حساب باید حداقل 3 کاراکتر باشد';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _wipCtrl,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'کد حساب کالای در جریان ساخت/محصول تولیدی',
                          helperText: 'کد حساب برای محصول در حال تولید',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'لطفاً کد حساب را وارد کنید';
                          }
                          if (value.trim().length < 3) {
                            return 'کد حساب باید حداقل 3 کاراکتر باشد';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _overheadCtrl,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'کد حساب هزینه عملیات/سربار تولید',
                          helperText: 'برای ثبت هزینه عملیات تولید: بدهکار WIP / بستانکار این حساب',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'لطفاً کد حساب را وارد کنید';
                          }
                          if (value.trim().length < 3) {
                            return 'کد حساب باید حداقل 3 کاراکتر باشد';
                          }
                          return null;
                        },
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context, false),
                      child: const Text('انصراف'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _handleSave,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('ذخیره'),
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


