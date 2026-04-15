import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/date_formatters.dart' as date_formatters;
import 'package:hesabix_ui/widgets/data_table/data_table.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  CalendarController? _calendarController;
  Set<int> _selectedRowIndexes = const {};

  int get _selectedCount => _selectedRowIndexes.length;

  @override
  void initState() {
    super.initState();
    _initCalendarController();
  }

  Future<void> _initCalendarController() async {
    try {
      final controller = await CalendarController.load();
      if (mounted) {
        setState(() => _calendarController = controller);
      }
    } catch (_) {
      // این صفحه بدون کنترلر تقویم هم کار می‌کند
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مدیریت کاربران سیستم',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
      ),
      body: SingleChildScrollView(
        child: DataTableWidget<Map<String, dynamic>>(
          config: _buildTableConfig(theme),
          fromJson: (json) => Map<String, dynamic>.from(json),
          calendarController: _calendarController,
        ),
      ),
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(ThemeData theme) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/users/search',
      title: 'مدیریت کاربران',
      subtitle: 'نمایش، فیلتر و کنترل کاربران سیستم حسابیکس',
      tableId: 'admin_users',
      showSearch: true,
      showFilters: true,
      showPagination: true,
      showClearFiltersButton: true,
      showRefreshButton: true,
      enableSorting: true,
      enableGlobalSearch: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      enableDateRangeFilter: true,
      dateRangeField: 'created_at',
      defaultSortBy: 'created_at',
      defaultSortDesc: true,
      defaultPageSize: 20,
      expandBodyHeightToFitRows: true,
      pageSizeOptions: const [10, 20, 50, 100],
      searchFields: const ['full_name', 'email', 'mobile'],
      filterFields: const ['status', 'role'],
      emptyStateMessage: 'کاربری یافت نشد',
      onRowTap: (item) => _openUserDetailsDialog(item as Map<String, dynamic>),
      onRowSelectionChanged: (indexes) {
        setState(() => _selectedRowIndexes = {...indexes});
      },
      customHeaderActions: [
        Tooltip(
          message: 'فعال‌سازی کاربران انتخاب‌شده',
          child: FilledButton.icon(
            onPressed: _selectedCount > 0
                ? () => _handleBulkAction(_BulkUserAction.activate)
                : null,
            icon: const Icon(Icons.verified_user_outlined),
            label: Text('فعال‌سازی ($_selectedCount)'),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'تعلیق یا غیرفعال‌سازی کاربران انتخاب‌شده',
          child: FilledButton.icon(
            onPressed: _selectedCount > 0
                ? () => _handleBulkAction(_BulkUserAction.deactivate)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.pause_circle_outline),
            label: Text('تعلیق ($_selectedCount)'),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'بازنشانی رمز عبور کاربران انتخاب‌شده',
          child: OutlinedButton.icon(
            onPressed: _selectedCount > 0
                ? () => _handleBulkAction(_BulkUserAction.resetPassword)
                : null,
            icon: const Icon(Icons.key_outlined),
            label: const Text('بازنشانی رمز'),
          ),
        ),
      ],
      columns: [
        TextColumn(
          'id',
          'ID',
          width: ColumnWidth.small,
          sortable: true,
          searchable: true,
          textAlign: TextAlign.center,
        ),
        TextColumn(
          'full_name',
          'نام کاربر',
          width: ColumnWidth.medium,
          sortable: true,
          searchable: true,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            final fullName = (map['full_name'] as String?) ??
                '${map['first_name'] ?? ''} ${map['last_name'] ?? ''}'.trim();
            return fullName.isNotEmpty ? fullName : 'نام ثبت نشده';
          },
        ),
        TextColumn(
          'email',
          'ایمیل',
          width: ColumnWidth.medium,
          sortable: true,
          searchable: true,
          formatter: (item) {
            final email = (item as Map<String, dynamic>)['email'] as String?;
            return email ?? '-';
          },
        ),
        TextColumn(
          'mobile',
          'موبایل',
          width: ColumnWidth.medium,
          sortable: true,
          searchable: true,
          formatter: (item) {
            final mobile = _cleanMobileNumber((item as Map<String, dynamic>)['mobile'] as String?);
            return mobile ?? '-';
          },
        ),
        CustomColumn(
          'status',
          'وضعیت',
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: const [
            FilterOption(value: 'active', label: 'فعال'),
            FilterOption(value: 'inactive', label: 'غیرفعال'),
            FilterOption(value: 'pending', label: 'در انتظار'),
            FilterOption(value: 'suspended', label: 'معلق'),
          ],
          builder: (item, index) {
            final map = item as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: _StatusChip(value: map['status']?.toString() ?? 'unknown'),
            );
          },
          formatter: (item) =>
              _statusLabel((item as Map<String, dynamic>)['status']),
        ),
        CustomColumn(
          'role',
          'نقش',
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: const [
            FilterOption(value: 'admin', label: 'مدیر سیستم'),
            FilterOption(value: 'operator', label: 'اپراتور'),
            FilterOption(value: 'supervisor', label: 'ناظر'),
            FilterOption(value: 'user', label: 'کاربر'),
          ],
          builder: (item, index) {
            final map = item as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: _RoleChip(value: map['role']?.toString() ?? 'user'),
            );
          },
          formatter: (item) =>
              _roleLabel((item as Map<String, dynamic>)['role']),
        ),
        CustomColumn(
          'businesses_count',
          'کسب‌وکارها',
          width: ColumnWidth.small,
          builder: (item, index) {
            final count = (item as Map<String, dynamic>)['businesses_count'] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.business_outlined, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    count.toString(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          },
          formatter: (item) =>
              ((item as Map<String, dynamic>)['businesses_count'] ?? 0)
                  .toString(),
        ),
        DateColumn(
          'last_login_at',
          'آخرین ورود',
          width: ColumnWidth.medium,
          showTime: false,
          formatter: (item) =>
              _formatDate((item as Map<String, dynamic>)['last_login_at'],
                  showTime: false),
        ),
        DateColumn(
          'created_at',
          'تاریخ ثبت‌نام',
          width: ColumnWidth.medium,
          showTime: false,
          formatter: (item) =>
              _formatDate((item as Map<String, dynamic>)['created_at']),
        ),
        ActionColumn(
          'actions',
          'عملیات',
          actions: [
            DataTableAction(
              icon: Icons.info_outline,
              label: 'جزئیات',
              onTap: (item) =>
                  _openUserDetailsDialog(item as Map<String, dynamic>),
            ),
            DataTableAction(
              icon: Icons.key,
              label: 'بازنشانی رمز',
              onTap: (item) => _resetUserPassword(item as Map<String, dynamic>),
            ),
            DataTableAction(
              icon: Icons.pause_circle_outline,
              label: 'تعلیق',
              isDestructive: true,
              onTap: (item) => _suspendUser(item as Map<String, dynamic>),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleBulkAction(_BulkUserAction action) async {
    if (_selectedRowIndexes.isEmpty) return;
    
    final messenger = ScaffoldMessenger.of(context);
    
    // TODO: دریافت شناسه‌های واقعی کاربران از DataTableWidget
    // برای حالا، یک پیام نمایش می‌دهیم
    String message;
    switch (action) {
      case _BulkUserAction.activate:
        message = 'این عملیات نیاز به دریافت شناسه‌های کاربران دارد.';
        break;
      case _BulkUserAction.deactivate:
        message = 'این عملیات نیاز به دریافت شناسه‌های کاربران دارد.';
        break;
      case _BulkUserAction.resetPassword:
        message = 'این عملیات نیاز به دریافت شناسه‌های کاربران دارد.';
        break;
    }
    
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _openUserDetailsDialog(Map<String, dynamic> user) async {
    final userId = user['id'] as int?;
    if (userId == null) return;
    
    // دریافت اطلاعات کامل کاربر از API
    try {
      final api = ApiClient();
      final response = await api.get('/api/v1/users/$userId');
      if (response.statusCode == 200 && mounted) {
        final userData = response.data?['data'] as Map<String, dynamic>?;
        if (userData != null) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => _UserDetailsDialog(user: userData),
            );
          }
        }
      }
    } catch (e) {
      // در صورت خطا، از داده‌های موجود استفاده می‌کنیم
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => _UserDetailsDialog(user: user),
        );
      }
    }
  }

  Future<void> _suspendUser(Map<String, dynamic> user) async {
    final userId = user['id'] as int?;
    if (userId == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعلیق کاربر'),
        content: Text('آیا مطمئن هستید که می‌خواهید ${user['full_name'] ?? 'کاربر'} را تعلیق کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('تعلیق'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final api = ApiClient();
      final response = await api.post('/api/v1/users/$userId/suspend');
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('کاربر با موفقیت تعلیق شد')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در تعلیق کاربر: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _resetUserPassword(Map<String, dynamic> user) async {
    final userId = user['id'] as int?;
    if (userId == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بازنشانی رمز عبور'),
        content: Text('آیا مطمئن هستید که می‌خواهید رمز عبور ${user['full_name'] ?? 'کاربر'} را بازنشانی کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('بازنشانی'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final api = ApiClient();
      final response = await api.post('/api/v1/users/$userId/reset-password');
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('توکن بازنشانی رمز عبور ایجاد شد')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در بازنشانی رمز عبور: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  static String? _cleanMobileNumber(String? mobile) {
    if (mobile == null || mobile.isEmpty) return null;
    var cleaned = mobile.replaceAll('+', '').replaceAll(' ', '');
    if (cleaned.startsWith('98') && cleaned.length >= 12) {
      cleaned = '0${cleaned.substring(2)}';
    } else if (!cleaned.startsWith('0') && cleaned.length == 10) {
      cleaned = '0$cleaned';
    }
    return cleaned;
  }

  static String _formatDate(dynamic value, {bool showTime = false}) {
    if (value == null) return '-';
    return showTime
        ? date_formatters.DateFormatters.formatServerDateTime(value)
        : date_formatters.DateFormatters.formatServerDate(value);
  }

  static String _statusLabel(dynamic status) {
    switch (status) {
      case 'active':
        return 'فعال';
      case 'inactive':
        return 'غیرفعال';
      case 'pending':
        return 'در انتظار';
      case 'suspended':
        return 'معلق';
      default:
        return 'نامشخص';
    }
  }

  static String _roleLabel(dynamic role) {
    switch (role) {
      case 'admin':
        return 'مدیر سیستم';
      case 'operator':
        return 'اپراتور';
      case 'supervisor':
        return 'ناظر';
      case 'user':
        return 'کاربر';
      default:
        return 'نامشخص';
    }
  }
}

enum _BulkUserAction { activate, deactivate, resetPassword }

class _StatusChip extends StatelessWidget {
  final String value;

  const _StatusChip({required this.value});

  @override
  Widget build(BuildContext context) {
    final label = _UserManagementPageState._statusLabel(value);
    final Color background;
    final Color foreground;
    switch (value) {
      case 'active':
        background = Colors.green.shade100;
        foreground = Colors.green.shade800;
        break;
      case 'inactive':
        background = Colors.grey.shade200;
        foreground = Colors.grey.shade800;
        break;
      case 'pending':
        background = Colors.amber.shade100;
        foreground = Colors.amber.shade800;
        break;
      case 'suspended':
        background = Colors.red.shade100;
        foreground = Colors.red.shade800;
        break;
      default:
        background = Colors.blueGrey.shade100;
        foreground = Colors.blueGrey.shade800;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String value;

  const _RoleChip({required this.value});

  @override
  Widget build(BuildContext context) {
    final label = _UserManagementPageState._roleLabel(value);
    final Color background;
    final Color foreground;
    switch (value) {
      case 'admin':
        background = Colors.deepPurple.shade100;
        foreground = Colors.deepPurple.shade800;
        break;
      case 'operator':
        background = Colors.blue.shade100;
        foreground = Colors.blue.shade800;
        break;
      case 'supervisor':
        background = Colors.teal.shade100;
        foreground = Colors.teal.shade800;
        break;
      case 'user':
        background = Colors.grey.shade200;
        foreground = Colors.grey.shade800;
        break;
      default:
        background = Colors.blueGrey.shade100;
        foreground = Colors.blueGrey.shade800;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _UserDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> user;

  const _UserDetailsDialog({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final displayName = (user['full_name'] as String?) ??
        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: size.width > 920 ? 900 : size.width - 64,
        height: size.height > 720 ? 660 : size.height - 120,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_outline, color: theme.colorScheme.onPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isNotEmpty ? displayName : 'کاربر بدون نام',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user['email']?.toString() ?? '-',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'اطلاعات کاربر'),
                        Tab(text: 'کسب‌وکارها'),
                        Tab(text: 'نشست‌ها و فعالیت'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _OverviewTab(user: user),
                          _BusinessesTab(user: user),
                          _ActivityTab(user: user),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> user;

  const _OverviewTab({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: 'اطلاعات هویتی', theme: theme),
          _InfoCard(
            children: [
              _InfoRow(label: 'نام کامل', value: user['full_name'] ?? '-'),
              _InfoRow(label: 'ایمیل', value: user['email'] ?? '-'),
              _InfoRow(label: 'موبایل', value: user['mobile'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          _SectionTitle(title: 'اطلاعات دسترسی', theme: theme),
          _InfoCard(
            children: [
              _InfoRow(
                label: 'نقش جاری',
                value: _UserManagementPageState._roleLabel(user['role']),
              ),
              _InfoRow(
                label: 'وضعیت',
                value: _UserManagementPageState._statusLabel(user['status']),
              ),
              _InfoRow(
                label: 'تاریخ ایجاد',
                value: _UserManagementPageState._formatDate(user['created_at']),
              ),
              _InfoRow(
                label: 'آخرین ورود',
                value: _UserManagementPageState._formatDate(
                  user['last_login_at'],
                  showTime: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusinessesTab extends StatelessWidget {
  final Map<String, dynamic> user;

  const _BusinessesTab({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final businesses = (user['businesses'] as List<dynamic>?) ?? const [];

    if (businesses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_mall_directory_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'کسب‌وکاری برای این کاربر ثبت نشده است.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: businesses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final business = businesses[index] as Map<String, dynamic>? ?? {};
        return Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        business['name']?.toString() ?? 'بدون نام',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _RoleChip(
                      value: business['role']?.toString() ?? 'user',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _BusinessMetaChip(
                      icon: Icons.numbers,
                      label: 'شناسه: ${business['id'] ?? '-'}',
                    ),
                    if (business['status'] != null)
                      _BusinessMetaChip(
                        icon: Icons.verified_user_outlined,
                        label:
                            'وضعیت: ${_UserManagementPageState._statusLabel(business['status'])}',
                      ),
                    if (business['field'] != null)
                      _BusinessMetaChip(
                        icon: Icons.work_outline,
                        label: 'حوزه: ${business['field']}',
                      ),
                  ],
                ),
                if (business['created_at'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'تاریخ عضویت: ${_UserManagementPageState._formatDate(business['created_at'])}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActivityTab extends StatelessWidget {
  final Map<String, dynamic> user;

  const _ActivityTab({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = (user['sessions'] as List<dynamic>?) ?? const [];
    final audits = (user['audit_logs'] as List<dynamic>?) ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: 'نشست‌های فعال', theme: theme),
          if (sessions.isEmpty)
            _EmptyInlineState(
              icon: Icons.laptop_chromebook_outlined,
              message: 'نشستی ثبت نشده است.',
            )
          else
            ...sessions.map((session) => _SessionTile(session: session)),
          const SizedBox(height: 24),
          _SectionTitle(title: 'آخرین فعالیت‌ها', theme: theme),
          if (audits.isEmpty)
            _EmptyInlineState(
              icon: Icons.timeline_outlined,
              message: 'رخدادی برای نمایش وجود ندارد.',
            )
          else
            ...audits.map((log) => _AuditTile(log: log)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionTitle({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: children),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BusinessMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyInlineState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final dynamic session;

  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final map = session as Map<String, dynamic>? ?? const {};
    return ListTile(
      leading: const Icon(Icons.devices_other),
      title: Text(map['device']?.toString() ?? 'دستگاه نامشخص'),
      subtitle: Text(
        'IP: ${map['ip'] ?? '-'} • آخرین فعالیت: ${_UserManagementPageState._formatDate(map['last_active_at'], showTime: true)}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'خروج از نشست',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('درخواست خروج از نشست ثبت شد')),
          );
        },
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  final dynamic log;

  const _AuditTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final map = log as Map<String, dynamic>? ?? const {};
    return ListTile(
      leading: const Icon(Icons.timeline),
      title: Text(map['action']?.toString() ?? 'اقدام نامشخص'),
      subtitle: Text(map['description']?.toString() ?? '-'),
      trailing: Text(
        _UserManagementPageState._formatDate(map['created_at'], showTime: true),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
