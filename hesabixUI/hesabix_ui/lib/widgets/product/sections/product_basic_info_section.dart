import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../category/category_picker_field.dart';
import '../../../models/product_form_data.dart';
import '../../../utils/number_normalizer.dart';
import '../../../utils/product_form_validator.dart';

class ProductBasicInfoSection extends StatelessWidget {
  final int businessId;
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> attributes;

  const ProductBasicInfoSection({
    super.key,
    required this.businessId,
    required this.formData,
    required this.onChanged,
    required this.categories,
    required this.attributes,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isWideScreen = MediaQuery.of(context).size.width > 1000;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isWideScreen) ...[
          // دو ستون برای صفحه‌های بزرگ
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _buildItemTypeSelector(context),
                    const SizedBox(height: 20),
                    
                    TextFormField(
                      initialValue: formData.code,
                      decoration: InputDecoration(labelText: '${t.code} (اختیاری)'),
                      validator: ProductFormValidator.validateCode,
                      onChanged: (value) => _updateFormData(formData.copyWith(code: value.trim().isEmpty ? null : value.trim())),
                    ),
                    const SizedBox(height: 20),
                    
                    TextFormField(
                      initialValue: formData.name,
                      decoration: InputDecoration(labelText: t.title),
                      validator: ProductFormValidator.validateName,
                      onChanged: (value) => _updateFormData(formData.copyWith(name: value)),
                    ),
                    const SizedBox(height: 20),
                    _buildUnitsSection(context),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: formData.description,
                      decoration: InputDecoration(labelText: t.description),
                      onChanged: (value) => _updateFormData(formData.copyWith(description: value.trim().isEmpty ? null : value)),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 20),
                    
                    CategoryPickerField(
                      businessId: businessId,
                      categoriesTree: categories,
                      initialValue: formData.categoryId,
                      label: t.categories,
                      onChanged: (value) => _updateFormData(formData.copyWith(categoryId: value)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ] else ...[
          // یک ستون برای صفحه‌های کوچک
          _buildItemTypeSelector(context),
          const SizedBox(height: 20),
          
          TextFormField(
            initialValue: formData.code,
            decoration: InputDecoration(labelText: '${t.code} (اختیاری)'),
            validator: ProductFormValidator.validateCode,
            onChanged: (value) => _updateFormData(formData.copyWith(code: value.trim().isEmpty ? null : value.trim())),
          ),
          const SizedBox(height: 20),
          
          TextFormField(
            initialValue: formData.name,
            decoration: InputDecoration(labelText: t.title),
            validator: ProductFormValidator.validateName,
            onChanged: (value) => _updateFormData(formData.copyWith(name: value)),
          ),
          const SizedBox(height: 20),
          
          TextFormField(
            initialValue: formData.description,
            decoration: InputDecoration(labelText: t.description),
            onChanged: (value) => _updateFormData(formData.copyWith(description: value.trim().isEmpty ? null : value)),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          
          CategoryPickerField(
            businessId: businessId,
            categoriesTree: categories,
            initialValue: formData.categoryId,
            label: t.categories,
            onChanged: (value) => _updateFormData(formData.copyWith(categoryId: value)),
          ),
          const SizedBox(height: 20),
          _buildUnitsSection(context),
        ],
        
        if (attributes.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(t.productAttributes, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: attributes.map((attr) {
              final id = (attr['id'] as num).toInt();
              final title = (attr['title'] ?? 'ویژگی ${attr['id']}').toString();
              final selected = formData.selectedAttributeIds.contains(id);
              return FilterChip(
                label: Text(title),
                selected: selected,
                onSelected: (value) {
                  final newIds = Set<int>.from(formData.selectedAttributeIds);
                  if (value) {
                    newIds.add(id);
                  } else {
                    newIds.remove(id);
                  }
                  _updateFormData(formData.copyWith(selectedAttributeIds: newIds));
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  void _updateFormData(ProductFormData newData) {
    onChanged(newData);
  }

  Widget _buildUnitsSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.unitsTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: formData.mainUnit ?? '',
                decoration: InputDecoration(labelText: t.mainUnit),
                validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
                onChanged: (text) {
                  _updateFormData(formData.copyWith(
                    mainUnit: text.trim().isEmpty ? null : text.trim(),
                  ));
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: formData.secondaryUnit ?? '',
                decoration: InputDecoration(labelText: t.secondaryUnit),
                onChanged: (text) {
                  _updateFormData(formData.copyWith(
                    secondaryUnit: text.trim().isEmpty ? null : text.trim(),
                  ));
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: formData.unitConversionFactor.toString(),
                decoration: InputDecoration(labelText: t.unitConversionFactor),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]')),
                ],
                validator: (value) {
                  // اگر واحد فرعی انتخاب شده، ضریب اجباری و > 0 است
                  final hasSecondary = formData.secondaryUnit?.trim().isNotEmpty == true;
                  if (hasSecondary && (value == null || value.trim().isEmpty)) {
                    return t.required;
                  }
                  return ProductFormValidator.validateConversionFactor(value);
                },
                onChanged: (value) => _updateFormData(formData.copyWith(unitConversionFactor: num.tryParse(value))),
              ),
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildItemTypeSelector(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.itemType,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildItemTypeCard(
                context: context,
                title: t.products,
                subtitle: t.productPhysicalDesc,
                icon: Icons.inventory_2_outlined,
                value: 'کالا',
                isSelected: formData.itemType == 'کالا',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildItemTypeCard(
                context: context,
                title: t.services,
                subtitle: t.serviceDesc,
                icon: Icons.handyman_outlined,
                value: 'خدمت',
                isSelected: formData.itemType == 'خدمت',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemTypeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => _updateFormData(formData.copyWith(itemType: value)),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).primaryColor 
                : Theme.of(context).dividerColor,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected 
              ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
              : Theme.of(context).cardColor,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected 
                  ? Theme.of(context).primaryColor 
                  : Theme.of(context).iconTheme.color,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected 
                    ? Theme.of(context).primaryColor 
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Radio<String>(
              value: value,
              groupValue: formData.itemType,
              onChanged: (val) => _updateFormData(formData.copyWith(itemType: val ?? 'کالا')),
              activeColor: Theme.of(context).primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
