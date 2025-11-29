import 'package:flutter/material.dart';
import '../../zohal_result_widget.dart';
import '../../../utils/number_formatters.dart' show formatWithThousands;

/// ویجت پیش‌فرض برای نمایش نتایج سرویس‌های زحل
/// داده‌های نتیجه را به صورت ساختاریافته نمایش می‌دهد
class DefaultResultWidget extends ZohalResultWidget {
  const DefaultResultWidget({
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
    final data = responseBody?['data'] as dynamic;

    if (data == null) {
      return [
        Text(
          'هیچ داده‌ای دریافت نشد.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ];
    }

    // اگر data یک Map است، به صورت key-value نمایش می‌دهیم
    if (data is Map) {
      return _buildMapData(context, data as Map<String, dynamic>);
    }

    // اگر data یک List است، به صورت لیست نمایش می‌دهیم
    if (data is List) {
      return _buildListData(context, data);
    }

    // در غیر این صورت به صورت متن ساده
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          data.toString(),
          style: theme.textTheme.bodyMedium,
        ),
      ),
    ];
  }

  List<Widget> _buildMapData(BuildContext context, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    data.forEach((key, value) {
      if (value != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatKey(key),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _buildValueWidget(context, value),
                ),
              ],
            ),
          ),
        );
      }
    });

    if (widgets.isEmpty) {
      return [
        Text(
          'هیچ داده‌ای یافت نشد.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ];
    }

    return widgets;
  }

  List<Widget> _buildListData(BuildContext context, List data) {
    final theme = Theme.of(context);
    if (data.isEmpty) {
      return [
        Text(
          'لیست خالی است.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ];
    }

    return [
      ...data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'آیتم ${index + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (item is Map)
                  ..._buildMapData(context, item as Map<String, dynamic>)
                else
                  Text(
                    item.toString(),
                    style: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
        );
      }),
    ];
  }

  Widget _buildValueWidget(BuildContext context, dynamic value) {
    final theme = Theme.of(context);

    if (value is Map) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildMapData(context, value as Map<String, dynamic>),
        ),
      );
    }

    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${entry.key + 1}. ${entry.value.toString()}',
              style: theme.textTheme.bodyMedium,
            ),
          );
        }).toList(),
      );
    }

    if (value is bool) {
      return Chip(
        label: Text(value ? 'بله' : 'خیر'),
        backgroundColor: value
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer,
        labelStyle: TextStyle(
          color: value
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onErrorContainer,
        ),
      );
    }

    if (value is num) {
      return Text(
        formatWithThousands(value),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Text(
      value.toString(),
      style: theme.textTheme.bodyMedium,
    );
  }

  String _formatKey(String key) {
    // تبدیل snake_case به متن فارسی قابل خواندن
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

