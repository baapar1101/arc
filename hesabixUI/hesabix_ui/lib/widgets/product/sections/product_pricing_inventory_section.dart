import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/product_form_data.dart';
import '../../../utils/product_form_validator.dart';

class ProductPricingInventorySection extends StatelessWidget {
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> units;

  const ProductPricingInventorySection({
    super.key,
    required this.formData,
    required this.onChanged,
    required this.units,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInventorySection(),
        const SizedBox(height: 24),
        _buildPricingSection(context),
      ],
    );
  }


  Widget _buildInventorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: formData.trackInventory,
          onChanged: (value) => _updateFormData(formData.copyWith(trackInventory: value)),
          title: const Text('کنترل موجودی'),
        ),
        if (formData.trackInventory) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: formData.reorderPoint?.toString(),
                  decoration: const InputDecoration(labelText: 'نقطه سفارش مجدد'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (value) => ProductFormValidator.validateQuantity(value, fieldName: 'نقطه سفارش مجدد'),
                  onChanged: (value) => _updateFormData(formData.copyWith(reorderPoint: int.tryParse(value))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: formData.minOrderQty?.toString(),
                  decoration: const InputDecoration(labelText: 'کمینه مقدار سفارش'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (value) => ProductFormValidator.validateQuantity(value, fieldName: 'کمینه مقدار سفارش'),
                  onChanged: (value) => _updateFormData(formData.copyWith(minOrderQty: int.tryParse(value))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: formData.leadTimeDays?.toString(),
                  decoration: const InputDecoration(labelText: 'زمان تحویل (روز)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: ProductFormValidator.validateLeadTime,
                  onChanged: (value) => _updateFormData(formData.copyWith(leadTimeDays: int.tryParse(value))),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPricingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('قیمت‌گذاری', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: formData.baseSalesPrice?.toString(),
          decoration: const InputDecoration(labelText: 'قیمت فروش'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
          ],
          validator: (value) => ProductFormValidator.validatePrice(value, fieldName: 'قیمت فروش'),
          onChanged: (value) => _updateFormData(formData.copyWith(baseSalesPrice: num.tryParse(value))),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: formData.baseSalesNote,
          decoration: const InputDecoration(labelText: 'توضیح قیمت فروش'),
          maxLines: 2,
          onChanged: (value) => _updateFormData(formData.copyWith(baseSalesNote: value.trim().isEmpty ? null : value)),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: formData.basePurchasePrice?.toString(),
          decoration: const InputDecoration(labelText: 'قیمت خرید'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
          ],
          validator: (value) => ProductFormValidator.validatePrice(value, fieldName: 'قیمت خرید'),
          onChanged: (value) => _updateFormData(formData.copyWith(basePurchasePrice: num.tryParse(value))),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: formData.basePurchaseNote,
          decoration: const InputDecoration(labelText: 'توضیح قیمت خرید'),
          maxLines: 2,
          onChanged: (value) => _updateFormData(formData.copyWith(basePurchaseNote: value.trim().isEmpty ? null : value)),
        ),
      ],
    );
  }

  void _updateFormData(ProductFormData newData) {
    onChanged(newData);
  }
}
