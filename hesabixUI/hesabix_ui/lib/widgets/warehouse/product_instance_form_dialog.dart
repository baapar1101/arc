import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/number_normalizer.dart' show parseFormattedNumber;

class ProductInstanceFormDialog extends StatefulWidget {
  final int businessId;
  final int productId;
  final String productName;
  final bool trackSerial;
  final bool trackBarcode;
  final List<Map<String, dynamic>> productAttributes;
  final Map<String, dynamic>? initialData;
  final VoidCallback? onSuccess;

  const ProductInstanceFormDialog({
    super.key,
    required this.businessId,
    required this.productId,
    required this.productName,
    required this.trackSerial,
    required this.trackBarcode,
    required this.productAttributes,
    this.initialData,
    this.onSuccess,
  });

  @override
  State<ProductInstanceFormDialog> createState() => _ProductInstanceFormDialogState();
}

class _ProductInstanceFormDialogState extends State<ProductInstanceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _serialController = TextEditingController();
  final _barcodeController = TextEditingController();
  final Map<String, dynamic> _attributeValues = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _serialController.text = widget.initialData!['serial_number']?.toString() ?? '';
      _barcodeController.text = widget.initialData!['barcode']?.toString() ?? '';
      final attrs = widget.initialData!['custom_attributes'] as Map<String, dynamic>? ?? {};
      _attributeValues.addAll(attrs);
    }
  }

  @override
  void dispose() {
    _serialController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.trackSerial && _serialController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً شماره سریال را وارد کنید')),
      );
      return;
    }

    final result = {
      'serial_number': widget.trackSerial ? _serialController.text.trim() : null,
      'barcode': widget.trackBarcode && _barcodeController.text.trim().isNotEmpty
          ? _barcodeController.text.trim()
          : null,
      'custom_attributes': _attributeValues.isNotEmpty ? _attributeValues : null,
    };

    Navigator.of(context).pop(result);
    widget.onSuccess?.call();
  }

  Widget _buildAttributeField(Map<String, dynamic> attribute) {
    final attrId = attribute['id'] as int?;
    final attrName = (attribute['title'] ?? 'ویژگی ${attrId}').toString();
    final attrType = (attribute['attribute_type'] ?? 'text').toString();
    final isRequired = (attribute['is_required'] == true);
    final currentValue = _attributeValues[attrName]?.toString() ?? '';

    switch (attrType) {
      case 'number':
        return TextFormField(
          key: ValueKey('attr_${attrId}_$currentValue'),
          initialValue: currentValue,
          decoration: InputDecoration(
            labelText: attrName + (isRequired ? ' *' : ''),
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          validator: isRequired
              ? (value) => value == null || value.trim().isEmpty
                  ? 'لطفاً $attrName را وارد کنید'
                  : null
              : null,
          onChanged: (value) {
            if (value.trim().isNotEmpty) {
              final numValue = parseFormattedNumber(value);
              _attributeValues[attrName] = numValue;
            } else {
              _attributeValues.remove(attrName);
            }
          },
        );
      case 'select':
        final options = (attribute['options'] as List<dynamic>?) ?? [];
        return DropdownButtonFormField<String>(
          value: currentValue.isNotEmpty ? currentValue : null,
          decoration: InputDecoration(
            labelText: attrName + (isRequired ? ' *' : ''),
            border: const OutlineInputBorder(),
          ),
          items: options.map((opt) {
            final optValue = opt.toString();
            return DropdownMenuItem(
              value: optValue,
              child: Text(optValue),
            );
          }).toList(),
          validator: isRequired
              ? (value) => value == null || value.isEmpty
                  ? 'لطفاً $attrName را انتخاب کنید'
                  : null
              : null,
          onChanged: (value) {
            if (value != null) {
              _attributeValues[attrName] = value;
            } else {
              _attributeValues.remove(attrName);
            }
            setState(() {});
          },
        );
      default: // text
        return TextFormField(
          key: ValueKey('attr_${attrId}_$currentValue'),
          initialValue: currentValue,
          decoration: InputDecoration(
            labelText: attrName + (isRequired ? ' *' : ''),
            border: const OutlineInputBorder(),
          ),
          validator: isRequired
              ? (value) => value == null || value.trim().isEmpty
                  ? 'لطفاً $attrName را وارد کنید'
                  : null
              : null,
          onChanged: (value) {
            if (value.trim().isNotEmpty) {
              _attributeValues[attrName] = value.trim();
            } else {
              _attributeValues.remove(attrName);
            }
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ثبت اطلاعات کالای یونیک',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    tooltip: 'بستن',
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // نام کالا
                        Card(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          child: ListTile(
                            leading: const Icon(Icons.inventory_2),
                            title: const Text('کالا'),
                            subtitle: Text(widget.productName),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // سریال نامبر
                        if (widget.trackSerial)
                          TextFormField(
                            controller: _serialController,
                            decoration: const InputDecoration(
                              labelText: 'شماره سریال *',
                              border: OutlineInputBorder(),
                              hintText: 'مثال: SN-123456',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'لطفاً شماره سریال را وارد کنید';
                              }
                              return null;
                            },
                          ),
                        if (widget.trackSerial) const SizedBox(height: 16),
                        // بارکد
                        if (widget.trackBarcode)
                          TextFormField(
                            controller: _barcodeController,
                            decoration: const InputDecoration(
                              labelText: 'بارکد',
                              border: OutlineInputBorder(),
                              hintText: 'مثال: BC-789012',
                            ),
                          ),
                        if (widget.trackBarcode) const SizedBox(height: 16),
                        // ویژگی‌های کالا
                        if (widget.productAttributes.isNotEmpty) ...[
                          Text(
                            'ویژگی‌های کالا',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          ...widget.productAttributes.map((attr) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildAttributeField(attr),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('ذخیره'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

