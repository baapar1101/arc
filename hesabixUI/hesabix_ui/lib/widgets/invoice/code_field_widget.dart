import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class CodeFieldWidget extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final String? label;
  final String? hintText;
  final bool isRequired;
  final bool autoGenerateCode;

  const CodeFieldWidget({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.label,
    this.hintText,
    this.isRequired = false,
    this.autoGenerateCode = true,
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
    
    return TextFormField(
      controller: _controller,
      readOnly: _autoGenerateCode,
      decoration: InputDecoration(
        labelText: widget.label ?? t.code,
        hintText: widget.hintText ?? t.uniqueCodeNumeric,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // سویچ اتوماتیک/دستی
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
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
      keyboardType: TextInputType.text,
      onChanged: (value) {
        widget.onChanged(_autoGenerateCode ? null : value.trim().isEmpty ? null : value.trim());
      },
      validator: (value) {
        if (widget.isRequired && !_autoGenerateCode) {
          if (value == null || value.trim().isEmpty) {
            return t.personCodeRequired;
          }
          if (value.trim().length < 3) {
            return t.passwordMinLength;
          }
          if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
            return t.codeMustBeNumeric;
          }
        }
        return null;
      },
    );
  }
}
