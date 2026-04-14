import 'package:flutter/material.dart';

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

  const CommissionTypeSelector({
    super.key,
    this.selectedType,
    required this.onTypeChanged,
    this.isRequired = false,
    this.label = 'نوع کارمزد',
    this.hintText = 'انتخاب نوع کارمزد',
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
      onChanged: (CommissionType? newValue) {
        if (newValue != null) {
          _selectType(newValue);
        } else if (!widget.isRequired) {
          _clearSelection();
        }
      },
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
        prefixIcon: _selectedType != null
            ? Icon(_getTypeIcon(_selectedType!))
            : const Icon(Icons.toggle_on_outlined),
        suffixIcon: _selectedType != null && !widget.isRequired
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: _clearSelection,
                iconSize: 18,
              )
            : null,
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
