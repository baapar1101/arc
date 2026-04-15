import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';

class ActivityLogsPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const ActivityLogsPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends State<ActivityLogsPage> {
  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedCategory;
  String? _selectedEntityType;

  // Categories and entity types
  static const List<String> _categories = [
    'accounting',
    'warehouse',
    'product',
    'person',
    'business',
    'user',
    'settings',
    'invoice',
    'document',
    'workflow',
    'marketplace',
    'storage',
    'payment',
    'wallet',
    'warranty',
    'ai',
    'support',
    'other',
  ];

  static const List<String> _entityTypes = [
    'invoice',
    'document',
    'warehouse_document',
    'product',
    'person',
    'account',
    'business',
    'user',
    'fiscal_year',
  ];

  @override
  void initState() {
    super.initState();
    // تنظیم تاریخ پیش‌فرض: 30 روز گذشته
    _endDate = DateTime.now();
    _startDate = DateTime.now().subtract(const Duration(days: 30));
  }

  void _refreshData() {
    // با تغییر key در DataTableWidget، خودکار rebuild می‌شود و config جدید با additionalParams جدید استفاده می‌شود
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_startDate != null) 'start_date': _startDate!.toIso8601String(),
      if (_endDate != null) 'end_date': _endDate!.toIso8601String(),
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) 'category': _selectedCategory,
      if (_selectedEntityType != null && _selectedEntityType!.isNotEmpty) 'entity_type': _selectedEntityType,
    };
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    
    // استفاده از helper موجود
    return HesabixDateUtils.formatForDisplay(
      value is DateTime ? value : (value is String ? DateTime.tryParse(value) : null),
      widget.calendarController.isJalali,
    );
  }

  String _getCategoryLabel(String? category) {
    if (category == null) return '';
    const labels = {
      'accounting': 'حسابداری',
      'warehouse': 'انبار',
      'product': 'کالا',
      'person': 'شخص',
      'business': 'کسب و کار',
      'user': 'کاربر',
      'settings': 'تنظیمات',
      'invoice': 'فاکتور',
      'document': 'سند',
      'workflow': 'گردش کار',
      'marketplace': 'مارکت‌پلیس',
      'storage': 'ذخیره‌سازی',
      'payment': 'پرداخت',
      'wallet': 'کیف پول',
      'warranty': 'گارانتی',
      'ai': 'هوش مصنوعی',
      'support': 'پشتیبانی',
      'other': 'سایر',
    };
    return labels[category] ?? category;
  }

  String _getActionLabel(String? action) {
    if (action == null) return '';
    const labels = {
      'create': 'ایجاد',
      'update': 'ویرایش',
      'delete': 'حذف',
      'post': 'ثبت',
      'cancel': 'لغو',
      'approve': 'تایید',
      'reject': 'رد',
      'export': 'خروجی',
      'import': 'ورودی',
      'login': 'ورود',
      'logout': 'خروج',
      'logout_all': 'خروج از همه',
      'login_failed': 'ورود ناموفق',
      'password_change': 'تغییر رمز',
      'execute': 'اجرا',
      'execute_failed': 'اجرا ناموفق',
      'restart_service': 'راه‌اندازی مجدد',
    };
    return labels[action] ?? action;
  }

  Color _getCategoryColor(String? category) {
    if (category == null) return Colors.grey;
    const colors = {
      'accounting': Colors.blue,
      'warehouse': Colors.orange,
      'product': Colors.green,
      'person': Colors.purple,
      'business': Colors.indigo,
      'user': Colors.red,
      'settings': Colors.teal,
      'invoice': Colors.amber,
      'document': Colors.cyan,
      'workflow': Colors.deepPurple,
      'marketplace': Colors.pink,
      'storage': Colors.brown,
      'payment': Colors.lightGreen,
      'wallet': Colors.lime,
      'warranty': Colors.deepOrange,
      'ai': Colors.blueGrey,
      'support': Colors.lightBlue,
      'other': Colors.grey,
    };
    return colors[category] ?? Colors.grey;
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/activity-logs/business/${widget.businessId}/table',
      businessId: widget.businessId,
      reportModuleKey: 'activity_logs',
      reportSubtype: 'list',
      title: 'گزارش فعالیت‌های کاربران',
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: false, // فعلاً export نداریم
      additionalParams: _additionalParams(),
      // استفاده از pagination با page و per_page
      defaultPageSize: 50,
      pageSizeOptions: const [25, 50, 100, 200],
      columns: [
        DateColumn(
          'created_at',
          'تاریخ و زمان',
          width: ColumnWidth.medium,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return _formatDate(m['created_at']);
          },
        ),
        TextColumn(
          'user_name',
          'کاربر',
          width: ColumnWidth.medium,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return m['user_name']?.toString() ?? 'نامشخص';
          },
        ),
        TextColumn(
          'category',
          'دسته فعالیت',
          width: ColumnWidth.medium,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return _getCategoryLabel(m['category']?.toString());
          },
        ),
        TextColumn(
          'action',
          'نوع عمل',
          width: ColumnWidth.small,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return _getActionLabel(m['action']?.toString());
          },
        ),
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return m['description']?.toString() ?? '';
          },
        ),
        TextColumn(
          'entity_info',
          'موجودیت مرتبط',
          width: ColumnWidth.medium,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final entityType = m['entity_type']?.toString();
            final entityId = m['entity_id'];
            if (entityType != null && entityId != null) {
              return '$entityType #$entityId';
            }
            return '-';
          },
        ),
      ],
      searchFields: const ['description', 'user_name'],
      dateRangeField: 'created_at',
      enableDateRangeFilter: true,
      expandBodyHeightToFitRows: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('گزارش فعالیت‌های کاربران'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _refreshData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.filter_list, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'فیلترها',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 160,
                        child: DateInputField(
                          labelText: 'از تاریخ',
                          value: _startDate,
                          calendarController: widget.calendarController,
                          onChanged: (date) {
                            setState(() {
                              _startDate = date;
                            });
                            _refreshData();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: DateInputField(
                          labelText: 'تا تاریخ',
                          value: _endDate,
                          calendarController: widget.calendarController,
                          onChanged: (date) {
                            setState(() {
                              _endDate = date;
                            });
                            _refreshData();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'دسته فعالیت',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('همه'),
                            ),
                            ..._categories.map((cat) => DropdownMenuItem<String>(
                              value: cat,
                              child: Text(_getCategoryLabel(cat)),
                            )),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedCategory = value;
                            });
                            _refreshData();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _selectedEntityType,
                          decoration: const InputDecoration(
                            labelText: 'نوع موجودیت',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('همه'),
                            ),
                            ..._entityTypes.map((type) => DropdownMenuItem<String>(
                              value: type,
                              child: Text(type),
                            )),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedEntityType = value;
                            });
                            _refreshData();
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _startDate = DateTime.now().subtract(const Duration(days: 30));
                            _endDate = DateTime.now();
                            _selectedCategory = null;
                            _selectedEntityType = null;
                          });
                          _refreshData();
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('پاک کردن فیلترها'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Data Table
          SingleChildScrollView(
            child: DataTableWidget<Map<String, dynamic>>(
              key: ValueKey(_additionalParams().toString()), // برای rebuild با تغییر فیلترها
              config: _buildTableConfig(t),
              fromJson: (json) => Map<String, dynamic>.from(json as Map),
            ),
          ),
        ],
      ),
    );
  }
}

