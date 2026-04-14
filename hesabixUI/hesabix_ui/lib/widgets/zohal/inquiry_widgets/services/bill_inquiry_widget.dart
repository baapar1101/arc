import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_input_formatters.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// ویجت فرم ورودی مشترک برای استعلام قبض‌های موبایل
class BillInquiryWidget extends ZohalInquiryFormWidget {
  final String billType; // 'mci', 'irancell', 'rightel'
  
  const BillInquiryWidget({
    super.key,
    required super.service,
    required super.controllers,
    required super.formKey,
    required super.onSubmit,
    required super.isSubmitting,
    required this.billType,
    super.onClose,
  });

  @override
  List<Widget> buildFormFields(BuildContext context) {
    final theme = Theme.of(context);
    final mobileController = controllers['mobile'] ?? TextEditingController();

    return [
      Text(
        'شماره موبایل $billType خود را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: mobileController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.mobile,
          hintText: ZohalFieldLabels.mobileHint,
          helperText: ZohalFieldLabels.mobileHelper,
          prefixIcon: const Icon(Icons.phone_android),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.phone,
        inputFormatters: ZohalInputFormatters.mobile(),
        validator: ZohalValidators.validateMobile,
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final mobileController = controllers['mobile'] ?? TextEditingController();
    final mobile = toEnglishDigits(mobileController.text.trim());
    
    return {
      'mobile': mobile,
    };
  }
}

/// ویجت فرم ورودی برای استعلام قبض تلفن ثابت
class FixedLineBillWidget extends ZohalInquiryFormWidget {
  const FixedLineBillWidget({
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
    final phoneController = controllers['phone'] ?? TextEditingController();

    return [
      Text(
        'شماره تلفن ثابت خود را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: phoneController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.phone,
          hintText: ZohalFieldLabels.phoneHint,
          helperText: ZohalFieldLabels.phoneHelper,
          prefixIcon: const Icon(Icons.phone),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.phone,
        inputFormatters: [
          EnglishDigitsFormatter(),
          FilteringTextInputFormatter.digitsOnly,
        ],
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'شماره تلفن الزامی است';
          }
          final cleaned = toEnglishDigits(value.trim());
          if (cleaned.length < 8 || cleaned.length > 11) {
            return 'شماره تلفن معتبر نیست';
          }
          return null;
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final phoneController = controllers['phone'] ?? TextEditingController();
    final phone = toEnglishDigits(phoneController.text.trim());
    
    return {
      'phone': phone,
    };
  }
}
