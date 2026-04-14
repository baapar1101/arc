import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_input_formatters.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// ویجت فرم ورودی برای تبدیل کارت به شبا
class CardToIbanWidget extends ZohalInquiryFormWidget {
  const CardToIbanWidget({
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

    return [
      Text(
        'شماره کارت بانکی خود را وارد کنید تا اطلاعات شبا استخراج شود:',
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
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final cardController = controllers['card_number'] ?? TextEditingController();
    final cardNumber = toEnglishDigits(cardController.text.trim().replaceAll(RegExp(r'[^\d]'), ''));
    
    return {
      'card_number': cardNumber,
    };
  }
}
