import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_input_formatters.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// ویجت فرم ورودی برای تطابق شبا و نام صاحب حساب
class CheckIbanWithNameWidget extends ZohalInquiryFormWidget {
  const CheckIbanWithNameWidget({
    super.key,
    required super.service,
    required super.controllers,
    required super.formKey,
    required super.onSubmit,
    required super.isSubmitting,
    super.onClose,
  });

  @override
  List<Widget> buildFormFields(BuildContext context) {
    final theme = Theme.of(context);
    final ibanController = controllers['iban'] ?? TextEditingController();
    final nameController = controllers['name'] ?? TextEditingController();

    return [
      Text(
        'شماره شبا و نام صاحب حساب را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: ibanController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.iban,
          hintText: ZohalFieldLabels.ibanHint,
          helperText: ZohalFieldLabels.ibanHelper,
          prefixIcon: const Icon(Icons.account_balance),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: ZohalInputFormatters.iban(),
        validator: ZohalValidators.validateIban,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: nameController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.name,
          hintText: ZohalFieldLabels.nameHint,
          helperText: ZohalFieldLabels.nameHelper,
          prefixIcon: const Icon(Icons.person),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.text,
        textDirection: TextDirection.rtl,
        validator: ZohalValidators.validatePersianName,
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final ibanController = controllers['iban'] ?? TextEditingController();
    final nameController = controllers['name'] ?? TextEditingController();
    
    final iban = toEnglishDigits(ibanController.text.trim().replaceAll(RegExp(r'[\s\-]'), ''));
    final name = nameController.text.trim();
    
    return {
      'iban': iban,
      'name': name,
    };
  }
}
