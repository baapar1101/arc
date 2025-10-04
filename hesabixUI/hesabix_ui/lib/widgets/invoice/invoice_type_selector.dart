import 'package:flutter/material.dart';
import '../../models/invoice_type_model.dart';

class InvoiceTypeSelector extends StatefulWidget {
  final InvoiceType? selectedType;
  final ValueChanged<InvoiceType?> onTypeChanged;
  final bool isRequired;

  const InvoiceTypeSelector({
    super.key,
    this.selectedType,
    required this.onTypeChanged,
    this.isRequired = true,
  });

  @override
  State<InvoiceTypeSelector> createState() => _InvoiceTypeSelectorState();
}

class _InvoiceTypeSelectorState extends State<InvoiceTypeSelector> {
  InvoiceType? _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.selectedType;
  }

  @override
  void didUpdateWidget(InvoiceTypeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedType != oldWidget.selectedType) {
      setState(() {
        _selectedType = widget.selectedType;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.category_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'انتخاب نوع فاکتور',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.isRequired)
                Text(
                  ' *',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          // استفاده از SegmentedButton
          SegmentedButton<InvoiceType>(
            segments: InvoiceType.allTypes.map((type) {
              return ButtonSegment<InvoiceType>(
                value: type,
                label: Text(type.label),
                icon: Icon(_getTypeIcon(type)),
              );
            }).toList(),
            selected: _selectedType != null ? {_selectedType!} : <InvoiceType>{},
            onSelectionChanged: (Set<InvoiceType> selection) {
              final selectedType = selection.isNotEmpty ? selection.first : null;
              setState(() {
                _selectedType = selectedType;
              });
              widget.onTypeChanged(selectedType);
            },
            multiSelectionEnabled: false,
            showSelectedIcon: true,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return colorScheme.primaryContainer;
                }
                return colorScheme.surfaceContainerHighest;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return colorScheme.onPrimaryContainer;
                }
                return colorScheme.onSurfaceVariant;
              }),
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return BorderSide(
                    color: colorScheme.primary,
                    width: 2,
                  );
                }
                return BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                  width: 1,
                );
              }),
            ),
          ),
        ],
      ),
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
