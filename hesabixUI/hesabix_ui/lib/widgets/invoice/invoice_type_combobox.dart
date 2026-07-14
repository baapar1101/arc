import 'package:flutter/material.dart';
import '../../models/invoice_type_model.dart';
import 'invoice_form_layout.dart';

class InvoiceTypeCombobox extends StatefulWidget {
  final InvoiceType? selectedType;
  final ValueChanged<InvoiceType?> onTypeChanged;
  final bool isDraft;
  final ValueChanged<bool> onDraftChanged;
  final bool isRequired;
  final String? label;
  final String? hintText;
  /// اگر false باشد انتخاب نوع فاکتور غیرفعال است (مثلاً پس از ارسال به مودیان).
  final bool enableTypeChange;
  /// اگر false باشد سویچ پیش‌فاکتور غیرفعال است.
  final bool enableDraftToggle;
  /// محدودیت لیست انواع مجاز؛ null = همه انواع.
  final List<InvoiceType>? allowedTypes;
  /// سویچ پیش‌نویس داخل suffix فیلد؛ در فرم فاکتور جدید بیرون فیلد نمایش داده می‌شود.
  final bool showInlineDraftToggle;
  /// بدون آیکون prefix برای چیدمان فشرده.
  final bool compact;

  const InvoiceTypeCombobox({
    super.key,
    this.selectedType,
    required this.onTypeChanged,
    this.isDraft = false,
    required this.onDraftChanged,
    this.isRequired = true,
    this.label = 'نوع فاکتور',
    this.hintText = 'انتخاب نوع فاکتور',
    this.enableTypeChange = true,
    this.enableDraftToggle = true,
    this.allowedTypes,
    this.showInlineDraftToggle = false,
    this.compact = false,
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
    final typeOptions = widget.allowedTypes ?? InvoiceType.allTypes;

    return DropdownButtonFormField<InvoiceType>(
      initialValue: _selectedType,
      isDense: widget.compact,
      onChanged: widget.enableTypeChange
          ? (InvoiceType? newValue) {
              if (newValue != null) {
                _selectType(newValue);
              } else if (!widget.isRequired) {
                _clearSelection();
              }
            }
          : null,
      decoration: InvoiceFormFieldMetrics.mergeDecoration(
        context,
        InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          prefixIcon: widget.compact
              ? null
              : (_selectedType != null
                  ? Icon(_getTypeIcon(_selectedType!), size: 20)
                  : const Icon(Icons.category_outlined, size: 20)),
          suffixIcon: widget.showInlineDraftToggle
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: Tooltip(
                        message: _isDraft
                            ? 'حالت پیش‌نویس فعال است'
                            : 'فعال کردن حالت پیش‌نویس',
                        child: Switch(
                          value: _isDraft,
                          onChanged: widget.enableDraftToggle
                              ? (value) {
                                  setState(() {
                                    _isDraft = value;
                                  });
                                  widget.onDraftChanged(value);
                                }
                              : null,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    if (_selectedType != null && !widget.isRequired)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSelection,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: InvoiceFormFieldMetrics.compactSuffixIconConstraints,
                      ),
                  ],
                )
              : (_selectedType != null && !widget.isRequired)
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearSelection,
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: InvoiceFormFieldMetrics.compactSuffixIconConstraints,
                    )
                  : null,
          suffixIconConstraints: widget.showInlineDraftToggle
              ? InvoiceFormFieldMetrics.suffixIconConstraints
              : InvoiceFormFieldMetrics.compactSuffixIconConstraints,
        ),
      ),
      items: typeOptions.map((InvoiceType type) {
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
