import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_input_formatters.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// ویجت فرم ورودی برای استعلام کد پستی
class PostalCodeInquiryWidget extends ZohalInquiryFormWidget {
  const PostalCodeInquiryWidget({
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
    final postalCodeController = controllers['postal_code'] ?? TextEditingController();

    return [
      Text(
        'کد پستی را وارد کنید تا آدرس کامل نمایش داده شود:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: postalCodeController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.postalCode,
          hintText: ZohalFieldLabels.postalCodeHint,
          helperText: ZohalFieldLabels.postalCodeHelper,
          prefixIcon: const Icon(Icons.local_post_office),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: ZohalInputFormatters.postalCode(),
        validator: ZohalValidators.validatePostalCode,
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final postalCodeController = controllers['postal_code'] ?? TextEditingController();
    final postalCode = toEnglishDigits(postalCodeController.text.trim());
    
    return {
      'postal_code': postalCode,
    };
  }
}
