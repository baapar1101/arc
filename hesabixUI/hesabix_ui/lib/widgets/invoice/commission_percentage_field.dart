import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CommissionPercentageField extends StatefulWidget {
  final double? initialValue;
  final Function(double?) onChanged;
  final bool isRequired;
  final String label;
  final String hintText;

  const CommissionPercentageField({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.isRequired = false,
    this.label = 'درصد کارمزد',
    this.hintText = 'مثال: 5.5',
  });

  @override
  State<CommissionPercentageField> createState() => _CommissionPercentageFieldState();
}

class _CommissionPercentageFieldState extends State<CommissionPercentageField> {
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
        _errorText = 'لطفا عدد معتبر وارد کنید';
      });
      widget.onChanged(null);
      return;
    }

    if (doubleValue < 0 || doubleValue > 100) {
      setState(() {
        _errorText = 'درصد کارمزد باید بین 0 تا 100 باشد';
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
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        suffixText: '%',
        suffixStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(
          Icons.percent,
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
