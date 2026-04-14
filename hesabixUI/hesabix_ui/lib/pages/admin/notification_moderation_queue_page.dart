import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';

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
            _error = 'خطا در بارگذاری صف (${response.statusCode})';
            _cachedFilteredItems = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'خطا: $e';
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
      'pending' => 'در انتظار',
      'ai_reviewing' => 'در حال بررسی AI',
      'ai_reviewed' => 'بررسی شده AI',
      'admin_reviewing' => 'در بررسی مدیر',
      'completed' => 'بررسی شده',
      _ => status ?? 'نامعلوم',
    };
  }

  String _aiDecisionLabel(dynamic item) {
    final ai = item['ai_review'] as Map<String, dynamic>?;
    if (ai == null) return '-';
    final d = ai['decision'] as String?;
    final c = ai['confidence'] as num?;
    if (d == null) return '-';
    final label = d == 'approve' ? 'تایید' : (d == 'reject' ? 'رد' : 'نیاز به بررسی');
    if (c != null) return '$label (${c.toStringAsFixed(0)}٪)';
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
          const SnackBar(content: Text('✅ قالب تایید شد')),
        );
        await _loadQueue();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: کد ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e')),
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
          const SnackBar(content: Text('❌ قالب رد شد')),
        );
        await _loadQueue();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: کد ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e')),
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
          const SnackBar(content: Text('قالب به‌روزرسانی شد')),
        );
        await _loadQueue();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: کد ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e')),
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
        title: const Text('تایید قالب'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (aiReview != null) ...[
                const Text('نظر هوش مصنوعی:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                decoration: const InputDecoration(
                  labelText: 'یادداشت برای مالک کسب‌وکار (اختیاری)',
                  hintText: 'دلیل تایید یا توضیح برای مالک',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _approveWithNotes(queueId, {'_approve_notes': notesController.text});
            },
            child: const Text('تایید قالب'),
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
        title: const Text('رد قالب'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (aiReview != null) ...[
                const Text('نظر هوش مصنوعی:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                decoration: const InputDecoration(
                  labelText: 'دلیل رد (الزامی)',
                  hintText: 'مثلاً: محتوای تبلیغاتی',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'یادداشت برای مالک کسب‌وکار (اختیاری)',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('دلیل رد را وارد کنید')),
                );
                return;
              }
              Navigator.pop(ctx);
              _rejectWithReasonAndNotes(queueId, reason, notesController.text.trim().isEmpty ? null : notesController.text.trim());
            },
            child: const Text('رد قالب'),
          ),
        ],
      ),
    );
  }

  String _buildAiSummaryText(Map<String, dynamic> aiReview) {
    final parts = <String>[];
    final d = aiReview['decision'] as String?;
    if (d != null) {
      final label = d == 'approve' ? 'تایید' : (d == 'reject' ? 'رد' : 'نیاز به بررسی مدیر');
      parts.add('تصمیم: $label');
    }
    final c = aiReview['confidence'] as num?;
    if (c != null) parts.add('اطمینان: ${c.toStringAsFixed(0)}٪');
    final s = aiReview['suggestions'] as String?;
    if (s != null && s.trim().isNotEmpty) parts.add('پیشنهادات: $s');
    final f = aiReview['flags'];
    if (f is List && f.isNotEmpty) parts.add('موارد: ${f.join('؛ ')}');
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
        title: const Text('ویرایش قالب توسط مدیر'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(labelText: 'موضوع'),
                maxLines: 1,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                decoration: const InputDecoration(labelText: 'متن قالب'),
                maxLines: 8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
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
            child: const Text('ذخیره'),
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
        title: const Text('جزئیات قالب'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (template != null) ...[
                Text('نام: ${template['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('کد: ${template['code'] ?? '-'}'),
                Text('وضعیت: ${_statusLabel(status)}'),
                if (aiReview != null) ...[
                  const SizedBox(height: 8),
                  Text('نظر AI: ${_buildAiSummaryText(aiReview)}', style: Theme.of(ctx).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                const Text('محتوا:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(fullBody, style: Theme.of(ctx).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(ThemeData theme, ColorScheme cs) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/admin/notification-moderation/queue',
      title: 'صف بررسی قالب‌های نوتیفیکیشن',
      tableId: 'admin_notification_moderation_queue',
      showSearch: true,
      showPagination: true,
      showRefreshButton: true,
      enableSorting: true,
      defaultPageSize: 20,
      pageSizeOptions: const [10, 20, 50, 100],
      searchFields: const ['business.name', 'template.name', 'template.code', 'template.event_type'],
      emptyStateMessage: 'هیچ قالبی در صف نیست',
      enableColumnSettings: false,
      showTableIcon: false,
      columns: [
        TextColumn(
          'id',
          'شناسه',
          width: ColumnWidth.small,
          sortable: true,
          formatter: (item) => '${item['queue_id'] ?? item['id']}',
        ),
        TextColumn(
          'business_name',
          'کسب‌وکار',
          width: ColumnWidth.medium,
          formatter: (item) {
            final b = item['business'] as Map<String, dynamic>?;
            return b?['name'] as String? ?? '-';
          },
        ),
        TextColumn(
          'template_name',
          'قالب',
          width: ColumnWidth.medium,
          formatter: (item) {
            final t = item['template'] as Map<String, dynamic>?;
            return t?['name'] as String? ?? t?['code'] as String? ?? '-';
          },
        ),
        CustomColumn(
          'channel',
          'کانال',
          width: ColumnWidth.small,
          builder: (item, _) {
            final t = item['template'] as Map<String, dynamic>?;
            final ch = t?['channel'] as String?;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ch == 'sms' ? Icons.sms : Icons.email, size: 18, color: cs.primary),
                const SizedBox(width: 4),
                Text(ch == 'sms' ? 'پیامک' : 'ایمیل', style: theme.textTheme.bodySmall),
              ],
            );
          },
        ),
        TextColumn(
          'status',
          'وضعیت',
          width: ColumnWidth.medium,
          formatter: (item) => _statusLabel(item['status'] as String?),
        ),
        TextColumn(
          'created_at',
          'تاریخ',
          width: ColumnWidth.medium,
          formatter: _formatCreatedAt,
        ),
        TextColumn(
          'ai_decision',
          'نظر AI',
          width: ColumnWidth.medium,
          formatter: _aiDecisionLabel,
        ),
        CustomColumn(
          'actions',
          'عملیات',
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
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: () => _showDetailsDialog(item),
                  tooltip: 'جزئیات',
                  iconSize: 20,
                ),
                if (canAct) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _isProcessing ? null : () => _showEditDialog(item),
                    tooltip: 'ویرایش',
                    iconSize: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isProcessing ? null : () => _showRejectDialog(item),
                    tooltip: 'رد',
                    color: cs.error,
                    iconSize: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _isProcessing ? null : () => _showApproveDialog(item),
                    tooltip: 'تایید',
                    color: Colors.green,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('صف بررسی قالب‌های نوتیفیکیشن'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadQueue,
            tooltip: 'بروزرسانی',
          ),
        ],
      ),
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
                _buildFilterChip('همه', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('در انتظار', 'pending'),
                const SizedBox(width: 8),
                _buildFilterChip('بررسی شده AI', 'ai_reviewed'),
                const SizedBox(width: 8),
                _buildFilterChip('در بررسی مدیر', 'admin_reviewing'),
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
                              label: const Text('تلاش مجدد'),
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
                                  'هیچ قالبی در صف نیست',
                                  style: theme.textTheme.titleMedium?.copyWith(color: cs.outline),
                                ),
                              ],
                            ),
                          )
                        : DataTableWidget<Map<String, dynamic>>(
                            config: _buildTableConfig(theme, cs),
                            fromJson: (json) => Map<String, dynamic>.from(json),
                            calendarController: _calendarController,
                            localRawItems: _cachedFilteredItems,
                            // onRefresh نگذاریم تا DataTable بعد از _fetchData درخواست پیاپی نفرستد؛ بروزرسانی از دکمهٔ اپ‌بار
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _filter = value);
        _loadQueue();
      },
    );
  }
}
