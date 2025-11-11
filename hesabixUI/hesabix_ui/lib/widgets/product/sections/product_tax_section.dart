import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../models/product_form_data.dart';
import '../../../utils/number_normalizer.dart';
import '../../../utils/product_form_validator.dart';

class ProductTaxSection extends StatefulWidget {
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
  State<ProductTaxSection> createState() => _ProductTaxSectionState();
}

class _ProductTaxSectionState extends State<ProductTaxSection> {

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.taxTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 16),
        _buildTaxCodeTypeUnitRow(context),
        const SizedBox(height: 24),
        _buildSalesTaxSection(context),
        const SizedBox(height: 24),
        _buildPurchaseTaxSection(context),
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
              Expanded(child: _buildTaxCodeField(context)),
              const SizedBox(width: 12),
              Expanded(child: _buildTaxTypeDropdown(context)),
              const SizedBox(width: 12),
              Expanded(child: _buildTaxUnitDropdown(context)),
            ],
          );
        }
        return Column(
          children: [
            _buildTaxCodeField(context),
            const SizedBox(height: 12),
            _buildTaxTypeDropdown(context),
            const SizedBox(height: 12),
            _buildTaxUnitDropdown(context),
          ],
        );
      },
    );
  }

  Widget _buildTaxCodeField(BuildContext context) {
    final t = AppLocalizations.of(context);
    return TextFormField(
      initialValue: widget.formData.taxCode,
      decoration: InputDecoration(labelText: t.taxCode),
      keyboardType: TextInputType.number,
      inputFormatters: [
        const EnglishDigitsFormatter(),
        FilteringTextInputFormatter.digitsOnly,
      ],
      onChanged: (value) => widget.onChanged(
        widget.formData.copyWith(taxCode: value.trim().isEmpty ? null : toEnglishDigits(value)),
      ),
    );
  }

  Widget _buildSalesTaxSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: widget.formData.isSalesTaxable,
          onChanged: (value) => widget.onChanged(widget.formData.copyWith(isSalesTaxable: value)),
          title: Text(t.isSalesTaxable),
        ),
        if (widget.formData.isSalesTaxable) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.formData.salesTaxRate?.toString(),
            decoration: InputDecoration(labelText: t.salesTaxRate),
            keyboardType: TextInputType.number,
            inputFormatters: [
              const EnglishDigitsFormatter(),
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: (value) => ProductFormValidator.validateTaxRate(value, fieldName: t.salesTaxRate),
            onChanged: (value) => widget.onChanged(widget.formData.copyWith(salesTaxRate: num.tryParse(value))),
          ),
        ],
      ],
    );
  }

  Widget _buildPurchaseTaxSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: widget.formData.isPurchaseTaxable,
          onChanged: (value) => widget.onChanged(widget.formData.copyWith(isPurchaseTaxable: value)),
          title: Text(t.isPurchaseTaxable),
        ),
        if (widget.formData.isPurchaseTaxable) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.formData.purchaseTaxRate?.toString(),
            decoration: InputDecoration(labelText: t.purchaseTaxRate),
            keyboardType: TextInputType.number,
            inputFormatters: [
              const EnglishDigitsFormatter(),
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: (value) => ProductFormValidator.validateTaxRate(value, fieldName: t.purchaseTaxRate),
            onChanged: (value) => widget.onChanged(widget.formData.copyWith(purchaseTaxRate: num.tryParse(value))),
          ),
        ],
      ],
    );
  }

  Widget _buildTaxTypeDropdown(BuildContext context) {
    if (widget.taxTypes.isNotEmpty) {
      final t = AppLocalizations.of(context);
      return DropdownButtonFormField<int>(
        initialValue: widget.formData.taxTypeId,
        items: [
          DropdownMenuItem<int>(
            value: null,
            child: Text('انتخاب ${t.taxType}'),
          ),
          ...widget.taxTypes
              .map((taxType) => DropdownMenuItem<int>(
                    value: (taxType['id'] as num).toInt(),
                    child: Text((taxType['title'] ?? taxType['name'] ?? 'نوع ${taxType['id']}').toString()),
                  )),
        ],
        onChanged: (value) => widget.onChanged(widget.formData.copyWith(taxTypeId: value)),
        decoration: InputDecoration(labelText: t.taxType),
      );
    } else {
      final t = AppLocalizations.of(context);
      return TextFormField(
        initialValue: widget.formData.taxTypeId?.toString(),
        decoration: InputDecoration(labelText: t.taxType),
        keyboardType: TextInputType.number,
        onChanged: (value) => widget.onChanged(widget.formData.copyWith(taxTypeId: int.tryParse(value))),
      );
    }
  }

  Widget _buildTaxUnitDropdown(BuildContext context) {
    final List<Map<String, dynamic>> effectiveTaxUnits = widget.taxUnits.isNotEmpty ? widget.taxUnits : _fallbackTaxUnits();
    if (effectiveTaxUnits.isNotEmpty) {
      final t = AppLocalizations.of(context);
      return DropdownButtonFormField<int>(
        initialValue: widget.formData.taxUnitId,
        items: [
          DropdownMenuItem<int>(
            value: null,
            child: Text('انتخاب ${t.taxUnit}'),
          ),
          ...effectiveTaxUnits
              .map((taxUnit) => DropdownMenuItem<int>(
                    value: (taxUnit['id'] as num).toInt(),
                    child: Text((taxUnit['title'] ?? taxUnit['name'] ?? 'واحد ${taxUnit['id']}').toString()),
                  )),
        ],
        onChanged: (value) => widget.onChanged(widget.formData.copyWith(taxUnitId: value)),
        decoration: InputDecoration(labelText: t.taxUnit),
      );
    } else {
      final t = AppLocalizations.of(context);
      return TextFormField(
        initialValue: widget.formData.taxUnitId?.toString(),
        decoration: InputDecoration(labelText: t.taxUnitId),
        keyboardType: TextInputType.number,
        onChanged: (value) => widget.onChanged(widget.formData.copyWith(taxUnitId: int.tryParse(value))),
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

}
