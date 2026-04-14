import 'package:intl/intl.dart';
import '../core/date_utils.dart';

/// Utility class for formatting product attribute values based on their data type
class AttributeFormatter {
  /// Format attribute value based on data type
  static String formatAttributeValue(
    Map<String, dynamic> attribute,
    dynamic value,
    bool isJalali,
  ) {
    if (value == null) return '-';

    final dataType = attribute['data_type']?.toString() ?? 'text';

    switch (dataType) {
      case 'text':
        return value.toString();

      case 'number':
        final numValue = num.tryParse(value.toString());
        if (numValue == null) return value.toString();
        // Format with thousand separators
        return NumberFormat('#,###').format(numValue);

      case 'date':
        if (value is String) {
          final date = DateTime.tryParse(value);
          if (date != null) {
            // Format based on calendar type
            return HesabixDateUtils.formatForDisplay(date, isJalali);
          }
        } else if (value is DateTime) {
          return HesabixDateUtils.formatForDisplay(value, isJalali);
        }
        return value.toString();

      case 'boolean':
        final boolValue = value == true ||
            value.toString().toLowerCase() == 'true' ||
            value == 1 ||
            value.toString() == '1';
        return boolValue ? 'بله' : 'خیر';

      case 'select':
        // Find label from options
        final options = attribute['options'];
        if (options != null) {
          if (options is Map && options['items'] != null) {
            final items = options['items'] as List?;
            if (items != null) {
              try {
                final item = items.firstWhere(
                  (e) => e['value']?.toString() == value.toString(),
                  orElse: () => null,
                );
                if (item != null && item['label'] != null) {
                  return item['label'].toString();
                }
              } catch (e) {
                // If not found, continue to fallback
              }
            }
          } else if (options is List) {
            try {
              final item = options.firstWhere(
                (e) => e['value']?.toString() == value.toString(),
                orElse: () => null,
              );
              if (item != null && item['label'] != null) {
                return item['label'].toString();
              }
            } catch (e) {
              // If not found, continue to fallback
            }
          }
        }
        return value.toString(); // fallback

      default:
        return value.toString();
    }
  }

  /// Format multiple attributes for display
  static String formatAttributesForDisplay(
    Map<String, dynamic> customAttributes,
    Map<String, Map<String, dynamic>> attributesMap,
    bool isJalali,
  ) {
    if (customAttributes.isEmpty) return '';

    final formatted = <String>[];
    for (var entry in customAttributes.entries) {
      final attrTitle = entry.key;
      final attrValue = entry.value;
      final attribute = attributesMap[attrTitle];

      if (attribute != null) {
        final formattedValue = formatAttributeValue(attribute, attrValue, isJalali);
        formatted.add('$attrTitle: $formattedValue');
      } else {
        // If attribute not found, just show raw value
        formatted.add('$attrTitle: $attrValue');
      }
    }

    return formatted.join(', ');
  }
}

