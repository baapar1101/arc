import 'package:flutter/material.dart';
import '../../models/invoice_type_model.dart';

class InvoiceTypeCombobox extends StatefulWidget {
  final InvoiceType? selectedType;
  final ValueChanged<InvoiceType?> onTypeChanged;
  final bool isDraft;
  final ValueChanged<bool> onDraftChanged;
  final bool isRequired;
  final String? label;
  final String? hintText;

  const InvoiceTypeCombobox({
    super.key,
    this.selectedType,
    required this.onTypeChanged,
    this.isDraft = false,
    required this.onDraftChanged,
    this.isRequired = true,
    this.label = 'نوع فاکتور',
    this.hintText = 'انتخاب نوع فاکتور',
  });

  @override
  State<InvoiceTypeCombobox> createState() => _InvoiceTypeComboboxState();
}

class _InvoiceTypeComboboxState extends State<InvoiceTypeCombobox> {
  InvoiceType? _selectedType;
  late bool _isDraft;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.selectedType;
    _isDraft = widget.isDraft;
  }

  @override
  void didUpdateWidget(InvoiceTypeCombobox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedType != oldWidget.selectedType) {
      setState(() {
        _selectedType = widget.selectedType;
      });
    }
    if (widget.isDraft != oldWidget.isDraft) {
      setState(() {
        _isDraft = widget.isDraft;
      });
    }
  }

  void _selectType(InvoiceType type) {
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

    return DropdownButtonFormField<InvoiceType>(
      value: _selectedType,
      onChanged: (InvoiceType? newValue) {
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
            : const Icon(Icons.category_outlined),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // سویچ پیش‌نویس کوچک
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: _isDraft ? 'حالت پیش‌نویس فعال است' : 'فعال کردن حالت پیش‌نویس',
                child: Switch(
                  value: _isDraft,
                  onChanged: (value) {
                    setState(() {
                      _isDraft = value;
                    });
                    widget.onDraftChanged(value);
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            // دکمه پاک کردن (اگر نیاز باشد)
            if (_selectedType != null && !widget.isRequired)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: _clearSelection,
                iconSize: 18,
              ),
          ],
        ),
      ),
      items: InvoiceType.allTypes.map((InvoiceType type) {
        return DropdownMenuItem<InvoiceType>(
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
          return 'انتخاب ${widget.label} الزامی است';
        }
        return null;
      },
    );
  }

  IconData _getTypeIcon(InvoiceType type) {
    switch (type) {
      case InvoiceType.sales:
        return Icons.shopping_cart_outlined;
      case InvoiceType.salesReturn:
        return Icons.keyboard_return_outlined;
      case InvoiceType.purchase:
        return Icons.shop_outlined;
      case InvoiceType.purchaseReturn:
        return Icons.assignment_return_outlined;
      case InvoiceType.waste:
        return Icons.delete_outline;
      case InvoiceType.directConsumption:
        return Icons.flash_on_outlined;
      case InvoiceType.production:
        return Icons.precision_manufacturing_outlined;
    }
  }
}
