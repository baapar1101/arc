import 'package:flutter/material.dart';
import 'zohal_inquiry_form_widget.dart';
import 'zohal_result_widget.dart';
import 'inquiry_widgets/card_inquiry_widget.dart';
import 'inquiry_widgets/shahkar_inquiry_widget.dart';
import 'inquiry_widgets/vehicle_inquiry_widget.dart';
import 'inquiry_widgets/company_inquiry_widget.dart';
import 'inquiry_widgets/identity_inquiry_widget.dart';
import 'inquiry_widgets/default_inquiry_widget.dart';
import 'result_widgets/card_inquiry_result_widget.dart';
import 'result_widgets/shahkar_result_widget.dart';
import 'result_widgets/vehicle_inquiry_result_widget.dart';
import 'result_widgets/company_inquiry_result_widget.dart';
import 'result_widgets/identity_inquiry_result_widget.dart';
import 'result_widgets/default_result_widget.dart';

/// فکتوری برای ساخت ویجت‌های اختصاصی ورودی و نمایش نتیجه سرویس‌های زحل
class ZohalServiceWidgetFactory {
  /// ساخت ویجت فرم ورودی بر اساس service_code
  static Widget buildInquiryForm({
    required Map<String, dynamic> service,
    required Map<String, TextEditingController> controllers,
    required GlobalKey<FormState> formKey,
    required Function(Map<String, dynamic>) onSubmit,
    required bool isSubmitting,
  }) {
    final serviceCode = service['service_code']?.toString() ?? '';
    
    // مسیر API را به service_code تبدیل می‌کنیم
    final normalizedCode = _normalizeServiceCode(serviceCode);
    
    switch (normalizedCode) {
      case 'card_inquiry':
        return CardInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
        );
      
      case 'shahkar':
        return ShahkarInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
        );
      
      case 'vehicle_inquiry_total_violations':
      case 'vehicle_inquiry_violations_details':
        return VehicleInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
        );
      
      case 'company_inquiry':
        return CompanyInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
        );
      
      case 'identity_inquiry':
      case 'national_code_inquiry':
      case 'identity':
      case 'national_code':
        return IdentityInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
        );
      
      default:
        return DefaultInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
        );
    }
  }

  /// ساخت ویجت نمایش نتیجه بر اساس service_code
  static Widget buildResultWidget({
    required Map<String, dynamic> result,
    required String? serviceCode,
    required double? amountCharged,
    required double? remainingBalance,
    required String? walletCurrency,
  }) {
    final normalizedCode = _normalizeServiceCode(serviceCode ?? '');
    
    switch (normalizedCode) {
      case 'card_inquiry':
        return CardInquiryResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'shahkar':
        return ShahkarResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'vehicle_inquiry_total_violations':
      case 'vehicle_inquiry_violations_details':
        return VehicleInquiryResultWidget(
          result: result,
          serviceCode: normalizedCode,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'company_inquiry':
        return CompanyInquiryResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'identity_inquiry':
      case 'national_code_inquiry':
      case 'identity':
      case 'national_code':
        return IdentityInquiryResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      default:
        return DefaultResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
    }
  }

  /// تبدیل مسیر API به service_code یکتا
  static String _normalizeServiceCode(String serviceCode) {
    // اگر service_code خالی است
    if (serviceCode.isEmpty) return 'default';
    
    String code = serviceCode.toLowerCase().trim();
    
    // اگر شامل مسیر کامل API است، استخراج کنیم
    // مثال: /services/inquiry/card_inquiry -> card_inquiry
    // مثال: /services/inquiry/vehicle_inquiry/total_violations -> vehicle_inquiry_total_violations
    if (code.contains('/')) {
      final parts = code.split('/').where((p) => p.isNotEmpty).toList();
      
      // پیدا کردن بخش inquiry
      final inquiryIndex = parts.indexOf('inquiry');
      if (inquiryIndex != -1 && inquiryIndex < parts.length - 1) {
        // گرفتن بخش‌های بعد از inquiry
        final serviceParts = parts.sublist(inquiryIndex + 1);
        code = serviceParts.join('_');
      } else {
        // اگر inquiry پیدا نشد، آخرین بخش را می‌گیریم
        code = parts.last;
      }
    }
    
    // تبدیل به فرمت استاندارد (حذف کاراکترهای غیرمجاز)
    code = code.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    
    // حذف underscoreهای اضافی
    code = code.replaceAll(RegExp(r'_+'), '_');
    code = code.replaceAll(RegExp(r'^_|_$'), '');
    
    return code.isEmpty ? 'default' : code;
  }
}
