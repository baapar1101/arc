import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/document_numbering_models.dart';
import 'package:hesabix_ui/services/document_numbering_api_service.dart';
import '../../utils/snackbar_helper.dart';
import 'package:shamsi_date/shamsi_date.dart';

class DocumentNumberingSettingsPage extends StatefulWidget {
  final int businessId;
  const DocumentNumberingSettingsPage({super.key, required this.businessId});

  @override
  State<DocumentNumberingSettingsPage> createState() =>
      _DocumentNumberingSettingsPageState();
}

class _DocumentNumberingSettingsPageState
    extends State<DocumentNumberingSettingsPage> {
  bool _loading = true;
  List<DocumentNumberingSetting> _settings = [];
  final Map<String, String> _documentTypeNames = {
    'invoice_sales': 'فاکتور فروش',
    'invoice_sales_return': 'برگشت از فروش',
    'invoice_purchase': 'فاکتور خرید',
    'invoice_purchase_return': 'برگشت از خرید',
    'invoice_direct_consumption': 'مصرف مستقیم',
    'invoice_production': 'تولید',
    'invoice_waste': 'ضایعات',
    'receipt': 'دریافت',
    'payment': 'پرداخت',
    'transfer': 'انتقال',
    'expense': 'هزینه',
    'income': 'درآمد',
    'manual': 'سند دستی',
    'opening_balance': 'تراز افتتاحیه',
    'warehouse_document': 'حواله انبار',
    'warehouse_location': 'کد محل انبار',
    'crm_lead': 'کد سرنخ',
    'crm_deal': 'کد فرصت فروش',
    'crm_activity': 'کد فعالیت',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings =
          await DocumentNumberingApiService.getSettings(widget.businessId);
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا در بارگذاری: $e');
      }
    }
  }

  DocumentNumberingSetting _getDefaultSetting(String documentType) {
    return DocumentNumberingSetting(
      businessId: widget.businessId,
      documentType: documentType,
      prefix: _getDefaultPrefix(documentType),
      includeDate: true,
      calendarType: 'gregorian',
      dateFormat: 'YYYYMMDD',
      separator: '-',
      startNumber: 1,
      numberPadding: 4,
      resetPeriod: 'never',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  String _getDefaultPrefix(String documentType) {
    final prefixes = {
      'invoice_sales': 'INV',
      'invoice_sales_return': 'INV-RET',
      'invoice_purchase': 'INV-PUR',
      'invoice_purchase_return': 'INV-PUR-RET',
      'invoice_direct_consumption': 'INV-CON',
      'invoice_production': 'INV-PROD',
      'invoice_waste': 'INV-WASTE',
      'receipt': 'RC',
      'payment': 'PY',
      'transfer': 'TR',
      'expense': 'EXP',
      'income': 'INC',
      'manual': 'DOC',
      'opening_balance': 'OB',
      'warehouse_document': 'WH',
      'warehouse_location': 'LOC',
      'crm_lead': 'L',
      'crm_deal': 'D',
      'crm_activity': 'A',
    };
    return prefixes[documentType] ?? 'DOC';
  }

  String _formatPreview(DocumentNumberingSetting setting) {
    final today = DateTime.now();
    String datePart = '';

    if (setting.includeDate) {
      if (setting.calendarType == 'jalali') {
        final jalali = Jalali.fromDateTime(today);
        datePart = _formatJalaliDate(jalali, setting.dateFormat ?? 'YYYYMMDD');
      } else {
        datePart = _formatGregorianDate(today, setting.dateFormat ?? 'YYYYMMDD');
      }
    }

    final numberPart = '1'.padLeft(setting.numberPadding, '0');

    if (datePart.isNotEmpty) {
      return '${setting.prefix}${setting.separator}$datePart${setting.separator}$numberPart';
    }
    return '${setting.prefix}${setting.separator}$numberPart';
  }

  String _formatGregorianDate(DateTime date, String format) {
    String result = format;
    result = result.replaceAll('YYYY', date.year.toString().padLeft(4, '0'));
    result = result.replaceAll('YY', (date.year % 100).toString().padLeft(2, '0'));
    result = result.replaceAll('MM', date.month.toString().padLeft(2, '0'));
    result = result.replaceAll('M', date.month.toString());
    result = result.replaceAll('DD', date.day.toString().padLeft(2, '0'));
    result = result.replaceAll('D', date.day.toString());
    return result;
  }

  String _formatJalaliDate(Jalali jalali, String format) {
    String result = format;
    result = result.replaceAll('YYYY', jalali.year.toString().padLeft(4, '0'));
    result = result.replaceAll('YY', (jalali.year % 100).toString().padLeft(2, '0'));
    result = result.replaceAll('MM', jalali.month.toString().padLeft(2, '0'));
    result = result.replaceAll('M', jalali.month.toString());
    result = result.replaceAll('DD', jalali.day.toString().padLeft(2, '0'));
    result = result.replaceAll('D', jalali.day.toString());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات شماره‌گذاری اسناد'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _documentTypeNames.length,
              itemBuilder: (context, index) {
                final documentType = _documentTypeNames.keys.elementAt(index);
                final documentName = _documentTypeNames[documentType]!;
                final setting = _settings.firstWhere(
                  (s) => s.documentType == documentType,
                  orElse: () => _getDefaultSetting(documentType),
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(documentName),
                    subtitle: Text(_formatPreview(setting)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showEditDialog(documentType, setting),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showEditDialog(
    String documentType,
    DocumentNumberingSetting setting,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _EditDocumentNumberingDialog(
        documentType: documentType,
        documentTypeName: _documentTypeNames[documentType]!,
        setting: setting,
        onSave: (updatedSetting) async {
          try {
            await DocumentNumberingApiService.saveSetting(
              widget.businessId,
              updatedSetting,
            );
            await _load();
            if (mounted) {
              SnackBarHelper.show(context, message: 'تنظیمات با موفقیت ذخیره شد');
            }
            return true;
          } catch (e) {
            if (mounted) {
              SnackBarHelper.show(context, message: 'خطا در ذخیره: $e');
            }
            return false;
          }
        },
        onDelete: () async {
          try {
            await DocumentNumberingApiService.deleteSetting(
              widget.businessId,
              documentType,
            );
            await _load();
            if (mounted) {
              SnackBarHelper.show(context, message: 'تنظیمات حذف شد و به پیش‌فرض بازگشت');
            }
            return true;
          } catch (e) {
            if (mounted) {
              SnackBarHelper.show(context, message: 'خطا در حذف: $e');
            }
            return false;
          }
        },
        formatPreview: _formatPreview,
      ),
    );

    if (result == true && mounted) {
      // تنظیمات به‌روزرسانی شد
    }
  }
}

class _EditDocumentNumberingDialog extends StatefulWidget {
  final String documentType;
  final String documentTypeName;
  final DocumentNumberingSetting setting;
  final Future<bool> Function(DocumentNumberingSetting) onSave;
  final Future<bool> Function() onDelete;
  final String Function(DocumentNumberingSetting) formatPreview;

  const _EditDocumentNumberingDialog({
    required this.documentType,
    required this.documentTypeName,
    required this.setting,
    required this.onSave,
    required this.onDelete,
    required this.formatPreview,
  });

  @override
  State<_EditDocumentNumberingDialog> createState() =>
      _EditDocumentNumberingDialogState();
}

class _EditDocumentNumberingDialogState
    extends State<_EditDocumentNumberingDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _prefixController;
  late TextEditingController _separatorController;
  late TextEditingController _startNumberController;
  late TextEditingController _numberPaddingController;
  bool _includeDate = true;
  String _calendarType = 'gregorian';
  String? _dateFormat;
  String? _resetPeriod;
  bool _isActive = true;
  bool _saving = false;
  bool _deleting = false;
  bool _hasCustomSettings = false;

  List<String> get _dateFormats {
    if (_calendarType == 'jalali') {
      return [
        'YYYYMMDD',
        'YYMMDD',
        'YYYY/MM/DD',
        'YYYY-MM-DD',
        'YY/MM/DD',
        'YY-MM-DD',
      ];
    } else {
      return [
        'YYYYMMDD',
        'YYMMDD',
        'YYYY-MM-DD',
        'YYYY/MM/DD',
        'YY-MM-DD',
        'YY/MM/DD',
      ];
    }
  }

  @override
  void initState() {
    super.initState();
    _prefixController = TextEditingController(text: widget.setting.prefix ?? '');
    _separatorController = TextEditingController(text: widget.setting.separator);
    _startNumberController =
        TextEditingController(text: widget.setting.startNumber.toString());
    _numberPaddingController =
        TextEditingController(text: widget.setting.numberPadding.toString());
    _includeDate = widget.setting.includeDate;
    _calendarType = widget.setting.calendarType;
    _dateFormat = widget.setting.dateFormat;
    _resetPeriod = widget.setting.resetPeriod;
    _isActive = widget.setting.isActive;
    _hasCustomSettings = widget.setting.id != null;
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _separatorController.dispose();
    _startNumberController.dispose();
    _numberPaddingController.dispose();
    super.dispose();
  }

  DocumentNumberingSetting _buildCurrentSetting() {
    return DocumentNumberingSetting(
      id: widget.setting.id,
      businessId: widget.setting.businessId,
      documentType: widget.setting.documentType,
      prefix: _prefixController.text.trim().isEmpty
          ? null
          : _prefixController.text.trim(),
      includeDate: _includeDate,
      calendarType: _calendarType,
      dateFormat: _includeDate ? (_dateFormat ?? 'YYYYMMDD') : null,
      separator: _separatorController.text.trim().isEmpty
          ? '-'
          : _separatorController.text.trim(),
      startNumber: int.tryParse(_startNumberController.text.trim()) ?? 1,
      numberPadding: int.tryParse(_numberPaddingController.text.trim()) ?? 4,
      resetPeriod: _resetPeriod,
      isActive: _isActive,
      createdAt: widget.setting.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final updated = _buildCurrentSetting();
    final success = await widget.onSave(updated);
    setState(() => _saving = false);

    if (success && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف تنظیمات'),
        content: const Text(
            'آیا مطمئن هستید که می‌خواهید تنظیمات سفارشی را حذف کنید و به حالت پیش‌فرض بازگردید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);
    final success = await widget.onDelete();
    setState(() => _deleting = false);

    if (success && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentSetting = _buildCurrentSetting();
    final preview = widget.formatPreview(currentSetting);

    return AlertDialog(
      title: Text('ویرایش تنظیمات: ${widget.documentTypeName}'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // پیش‌نمایش
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'پیش‌نمایش:',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // پیشوند
                TextFormField(
                  controller: _prefixController,
                  decoration: const InputDecoration(
                    labelText: 'پیشوند *',
                    hintText: 'مثلاً INV, RC, PY',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'پیشوند الزامی است' : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // شامل تاریخ
                SwitchListTile(
                  title: const Text('شامل تاریخ'),
                  value: _includeDate,
                  onChanged: (v) => setState(() => _includeDate = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),

                // نوع تقویم
                if (_includeDate)
                  DropdownButtonFormField<String>(
                    value: _calendarType,
                    items: const [
                      DropdownMenuItem(value: 'gregorian', child: Text('میلادی')),
                      DropdownMenuItem(value: 'jalali', child: Text('شمسی')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _calendarType = v ?? 'gregorian';
                        // تنظیم فرمت پیش‌فرض بر اساس نوع تقویم
                        if (_dateFormat == null) {
                          _dateFormat = 'YYYYMMDD';
                        }
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'نوع تقویم',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                if (_includeDate) const SizedBox(height: 12),

                // فرمت تاریخ
                if (_includeDate)
                  DropdownButtonFormField<String>(
                    value: _dateFormat ?? 'YYYYMMDD',
                    items: _dateFormats
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (v) => setState(() => _dateFormat = v),
                    decoration: const InputDecoration(
                      labelText: 'فرمت تاریخ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                if (_includeDate) const SizedBox(height: 12),

                // جداکننده
                TextFormField(
                  controller: _separatorController,
                  decoration: const InputDecoration(
                    labelText: 'جداکننده',
                    hintText: 'مثلاً -, _, /',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLength: 5,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // شماره شروع و تعداد صفرها
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _startNumberController,
                        decoration: const InputDecoration(
                          labelText: 'شماره شروع',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final num = int.tryParse(v ?? '');
                          if (num == null || num < 1) {
                            return 'باید عدد مثبت باشد';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _numberPaddingController,
                        decoration: const InputDecoration(
                          labelText: 'تعداد صفرهای پیش‌رو',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final num = int.tryParse(v ?? '');
                          if (num == null || num < 1 || num > 10) {
                            return 'باید بین 1 تا 10 باشد';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // دوره ریست
                DropdownButtonFormField<String>(
                  value: _resetPeriod,
                  items: const [
                    DropdownMenuItem(value: 'never', child: Text('هرگز')),
                    DropdownMenuItem(value: 'daily', child: Text('روزانه')),
                    DropdownMenuItem(value: 'monthly', child: Text('ماهانه')),
                    DropdownMenuItem(value: 'yearly', child: Text('سالانه')),
                  ],
                  onChanged: (v) => setState(() => _resetPeriod = v),
                  decoration: const InputDecoration(
                    labelText: 'دوره ریست شماره‌گذاری',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // فعال/غیرفعال
                SwitchListTile(
                  title: const Text('فعال'),
                  subtitle: const Text('در صورت غیرفعال بودن، از تنظیمات پیش‌فرض استفاده می‌شود'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_hasCustomSettings)
          TextButton.icon(
            onPressed: _deleting ? null : _handleDelete,
            icon: _deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            label: const Text('حذف تنظیمات'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _handleSave,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('ذخیره'),
        ),
      ],
    );
  }
}

