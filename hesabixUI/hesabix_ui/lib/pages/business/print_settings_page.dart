import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';

class BusinessPrintSettingsPage extends StatefulWidget {
  final int businessId;

  const BusinessPrintSettingsPage({super.key, required this.businessId});

  @override
  State<BusinessPrintSettingsPage> createState() => _BusinessPrintSettingsPageState();
}

class _BusinessPrintSettingsPageState extends State<BusinessPrintSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final Map<String, _PrintConfig> _configs = {};
  String _selectedDocType = 'all';

  final List<_DocTypeDef> _docTypes = const [
    _DocTypeDef('all', 'تنظیمات عمومی (همه فاکتورها)'),
    _DocTypeDef('invoice_sales', 'فاکتور فروش'),
    _DocTypeDef('invoice_sales_return', 'برگشت از فروش'),
    _DocTypeDef('invoice_purchase', 'فاکتور خرید'),
    _DocTypeDef('invoice_purchase_return', 'برگشت از خرید'),
    _DocTypeDef('invoice_direct_consumption', 'مصرف مستقیم'),
    _DocTypeDef('invoice_production', 'تولید'),
    _DocTypeDef('invoice_waste', 'ضایعات'),
  ];

  final _footerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await BusinessApiService.getPrintSettings(widget.businessId);
      _configs.clear();

      final defaultJson = (data['default'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      _configs['all'] = _PrintConfig.fromJson(defaultJson);

      final perTypeJson = (data['per_type'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      perTypeJson.forEach((key, value) {
        if (value is Map) {
          _configs[key] = _PrintConfig.fromJson(value.cast<String, dynamic>());
        }
      });

      _selectedDocType = 'all';
      _syncFormWithConfig();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  _PrintConfig _currentConfig() {
    return _configs[_selectedDocType] ?? _configs['all'] ?? _PrintConfig.initial();
  }

  bool _hasCustomConfigForCurrentType() {
    if (_selectedDocType == 'all') return true;
    return _configs.containsKey(_selectedDocType);
  }

  void _syncFormWithConfig() {
    final cfg = _currentConfig();
    _footerController.text = cfg.footerNote ?? '';
  }

  void _updateCurrentConfig(_PrintConfig cfg) {
    if (_selectedDocType == 'all') {
      _configs['all'] = cfg;
    } else {
      // اگر برای این نوع تنظیم اختصاصی نداریم، آن را ایجاد می‌کنیم
      _configs[_selectedDocType] = cfg;
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // آخرین تغییرات فیلد متن را روی مدل اعمال کنیم
      final current = _currentConfig().copyWith(
        footerNote: _footerController.text.trim().isEmpty ? null : _footerController.text.trim(),
      );
      _updateCurrentConfig(current);

      final defaultCfg = _configs['all'] ?? _PrintConfig.initial();

      final Map<String, dynamic> payload = {
        'default': defaultCfg.toJson(),
        'per_type': <String, dynamic>{},
      };

      final perType = payload['per_type'] as Map<String, dynamic>;
      _configs.forEach((key, value) {
        if (key == 'all') return;
        perType[key] = value.toJson();
      });

      final saved = await BusinessApiService.updatePrintSettings(widget.businessId, payload);

      // بعد از ذخیره، از پاسخ سرور دوباره هم‌خوان‌سازی می‌کنیم
      final defaultJson = (saved['default'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final perTypeJson = (saved['per_type'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

      _configs.clear();
      _configs['all'] = _PrintConfig.fromJson(defaultJson);
      perTypeJson.forEach((key, value) {
        if (value is Map) {
          _configs[key] = _PrintConfig.fromJson(value.cast<String, dynamic>());
        }
      });

      _syncFormWithConfig();

      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.savedSuccessfully);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.printSettings),
        leading: businessSubpageBackLeading(context, widget.businessId),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.printDocuments,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedDocType,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: _docTypes
                            .map(
                              (d) => DropdownMenuItem<String>(
                                value: d.key,
                                child: Text(d.label),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            // قبل از سوییچ، متن فوتر را روی کانفیگ قبلی ذخیره کنیم
                            final prev = _currentConfig().copyWith(
                              footerNote: _footerController.text.trim().isEmpty
                                  ? null
                                  : _footerController.text.trim(),
                            );
                            _updateCurrentConfig(prev);

                            _selectedDocType = val;
                            _syncFormWithConfig();
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_selectedDocType != 'all') ...[
                        SwitchListTile(
                          title: Text(t.printSettings),
                          subtitle: const Text(
                            'در صورت خاموش بودن، از تنظیمات عمومی (همه فاکتورها) استفاده می‌شود',
                          ),
                          value: _hasCustomConfigForCurrentType(),
                          onChanged: (v) {
                            setState(() {
                              if (v) {
                                // ساخت تنظیم اختصاصی بر اساس عمومی
                                _configs[_selectedDocType] = _configs[_selectedDocType] ?? _configs['all'] ?? _PrintConfig.initial();
                              } else {
                                // حذف تنظیم اختصاصی → استفاده از عمومی
                                _configs.remove(_selectedDocType);
                              }
                              _syncFormWithConfig();
                            });
                          },
                        ),
                        const Divider(),
                      ],
                      Expanded(
                        child: SingleChildScrollView(
                          child: AbsorbPointer(
                            absorbing: _selectedDocType != 'all' && !_hasCustomConfigForCurrentType(),
                            child: _buildConfigForm(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: Text(t.save),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _loading ? null : _load,
                            icon: const Icon(Icons.refresh),
                            label: Text(t.reload),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildConfigForm(BuildContext context) {
    final cfg = _currentConfig();
    final t = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(t.printDocuments),
          subtitle: const Text('نمایش لوگوی کسب‌وکار در بالای فاکتور'),
          value: cfg.showLogo,
          onChanged: (v) {
            setState(() {
              _updateCurrentConfig(cfg.copyWith(showLogo: v));
            });
          },
        ),
        SwitchListTile(
          title: const Text('نمایش مهر / امضای شرکت'),
          subtitle: const Text('نمایش مهر و امضای ثبت‌شده در پایین فاکتور'),
          value: cfg.showStamp,
          onChanged: (v) {
            setState(() {
              _updateCurrentConfig(cfg.copyWith(showStamp: v));
            });
          },
        ),
        SwitchListTile(
          title: const Text('نمایش تراکنش‌های پرداخت مرتبط'),
          subtitle: const Text('جدول رسیدها / پرداخت‌های متصل به فاکتور در پایین صفحه'),
          value: cfg.showPayments,
          onChanged: (v) {
            setState(() {
              _updateCurrentConfig(cfg.copyWith(showPayments: v));
            });
          },
        ),
        SwitchListTile(
          title: const Text('نمایش برنامه اقساط'),
          subtitle: const Text('در صورت فروش اقساطی، برنامه اقساط در صفحه جداگانه چاپ شود'),
          value: cfg.showInstallmentPlan,
          onChanged: (v) {
            setState(() {
              _updateCurrentConfig(cfg.copyWith(showInstallmentPlan: v));
            });
          },
        ),
        SwitchListTile(
          title: const Text('QR نمایش آنلاین / اعتبارسنجی'),
          subtitle: const Text('امکان درج QR در فاکتور چاپی برای مشاهدهٔ آنلاین (در صدور/چاپ موردی قابل خاموش)'),
          value: cfg.showShareQr,
          onChanged: (v) {
            setState(() {
              _updateCurrentConfig(cfg.copyWith(showShareQr: v));
            });
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _footerController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'متن ثابت انتهای فاکتور (پاورقی)',
            hintText: 'مثال: این فاکتور بر اساس قوانین و مقررات مالیاتی جاری صادر شده است.',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _PrintConfig {
  final bool showLogo;
  final bool showStamp;
  final bool showPayments;
  final bool showInstallmentPlan;
  final bool showShareQr;
  final String? footerNote;

  const _PrintConfig({
    required this.showLogo,
    required this.showStamp,
    required this.showPayments,
    required this.showInstallmentPlan,
    required this.showShareQr,
    required this.footerNote,
  });

  factory _PrintConfig.initial() {
    return const _PrintConfig(
      showLogo: true,
      showStamp: true,
      showPayments: true,
      showInstallmentPlan: true,
      showShareQr: false,
      footerNote: null,
    );
  }

  factory _PrintConfig.fromJson(Map<String, dynamic> json) {
    bool _b(String key, bool def) {
      final v = json[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
        if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
      }
      return def;
    }

    return _PrintConfig(
      showLogo: _b('show_logo', true),
      showStamp: _b('show_stamp', true),
      showPayments: _b('show_payments', true),
      showInstallmentPlan: _b('show_installment_plan', true),
      showShareQr: _b('show_share_qr', false),
      footerNote: (json['footer_note'] as String?)?.trim().isEmpty == true
          ? null
          : json['footer_note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'show_logo': showLogo,
      'show_stamp': showStamp,
      'show_payments': showPayments,
      'show_installment_plan': showInstallmentPlan,
      'show_share_qr': showShareQr,
      'footer_note': footerNote,
    };
  }

  _PrintConfig copyWith({
    bool? showLogo,
    bool? showStamp,
    bool? showPayments,
    bool? showInstallmentPlan,
    bool? showShareQr,
    String? footerNote,
  }) {
    return _PrintConfig(
      showLogo: showLogo ?? this.showLogo,
      showStamp: showStamp ?? this.showStamp,
      showPayments: showPayments ?? this.showPayments,
      showInstallmentPlan: showInstallmentPlan ?? this.showInstallmentPlan,
      showShareQr: showShareQr ?? this.showShareQr,
      footerNote: footerNote ?? this.footerNote,
    );
  }
}

class _DocTypeDef {
  final String key;
  final String label;
  const _DocTypeDef(this.key, this.label);
}


