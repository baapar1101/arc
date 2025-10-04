import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CommissionAmountField extends StatefulWidget {
  final double? initialValue;
  final Function(double?) onChanged;
  final bool isRequired;
  final String label;
  final String hintText;

  const CommissionAmountField({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.isRequired = false,
    this.label = 'مبلغ کارمزد',
    this.hintText = 'مثال: 100000',
  });

  @override
  State<CommissionAmountField> createState() => _CommissionAmountFieldState();
}

class _CommissionAmountFieldState extends State<CommissionAmountField> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndUpdate(String value) {
    setState(() {
      _errorText = null;
    });

    if (value.isEmpty) {
      widget.onChanged(null);
      return;
    }

    final doubleValue = double.tryParse(value);
    if (doubleValue == null) {
      setState(() {
        _errorText = 'لطفا مبلغ معتبر وارد کنید';
      });
      widget.onChanged(null);
      return;
    }

    if (doubleValue < 0) {
      setState(() {
        _errorText = 'مبلغ کارمزد نمی‌تواند منفی باشد';
      });
      widget.onChanged(null);
      return;
    }

    widget.onChanged(doubleValue);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ThousandsSeparatorInputFormatter(),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        prefixIcon: Icon(
          Icons.attach_money,
          color: Theme.of(context).colorScheme.primary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        errorText: _errorText,
        errorStyle: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12,
        ),
      ),
      onChanged: _validateAndUpdate,
      validator: (value) {
        if (widget.isRequired && (value == null || value.isEmpty)) {
          return 'این فیلد الزامی است';
        }
        return _errorText;
      },
    );
  }
}

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Remove all non-digit characters except decimal point
    String cleanText = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');
    
    // Split by decimal point
    List<String> parts = cleanText.split('.');
    String integerPart = parts[0];
    String decimalPart = parts.length > 1 ? '.${parts[1]}' : '';

    // Add thousands separators to integer part
    String formattedInteger = _addThousandsSeparator(integerPart);
    
    String formattedText = formattedInteger + decimalPart;

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }

  String _addThousandsSeparator(String text) {
    if (text.isEmpty) return text;
    
    String reversed = text.split('').reversed.join('');
    String withCommas = reversed.replaceAllMapped(
      RegExp(r'(\d{3})(?=\d)'),
      (Match match) => '${match.group(1)},',
    );
    return withCommas.split('').reversed.join('');
  }
}
