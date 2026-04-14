import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';

/// ویجت پیش‌فرض برای فرم‌های ورودی سرویس‌های زحل
/// از request_schema استفاده می‌کند تا به صورت خودکار فیلدها را بسازد
class DefaultInquiryWidget extends ZohalInquiryFormWidget {
  const DefaultInquiryWidget({
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
    final requestSchema = service['request_schema'] as Map<String, dynamic>?;
    final properties = requestSchema?['properties'] as Map<String, dynamic>? ?? {};
    final requiredFields = requestSchema?['required'] as List? ?? [];

    if (properties.isEmpty) {
      return [
        Text(
          'برای این سرویس فیلدهای ورودی تعریف نشده‌اند.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ];
    }

    return properties.entries.map((entry) {
      final fieldName = entry.key;
      final fieldSchema = entry.value as Map<String, dynamic>;
      final isRequired = requiredFields.contains(fieldName);
      final fieldType = fieldSchema['type']?.toString() ?? 'string';
      final example = fieldSchema['example']?.toString();
      final description = fieldSchema['description']?.toString();

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: controllers[fieldName] ?? TextEditingController(),
          decoration: InputDecoration(
            labelText: fieldName.replaceAll('_', ' '),
            hintText: example,
            helperText: description,
            border: const OutlineInputBorder(),
            prefixIcon: _getIconForField(fieldName),
          ),
          keyboardType: _getKeyboardType(fieldType),
          inputFormatters: _getInputFormatters(fieldName, fieldType),
          validator: (value) {
            if (isRequired && (value == null || value.trim().isEmpty)) {
              return 'این فیلد الزامی است';
            }
            return _validateField(value, fieldName, fieldSchema);
          },
        ),
      );
    }).toList();
  }

  @override
  Map<String, dynamic> collectFormData() {
    final requestSchema = service['request_schema'] as Map<String, dynamic>?;
    final properties = requestSchema?['properties'] as Map<String, dynamic>? ?? {};
    final data = <String, dynamic>{};

    for (var key in properties.keys) {
      final controller = controllers[key];
      if (controller != null) {
        final value = controller.text.trim();
        if (value.isNotEmpty) {
          final fieldSchema = properties[key] as Map<String, dynamic>;
          final fieldType = fieldSchema['type']?.toString() ?? 'string';
          
          if (fieldType == 'number' || fieldType == 'integer') {
            final numValue = num.tryParse(value);
            if (numValue != null) {
              data[key] = fieldType == 'integer' ? numValue.toInt() : numValue.toDouble();
            }
          } else {
            data[key] = value;
          }
        }
      }
    }

    return data;
  }

  Icon? _getIconForField(String fieldName) {
    if (fieldName.contains('mobile') || fieldName.contains('phone')) {
      return const Icon(Icons.phone);
    } else if (fieldName.contains('card')) {
      return const Icon(Icons.credit_card);
    } else if (fieldName.contains('iban')) {
      return const Icon(Icons.account_balance);
    } else if (fieldName.contains('national_code') || fieldName.contains('code')) {
      return const Icon(Icons.badge);
    } else if (fieldName.contains('name')) {
      return const Icon(Icons.person);
    } else if (fieldName.contains('date') || fieldName.contains('birth')) {
      return const Icon(Icons.calendar_today);
    } else if (fieldName.contains('email')) {
      return const Icon(Icons.email);
    } else if (fieldName.contains('plate')) {
      return const Icon(Icons.directions_car);
    } else if (fieldName.contains('region')) {
      return const Icon(Icons.location_on);
    }
    return const Icon(Icons.input);
  }

  TextInputType _getKeyboardType(String fieldType) {
    switch (fieldType) {
      case 'number':
      case 'integer':
        return TextInputType.number;
      case 'email':
        return TextInputType.emailAddress;
      case 'phone':
        return TextInputType.phone;
      default:
        return TextInputType.text;
    }
  }

  List<TextInputFormatter>? _getInputFormatters(String fieldName, String fieldType) {
    final formatters = <TextInputFormatter>[];

    if (fieldType == 'number' || fieldType == 'integer') {
      formatters.add(FilteringTextInputFormatter.allow(RegExp(r'[\d.]')));
    } else if (fieldName.contains('mobile') || fieldName.contains('phone')) {
      formatters.add(FilteringTextInputFormatter.digitsOnly);
    } else if (fieldName.contains('card') || fieldName.contains('national_code')) {
      formatters.add(FilteringTextInputFormatter.digitsOnly);
    }

    return formatters.isEmpty ? null : formatters;
  }

  String? _validateField(String? value, String fieldName, Map<String, dynamic> fieldSchema) {
    if (value == null || value.isEmpty) return null;

    // اعتبارسنجی کد ملی
    if (fieldName.contains('national_code')) {
      final cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
      if (cleaned.length != 10) {
        return 'کد ملی باید 10 رقم باشد';
      }
    }

    // اعتبارسنجی شماره کارت
    if (fieldName.contains('card')) {
      final cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
      if (cleaned.length != 16) {
        return 'شماره کارت باید 16 رقم باشد';
      }
    }

    // اعتبارسنجی موبایل
    if (fieldName.contains('mobile') || fieldName.contains('phone')) {
      final cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
      if (!RegExp(r'^09\d{9}$').hasMatch(cleaned)) {
        return 'شماره موبایل معتبر نیست';
      }
    }

    return null;
  }
}

