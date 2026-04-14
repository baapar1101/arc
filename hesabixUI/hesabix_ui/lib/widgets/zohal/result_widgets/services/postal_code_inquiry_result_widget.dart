import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/zohal/zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای استعلام کد پستی
class PostalCodeInquiryResultWidget extends ZohalResultWidget {
  const PostalCodeInquiryResultWidget({
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
    final addressData = responseBody?['data']?['address'] as Map<String, dynamic>?;
    
    if (addressData == null || addressData.isEmpty) {
      return [
        Text(
          'آدرس یافت نشد.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ];
    }

    final province = addressData['province']?.toString() ?? '';
    final city = addressData['city']?.toString() ?? '';
    final mainStreet = addressData['main_street']?.toString() ?? '';
    final subStreet = addressData['sub_street']?.toString() ?? '';
    final buildingNumber = addressData['building_number']?.toString() ?? '';
    final floor = addressData['floor']?.toString() ?? '';
    final unit = addressData['unit']?.toString() ?? '';
    final district = addressData['district']?.toString() ?? '';
    final description = addressData['description']?.toString() ?? '';

    // ساخت آدرس کامل
    final fullAddress = [
      province,
      city,
      district,
      mainStreet,
      subStreet,
      buildingNumber.isNotEmpty ? 'پلاک $buildingNumber' : '',
      floor.isNotEmpty ? 'طبقه $floor' : '',
      unit.isNotEmpty ? 'واحد $unit' : '',
      description,
    ].where((s) => s.isNotEmpty).join('، ');

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'آدرس کامل',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.content_copy),
                  onPressed: () => _copyToClipboard(context, fullAddress),
                  tooltip: 'کپی آدرس',
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            SelectableText(
              fullAddress,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.8,
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    ];
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('آدرس کپی شد')),
    );
  }
}
