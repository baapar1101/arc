import 'package:flutter/material.dart';

import 'invoice_form_layout.dart';

enum CommissionType {
  percentage('درصدی'),
  amount('مبلغی');

  const CommissionType(this.label);
  final String label;
}

class CommissionTypeSelector extends StatefulWidget {
  final CommissionType? selectedType;
  final ValueChanged<CommissionType?> onTypeChanged;
  final bool isRequired;
  final String label;
  final String hintText;
  final bool compact;

  const CommissionTypeSelector({
    super.key,
    this.selectedType,
    required this.onTypeChanged,
    this.isRequired = false,
    this.label = 'نوع کارمزد',
    this.hintText = 'انتخاب نوع کارمزد',
    this.compact = false,
  });

  @override
  State<CommissionTypeSelector> createState() => _CommissionTypeSelectorState();
}

class _CommissionTypeSelectorState extends State<CommissionTypeSelector> {
  CommissionType? _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.selectedType;
  }

  @override
  void didUpdateWidget(CommissionTypeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedType != oldWidget.selectedType) {
      setState(() {
        _selectedType = widget.selectedType;
      });
    }
  }

  void _selectType(CommissionType type) {
    setState(() {
      _selectedType = type;
    });
    widget.onTypeChanged(type);
  }

  void _clearSelection() {
    setState(() {
      _selectedType = null;
    });
    widget.onTypeChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DropdownButtonFormField<CommissionType>(
      initialValue: _selectedType,
      isDense: widget.compact,
      onChanged: (CommissionType? newValue) {
        if (newValue != null) {
          _selectType(newValue);
        } else if (!widget.isRequired) {
          _clearSelection();
        }
      },
      decoration: InvoiceFormFieldMetrics.mergeDecoration(
        context,
        InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          prefixIcon: widget.compact
              ? null
              : (_selectedType != null
                  ? Icon(_getTypeIcon(_selectedType!), size: 20)
                  : const Icon(Icons.toggle_on_outlined, size: 20)),
          suffixIcon: _selectedType != null && !widget.isRequired
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _clearSelection,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: InvoiceFormFieldMetrics.compactSuffixIconConstraints,
                )
              : null,
          suffixIconConstraints: InvoiceFormFieldMetrics.compactSuffixIconConstraints,
        ),
      ),
      items: CommissionType.values.map((CommissionType type) {
        return DropdownMenuItem<CommissionType>(
          value: type,
          child: Row(
            children: [
              Icon(
                _getTypeIcon(type),
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  type.label,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      validator: (value) {
        if (widget.isRequired && value == null) {
          return 'لطفا نوع کارمزد را انتخاب کنید';
        }
        return null;
      },
    );
  }

  IconData _getTypeIcon(CommissionType type) {
    switch (type) {
      case CommissionType.percentage:
        return Icons.percent;
      case CommissionType.amount:
        return Icons.attach_money;
    }
  }
}
