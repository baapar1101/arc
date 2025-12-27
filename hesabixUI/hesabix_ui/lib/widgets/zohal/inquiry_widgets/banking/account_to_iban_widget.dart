import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_inquiry_form_widget.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_validators.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_input_formatters.dart';
import 'package:hesabix_ui/widgets/zohal/common/zohal_field_labels.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// ویجت فرم ورودی برای تبدیل حساب به شبا
class AccountToIbanWidget extends ZohalInquiryFormWidget {
  const AccountToIbanWidget({
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
    final accountController = controllers['bank_account'] ?? TextEditingController();
    final bankCodeController = controllers['bank_code'] ?? TextEditingController();

    return [
      Text(
        'شماره حساب و کد بانک را وارد کنید:',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: accountController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.bankAccount,
          hintText: ZohalFieldLabels.bankAccountHint,
          helperText: ZohalFieldLabels.bankAccountHelper,
          prefixIcon: const Icon(Icons.account_balance_wallet),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: ZohalInputFormatters.bankAccount(),
        validator: ZohalValidators.validateBankAccount,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: bankCodeController,
        decoration: InputDecoration(
          labelText: ZohalFieldLabels.bankCode,
          hintText: '062',
          helperText: ZohalFieldLabels.bankCodeHelper,
          prefixIcon: const Icon(Icons.business),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: ZohalInputFormatters.bankCode(),
        validator: ZohalValidators.validateBankCode,
      ),
    ];
  }

  @override
  Map<String, dynamic> collectFormData() {
    final accountController = controllers['bank_account'] ?? TextEditingController();
    final bankCodeController = controllers['bank_code'] ?? TextEditingController();
    
    final account = toEnglishDigits(accountController.text.trim());
    final bankCode = toEnglishDigits(bankCodeController.text.trim());
    
    return {
      'bank_account': account,
      'bank_code': bankCode,
    };
  }
}
