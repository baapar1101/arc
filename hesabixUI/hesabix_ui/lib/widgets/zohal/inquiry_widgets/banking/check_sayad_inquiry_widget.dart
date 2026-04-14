import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_input_formatters.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// ویجت فرم ورودی برای استعلام چک صیادی
class CheckSayadInquiryWidget extends ZohalInquiryFormWidget {
  const CheckSayadInquiryWidget({
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
    final sayadIdController = controllers['sayad_id'] ?? TextEditingController();

    return [
      Text(
        'شناسه صیادی چک را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: sayadIdController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.sayadId,
          hintText: ZohalFieldLabels.sayadIdHint,
          helperText: ZohalFieldLabels.sayadIdHelper,
          prefixIcon: const Icon(Icons.receipt_long),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: ZohalInputFormatters.sayadId(),
        validator: ZohalValidators.validateSayadId,
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final sayadIdController = controllers['sayad_id'] ?? TextEditingController();
    final sayadId = toEnglishDigits(sayadIdController.text.trim());
    
    return {
      'sayad_id': sayadId,
    };
  }
}
