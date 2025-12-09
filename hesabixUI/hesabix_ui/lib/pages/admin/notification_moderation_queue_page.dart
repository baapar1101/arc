import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';

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
  bool _isProcessing = false; // برای approve/reject
  List<Map<String, dynamic>> _queueItems = [];
  String? _error;
  String _filter = 'all'; // all, pending, ai_reviewed, admin_reviewing

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final queryParams = <String, dynamic>{};
      if (_filter != 'all') {
        // تبدیل فیلتر UI به status API
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
        query: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data!['data'] as Map<String, dynamic>?;
        final items = data?['items'] as List? ?? [];

        setState(() {
          _queueItems = items.map((e) => e as Map<String, dynamic>).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'خطا در بارگذاری صف (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'خطا: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _approveTemplate(int queueId) async {
    setState(() => _isProcessing = true);
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/admin/notification-moderation/queue/$queueId/approve',
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ قالب تایید شد')),
          );
        }
        await _loadQueue();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('خطا: کد ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _rejectTemplate(int queueId) async {
    final reason = await _showRejectDialog();
    if (reason == null || reason.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/admin/notification-moderation/queue/$queueId/reject',
        data: {'reason': reason},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ قالب رد شد')),
          );
        }
        await _loadQueue();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('خطا: کد ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<String?> _showRejectDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('دلیل رد'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'دلیل رد قالب',
            hintText: 'مثلاً: محتوای تبلیغاتی',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('رد قالب'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_filter == 'all') return _queueItems;

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
            onPressed: _loadQueue,
            tooltip: 'بروزرسانی',
          ),
        ],
      ),
      body: Column(
        children: [
          // فیلترها
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

          // محتوا
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 64, color: cs.error),
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
                    : _filteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 64, color: cs.outline),
                                const SizedBox(height: 16),
                                Text(
                                  'هیچ قالبی در صف نیست',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(color: cs.outline),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, index) =>
                                _buildQueueItem(_filteredItems[index]),
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
      onSelected: (selected) {
        setState(() => _filter = value);
      },
    );
  }

  Widget _buildQueueItem(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final template = item['template'] as Map<String, dynamic>?;
    final status = item['status'] as String?;
    final aiReview = item['ai_review'] as Map<String, dynamic>?;
    final aiDecision = aiReview?['decision'] as String?;
    final aiConfidence = aiReview?['confidence'] as num?;
    final createdAt = item['created_at'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                _buildStatusBadge(status),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    createdAt.substring(0, 19).replaceAll('T', ' '),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // قالب
            if (template != null) ...[
              Text(
                template['name'] as String? ?? 'بدون نام',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'کد: ${template['code']}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    template['channel'] == 'sms' ? Icons.sms : Icons.email,
                    size: 16,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    template['channel'] == 'sms' ? 'پیامک' : 'ایمیل',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'رویداد: ${template['event_type']}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // محتوا
              InkWell(
                onTap: () => _showFullBody(template['full_body'] as String? ?? template['body'] as String? ?? ''),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template['body'] as String? ?? '',
                        style: theme.textTheme.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((template['body'] as String? ?? '').length > 100)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'برای مشاهده کامل کلیک کنید',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            // نتیجه AI
            if (aiDecision != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: aiDecision == 'approve'
                      ? cs.primary.withValues(alpha: 0.1)
                      : cs.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.smart_toy,
                          size: 20,
                          color: aiDecision == 'approve' ? cs.primary : cs.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI: ${aiDecision == "approve" ? "تایید" : "رد"}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (aiConfidence != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(${aiConfidence.toStringAsFixed(0)}%)',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                    if (aiReview != null && aiReview['suggestions'] != null && (aiReview['suggestions'] as String).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'پیشنهادات AI:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        aiReview!['suggestions'] as String,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // دکمه‌ها
            if (status == 'admin_reviewing' || status == 'ai_reviewed') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : () {
                        final id = item['id'];
                        final queueId = id is int ? id : int.parse(id.toString());
                        _rejectTemplate(queueId);
                      },
                      icon: _isProcessing 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.close),
                      label: const Text('رد'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () {
                        final id = item['id'];
                        final queueId = id is int ? id : int.parse(id.toString());
                        _approveTemplate(queueId);
                      },
                      icon: _isProcessing 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('تایید'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (label, color) = switch (status) {
      'pending' => ('در انتظار', cs.secondary),
      'ai_reviewing' => ('در حال بررسی AI', cs.tertiary),
      'ai_reviewed' => ('بررسی شده AI', cs.primary),
      'admin_reviewing' => ('نیاز به بررسی مدیر', Colors.orange),
      'approved' => ('تایید شده', Colors.green),
      'rejected' => ('رد شده', cs.error),
      _ => ('نامعلوم', cs.outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showFullBody(String fullBody) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('محتوی کامل قالب'),
        content: SingleChildScrollView(
          child: SelectableText(
            fullBody,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }
}

