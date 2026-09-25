import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../models/business_models.dart';
import '../../../utils/number_normalizer.dart';
import '../../../utils/responsive_helper.dart';
import 'new_business_labels.dart';
import 'new_business_shared.dart';

class NewBusinessIdentityStep extends StatelessWidget {
  final BusinessData data;
  final TextEditingController nameController;
  final FocusNode? nameFocusNode;
  final ValueChanged<BusinessData> onChanged;
  final bool showNameError;

  const NewBusinessIdentityStep({
    super.key,
    required this.data,
    required this.nameController,
    required this.onChanged,
    this.nameFocusNode,
    this.showNameError = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final spacing = ResponsiveHelper.responsiveValue(
      context,
      mobile: 18,
      tablet: 20,
      desktop: 22,
    );
    final crossAxisCount = ResponsiveHelper.isMobile(context)
        ? 2
        : (ResponsiveHelper.isTablet(context) ? 3 : 4);

    return NewBusinessFormShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NewBusinessSectionHeader(
            title: t.newBusinessIdentityStepTitle,
            subtitle: t.newBusinessIdentityStepSubtitle,
          ),
          SizedBox(height: spacing * 1.25),
          TextFormField(
            controller: nameController,
            focusNode: nameFocusNode,
            textInputAction: TextInputAction.next,
            decoration: newBusinessInputDecoration(
              context,
              labelText: t.businessName,
              hintText: t.newBusinessNameHint,
              required: true,
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: showNameError && data.name.trim().isEmpty
                  ? '${t.businessName} ${t.required}'
                  : null,
            ),
            onChanged: (value) {
              onChanged(data.copyWith(name: value));
            },
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
          ),
          SizedBox(height: spacing * 1.35),
          Text(
            t.businessType,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: BusinessType.values.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: ResponsiveHelper.isMobile(context)
                  ? 1.15
                  : 1.25,
            ),
            itemBuilder: (context, index) {
              final type = BusinessType.values[index];
              return NewBusinessSelectTile(
                icon: businessTypeIcon(type),
                label: localizedBusinessType(t, type),
                selected: data.businessType == type,
                onTap: () => onChanged(data.copyWith(businessType: type)),
              );
            },
          ),
          SizedBox(height: spacing * 1.35),
          Text(
            t.businessField,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: BusinessField.values.map((field) {
              return NewBusinessFieldChip(
                icon: businessFieldIcon(field),
                label: localizedBusinessField(t, field),
                selected: data.businessField == field,
                onTap: () => onChanged(data.copyWith(businessField: field)),
              );
            }).toList(),
          ),
          SizedBox(height: spacing * 1.25),
          NewBusinessSurface(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: data.includeSampleData,
              onChanged: (v) => onChanged(data.copyWith(includeSampleData: v)),
              title: Text(
                t.includeSampleDataLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t.includeSampleDataSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: spacing),
          NewBusinessSurface(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                t.newBusinessOptionalDetails,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                t.newBusinessOptionalDetailsHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              children: [
                _OptionalDetailsForm(data: data, onChanged: onChanged),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionalDetailsForm extends StatelessWidget {
  final BusinessData data;
  final ValueChanged<BusinessData> onChanged;

  const _OptionalDetailsForm({required this.data, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final spacing = 14.0;
    final twoCol = !ResponsiveHelper.isMobile(context);

    Widget field({
      required String label,
      String? value,
      String? hint,
      String? errorText,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      int maxLines = 1,
      required ValueChanged<String> onFieldChanged,
    }) {
      return TextFormField(
        initialValue: value ?? '',
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: newBusinessInputDecoration(
          context,
          labelText: label,
          helperText: hint,
          errorText: errorText,
        ),
        onChanged: onFieldChanged,
      );
    }

    final phoneMobile = twoCol
        ? Row(
            children: [
              Expanded(
                child: field(
                  label: t.phone,
                  value: data.phone,
                  hint: '${t.example}: ${t.phoneExample}',
                  errorText: data.getValidationError('phone'),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [EnglishDigitsFormatter()],
                  onFieldChanged: (v) => onChanged(data.copyWith(phone: v)),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: field(
                  label: t.mobile,
                  value: data.mobile,
                  hint: '${t.example}: ${t.mobileExample}',
                  errorText: data.getValidationError('mobile'),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [EnglishDigitsFormatter()],
                  onFieldChanged: (v) =>
                      onChanged(data.copyWith(mobile: toEnglishDigits(v))),
                ),
              ),
            ],
          )
        : Column(
            children: [
              field(
                label: t.phone,
                value: data.phone,
                hint: '${t.example}: ${t.phoneExample}',
                errorText: data.getValidationError('phone'),
                keyboardType: TextInputType.phone,
                inputFormatters: [EnglishDigitsFormatter()],
                onFieldChanged: (v) => onChanged(data.copyWith(phone: v)),
              ),
              SizedBox(height: spacing),
              field(
                label: t.mobile,
                value: data.mobile,
                hint: '${t.example}: ${t.mobileExample}',
                errorText: data.getValidationError('mobile'),
                keyboardType: TextInputType.phone,
                inputFormatters: [EnglishDigitsFormatter()],
                onFieldChanged: (v) =>
                    onChanged(data.copyWith(mobile: toEnglishDigits(v))),
              ),
            ],
          );

    return Column(
      children: [
        field(
          label: t.address,
          value: data.address,
          maxLines: 2,
          onFieldChanged: (v) => onChanged(data.copyWith(address: v)),
        ),
        SizedBox(height: spacing),
        phoneMobile,
        SizedBox(height: spacing),
        field(
          label: t.postalCode,
          value: data.postalCode,
          keyboardType: TextInputType.number,
          inputFormatters: [
            EnglishDigitsFormatter(),
            FilteringTextInputFormatter.digitsOnly,
          ],
          onFieldChanged: (v) =>
              onChanged(data.copyWith(postalCode: toEnglishDigits(v))),
        ),
        SizedBox(height: spacing),
        if (twoCol)
          Row(
            children: [
              Expanded(
                child: field(
                  label: t.country,
                  value: data.country,
                  onFieldChanged: (v) => onChanged(data.copyWith(country: v)),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: field(
                  label: t.province,
                  value: data.province,
                  onFieldChanged: (v) => onChanged(data.copyWith(province: v)),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: field(
                  label: t.city,
                  value: data.city,
                  onFieldChanged: (v) => onChanged(data.copyWith(city: v)),
                ),
              ),
            ],
          )
        else ...[
          field(
            label: t.country,
            value: data.country,
            onFieldChanged: (v) => onChanged(data.copyWith(country: v)),
          ),
          SizedBox(height: spacing),
          field(
            label: t.province,
            value: data.province,
            onFieldChanged: (v) => onChanged(data.copyWith(province: v)),
          ),
          SizedBox(height: spacing),
          field(
            label: t.city,
            value: data.city,
            onFieldChanged: (v) => onChanged(data.copyWith(city: v)),
          ),
        ],
        SizedBox(height: spacing),
        field(
          label: t.nationalId,
          value: data.nationalId,
          hint: '${t.example}: ${t.nationalIdExample}',
          errorText: data.getValidationError('nationalId'),
          keyboardType: TextInputType.number,
          inputFormatters: [
            EnglishDigitsFormatter(),
            FilteringTextInputFormatter.digitsOnly,
          ],
          onFieldChanged: (v) =>
              onChanged(data.copyWith(nationalId: toEnglishDigits(v))),
        ),
        SizedBox(height: spacing),
        if (twoCol)
          Row(
            children: [
              Expanded(
                child: field(
                  label: t.registrationNumber,
                  value: data.registrationNumber,
                  onFieldChanged: (v) =>
                      onChanged(data.copyWith(registrationNumber: v)),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: field(
                  label: t.economicId,
                  value: data.economicId,
                  onFieldChanged: (v) =>
                      onChanged(data.copyWith(economicId: v)),
                ),
              ),
            ],
          )
        else ...[
          field(
            label: t.registrationNumber,
            value: data.registrationNumber,
            onFieldChanged: (v) =>
                onChanged(data.copyWith(registrationNumber: v)),
          ),
          SizedBox(height: spacing),
          field(
            label: t.economicId,
            value: data.economicId,
            onFieldChanged: (v) => onChanged(data.copyWith(economicId: v)),
          ),
        ],
      ],
    );
  }
}
