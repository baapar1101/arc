import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../zohal_inquiry_form_widget.dart';
import '../../../utils/number_normalizer.dart';

/// ویجت فرم ورودی برای سرویس شاهکار (تطابق کد ملی و موبایل)
class ShahkarInquiryWidget extends ZohalInquiryFormWidget {
  const ShahkarInquiryWidget({
    super.key,
    required super.service,
    required super.controllers,
    required super.formKey,
    required super.onSubmit,
    required super.isSubmitting,
  });

  @override
  List<Widget> buildFormFields(BuildContext context) {
    final theme = Theme.of(context);
    final mobileController = controllers['mobile'] ?? TextEditingController();
    final nationalCodeController = controllers['national_code'] ?? TextEditingController();

    return [
      Text(
        'لطفاً شماره موبایل و کد ملی را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: mobileController,
        decoration: InputDecoration(
          labelText: 'شماره موبایل',
          hintText: '09123456789',
          prefixIcon: const Icon(Icons.phone),
          border: const OutlineInputBorder(),
          helperText: 'شماره 11 رقمی موبایل',
        ),
        keyboardType: TextInputType.phone,
        maxLength: 11,
        inputFormatters: [
          const EnglishDigitsFormatter(),
          FilteringTextInputFormatter.digitsOnly,
        ],
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'شماره موبایل الزامی است';
          }
          final cleaned = toEnglishDigits(value.trim());
          if (cleaned.length != 11) {
            return 'شماره موبایل باید 11 رقم باشد';
          }
          if (!RegExp(r'^09\d{9}$').hasMatch(cleaned)) {
            return 'شماره موبایل باید با 09 شروع شود';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: nationalCodeController,
        decoration: InputDecoration(
          labelText: 'کد ملی',
          hintText: '1234567890',
          prefixIcon: const Icon(Icons.badge),
          border: const OutlineInputBorder(),
          helperText: 'کد ملی 10 رقمی',
        ),
        keyboardType: TextInputType.number,
        maxLength: 10,
        inputFormatters: [
          const EnglishDigitsFormatter(),
          FilteringTextInputFormatter.digitsOnly,
        ],
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'کد ملی الزامی است';
          }
          final cleaned = toEnglishDigits(value.trim());
          if (cleaned.length != 10) {
            return 'کد ملی باید 10 رقم باشد';
          }
          return null;
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final mobileController = controllers['mobile'] ?? TextEditingController();
    final nationalCodeController = controllers['national_code'] ?? TextEditingController();
    
    return {
      'mobile': toEnglishDigits(mobileController.text.trim()),
      'national_code': toEnglishDigits(nationalCodeController.text.trim()),
    };
  }
}

