import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/core/date_utils.dart';

class NotificationHistoryPage extends StatefulWidget {
  final CalendarController calendarController;

  const NotificationHistoryPage({
    super.key,
    required this.calendarController,
  });

  @override
  State<NotificationHistoryPage> createState() => _NotificationHistoryPageState();
}

class _NotificationHistoryPageState extends State<NotificationHistoryPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تاریخچه ناتیفیکیشن‌ها',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/account-settings'),
        ),
      ),
      body: DataTableWidget<Map<String, dynamic>>(
        config: DataTableConfig<Map<String, dynamic>>(
          endpoint: '/api/v1/notifications/history',
          title: 'تاریخچه ناتیفیکیشن‌ها',
          subtitle: 'مشاهده تمام ناتیفیکیشن‌های ارسال شده به شما',
          columns: [
            TextColumn(
              'id',
              'شناسه',
              width: ColumnWidth.small,
              sortable: true,
            ),
            CustomColumn(
              'channel',
              'کانال',
              width: ColumnWidth.medium,
              builder: (item, index) {
                final channel = item['channel'] as String? ?? '';
                IconData icon;
                Color color;
                String label;

                switch (channel) {
                  case 'email':
                    icon = Icons.email_outlined;
                    color = Colors.blue;
                    label = 'ایمیل';
                    break;
                  case 'sms':
                    icon = Icons.sms_outlined;
                    color = Colors.green;
                    label = 'پیامک';
                    break;
                  case 'telegram':
                    icon = Icons.telegram;
                    color = Colors.lightBlue;
                    label = 'تلگرام';
                    break;
                  case 'bale':
                    icon = Icons.chat_bubble_outline;
                    color = Colors.indigo;
                    label = 'بله';
                    break;
                  case 'inapp':
                    icon = Icons.notifications_active_outlined;
                    color = Colors.orange;
                    label = 'درون برنامه';
                    break;
                  default:
                    icon = Icons.notifications_outlined;
                    color = Colors.grey;
                    label = channel;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            TextColumn(
              'event_title',
              'نوع رویداد',
              width: ColumnWidth.large,
              sortable: true,
              searchable: true,
            ),
            CustomColumn(
              'status',
              'وضعیت',
              width: ColumnWidth.medium,
              builder: (item, index) {
                final status = item['status'] as String? ?? 'pending';
                Color bgColor;
                Color textColor;
                String label;

                switch (status) {
                  case 'sent':
                    bgColor = Colors.green.shade100;
                    textColor = Colors.green.shade900;
                    label = 'ارسال شده';
                    break;
                  case 'failed':
                    bgColor = Colors.red.shade100;
                    textColor = Colors.red.shade900;
                    label = 'ناموفق';
                    break;
                  case 'pending':
                    bgColor = Colors.orange.shade100;
                    textColor = Colors.orange.shade900;
                    label = 'در انتظار';
                    break;
                  default:
                    bgColor = Colors.grey.shade100;
                    textColor = Colors.grey.shade900;
                    label = status;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
            CustomColumn(
              'payload',
              'محتوا',
              width: ColumnWidth.large,
              builder: (item, index) {
                final payload = item['payload'] as Map<String, dynamic>? ?? {};
                final eventKey = item['event_key'] as String? ?? '';
                
                // نمایش محتوای مناسب بر اساس event_key
                String content = '';
                
                if (eventKey == 'auth.otp_login' || eventKey == 'auth.password_reset') {
                  // نمایش کد OTP کامل
                  final code = payload['code'] as String?;
                  if (code != null) {
                    content = 'کد: $code';
                  }
                } else if (payload.containsKey('subject')) {
                  content = payload['subject'] as String? ?? '';
                } else if (payload.containsKey('message')) {
                  content = payload['message'] as String? ?? '';
                } else {
                  // نمایش خلاصه payload
                  content = payload.toString();
                  if (content.length > 50) {
                    content = '${content.substring(0, 50)}...';
                  }
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    content.isEmpty ? '-' : content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              },
            ),
            DateColumn(
              'created_at',
              'تاریخ و زمان',
              width: ColumnWidth.medium,
              sortable: true,
              showTime: true,
              formatter: (item) {
                final createdAt = item['created_at'] as String?;
                if (createdAt == null) return '-';
                final date = DateTime.tryParse(createdAt);
                if (date == null) return createdAt;
                // استفاده از formatDateTime برای نمایش تاریخ و زمان
                return HesabixDateUtils.formatDateTime(date, widget.calendarController.isJalali);
              },
            ),
            CustomColumn(
              'error_message',
              'خطا',
              width: ColumnWidth.medium,
              builder: (item, index) {
                final errorMessage = item['error_message'] as String?;
                if (errorMessage == null || errorMessage.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('-', style: TextStyle(color: Colors.grey)),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Tooltip(
                    message: errorMessage,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 16, color: Colors.red),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            errorMessage.length > 30
                                ? '${errorMessage.substring(0, 30)}...'
                                : errorMessage,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          searchFields: ['event_title', 'event_key', 'channel'],
          defaultSortBy: 'created_at',
          defaultSortDesc: true,
          defaultPageSize: 20,
          pageSizeOptions: const [10, 20, 50, 100],
          showSearch: true,
          showFilters: true,
          showPagination: true,
          enableSorting: true,
          enableGlobalSearch: true,
          showRefreshButton: true,
          showBackButton: false,
          emptyStateMessage: 'ناتیفیکیشنی یافت نشد',
          tableId: 'notification_history',
          onRowTap: (item) {
            _showNotificationDetails(context, item);
          },
        ),
        fromJson: (json) => Map<String, dynamic>.from(json),
        calendarController: widget.calendarController,
      ),
    );
  }

  void _showNotificationDetails(BuildContext context, Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (context) => _NotificationDetailsDialog(
        notification: notification,
        calendarController: widget.calendarController,
      ),
    );
  }
}

class _NotificationDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> notification;
  final CalendarController calendarController;

  const _NotificationDetailsDialog({
    required this.notification,
    required this.calendarController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final payload = notification['payload'] as Map<String, dynamic>? ?? {};
    final eventKey = notification['event_key'] as String? ?? '';
    final channel = notification['channel'] as String? ?? '';
    final status = notification['status'] as String? ?? '';
    final errorMessage = notification['error_message'] as String?;
    final createdAt = notification['created_at'] as String?;
    final retryCount = notification['retry_count'] as int? ?? 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'جزئیات ناتیفیکیشن',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('شناسه', notification['id'].toString()),
                    _buildDetailRow('کانال', _getChannelLabel(channel)),
                    _buildDetailRow('نوع رویداد', notification['event_title'] as String? ?? '-'),
                    _buildDetailRow('وضعیت', _getStatusLabel(status)),
                    if (createdAt != null)
                      _buildDetailRow(
                        'تاریخ و زمان',
                        HesabixDateUtils.formatDateTime(
                          DateTime.tryParse(createdAt),
                          calendarController.isJalali,
                        ),
                      ),
                    if (retryCount > 0)
                      _buildDetailRow('تعداد تلاش مجدد', retryCount.toString()),
                    if (errorMessage != null && errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'پیام خطا:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          errorMessage,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'محتوا:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _buildPayloadContent(payload, eventKey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('بستن'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadContent(Map<String, dynamic> payload, String eventKey) {
    if (eventKey == 'auth.otp_login' || eventKey == 'auth.password_reset') {
      final code = payload['code'] as String?;
      final expiryMinutes = payload['expiry_minutes'] as int?;
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (code != null) ...[
            Text(
              'کد OTP:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: SelectableText(
                code,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.blue.shade900,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          if (expiryMinutes != null) ...[
            const SizedBox(height: 12),
            Text('اعتبار: $expiryMinutes دقیقه'),
          ],
        ],
      );
    } else {
      // نمایش سایر محتواها
      final subject = payload['subject'] as String?;
      final message = payload['message'] as String?;
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subject != null) ...[
            Text(
              subject,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (message != null)
            Text(
              message,
              style: const TextStyle(fontSize: 14),
            ),
          if (subject == null && message == null)
            Text(
              payload.toString(),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
        ],
      );
    }
  }

  String _getChannelLabel(String channel) {
    switch (channel) {
      case 'email':
        return 'ایمیل';
      case 'sms':
        return 'پیامک';
      case 'telegram':
        return 'تلگرام';
      case 'bale':
        return 'بله';
      case 'inapp':
        return 'درون برنامه';
      default:
        return channel;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'sent':
        return 'ارسال شده';
      case 'failed':
        return 'ناموفق';
      case 'pending':
        return 'در انتظار';
      default:
        return status;
    }
  }
}

