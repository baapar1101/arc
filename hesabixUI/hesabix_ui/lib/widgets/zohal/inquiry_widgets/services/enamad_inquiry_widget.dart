import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';

/// ویجت فرم ورودی برای استعلام نماد اعتماد الکترونیکی
class EnamadInquiryWidget extends ZohalInquiryFormWidget {
  const EnamadInquiryWidget({
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
    final websiteController = controllers['website'] ?? TextEditingController();

    return [
      Text(
        'آدرس وب‌سایت را وارد کنید تا اطلاعات نماد اعتماد بررسی شود:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: websiteController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.website,
          hintText: ZohalFieldLabels.websiteHint,
          helperText: ZohalFieldLabels.websiteHelper,
          prefixIcon: const Icon(Icons.language),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.url,
        validator: ZohalValidators.validateUrl,
        onChanged: (value) {
          // تبدیل خودکار به lowercase و حذف http/https اگر کاربر وارد کرده
          final cleaned = value.trim().toLowerCase();
          if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
            websiteController.value = TextEditingValue(
              text: cleaned.substring(cleaned.indexOf('://') + 3),
              selection: TextSelection.collapsed(offset: cleaned.length - (cleaned.indexOf('://') + 3)),
            );
          }
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final websiteController = controllers['website'] ?? TextEditingController();
    final website = websiteController.text.trim().toLowerCase();
    
    // اگر http:// یا https:// ندارد، اضافه می‌کنیم
    String finalWebsite = website;
    if (!finalWebsite.startsWith('http://') && !finalWebsite.startsWith('https://')) {
      finalWebsite = 'http://$finalWebsite';
    }
    
    return {
      'website': finalWebsite,
    };
  }
}
