import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_input_formatters.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// ویجت فرم ورودی برای استعلام چک برگشتی
class BouncedChequeWidget extends ZohalInquiryFormWidget {
  const BouncedChequeWidget({
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
    final nationalCodeController = controllers['national_code'] ?? TextEditingController();
    final nationalityTypeController = controllers['nationality_type'] ?? TextEditingController();

    return [
      Text(
        'کد ملی و نوع ملیت را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: nationalCodeController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.nationalCode,
          hintText: ZohalFieldLabels.nationalCodeHint,
          helperText: ZohalFieldLabels.nationalCodeHelper,
          prefixIcon: const Icon(Icons.badge),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: ZohalInputFormatters.nationalCode(),
        validator: ZohalValidators.validateNationalCode,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        value: nationalityTypeController.text.isNotEmpty ? nationalityTypeController.text : null,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.nationalityType,
          helperText: ZohalFieldLabels.nationalityTypeHelper,
          prefixIcon: const Icon(Icons.flag),
          border: const OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: '1', child: Text('ایرانی')),
          DropdownMenuItem(value: '2', child: Text('غیرایرانی')),
        ],
        onChanged: (value) {
          if (value != null) {
            nationalityTypeController.text = value;
          }
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'نوع ملیت الزامی است';
          }
          return null;
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final nationalCodeController = controllers['national_code'] ?? TextEditingController();
    final nationalityTypeController = controllers['nationality_type'] ?? TextEditingController();
    
    final nationalCode = toEnglishDigits(nationalCodeController.text.trim());
    final nationalityType = int.tryParse(nationalityTypeController.text.trim()) ?? 1;
    
    return {
      'national_code': nationalCode,
      'nationality_type': nationalityType,
    };
  }
}
