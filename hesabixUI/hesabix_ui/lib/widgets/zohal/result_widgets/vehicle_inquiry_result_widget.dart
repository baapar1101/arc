import 'package:flutter/material.dart';
import '../../zohal_result_widget.dart';
import '../../../utils/number_formatters.dart' show formatWithThousands;

/// ویجت نمایش نتیجه برای استعلام خلافی خودرو
class VehicleInquiryResultWidget extends ZohalResultWidget {
  final String serviceCode;

  const VehicleInquiryResultWidget({
    super.key,
    required super.result,
    required this.serviceCode,
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
          'هیچ داده‌ای یافت نشد.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ];
    }

    // برای استعلام مجموع تخلفات
    if (serviceCode.contains('total_violations')) {
      return _buildTotalViolationsContent(context, data);
    }

    // برای استعلام جزئیات تخلفات
    if (serviceCode.contains('violations_details')) {
      return _buildViolationsDetailsContent(context, data);
    }

    // پیش‌فرض: نمایش همه داده‌ها
    return _buildDefaultContent(context, data);
  }

  List<Widget> _buildTotalViolationsContent(BuildContext context, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final plate = data['plate']?.toString() ?? 'نامشخص';
    final inquirePrice = data['inquire_price']?.toString() ?? '0';
    final warningPrice = data['warning_price']?.toString() ?? '0';
    final pageCount = data['page_count'] as num? ?? 0;
    final paymentId = data['payment_id']?.toString();
    final priceStatus = data['price_status']?.toString();
    final ejrInquireNo = data['ejr_inquire_no']?.toString();

    return [
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
            Row(
              children: [
                Icon(Icons.directions_car, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'پلاک: $plate',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow(context, 'مبلغ قابل پرداخت', formatWithThousands(num.tryParse(inquirePrice) ?? 0), Icons.attach_money),
            _buildInfoRow(context, 'مبلغ هشدار', formatWithThousands(num.tryParse(warningPrice) ?? 0), Icons.warning),
            _buildInfoRow(context, 'تعداد صفحات', pageCount.toString(), Icons.description),
            if (paymentId != null && paymentId.isNotEmpty)
              _buildInfoRow(context, 'شناسه پرداخت', paymentId, Icons.payment),
            if (ejrInquireNo != null && ejrInquireNo.isNotEmpty)
              _buildInfoRow(context, 'شماره پیگیری اجرایی', ejrInquireNo, Icons.receipt),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildViolationsDetailsContent(BuildContext context, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final warnings = data['warnings'] as List? ?? [];

    if (warnings.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'هیچ تخلفی ثبت نشده است',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ];
    }

    return [
      Text(
        'تخلفات ثبت شده: ${warnings.length} مورد',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 16),
      ...warnings.asMap().entries.map((entry) {
        final index = entry.key;
        final warning = entry.value as Map<String, dynamic>;
        return _buildViolationCard(context, warning, index + 1);
      }),
    ];
  }

  Widget _buildViolationCard(BuildContext context, Map<String, dynamic> warning, int index) {
    final theme = Theme.of(context);
    final violationType = warning['violation_type'] as Map<String, dynamic>?;
    final violationTypeName = violationType?['violation_type']?.toString() ?? 'نامشخص';
    final finalPrice = warning['final_price']?.toString() ?? '0';
    final occurrenceDate = warning['violation_occure_date']?.toString() ?? 'نامشخص';
    final violationAddress = warning['violatoin_address']?.toString() ?? 'نامشخص';
    final paperId = warning['paper_id']?.toString();
    final serialNo = warning['serial_no']?.toString();
    final hasImage = warning['has_image'] as bool? ?? false;
    final investigationAbility = warning['investigation_ability'] as bool? ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$index',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    violationTypeName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow(context, 'مبلغ جریمه', formatWithThousands(num.tryParse(finalPrice) ?? 0), Icons.attach_money),
            _buildInfoRow(context, 'تاریخ و زمان', occurrenceDate, Icons.calendar_today),
            _buildInfoRow(context, 'مکان تخلف', violationAddress, Icons.location_on),
            if (paperId != null && paperId.isNotEmpty)
              _buildInfoRow(context, 'شناسه مدرک', paperId, Icons.description),
            if (serialNo != null && serialNo.isNotEmpty)
              _buildInfoRow(context, 'شماره سریال', serialNo, Icons.confirmation_number),
            const SizedBox(height: 8),
            Row(
              children: [
                if (hasImage)
                  Chip(
                    label: const Text('دارای تصویر'),
                    avatar: const Icon(Icons.image, size: 16),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  ),
                const SizedBox(width: 8),
                if (investigationAbility)
                  Chip(
                    label: const Text('قابل رسیدگی'),
                    avatar: const Icon(Icons.gavel, size: 16),
                    backgroundColor: theme.colorScheme.secondaryContainer,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDefaultContent(BuildContext context, Map<String, dynamic> data) {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.key.replaceAll('_', ' '),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      entry.value?.toString() ?? 'نامشخص',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    ];
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
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
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

