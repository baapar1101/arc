import 'package:flutter/material.dart';

import '../../utils/number_normalizer.dart';
import '../money/amount_field_words_tooltip.dart';

class CommissionAmountField extends StatefulWidget {
  final double? initialValue;
  final Function(double?) onChanged;
  final bool isRequired;
  final String label;
  final String hintText;
  final String currencyUnit;

  const CommissionAmountField({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.isRequired = false,
    this.label = 'مبلغ کارمزد',
    this.hintText = 'مثال: 100000',
    this.currencyUnit = 'ریال',
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
      text: widget.initialValue != null ? formatNumberForInput(widget.initialValue) : '',
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

    final doubleValue = parseFormattedDouble(value);
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
    return AmountFieldWordsTooltip(
      controller: _controller,
      currencyUnit: widget.currencyUnit,
      child: TextFormField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          const EnglishDigitsFormatter(),
          const ThousandsSeparatorInputFormatter(allowDecimal: true),
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
      ),
    );
  }
}
