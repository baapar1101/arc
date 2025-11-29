import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../zohal_inquiry_form_widget.dart';
import '../../../utils/number_normalizer.dart';

/// ویجت فرم ورودی برای استعلام اطلاعات شرکت
class CompanyInquiryWidget extends ZohalInquiryFormWidget {
  const CompanyInquiryWidget({
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
    final nationalIdController = controllers['national_id'] ?? TextEditingController();

    return [
      Text(
        'شناسه ملی شرکت را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: nationalIdController,
        decoration: InputDecoration(
          labelText: 'شناسه ملی شرکت',
          hintText: '1400XXXXXX40',
          prefixIcon: const Icon(Icons.business),
          border: const OutlineInputBorder(),
          helperText: 'شناسه ملی 11 رقمی شرکت',
        ),
        keyboardType: TextInputType.number,
        maxLength: 11,
        inputFormatters: [
          const EnglishDigitsFormatter(),
          FilteringTextInputFormatter.digitsOnly,
        ],
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'شناسه ملی شرکت الزامی است';
          }
          final cleaned = toEnglishDigits(value.trim());
          if (cleaned.length < 10 || cleaned.length > 11) {
            return 'شناسه ملی شرکت باید 10 یا 11 رقم باشد';
          }
          return null;
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    return {
      'national_id': toEnglishDigits((controllers['national_id'] ?? TextEditingController()).text.trim()),
    };
  }
}

