import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای استعلام چک صیادی
class CheckSayadInquiryResultWidget extends ZohalResultWidget {
  const CheckSayadInquiryResultWidget({
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
    final isJalali =
        ApiClient.getCalendarController()?.isJalali ?? Localizations.localeOf(context).languageCode.startsWith('fa');

    if (data == null || data.isEmpty) {
      return [
        Text(
          'اطلاعات چک یافت نشد.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
      ];
    }

    final name = data['name']?.toString() ?? '';
    final sayadId = data['sayad_id']?.toString() ?? '';
    final iban = data['iban']?.toString() ?? '';
    final checkType = data['check_type']?.toString() ?? '';
    final serialNo = data['serial_no']?.toString() ?? '';
    final seriesNo = data['series_no']?.toString() ?? '';
    final issueDate = HesabixDateUtils.formatApiDateForDisplay(
      data['issue_date'],
      isJalali,
      rawValue: data['issue_date_raw'],
      fallback: '',
    );
    final expirationDate = HesabixDateUtils.formatApiDateForDisplay(
      data['expiration_date'],
      isJalali,
      rawValue: data['expiration_date_raw'],
      fallback: '',
    );
    final branchCode = data['branch_code']?.toString() ?? '';
    final returnedCheques = data['returned_cheques']?.toString() ?? '';

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'اطلاعات چک صیادی',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),
            if (name.isNotEmpty) _buildInfoRow(context, theme, 'نام صادرکننده', name),
            if (sayadId.isNotEmpty) _buildInfoRow(context, theme, 'شناسه صیادی', sayadId, isCopyable: true),
            if (iban.isNotEmpty) _buildInfoRow(context, theme, 'شماره شبا', iban, isCopyable: true),
            if (checkType.isNotEmpty) _buildInfoRow(context, theme, 'نوع چک', checkType),
            if (serialNo.isNotEmpty) _buildInfoRow(context, theme, 'شماره سریال', serialNo),
            if (seriesNo.isNotEmpty) _buildInfoRow(context, theme, 'سری چک', seriesNo),
            if (issueDate.isNotEmpty) _buildInfoRow(context, theme, 'تاریخ صدور', issueDate),
            if (expirationDate.isNotEmpty) _buildInfoRow(context, theme, 'تاریخ سررسید', expirationDate),
            if (branchCode.isNotEmpty) _buildInfoRow(context, theme, 'کد شعبه', branchCode),
            if (returnedCheques.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: theme.colorScheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'وضعیت چک‌های برگشتی: $returnedCheques',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _buildInfoRow(BuildContext context, ThemeData theme, String label, String value, {bool isCopyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isCopyable ? () => _copyToClipboard(context, value) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isCopyable ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isCopyable) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.content_copy, size: 18, color: theme.colorScheme.primary),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کپی شد')));
  }
}
