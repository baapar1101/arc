import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';

/// ویجت فرم ورودی برای تبدیل فارسی به فینگلیش
class PersianToFinglishWidget extends ZohalInquiryFormWidget {
  const PersianToFinglishWidget({
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
    final persianTextController = controllers['persian_text'] ?? TextEditingController();

    return [
      Text(
        'متن فارسی را وارد کنید تا به فینگلیش تبدیل شود:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: persianTextController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.persianText,
          helperText: ZohalFieldLabels.persianTextHelper,
          prefixIcon: const Icon(Icons.text_fields),
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        keyboardType: TextInputType.multiline,
        textDirection: TextDirection.rtl,
        maxLines: 5,
        minLines: 2,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'متن فارسی الزامی است';
          }
          if (value.trim().length < 2) {
            return 'متن باید حداقل 2 کاراکتر باشد';
          }
          return null;
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final persianTextController = controllers['persian_text'] ?? TextEditingController();
    final persianText = persianTextController.text.trim();
    
    return {
      'persian_text': persianText,
    };
  }
}
