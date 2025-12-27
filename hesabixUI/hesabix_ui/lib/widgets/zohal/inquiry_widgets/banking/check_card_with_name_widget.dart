import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_input_formatters.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// ویجت فرم ورودی برای تطابق کارت و نام صاحب کارت
class CheckCardWithNameWidget extends ZohalInquiryFormWidget {
  const CheckCardWithNameWidget({
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
    final cardController = controllers['card_number'] ?? TextEditingController();
    final nameController = controllers['name'] ?? TextEditingController();

    return [
      Text(
        'شماره کارت و نام صاحب کارت را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: cardController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.cardNumber,
          hintText: ZohalFieldLabels.cardNumberHint,
          helperText: ZohalFieldLabels.cardNumberHelper,
          prefixIcon: const Icon(Icons.credit_card),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: ZohalInputFormatters.cardNumber(),
        validator: ZohalValidators.validateCardNumber,
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
    final cardController = controllers['card_number'] ?? TextEditingController();
    final nameController = controllers['name'] ?? TextEditingController();
    
    final cardNumber = toEnglishDigits(cardController.text.trim().replaceAll(RegExp(r'[^\d]'), ''));
    final name = nameController.text.trim();
    
    return {
      'card_number': cardNumber,
      'name': name,
    };
  }
}
