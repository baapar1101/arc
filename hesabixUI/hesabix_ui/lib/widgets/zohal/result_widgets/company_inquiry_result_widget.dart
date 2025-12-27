import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای استعلام اطلاعات شرکت
class CompanyInquiryResultWidget extends ZohalResultWidget {
  const CompanyInquiryResultWidget({
    super.key,
    required super.result,
    required super.amountCharged,
    required super.remainingBalance,
    required super.walletCurrency,
  });

  @override
  List<Widget> buildResultContent(BuildContext context) {
    final theme = Theme.of(context);
    final responseBody = result['result']?['response_body'] as Map<String, dynamic>?;
    final data = responseBody?['data'] as Map<String, dynamic>?;

    if (data == null) {
      return [
        Text(
          'اطلاعات شرکت یافت نشد.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ];
    }

    final name = data['name']?.toString() ?? 'نامشخص';
    final nationalId = data['national_id']?.toString() ?? 'نامشخص';
    final companyType = data['company_type']?.toString() ?? 'نامشخص';
    final registerNumber = data['register_number']?.toString() ?? 'نامشخص';
    final registerDate = data['register_date']?.toString() ?? 'نامشخص';
    final issuanceDate = data['issuance_date']?.toString() ?? 'نامشخص';
    final address = data['address']?.toString() ?? 'نامشخص';
    final postalCode = data['postal_code']?.toString() ?? 'نامشخص';
    final phoneNumber = data['phone_number']?.toString();
    final faxNumber = data['fax_number']?.toString();
    final emailAddress = data['email_address']?.toString();
    final activityEndDate = data['activity_end_date']?.toString();

    return [
      // هدر شرکت
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              Icons.business,
              size: 64,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              companyType,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      // اطلاعات شرکت
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات ثبت شده',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            _buildInfoRow(context, 'شناسه ملی', nationalId, Icons.badge),
            _buildInfoRow(context, 'شماره ثبت', registerNumber, Icons.confirmation_number),
            _buildInfoRow(context, 'تاریخ ثبت', registerDate, Icons.calendar_today),
            if (issuanceDate.isNotEmpty)
              _buildInfoRow(context, 'تاریخ صدور', issuanceDate, Icons.date_range),
            if (activityEndDate != null && activityEndDate.isNotEmpty)
              _buildInfoRow(context, 'تاریخ پایان فعالیت', activityEndDate, Icons.event_busy),
          ],
        ),
      ),
      const SizedBox(height: 16),
      // اطلاعات تماس
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات تماس',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            _buildInfoRow(context, 'آدرس', address, Icons.location_on, isMultiline: true),
            if (postalCode.isNotEmpty)
              _buildInfoRow(context, 'کد پستی', postalCode, Icons.markunread_mailbox),
            if (phoneNumber != null && phoneNumber.isNotEmpty)
              _buildInfoRow(context, 'تلفن', phoneNumber, Icons.phone),
            if (faxNumber != null && faxNumber.isNotEmpty)
              _buildInfoRow(context, 'فکس', faxNumber, Icons.print),
            if (emailAddress != null && emailAddress.isNotEmpty)
              _buildInfoRow(context, 'ایمیل', emailAddress, Icons.email),
          ],
        ),
      ),
    ];
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    bool isMultiline = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
              maxLines: isMultiline ? null : 1,
              overflow: isMultiline ? null : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

