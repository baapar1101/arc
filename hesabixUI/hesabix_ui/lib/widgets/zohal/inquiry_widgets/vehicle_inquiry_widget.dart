import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart' show toEnglishDigits, EnglishDigitsFormatter;

/// ویجت فرم ورودی برای استعلام خلافی خودرو
class VehicleInquiryWidget extends ZohalInquiryFormWidget {
  const VehicleInquiryWidget({
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
    final mobileController = controllers['mobile'] ?? TextEditingController();
    final nationalCodeController = controllers['national_code'] ?? TextEditingController();
    final plateNumberController = controllers['plate_number'] ?? TextEditingController();
    final regionCodeController = controllers['region_code'] ?? TextEditingController();

    return [
      Text(
        'لطفاً اطلاعات خودرو را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: mobileController,
        decoration: InputDecoration(
          labelText: 'شماره موبایل مالک',
          hintText: '092XXXXXXXX',
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
          hintText: '002XXXXXX1',
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
      const SizedBox(height: 16),
      TextFormField(
        controller: plateNumberController,
        decoration: InputDecoration(
          labelText: 'شماره پلاک',
          hintText: '11 ب 111',
          prefixIcon: const Icon(Icons.directions_car),
          border: const OutlineInputBorder(),
          helperText: 'شماره پلاک خودرو',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'شماره پلاک الزامی است';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: regionCodeController,
        decoration: InputDecoration(
          labelText: 'کد منطقه',
          hintText: '11',
          prefixIcon: const Icon(Icons.location_on),
          border: const OutlineInputBorder(),
          helperText: 'کد منطقه پلاک',
        ),
        keyboardType: TextInputType.number,
        maxLength: 2,
        inputFormatters: [
          const EnglishDigitsFormatter(),
          FilteringTextInputFormatter.digitsOnly,
        ],
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'کد منطقه الزامی است';
          }
          return null;
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    return {
      'mobile': toEnglishDigits((controllers['mobile'] ?? TextEditingController()).text.trim()),
      'national_code': toEnglishDigits((controllers['national_code'] ?? TextEditingController()).text.trim()),
      'plate_number': (controllers['plate_number'] ?? TextEditingController()).text.trim(),
      'region_code': (controllers['region_code'] ?? TextEditingController()).text.trim(),
    };
  }
}

