import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/card_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/shahkar_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/vehicle_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/company_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/identity_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/default_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/banking/card_to_iban_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/banking/iban_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/banking/check_card_with_name_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/banking/account_to_iban_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/banking/check_iban_with_name_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/banking/check_sayad_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/banking/bounced_cheque_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/services/postal_code_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/services/bill_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/services/enamad_inquiry_widget.dart';
import 'package:hesabix_ui/widgets/zohal/inquiry_widgets/services/persian_to_finglish_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/card_inquiry_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/shahkar_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/vehicle_inquiry_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/company_inquiry_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/identity_inquiry_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/default_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/banking/card_to_iban_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/banking/iban_inquiry_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/banking/account_to_iban_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/banking/check_sayad_inquiry_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/banking/bounced_cheque_result_widget.dart';
import 'package:hesabix_ui/widgets/zohal/result_widgets/services/postal_code_inquiry_result_widget.dart';

/// فکتوری برای ساخت ویجت‌های اختصاصی ورودی و نمایش نتیجه سرویس‌های زحل
class ZohalServiceWidgetFactory {
  /// ساخت ویجت فرم ورودی بر اساس service_code
  static Widget buildInquiryForm({
    required Map<String, dynamic> service,
    required Map<String, TextEditingController> controllers,
    required GlobalKey<FormState> formKey,
    required Function(Map<String, dynamic>) onSubmit,
    required bool isSubmitting,
    VoidCallback? onClose,
  }) {
    final serviceCode = service['service_code']?.toString() ?? '';
    
    // مسیر API را به service_code تبدیل می‌کنیم
    final normalizedCode = _normalizeServiceCode(serviceCode);
    
    switch (normalizedCode) {
      // بانکی
      case 'card_inquiry':
        return CardInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'card_to_iban':
        return CardToIbanWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'iban':
        return IbanInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'check_card_with_name':
        return CheckCardWithNameWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'account_to_iban':
        return AccountToIbanWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'check_iban_with_name':
        return CheckIbanWithNameWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'check_sayad_inquiry':
        return CheckSayadInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'bounced_cheque':
        return BouncedChequeWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      // خدماتی
      case 'postal_code_inquiry':
        return PostalCodeInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'bill_mci':
        return BillInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          billType: 'mci',
          onClose: onClose,
        );
      
      case 'bill_irancell':
        return BillInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          billType: 'irancell',
          onClose: onClose,
        );
      
      case 'bill_rightel':
        return BillInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          billType: 'rightel',
          onClose: onClose,
        );
      
      case 'bill_fixed_line':
        return FixedLineBillWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'enamad_inquiry':
        return EnamadInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'persian_to_finglish':
        return PersianToFinglishWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      // دیگر سرویس‌ها
      case 'shahkar':
        return ShahkarInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'vehicle_inquiry_total_violations':
      case 'vehicle_inquiry_violations_details':
        return VehicleInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
        );
      
      case 'company_inquiry':
        return CompanyInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
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
          onClose: onClose,
        );
      
      default:
        return DefaultInquiryWidget(
          service: service,
          controllers: controllers,
          formKey: formKey,
          onSubmit: onSubmit,
          isSubmitting: isSubmitting,
          onClose: onClose,
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
      // بانکی
      case 'card_inquiry':
        return CardInquiryResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'card_to_iban':
        return CardToIbanResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'iban':
        return IbanInquiryResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'account_to_iban':
        return AccountToIbanResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'check_sayad_inquiry':
        return CheckSayadInquiryResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      case 'bounced_cheque':
        return BouncedChequeResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      // خدماتی
      case 'postal_code_inquiry':
        return PostalCodeInquiryResultWidget(
          result: result,
          amountCharged: amountCharged,
          remainingBalance: remainingBalance,
          walletCurrency: walletCurrency,
        );
      
      // دیگر سرویس‌ها
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
    // مثال: /services/inquiry/bill/mci -> bill_mci
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
