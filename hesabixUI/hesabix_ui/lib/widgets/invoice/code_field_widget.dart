import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

class CodeFieldWidget extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final String? label;
  final String? hintText;
  final bool isRequired;
  final bool autoGenerateCode;
  /// شماره سند فاکتور: حروف انگلیسی، اعداد، خط تیره و زیرخط (مثل INV-20240410-0001)
  final bool invoiceDocumentCode;
  /// کد محل انبار: همان الگوی کاراکتر فاکتور، پیام‌های اعتبارسنجی متفاوت
  final bool warehouseLocationCode;
  final ValueChanged<bool>? onAutoGenerateChanged;
  /// اگر false باشد، سوئیچ خودکار/دستی نمایش داده نمی‌شود (مثلاً در ویرایش).
  final bool showAutoManualToggle;

  const CodeFieldWidget({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.label,
    this.hintText,
    this.isRequired = false,
    this.autoGenerateCode = true,
    this.invoiceDocumentCode = false,
    this.warehouseLocationCode = false,
    this.onAutoGenerateChanged,
    this.showAutoManualToggle = true,
  });

  @override
  State<CodeFieldWidget> createState() => _CodeFieldWidgetState();
}

class _CodeFieldWidgetState extends State<CodeFieldWidget> {
  late TextEditingController _controller;
  late bool _autoGenerateCode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _autoGenerateCode = widget.autoGenerateCode;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    final useDocStyleCode = widget.invoiceDocumentCode || widget.warehouseLocationCode;
    final List<TextInputFormatter> formatters = useDocStyleCode
        ? <TextInputFormatter>[
            const EnglishDigitsFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-_]')),
          ]
        : const <TextInputFormatter>[];

    return TextFormField(
      controller: _controller,
      readOnly: widget.showAutoManualToggle && _autoGenerateCode,
      inputFormatters: formatters.isEmpty ? null : formatters,
      decoration: InputDecoration(
        labelText: widget.label ?? t.code,
        hintText: widget.hintText ?? t.uniqueCodeNumeric,
        suffixIcon: widget.showAutoManualToggle
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: _autoGenerateCode ? 'تولید خودکار کد فعال است' : 'تولید دستی کد فعال است',
                      child: Switch(
                        value: _autoGenerateCode,
                        onChanged: (value) {
                          setState(() {
                            _autoGenerateCode = value;
                            if (_autoGenerateCode) {
                              _controller.clear();
                              widget.onChanged(null);
                            }
                            widget.onAutoGenerateChanged?.call(_autoGenerateCode);
                          });
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              )
            : null,
      ),
      keyboardType: TextInputType.text,
      onChanged: (value) {
        widget.onChanged(_autoGenerateCode ? null : value.trim().isEmpty ? null : value.trim());
      },
      validator: (value) {
        if (widget.isRequired && !_autoGenerateCode) {
          if (value == null || value.trim().isEmpty) {
            if (widget.warehouseLocationCode) {
              return 'کد محل الزامی است';
            }
            return widget.invoiceDocumentCode ? 'شماره فاکتور الزامی است' : t.personCodeRequired;
          }
          final trimmed = value.trim();
          if (widget.invoiceDocumentCode || widget.warehouseLocationCode) {
            if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(trimmed)) {
              return 'فقط حروف انگلیسی، اعداد، خط تیره و زیرخط مجاز است';
            }
          } else {
            if (trimmed.length < 3) {
              return t.passwordMinLength;
            }
            if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
              return t.codeMustBeNumeric;
            }
          }
        }
        return null;
      },
    );
  }
}
