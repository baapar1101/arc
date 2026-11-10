import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';

/// صفحه مدیریت صف بررسی قالب‌های نوتیفیکیشن
class NotificationModerationQueuePage extends StatefulWidget {
  const NotificationModerationQueuePage({super.key});

  @override
  State<NotificationModerationQueuePage> createState() =>
      _NotificationModerationQueuePageState();
}

class _NotificationModerationQueuePageState
    extends State<NotificationModerationQueuePage> {
  final ApiClient _apiClient = ApiClient();
  bool _isLoading = true;
  bool _isProcessing = false;
  List<Map<String, dynamic>> _queueItems = [];
  /// لیست ثابت برای DataTable تا با هر build رفرنس عوض نشود و درخواست پیاپی نشود
  List<Map<String, dynamic>> _cachedFilteredItems = [];
  String? _error;
  String _filter = 'all';
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _initCalendar();
  }

  Future<void> _initCalendar() async {
    try {
      final c = await CalendarController.load();
      if (mounted) setState(() => _calendarController = c);
    } catch (_) {}
  }

  Future<void> _loadQueue() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final queryParams = <String, dynamic>{
        'offset': 0,
        'limit': 200,
      };
      if (_filter != 'all') {
        switch (_filter) {
          case 'pending':
            queryParams['status'] = 'pending';
            break;
          case 'ai_reviewed':
            queryParams['status'] = 'ai_reviewed';
            break;
          case 'admin_reviewing':
            queryParams['status'] = 'admin_reviewing';
            break;
        }
      }
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/admin/notification-moderation/queue',
        query: queryParams,
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data!['data'] as Map<String, dynamic>?;
        final items = data?['items'] as List? ?? [];
        if (mounted) {
          setState(() {
            _queueItems = items.map((e) => e as Map<String, dynamic>).toList();
            _cachedFilteredItems = _computeFilteredItems();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = adminTx(context, 'خطا در بارگذاری صف (${response.statusCode})', 'Could not load the queue (${response.statusCode})');
            _cachedFilteredItems = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = adminTx(context, 'خطا: ${ErrorExtractor.userMessage(e)}', '${ErrorExtractor.userMessage(e)}');
          _cachedFilteredItems = [];
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _computeFilteredItems() {
    if (_filter == 'all') return List.from(_queueItems);
    return _queueItems.where((item) {
      final status = item['status'] as String?;
      return switch (_filter) {
        'pending' => status == 'pending',
        'ai_reviewed' => status == 'ai_reviewed',
        'admin_reviewing' => status == 'admin_reviewing',
        _ => true,
      };
    }).toList();
  }

  int _getQueueId(dynamic item) {
    final id = item['id'];
    if (id is int) return id;
    return int.parse(id.toString());
  }

  String _formatCreatedAt(dynamic item) {
    final raw = item['created_at'] as String?;
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length >= 19 ? raw.substring(0, 19).replaceAll('T', ' ') : raw;
    final isJalali = _calendarController?.isJalali ?? true;
    return HesabixDateUtils.formatDateTime(dt, isJalali);
  }

  String _statusLabel(String? status) {
    return switch (status) {
      'pending' => adminTx(context, 'در انتظار', 'Pending'),
      'ai_reviewing' => adminTx(context, 'در حال بررسی AI', 'AI reviewing'),
      'ai_reviewed' => adminTx(context, 'بررسی شده AI', 'AI reviewed'),
      'admin_reviewing' => adminTx(context, 'در بررسی مدیر', 'In admin review'),
      'completed' => adminTx(context, 'بررسی شده', 'Reviewed'),
      _ => status ?? adminTx(context, 'نامعلوم', 'Unknown'),
    };
  }

  String _aiDecisionLabel(dynamic item) {
    final ai = item['ai_review'] as Map<String, dynamic>?;
    if (ai == null) return '-';
    final d = ai['decision'] as String?;
    final c = ai['confidence'] as num?;
    if (d == null) return '-';
    final label = d == 'approve' ? adminTx(context, 'تایید', 'Approve') : (d == 'reject' ? adminTx(context, 'رد', 'Reject') : adminTx(context, 'نیاز به بررسی', 'Needs review'));
    if (c != null) return adminTx(context, '$label (${c.toStringAsFixed(0)}٪)', '$label (${c.toStringAsFixed(0)}%)');
    return label;
  }

  bool _canApproveReject(dynamic item) {
    final status = item['status'] as String?;
    return status == 'admin_reviewing' || status == 'ai_reviewed';
  }

  Future<void> _approveWithNotes(int queueId, Map<String, dynamic> item) async {
    setState(() => _isProcessing = true);
    try {
      final notes = item['_approve_notes'] as String? ?? '';
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/admin/notification-moderation/queue/$queueId/approve',
        data: {'notes': notes},
      );
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, '✅ قالب تایید شد', 'Template approved'))),
        );
        await _loadQueue();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'خطا: کد ${response.statusCode}', 'Error ${response.statusCode}'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'خطا: ${ErrorExtractor.forContext(e, context)}', '${ErrorExtractor.forContext(e, context)}'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectWithReasonAndNotes(
    int queueId,
    String reason,
    String? notes,
  ) async {
    setState(() => _isProcessing = true);
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/admin/notification-moderation/queue/$queueId/reject',
        data: {'reason': reason, 'notes': notes ?? ''},
      );
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, '❌ قالب رد شد', 'Template rejected'))),
        );
        await _loadQueue();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'خطا: کد ${response.statusCode}', 'Error ${response.statusCode}'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'خطا: ${ErrorExtractor.forContext(e, context)}', '${ErrorExtractor.forContext(e, context)}'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _updateTemplateByAdmin(int queueId, {String? subject, String? body}) async {
    setState(() => _isProcessing = true);
    try {
      final payload = <String, dynamic>{};
      if (subject != null) payload['subject'] = subject;
      if (body != null) payload['body'] = body;
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '/api/v1/admin/notification-moderation/queue/$queueId/template',
        data: payload,
      );
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'قالب به‌روزرسانی شد', 'Template updated'))),
        );
        await _loadQueue();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'خطا: کد ${response.statusCode}', 'Error ${response.statusCode}'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'خطا: ${ErrorExtractor.forContext(e, context)}', '${ErrorExtractor.forContext(e, context)}'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showApproveDialog(Map<String, dynamic> item) {
    final queueId = _getQueueId(item);
    final aiReview = item['ai_review'] as Map<String, dynamic>?;
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(adminTx(context, 'تایید قالب', 'Approve template')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (aiReview != null) ...[
                Text(adminTx(context, 'نظر هوش مصنوعی:', 'AI note:'), style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _buildAiSummaryText(aiReview),
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'یادداشت برای مالک کسب‌وکار (اختیاری)', 'Note for the business owner (optional)'),
                  hintText: adminTx(context, 'دلیل تایید یا توضیح برای مالک', 'Approval note for the owner'),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(adminTx(context, 'انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _approveWithNotes(queueId, {'_approve_notes': notesController.text});
            },
            child: Text(adminTx(context, 'تایید قالب', 'Approve template')),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(Map<String, dynamic> item) {
    final queueId = _getQueueId(item);
    final aiReview = item['ai_review'] as Map<String, dynamic>?;
    final reasonController = TextEditingController();
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(adminTx(context, 'رد قالب', 'Reject template')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (aiReview != null) ...[
                Text(adminTx(context, 'نظر هوش مصنوعی:', 'AI note:'), style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _buildAiSummaryText(aiReview),
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'دلیل رد (الزامی)', 'Rejection reason (required)'),
                  hintText: adminTx(context, 'مثلاً: محتوای تبلیغاتی', 'Example: promotional content'),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'یادداشت برای مالک کسب‌وکار (اختیاری)', 'Note for the business owner (optional)'),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(adminTx(context, 'انصراف', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(adminTx(context, 'دلیل رد را وارد کنید', 'Enter a rejection reason'))),
                );
                return;
              }
              Navigator.pop(ctx);
              _rejectWithReasonAndNotes(queueId, reason, notesController.text.trim().isEmpty ? null : notesController.text.trim());
            },
            child: Text(adminTx(context, 'رد قالب', 'Reject template')),
          ),
        ],
      ),
    );
  }

  String _buildAiSummaryText(Map<String, dynamic> aiReview) {
    final parts = <String>[];
    final d = aiReview['decision'] as String?;
    if (d != null) {
      final label = d == 'approve' ? adminTx(context, 'تایید', 'Approve') : (d == 'reject' ? adminTx(context, 'رد', 'Reject') : adminTx(context, 'نیاز به بررسی مدیر', 'Needs an admin review'));
      parts.add(adminTx(context, 'تصمیم: $label', 'Decision: $label'));
    }
    final c = aiReview['confidence'] as num?;
    if (c != null) parts.add(adminTx(context, 'اطمینان: ${c.toStringAsFixed(0)}٪', 'Confidence: ${c.toStringAsFixed(0)}%'));
    final s = aiReview['suggestions'] as String?;
    if (s != null && s.trim().isNotEmpty) parts.add(adminTx(context, 'پیشنهادات: $s', 'Suggestions: $s'));
    final f = aiReview['flags'];
    if (f is List && f.isNotEmpty) parts.add(adminTx(context, 'موارد: ${f.join('؛ ')}', 'Flags: ${f.join('; ')}'));
    return parts.isEmpty ? '-' : parts.join('\n');
  }

  void _showEditDialog(Map<String, dynamic> item) {
    final queueId = _getQueueId(item);
    final template = item['template'] as Map<String, dynamic>? ?? {};
    final subjectController = TextEditingController(text: template['subject'] as String? ?? '');
    final bodyController = TextEditingController(text: template['full_body'] as String? ?? template['body'] as String? ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(adminTx(context, 'ویرایش قالب توسط مدیر', 'Edit template')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: InputDecoration(labelText: adminTx(context, 'موضوع', 'Subject')),
                maxLines: 1,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                decoration: InputDecoration(labelText: adminTx(context, 'متن قالب', 'Template body')),
                maxLines: 8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(adminTx(context, 'انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateTemplateByAdmin(
                queueId,
                subject: subjectController.text,
                body: bodyController.text,
              );
            },
            child: Text(adminTx(context, 'ذخیره', 'Save')),
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog(Map<String, dynamic> item) {
    final template = item['template'] as Map<String, dynamic>?;
    final fullBody = template != null
        ? (template['full_body'] as String? ?? template['body'] as String? ?? '')
        : '';
    final status = item['status'] as String?;
    final aiReview = item['ai_review'] as Map<String, dynamic>?;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(adminTx(context, 'جزئیات قالب', 'Template details')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (template != null) ...[
                Text(adminTx(context, 'نام: ${template['name'] ?? '-'}', 'Name: ${template['name'] ?? '-'}'), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(adminTx(context, 'کد: ${template['code'] ?? '-'}', 'Code: ${template['code'] ?? '-'}')),
                Text(adminTx(context, 'وضعیت: ${_statusLabel(status)}', 'Status: ${_statusLabel(status)}')),
                if (aiReview != null) ...[
                  const SizedBox(height: 8),
                  Text(adminTx(context, 'نظر AI: ${_buildAiSummaryText(aiReview)}', 'AI note: ${_buildAiSummaryText(aiReview)}'), style: Theme.of(ctx).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Text(adminTx(context, 'محتوا:', 'Content:'), style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(fullBody, style: Theme.of(ctx).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(adminTx(context, 'بستن', 'Close')),
          ),
        ],
      ),
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(ThemeData theme, ColorScheme cs) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/admin/notification-moderation/queue',
      title: adminTx(context, 'صف بررسی قالب‌های نوتیفیکیشن', 'Notification template review'),
      tableId: 'admin_notification_moderation_queue',
      showSearch: true,
      showPagination: true,
      showRefreshButton: true,
      enableSorting: true,
      defaultPageSize: 20,
      expandBodyHeightToFitRows: true,
      pageSizeOptions: const [10, 20, 50, 100],
      searchFields: const ['business.name', 'template.name', 'template.code', 'template.event_type'],
      emptyStateMessage: adminTx(context, 'هیچ قالبی در صف نیست', 'The queue is empty'),
      enableColumnSettings: false,
      showTableIcon: false,
      columns: [
        TextColumn(
          'id',
          adminTx(context, 'شناسه', 'Id'),
          width: ColumnWidth.small,
          sortable: true,
          formatter: (item) => '${item['queue_id'] ?? item['id']}',
        ),
        TextColumn(
          'business_name',
          adminTx(context, 'کسب‌وکار', 'Business'),
          width: ColumnWidth.medium,
          formatter: (item) {
            final b = item['business'] as Map<String, dynamic>?;
            return b?['name'] as String? ?? '-';
          },
        ),
        TextColumn(
          'template_name',
          adminTx(context, 'قالب', 'Template'),
          width: ColumnWidth.medium,
          formatter: (item) {
            final t = item['template'] as Map<String, dynamic>?;
            return t?['name'] as String? ?? t?['code'] as String? ?? '-';
          },
        ),
        CustomColumn(
          'channel',
          adminTx(context, 'کانال', 'Channel'),
          width: ColumnWidth.small,
          builder: (item, _) {
            final t = item['template'] as Map<String, dynamic>?;
            final ch = t?['channel'] as String?;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ch == 'sms' ? Icons.sms : Icons.email, size: 18, color: cs.primary),
                const SizedBox(width: 4),
                Text(ch == 'sms' ? adminTx(context, 'پیامک', 'SMS') : adminTx(context, 'ایمیل', 'Email'), style: theme.textTheme.bodySmall),
              ],
            );
          },
        ),
        TextColumn(
          'status',
          adminTx(context, 'وضعیت', 'Status'),
          width: ColumnWidth.medium,
          formatter: (item) => _statusLabel(item['status'] as String?),
        ),
        TextColumn(
          'created_at',
          adminTx(context, 'تاریخ', 'Date'),
          width: ColumnWidth.medium,
          formatter: _formatCreatedAt,
        ),
        TextColumn(
          'ai_decision',
          adminTx(context, 'نظر AI', 'AI note'),
          width: ColumnWidth.medium,
          formatter: _aiDecisionLabel,
        ),
        CustomColumn(
          'actions',
          adminTx(context, 'عملیات', 'Actions'),
          width: ColumnWidth.large,
          sortable: false,
          searchable: false,
          builder: (item, _) {
            final canAct = _canApproveReject(item);
            return Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                IconButton(
                  icon: Icon(Icons.visibility_outlined),
                  onPressed: () => _showDetailsDialog(item),
                  tooltip: adminTx(context, 'جزئیات', 'Details'),
                  iconSize: 20,
                ),
                if (canAct) ...[
                  IconButton(
                    icon: Icon(Icons.edit_outlined),
                    onPressed: _isProcessing ? null : () => _showEditDialog(item),
                    tooltip: adminTx(context, 'ویرایش', 'Edit'),
                    iconSize: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isProcessing ? null : () => _showRejectDialog(item),
                    tooltip: adminTx(context, 'رد', 'Reject'),
                    color: cs.error,
                    iconSize: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _isProcessing ? null : () => _showApproveDialog(item),
                    tooltip: adminTx(context, 'تایید', 'Approve'),
                    color: SemanticColorResolver.positive(context),
                    iconSize: 20,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AdminCompactScaffold(
      title: adminTx(context, 'صف بررسی قالب‌ها', 'Template review queue'),
      subtitle: adminTx(context, 'قالب‌های اعلان در انتظار بررسی', 'Notification templates waiting for review'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _isLoading ? null : _loadQueue,
          tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
        ),
      ],
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                _buildFilterChip(adminTx(context, 'همه', 'All'), 'all'),
                const SizedBox(width: 8),
                _buildFilterChip(adminTx(context, 'در انتظار', 'Pending'), 'pending'),
                const SizedBox(width: 8),
                _buildFilterChip(adminTx(context, 'بررسی‌شده توسط AI', 'Reviewed by AI'), 'ai_reviewed'),
                const SizedBox(width: 8),
                _buildFilterChip(adminTx(context, 'در بررسی مدیر', 'Admin review'), 'admin_reviewing'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: cs.error),
                            const SizedBox(height: 16),
                            Text(_error!, style: TextStyle(color: cs.error)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadQueue,
                              icon: const Icon(Icons.refresh),
                              label: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
                            ),
                          ],
                        ),
                      )
                    : _cachedFilteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined, size: 64, color: cs.outline),
                                const SizedBox(height: 16),
                                Text(
                                  adminTx(context, 'هیچ قالبی در صف نیست', 'The queue is empty'),
                                  style: theme.textTheme.titleMedium?.copyWith(color: cs.outline),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: DataTableWidget<Map<String, dynamic>>(
                              config: _buildTableConfig(theme, cs),
                              fromJson: (json) => Map<String, dynamic>.from(json),
                              calendarController: _calendarController,
                              localRawItems: _cachedFilteredItems,
                              // onRefresh نگذاریم تا DataTable بعد از _fetchData درخواست پیاپی نفرستد؛ بروزرسانی از دکمهٔ اپ‌بار
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return FilterChip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _filter = value);
        _loadQueue();
      },
    );
  }
}
