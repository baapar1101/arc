import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';

/// صفحه مدیریت قالب‌های نوتیفیکیشن کسب‌وکار
class NotificationTemplatesPage extends StatefulWidget {
  final int businessId;

  const NotificationTemplatesPage({
    super.key,
    required this.businessId,
  });

  @override
  State<NotificationTemplatesPage> createState() => _NotificationTemplatesPageState();
}

class _NotificationTemplatesPageState extends State<NotificationTemplatesPage> {
  final _apiClient = ApiClient();
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _templates = [];
  String? _errorMessage;
  
  // فیلترها
  String? _selectedChannel;
  String? _selectedStatus;
  int _currentPage = 0;
  int _totalItems = 0;
  static const int _itemsPerPage = 20;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final query = <String, dynamic>{
        'offset': _currentPage * _itemsPerPage,
        'limit': _itemsPerPage,
      };
      if (_selectedChannel != null) query['channel'] = _selectedChannel;
      if (_selectedStatus != null) query['status'] = _selectedStatus;

      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/business-notifications/businesses/${widget.businessId}/templates',
        query: query,
      );
      
      final data = response.data?['data'] as Map<String, dynamic>?;
      final items = data?['items'] as List? ?? [];
      final total = data?['total'] as int? ?? 0;
      
      setState(() {
        _templates = items.map((e) => e as Map<String, dynamic>).toList();
        _totalItems = total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطا در بارگذاری قالب‌ها: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('قالب‌های نوتیفیکیشن'),
        actions: [
          // فیلتر کانال
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'فیلتر کانال',
            onSelected: (value) {
              setState(() {
                _selectedChannel = value == 'all' ? null : value;
                _currentPage = 0; // بازگشت به صفحه اول
              });
              _loadTemplates();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('همه کانال‌ها')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'sms', child: Text('📱 پیامک')),
              const PopupMenuItem(value: 'email', child: Text('📧 ایمیل')),
            ],
          ),
          // فیلتر وضعیت
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            tooltip: 'فیلتر وضعیت',
            onSelected: (value) {
              setState(() {
                _selectedStatus = value == 'all' ? null : value;
                _currentPage = 0; // بازگشت به صفحه اول
              });
              _loadTemplates();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('همه وضعیت‌ها')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'draft', child: Text('📝 پیش‌نویس')),
              const PopupMenuItem(value: 'pending_approval', child: Text('⏳ در انتظار تایید')),
              const PopupMenuItem(value: 'approved', child: Text('✅ تایید شده')),
              const PopupMenuItem(value: 'rejected', child: Text('❌ رد شده')),
            ],
          ),
          // راهنما
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'راهنما',
            onPressed: () => _showHelp(),
          ),
        ],
      ),
      body: _buildBody(theme, colorScheme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createTemplate(),
        icon: const Icon(Icons.add),
        label: const Text('قالب جدید'),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTemplates,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off, size: 80, color: colorScheme.primary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('هنوز قالبی ایجاد نشده است', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'با ایجاد قالب‌های نوتیفیکیشن، به صورت خودکار برای مشتریان پیامک و ایمیل ارسال کنید',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createTemplate,
              icon: const Icon(Icons.add),
              label: const Text('ایجاد اولین قالب'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTemplates,
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                return _buildTemplateCard(_templates[index], theme, colorScheme);
              },
            ),
          ),
          // Pagination
          if (_totalItems > _itemsPerPage)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(top: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _currentPage > 0
                        ? () {
                            setState(() => _currentPage--);
                            _loadTemplates();
                          }
                        : null,
                    tooltip: 'صفحه قبل',
                  ),
                  Text(
                    '${_currentPage + 1} از ${(_totalItems / _itemsPerPage).ceil()}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: (_currentPage + 1) * _itemsPerPage < _totalItems
                        ? () {
                            setState(() => _currentPage++);
                            _loadTemplates();
                          }
                        : null,
                    tooltip: 'صفحه بعد',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(Map<String, dynamic> template, ThemeData theme, ColorScheme colorScheme) {
    final name = template['name'] as String? ?? '';
    final channel = template['channel'] as String? ?? '';
    final status = template['status'] as String? ?? '';
    final approvalStatus = template['approval_status'] as String? ?? '';
    final isActive = template['is_active'] as bool? ?? false;
    final eventType = template['event_type'] as String? ?? '';

    final channelIcon = channel == 'sms' ? Icons.sms : Icons.email;
    final statusColor = _getStatusColor(status, isActive);
    final statusLabel = _getStatusLabel(status, approvalStatus);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _viewTemplate(template),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(channelIcon, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.event, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'رویداد: $eventType',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
              if (template['description'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  template['description'] as String,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              // اطلاعات اضافی
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (template['daily_limit'] != null)
                    Chip(
                      label: Text('حد روزانه: ${template['daily_limit']}'),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.bodySmall,
                    ),
                  if (template['is_automated'] == true)
                    Chip(
                      label: const Text('خودکار'),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.bodySmall,
                      avatar: const Icon(Icons.autorenew, size: 16),
                    ),
                  if (template['ai_confidence_score'] != null)
                    Chip(
                      label: Text('AI: ${(template['ai_confidence_score'] as num).toStringAsFixed(0)}%'),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.bodySmall,
                      avatar: const Icon(Icons.smart_toy, size: 16),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // تاریخ
              if (template['created_at'] != null)
                Text(
                  'ایجاد شده: ${_formatDate(template['created_at'] as String)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[500], fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status, bool isActive) {
    if (!isActive) return Colors.grey;
    switch (status) {
      case 'approved': return Colors.green;
      case 'pending_approval': return Colors.orange;
      case 'rejected': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(String status, String approvalStatus) {
    if (status == 'approved') {
      if (approvalStatus == 'ai_approved') return '✅ تایید شده (AI)';
      if (approvalStatus == 'admin_approved') return '✅ تایید شده';
      return '✅ فعال';
    }
    if (status == 'pending_approval') return '⏳ در حال بررسی';
    if (status == 'rejected') return '❌ رد شده';
    if (status == 'draft') return '📝 پیش‌نویس';
    return status;
  }

  void _viewTemplate(Map<String, dynamic> template) async {
    final templateId = template['id'] as int;
    final status = template['status'] as String;
    
    // اگر approved باشد، فقط نمایش
    // اگر draft یا rejected باشد، امکان ویرایش
    final canEdit = status != 'approved' && status != 'pending_approval';
    
    if (canEdit) {
      // باز کردن صفحه ویرایش
      final result = await context.push(
        '/business/${widget.businessId}/notification-templates/$templateId/edit',
      );
      
      if (result == true) {
        _loadTemplates();
      }
    } else {
      // نمایش جزئیات با امکان submit for approval
      _showTemplateDetails(template);
    }
  }

  void _createTemplate() async {
    final result = await context.push(
      '/business/${widget.businessId}/notification-templates/new',
    );
    
    if (result == true) {
      _loadTemplates();
    }
  }
  
  void _showTemplateDetails(Map<String, dynamic> template) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(template['name'] as String),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('کد: ${template['code']}'),
              Text('رویداد: ${template['event_type']}'),
              Text('کانال: ${template['channel']}'),
              Text('وضعیت: ${template['status']}'),
              const Divider(),
              const Text('محتوا:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(template['body'] as String),
              if (template['status'] == 'draft' || template['status'] == 'rejected') ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _submitForApproval(template['id'] as int);
                  },
                  child: const Text('ارسال برای تایید'),
                ),
              ],
            ],
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
  
  Future<void> _submitForApproval(int templateId) async {
    try {
      await _apiClient.post(
        '/api/v1/business-notifications/businesses/${widget.businessId}/templates/$templateId/submit-for-approval',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ قالب برای تایید ارسال شد و به زودی بررسی خواهد شد'),
            backgroundColor: Colors.green,
          ),
        );
        _loadTemplates();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('راهنمای قالب‌های نوتیفیکیشن'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('قالب‌های نوتیفیکیشن به شما امکان می‌دهند برای رویدادهای مختلف (مانند ثبت فاکتور، تعمیر کالا، و...) به صورت خودکار به مشتریان پیام ارسال کنید.'),
              SizedBox(height: 16),
              Text('ویژگی‌ها:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('✅ استفاده از متغیرها مانند {{ customer_name }}'),
              Text('✅ تایید خودکار با هوش مصنوعی'),
              Text('✅ پیشگیری از ارسال spam'),
              Text('✅ محدودیت تعداد ارسال روزانه'),
              SizedBox(height: 16),
              Text('توجه:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('قالب‌ها قبل از فعال شدن توسط سیستم بررسی می‌شوند تا از ارسال محتوای تبلیغاتی جلوگیری شود.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('متوجه شدم'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final persianDate = '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      return persianDate;
    } catch (e) {
      return isoDate.substring(0, 10);
    }
  }
}

