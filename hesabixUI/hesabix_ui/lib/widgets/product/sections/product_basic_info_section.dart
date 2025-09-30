import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import '../../../models/product_form_data.dart';
import '../../../utils/product_form_validator.dart';

class ProductBasicInfoSection extends StatelessWidget {
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> attributes;
  final List<Map<String, dynamic>> units;

  const ProductBasicInfoSection({
    super.key,
    required this.formData,
    required this.onChanged,
    required this.categories,
    required this.attributes,
    required this.units,
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
                      decoration: InputDecoration(labelText: t.code + ' (اختیاری)'),
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
                    
                    DropdownButtonFormField<int>(
                      value: formData.categoryId,
                      items: categories
                          .map((category) => DropdownMenuItem<int>(
                                value: category['id'] as int,
                                child: Text((category['label'] ?? '').toString()),
                              ))
                          .toList(),
                      onChanged: (value) => _updateFormData(formData.copyWith(categoryId: value)),
                      decoration: InputDecoration(labelText: t.categories),
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
            decoration: InputDecoration(labelText: t.code + ' (اختیاری)'),
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
          
          DropdownButtonFormField<int>(
            value: formData.categoryId,
            items: categories
                .map((category) => DropdownMenuItem<int>(
                      value: category['id'] as int,
                      child: Text((category['label'] ?? '').toString()),
                    ))
                .toList(),
            onChanged: (value) => _updateFormData(formData.copyWith(categoryId: value)),
            decoration: InputDecoration(labelText: t.categories),
          ),
          const SizedBox(height: 20),
          _buildUnitsSection(context),
        ],
        
        if (attributes.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text('ویژگی‌ها', style: Theme.of(context).textTheme.titleSmall),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('واحدها', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildUnitTextField(
              label: 'واحد اصلی',
              isRequired: true,
              initialText: _unitNameById(formData.mainUnitId) ?? 'عدد',
              onChanged: (text) {
                final mappedId = _findUnitIdByTitle(text);
                _updateFormData(formData.copyWith(mainUnitId: mappedId));
              },
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildUnitTextField(
              label: 'واحد فرعی',
              isRequired: false,
              initialText: _unitNameById(formData.secondaryUnitId) ?? '',
              onChanged: (text) {
                final mappedId = _findUnitIdByTitle(text);
                _updateFormData(formData.copyWith(secondaryUnitId: mappedId));
              },
            )),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: formData.unitConversionFactor?.toString(),
                decoration: const InputDecoration(labelText: 'ضریب تبدیل واحد'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\\d*\\.?\\d{0,2}$')),
                ],
                validator: ProductFormValidator.validateConversionFactor,
                onChanged: (value) => _updateFormData(formData.copyWith(unitConversionFactor: num.tryParse(value))),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUnitTextField({
    required String label,
    required bool isRequired,
    required String initialText,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      initialValue: initialText,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.text,
      validator: isRequired ? (v) => (v == null || v.trim().isEmpty) ? '$label الزامی است' : null : null,
      onChanged: onChanged,
    );
  }

  String? _unitNameById(int? id) {
    if (id == null) return null;
    try {
      final u = units.firstWhere((e) => (e['id'] as num).toInt() == id);
      return (u['title'] ?? u['name'])?.toString();
    } catch (_) {
      return null;
    }
  }

  int? _findUnitIdByTitle(String? title) {
    if (title == null) return null;
    final t = title.trim();
    if (t.isEmpty) return null;
    for (final u in units) {
      final name = (u['title'] ?? u['name'] ?? '').toString();
      if (name.trim().toLowerCase() == t.toLowerCase()) {
        return (u['id'] as num).toInt();
      }
    }
    return null;
  }

  Widget _buildItemTypeSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نوع',
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
                title: 'کالا',
                subtitle: 'محصولات فیزیکی',
                icon: Icons.inventory_2_outlined,
                value: 'کالا',
                isSelected: formData.itemType == 'کالا',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildItemTypeCard(
                context: context,
                title: 'خدمت',
                subtitle: 'خدمات و سرویس‌ها',
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
              ? Theme.of(context).primaryColor.withOpacity(0.05)
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
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
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
