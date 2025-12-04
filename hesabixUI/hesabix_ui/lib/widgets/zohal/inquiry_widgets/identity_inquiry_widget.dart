import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../zohal_inquiry_form_widget.dart';
import '../../../utils/number_normalizer.dart';

/// ویجت فرم ورودی برای استعلام اطلاعات هویتی (کد ملی و تاریخ تولد)
class IdentityInquiryWidget extends ZohalInquiryFormWidget {
  const IdentityInquiryWidget({
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
    final nationalCodeController = controllers['national_code'] ?? TextEditingController();
    final birthDateController = controllers['birth_date'] ?? TextEditingController();

    return [
      Text(
        'لطفاً کد ملی و تاریخ تولد را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
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
          // اعتبارسنجی الگوریتم کد ملی
          if (!_isValidNationalId(cleaned)) {
            return 'کد ملی نامعتبر است';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: birthDateController,
        decoration: InputDecoration(
          labelText: 'تاریخ تولد',
          hintText: '1370-01-01 یا 1370/01/01',
          prefixIcon: const Icon(Icons.calendar_today),
          border: const OutlineInputBorder(),
          helperText: 'تاریخ تولد به فرمت شمسی (YYYY-MM-DD یا YYYY/MM/DD)',
          suffixIcon: IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () => _selectBirthDate(context, birthDateController),
            tooltip: 'انتخاب تاریخ',
          ),
        ),
        keyboardType: TextInputType.datetime,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'تاریخ تولد الزامی است';
          }
          final cleaned = value.trim();
          // اعتبارسنجی فرمت تاریخ شمسی
          if (!_isValidJalaliDate(cleaned)) {
            return 'فرمت تاریخ نامعتبر است. مثال: 1370-01-01 یا 1370/01/01';
          }
          return null;
        },
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final nationalCodeController = controllers['national_code'] ?? TextEditingController();
    final birthDateController = controllers['birth_date'] ?? TextEditingController();
    
    // تبدیل تاریخ به فرمت استاندارد (YYYY-MM-DD)
    String birthDate = birthDateController.text.trim();
    birthDate = birthDate.replaceAll('/', '-');
    
    return {
      'national_code': toEnglishDigits(nationalCodeController.text.trim()),
      'birth_date': birthDate,
    };
  }

  /// اعتبارسنجی کد ملی ایرانی
  bool _isValidNationalId(String nationalId) {
    if (nationalId.length != 10) return false;
    
    // بررسی اینکه همه ارقام یکسان نباشند
    if (RegExp(r'^(\d)\1{9}$').hasMatch(nationalId)) return false;
    
    // اعتبارسنجی الگوریتم کد ملی
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(nationalId[i]) * (10 - i);
    }
    int remainder = sum % 11;
    int checkDigit = remainder < 2 ? remainder : 11 - remainder;
    
    return checkDigit == int.parse(nationalId[9]);
  }

  /// اعتبارسنجی فرمت تاریخ شمسی
  bool _isValidJalaliDate(String date) {
    // تبدیل جداکننده‌ها به -
    String normalized = date.replaceAll('/', '-');
    
    // بررسی فرمت YYYY-MM-DD
    final regex = RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$');
    if (!regex.hasMatch(normalized)) return false;
    
    final parts = normalized.split('-');
    if (parts.length != 3) return false;
    
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    
    if (year == null || month == null || day == null) return false;
    
    // بررسی محدوده‌های منطقی
    if (year < 1300 || year > 1450) return false;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    
    return true;
  }

  /// انتخاب تاریخ تولد (در صورت نیاز می‌توان DatePicker اضافه کرد)
  Future<void> _selectBirthDate(BuildContext context, TextEditingController controller) async {
    // در حال حاضر فقط یک placeholder
    // می‌توان در آینده DatePicker شمسی اضافه کرد
    final textController = TextEditingController(text: controller.text);
    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تاریخ تولد'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: 'تاریخ تولد (YYYY-MM-DD)',
            hintText: '1370-01-01',
          ),
          keyboardType: TextInputType.datetime,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              if (textController.text.trim().isNotEmpty) {
                controller.text = textController.text.trim();
              }
              Navigator.pop(context);
            },
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
  }
}

