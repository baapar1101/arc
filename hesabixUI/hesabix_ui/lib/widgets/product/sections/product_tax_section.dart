import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/product_form_data.dart';
import '../../../utils/product_form_validator.dart';

class ProductTaxSection extends StatelessWidget {
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> taxTypes;
  final List<Map<String, dynamic>> taxUnits;

  const ProductTaxSection({
    super.key,
    required this.formData,
    required this.onChanged,
    required this.taxTypes,
    required this.taxUnits,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('مالیات', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 16),
        _buildTaxCodeTypeUnitRow(context),
        const SizedBox(height: 24),
        _buildSalesTaxSection(),
        const SizedBox(height: 24),
        _buildPurchaseTaxSection(),
      ],
    );
  }

  Widget _buildTaxCodeTypeUnitRow(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 1000;
        if (isDesktop) {
          return Row(
            children: [
              Expanded(child: _buildTaxCodeField()),
              const SizedBox(width: 12),
              Expanded(child: _buildTaxTypeDropdown()),
              const SizedBox(width: 12),
              Expanded(child: _buildTaxUnitDropdown()),
            ],
          );
        }
        return Column(
          children: [
            _buildTaxCodeField(),
            const SizedBox(height: 12),
            _buildTaxTypeDropdown(),
            const SizedBox(height: 12),
            _buildTaxUnitDropdown(),
          ],
        );
      },
    );
  }

  Widget _buildTaxCodeField() {
    return TextFormField(
      initialValue: formData.taxCode,
      decoration: const InputDecoration(labelText: 'کُد مالیاتی'),
      onChanged: (value) => _updateFormData(
        formData.copyWith(taxCode: value.trim().isEmpty ? null : value),
      ),
    );
  }

  Widget _buildSalesTaxSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: formData.isSalesTaxable,
          onChanged: (value) => _updateFormData(formData.copyWith(isSalesTaxable: value)),
          title: const Text('مشمول مالیات فروش'),
        ),
        if (formData.isSalesTaxable) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: formData.salesTaxRate?.toString(),
            decoration: const InputDecoration(labelText: 'نرخ مالیات فروش (%)'),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: (value) => ProductFormValidator.validateTaxRate(value, fieldName: 'نرخ مالیات فروش'),
            onChanged: (value) => _updateFormData(formData.copyWith(salesTaxRate: num.tryParse(value))),
          ),
        ],
      ],
    );
  }

  Widget _buildPurchaseTaxSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: formData.isPurchaseTaxable,
          onChanged: (value) => _updateFormData(formData.copyWith(isPurchaseTaxable: value)),
          title: const Text('مشمول مالیات خرید'),
        ),
        if (formData.isPurchaseTaxable) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: formData.purchaseTaxRate?.toString(),
            decoration: const InputDecoration(labelText: 'نرخ مالیات خرید (%)'),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: (value) => ProductFormValidator.validateTaxRate(value, fieldName: 'نرخ مالیات خرید'),
            onChanged: (value) => _updateFormData(formData.copyWith(purchaseTaxRate: num.tryParse(value))),
          ),
        ],
      ],
    );
  }

  Widget _buildTaxTypeDropdown() {
    if (taxTypes.isNotEmpty) {
      return DropdownButtonFormField<int>(
        value: formData.taxTypeId,
        items: taxTypes
            .map((taxType) => DropdownMenuItem<int>(
                  value: (taxType['id'] as num).toInt(),
                  child: Text((taxType['title'] ?? taxType['name'] ?? 'نوع ${taxType['id']}').toString()),
                ))
            .toList(),
        onChanged: (value) => _updateFormData(formData.copyWith(taxTypeId: value)),
        decoration: const InputDecoration(labelText: 'نوع مالیات'),
      );
    } else {
      return TextFormField(
        initialValue: formData.taxTypeId?.toString(),
        decoration: const InputDecoration(labelText: 'شناسه نوع مالیات'),
        keyboardType: TextInputType.number,
        onChanged: (value) => _updateFormData(formData.copyWith(taxTypeId: int.tryParse(value))),
      );
    }
  }

  Widget _buildTaxUnitDropdown() {
    final List<Map<String, dynamic>> effectiveTaxUnits = taxUnits.isNotEmpty ? taxUnits : _fallbackTaxUnits();
    if (effectiveTaxUnits.isNotEmpty) {
      return DropdownButtonFormField<int>(
        value: formData.taxUnitId,
        items: effectiveTaxUnits
            .map((taxUnit) => DropdownMenuItem<int>(
                  value: (taxUnit['id'] as num).toInt(),
                  child: Text((taxUnit['title'] ?? taxUnit['name'] ?? 'واحد ${taxUnit['id']}').toString()),
                ))
            .toList(),
        onChanged: (value) => _updateFormData(formData.copyWith(taxUnitId: value)),
        decoration: const InputDecoration(labelText: 'واحد مالیاتی'),
      );
    } else {
      return TextFormField(
        initialValue: formData.taxUnitId?.toString(),
        decoration: const InputDecoration(labelText: 'شناسه واحد مالیاتی'),
        keyboardType: TextInputType.number,
        onChanged: (value) => _updateFormData(formData.copyWith(taxUnitId: int.tryParse(value))),
      );
    }
  }

  List<Map<String, dynamic>> _fallbackTaxUnits() {
    final titles = [
      'بانكه', 'برگ', 'بسته', 'بشكه', 'بطری', 'بندیل', 'پاکت', 'پالت',
      'تانكر', 'تخته', 'تن', 'تن کیلومتر', 'توپ', 'تیوب', 'ثانیه', 'ثوب',
      'جام', 'جعبه', 'جفت', 'جلد', 'چلیك', 'حلب', 'حلقه (رول)', 'حلقه (دیسک)',
      'حلقه (رینگ)', 'دبه', 'دست', 'دستگاه', 'دقیقه', 'دوجین', 'روز', 'رول',
      'ساشه', 'ساعت', 'سال', 'سانتی متر', 'سانتی متر مربع', 'سبد', 'ست', 'سطل',
      'سیلندر', 'شاخه', 'شانه', 'شعله', 'شیت', 'صفحه', 'طاقه', 'طغرا', 'عدد',
      'عدل', 'فاقد بسته بندی', 'فروند', 'فوت مربع', 'قالب', 'قراص', 'قراصه (bundle)',
      'قرقره', 'قطعه', 'قوطي', 'قیراط', 'کارتن', 'کارتن (master case)', 'کلاف', 'کپسول',
      'کیسه', 'کیلوگرم', 'کیلومتر', 'کیلووات ساعت', 'گالن', 'گرم', 'گیگابایت بر ثانیه',
      'لنگه', 'لیتر', 'لیوان', 'ماه', 'متر', 'متر مربع', 'متر مكعب', 'مخزن',
      'مگاوات ساعت', 'ميلي گرم', 'ميلي لیتر', 'ميلي متر', 'نخ', 'نسخه (جلد)',
      'نفر', 'نفر- ساعت', 'نوبت', 'نیم دوجین', 'واحد', 'ورق', 'ویال'
    ];
    // Generate predictable ids starting from 1
    return List.generate(titles.length, (i) => {
      'id': i + 1,
      'title': titles[i],
    });
  }

  void _updateFormData(ProductFormData newData) {
    onChanged(newData);
  }
}
