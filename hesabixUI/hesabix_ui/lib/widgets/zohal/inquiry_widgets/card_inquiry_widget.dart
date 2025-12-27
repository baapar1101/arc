import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart' show toEnglishDigits, EnglishDigitsFormatter;

/// ویجت فرم ورودی برای استعلام نام صاحب کارت
class CardInquiryWidget extends ZohalInquiryFormWidget {
  const CardInquiryWidget({
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
        'شماره کارت بانکی خود را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: cardController,
        decoration: InputDecoration(
          labelText: 'شماره کارت',
          hintText: '6362141234567890',
          prefixIcon: const Icon(Icons.credit_card),
          border: const OutlineInputBorder(),
          helperText: 'شماره 16 رقمی کارت بانکی',
        ),
        keyboardType: TextInputType.number,
        maxLength: 16,
        inputFormatters: [
          const EnglishDigitsFormatter(),
          FilteringTextInputFormatter.digitsOnly,
        ],
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'شماره کارت الزامی است';
          }
          final cleaned = toEnglishDigits(value.trim());
          if (cleaned.length < 16) {
            return 'شماره کارت باید 16 رقم باشد';
          }
          if (!RegExp(r'^\d{16}$').hasMatch(cleaned)) {
            return 'شماره کارت نامعتبر است';
          }
          return null;
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final cardController = controllers['card_number'] ?? TextEditingController();
    final cardNumber = toEnglishDigits(cardController.text.trim());
    
    return {
      'card_number': cardNumber,
    };
  }
}
