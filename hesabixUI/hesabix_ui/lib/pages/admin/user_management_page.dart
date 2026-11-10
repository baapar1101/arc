import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/date_formatters.dart' as date_formatters;
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

import 'admin_compact_scaffold.dart';
import 'admin_user_password_dialog.dart';
import '../../theme/tokens/extensions.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final GlobalKey _usersTableKey = GlobalKey();
  CalendarController? _calendarController;
  Set<int> _selectedRowIndexes = const {};
  List<Map<String, dynamic>> _tableRawItems = [];
  Timer? _onlinePolling;

  /// تعداد کاربران فعال با ضربان اخیر (همان بازهٔ `window_minutes` API)
  int? _recentApproxCount;

  int get _selectedCount => _selectedRowIndexes.length;

  @override
  void initState() {
    super.initState();
    _initCalendarController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchRecentApproxCount();
      _onlinePolling?.cancel();
      _onlinePolling =
          Timer.periodic(const Duration(seconds: 55), (_) => _fetchRecentApproxCount());
    });
  }

  @override
  void dispose() {
    _onlinePolling?.cancel();
    super.dispose();
  }

  Future<void> _fetchRecentApproxCount() async {
    try {
      final res = await ApiClient().get<Map<String, dynamic>>(
        '/api/v1/users/stats/online',
        query: {'window_minutes': 5},
      );
      final body = res.data;
      if (!mounted || body == null) return;
      final data = body['data'];
      if (data is Map<String, dynamic>) {
        final n = data['recently_active_count'];
        final parsed = (n is int) ? n : int.tryParse('$n');
        if (!mounted || parsed == null) return;
        setState(() => _recentApproxCount = parsed);
      }
    } catch (_) {
      /* نادیده — شمارنده اختیاری است */
    }
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

    return AdminCompactScaffold(
      title: adminTx(context, 'کاربران', 'Users'),
      subtitle: adminTx(context, 'نمایش، فیلتر و کنترل کاربران سیستم', 'View, filter, and manage system users'),
      actions: [
        Tooltip(
          message: adminTx(
            context,
            'کاربرانی که در ۵ دقیقهٔ اخیر در اپ فعال بوده‌اند. این عدد برآورد است.',
            'Users active in the app during the last 5 minutes. This is an estimate.',
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(Icons.sensors_rounded, size: 16, color: theme.colorScheme.primary),
              label: Text(
                _recentApproxCount == null
                    ? adminTx(context, 'فعالیت اخیر: …', 'Recent activity: …')
                    : adminTx(context, '۵ دقیقه: ${_recentApproxCount!}', '5 min: ${_recentApproxCount!}'),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: adminTx(context, 'بازخوانی فعالیت اخیر', 'Refresh recent activity'),
          icon: const Icon(Icons.sync, size: 20),
          onPressed: _fetchRecentApproxCount,
        ),
      ],
      body: DataTableWidget<Map<String, dynamic>>(
          key: _usersTableKey,
          config: _buildTableConfig(theme),
          fromJson: (json) => Map<String, dynamic>.from(json),
          calendarController: _calendarController,
        ),
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(ThemeData theme) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/users/search',
      showTableIcon: false,
      emptyStateMessage: adminTx(context, 'کاربری یافت نشد', 'No users found'),
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
      searchFields: const ['first_name', 'last_name', 'email', 'mobile'],
      filterFields: const ['status', 'role'],
      onRowTap: (item) => _openUserDetailsDialog(item as Map<String, dynamic>),
      onRowSelectionChanged: (indexes) {
        setState(() => _selectedRowIndexes = {...indexes});
      },
      onTableDataChanged: (raw) {
        setState(() => _tableRawItems = raw);
      },
      customHeaderActions: [
        Tooltip(
          message: adminTx(context, 'فعال‌سازی کاربران انتخاب‌شده', 'Activate selected users'),
          child: FilledButton.icon(
            onPressed: _selectedCount > 0
                ? () => _handleBulkAction(_BulkUserAction.activate)
                : null,
            icon: const Icon(Icons.verified_user_outlined, size: 18),
            label: Text('${adminTx(context, 'فعال‌سازی', 'Activate')} ($_selectedCount)'),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: adminTx(context, 'تعلیق کاربران انتخاب‌شده', 'Suspend selected users'),
          child: FilledButton.icon(
            onPressed: _selectedCount > 0
                ? () => _handleBulkAction(_BulkUserAction.deactivate)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.pause_circle_outline, size: 18),
            label: Text('${adminTx(context, 'تعلیق', 'Suspend')} ($_selectedCount)'),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: adminTx(context, 'بازنشانی رمز کاربران انتخاب‌شده', 'Reset passwords for selected users'),
          child: OutlinedButton.icon(
            onPressed: _selectedCount > 0
                ? () => _handleBulkAction(_BulkUserAction.resetPassword)
                : null,
            icon: const Icon(Icons.key_outlined, size: 18),
            label: Text(adminTx(context, 'بازنشانی رمز', 'Reset password')),
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
          adminTx(context, 'نام کاربر', 'Name'),
          width: ColumnWidth.medium,
          sortable: true,
          searchable: true,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            final fullName = (map['full_name'] as String?) ??
                '${map['first_name'] ?? ''} ${map['last_name'] ?? ''}'.trim();
            return fullName.isNotEmpty ? fullName : adminTx(context, 'نام ثبت نشده', 'No name');
          },
        ),
        TextColumn(
          'email',
          adminTx(context, 'ایمیل', 'Email'),
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
          adminTx(context, 'موبایل', 'Mobile'),
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
          adminTx(context, 'وضعیت', 'Status'),
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: [
            FilterOption(value: 'active', label: adminTx(context, 'فعال', 'Active')),
            FilterOption(value: 'inactive', label: adminTx(context, 'غیرفعال', 'Inactive')),
            FilterOption(value: 'pending', label: adminTx(context, 'در انتظار', 'Pending')),
            FilterOption(value: 'suspended', label: adminTx(context, 'معلق', 'Suspended')),
          ],
          builder: (item, index) {
            final map = item as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: _StatusChip(value: map['status']?.toString() ?? 'unknown'),
            );
          },
          formatter: (item) =>
              _userStatusLabel(context, (item as Map<String, dynamic>)['status']),
        ),
        CustomColumn(
          'role',
          adminTx(context, 'نقش', 'Role'),
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: [
            FilterOption(value: 'admin', label: adminTx(context, 'مدیر سیستم', 'System admin')),
            FilterOption(value: 'operator', label: adminTx(context, 'اپراتور', 'Operator')),
            FilterOption(value: 'supervisor', label: adminTx(context, 'ناظر', 'Supervisor')),
            FilterOption(value: 'user', label: adminTx(context, 'کاربر', 'User')),
          ],
          builder: (item, index) {
            final map = item as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: _RoleChip(value: map['role']?.toString() ?? 'user'),
            );
          },
          formatter: (item) =>
              _userRoleLabel(context, (item as Map<String, dynamic>)['role']),
        ),
        CustomColumn(
          'businesses_count',
          adminTx(context, 'کسب‌وکارها', 'Businesses'),
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
          adminTx(context, 'آخرین ورود', 'Last login'),
          width: ColumnWidth.medium,
          sortable: true,
          showTime: false,
          filterType: ColumnFilterType.dateRange,
          formatter: (item) =>
              _formatDate((item as Map<String, dynamic>)['last_login_at'],
                  showTime: false),
        ),
        DateColumn(
          'created_at',
          adminTx(context, 'تاریخ ثبت‌نام', 'Signed up'),
          width: ColumnWidth.medium,
          sortable: true,
          showTime: false,
          filterType: ColumnFilterType.dateRange,
          formatter: (item) =>
              _formatDate((item as Map<String, dynamic>)['created_at']),
        ),
        ActionColumn(
          'actions',
          adminTx(context, 'عملیات', 'Actions'),
          actions: [
            DataTableAction(
              icon: Icons.info_outline,
              label: adminTx(context, 'جزئیات', 'Details'),
              onTap: (item) =>
                  _openUserDetailsDialog(item as Map<String, dynamic>),
            ),
            DataTableAction(
              icon: Icons.key,
              label: adminTx(context, 'مدیریت رمز', 'Password'),
              onTap: (item) => _openUserPasswordManager(item as Map<String, dynamic>),
            ),
            DataTableAction(
              icon: Icons.pause_circle_outline,
              label: adminTx(context, 'تعلیق', 'Suspend'),
              isDestructive: true,
              onTap: (item) => _suspendUser(item as Map<String, dynamic>),
            ),
          ],
        ),
      ],
    );
  }

  List<int> _selectedUserIds() {
    final out = <int>[];
    for (final i in _selectedRowIndexes) {
      if (i < 0 || i >= _tableRawItems.length) continue;
      final id = _tableRawItems[i]['id'];
      if (id is int) {
        out.add(id);
      } else if (id is num) {
        out.add(id.toInt());
      }
    }
    return out;
  }

  void _refreshTable() {
    try {
      (_usersTableKey.currentState as dynamic)?.refresh();
    } catch (_) {}
  }

  Future<void> _handleBulkAction(_BulkUserAction action) async {
    if (_selectedRowIndexes.isEmpty) return;

    final ids = _selectedUserIds();
    if (ids.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(adminTx(context, 'شناسهٔ معتبری در انتخاب نیست. صفحه را تازه کنید.', 'The selection has no valid id. Refresh the page.')),
            backgroundColor: SemanticColorResolver.warning(context),
          ),
        );
      }
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final api = ApiClient();

    if (action == _BulkUserAction.resetPassword) {
      var sendNotif = true;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (ctx, setSt) {
            return AlertDialog(
              title: Text(adminTx(context, 'بازنشانی رمز برای ${ids.length} کاربر', 'Reset password for ${ids.length} users')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(adminTx(
                    context,
                    'برای هر کاربر که ایمیل یا موبایل داشته باشد، توکن بازنشانی ساخته می‌شود.',
                    'A reset token is created for each user who has an email or mobile number.',
                  )),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: sendNotif,
                    onChanged: (v) => setSt(() => sendNotif = v),
                    title: Text(adminTx(context, 'ارسال اعلان بازنشانی', 'Send the reset notification')),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(adminTx(context, 'انصراف', 'Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(adminTx(context, 'ادامه', 'Continue'))),
              ],
            );
          },
        ),
      );
      if (go != true || !mounted) return;
      try {
        final res = await api.post<Map<String, dynamic>>(
          '/api/v1/users/bulk-reset-password',
          data: {
            'user_ids': ids,
            'send_notification': sendNotif,
          },
        );
        if (res.statusCode == 200) {
          final data = res.data?['data'] as Map<String, dynamic>?;
          final created = data?['tokens_created'] ?? 0;
          messenger.showSnackBar(
            SnackBar(content: Text('${adminTx(context, 'توکن ساخته‌شده', 'Tokens created')}: $created / ${ids.length}')),
          );
          setState(() => _selectedRowIndexes = const {});
          _refreshTable();
        }
      } catch (e) {
        if (!mounted) return;
        final err = Theme.of(context).colorScheme.error;
        messenger.showSnackBar(
          SnackBar(
            content: Text('${adminTx(context, 'خطا', 'Error')}: ${ErrorExtractor.forContext(e, context)}'),
            backgroundColor: err,
          ),
        );
      }
      return;
    }

    final title = action == _BulkUserAction.activate
        ? adminTx(context, 'فعال‌سازی ${ids.length} کاربر؟', 'Activate ${ids.length} users?')
        : adminTx(context, 'تعلیق ${ids.length} کاربر؟', 'Suspend ${ids.length} users?');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(adminTx(context, 'این کار روی همهٔ کاربران انتخاب‌شده در همین صفحه اعمال می‌شود.', 'This applies to every user selected on this page.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(adminTx(context, 'انصراف', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(adminTx(context, 'تأیید', 'Confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final path = action == _BulkUserAction.activate
        ? '/api/v1/users/bulk-activate'
        : '/api/v1/users/bulk-suspend';
    try {
      final res = await api.post<Map<String, dynamic>>(
        path,
        data: {'user_ids': ids},
      );
      if (res.statusCode == 200) {
        final data = res.data?['data'] as Map<String, dynamic>?;
        final updated = data?['updated_count'] ?? 0;
        messenger.showSnackBar(
          SnackBar(content: Text('${adminTx(context, 'به‌روزشده', 'Updated')}: $updated')),
        );
        setState(() => _selectedRowIndexes = const {});
        _refreshTable();
      }
    } catch (e) {
      if (!mounted) return;
      final err = Theme.of(context).colorScheme.error;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${adminTx(context, 'خطا', 'Error')}: ${ErrorExtractor.forContext(e, context)}'),
          backgroundColor: err,
        ),
      );
    }
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
      builder: (dialogContext) => AlertDialog(
        title: Text(adminTx(context, 'تعلیق کاربر', 'Suspend user')),
        content: Text(adminTx(
          context,
          '${user['full_name'] ?? adminTx(context, 'این کاربر', 'This user')} تعلیق شود؟',
          'Suspend ${user['full_name'] ?? 'this user'}?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(adminTx(context, 'انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: SemanticColorResolver.negative(dialogContext),
            ),
            child: Text(adminTx(context, 'تعلیق', 'Suspend')),
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
            SnackBar(content: Text(adminTx(context, 'کاربر تعلیق شد', 'User suspended'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${adminTx(context, 'خطا در تعلیق کاربر', 'Could not suspend the user')}: ${ErrorExtractor.forContext(e, context)}',
            ),
            backgroundColor: SemanticColorResolver.negative(context),
          ),
        );
      }
    }
  }
  
  Future<void> _openUserPasswordManager(Map<String, dynamic> user) async {
    await showAdminUserPasswordDialog(
      context,
      user: user,
      onSuccess: _refreshTable,
    );
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
}

String _userStatusLabel(BuildContext context, dynamic status) {
  switch (status) {
    case 'active':
      return adminTx(context, 'فعال', 'Active');
    case 'inactive':
      return adminTx(context, 'غیرفعال', 'Inactive');
    case 'pending':
      return adminTx(context, 'در انتظار', 'Pending');
    case 'suspended':
      return adminTx(context, 'معلق', 'Suspended');
    default:
      return adminTx(context, 'نامشخص', 'Unknown');
  }
}

String _userRoleLabel(BuildContext context, dynamic role) {
  switch (role) {
    case 'admin':
      return adminTx(context, 'مدیر سیستم', 'System admin');
    case 'operator':
      return adminTx(context, 'اپراتور', 'Operator');
    case 'supervisor':
      return adminTx(context, 'ناظر', 'Supervisor');
    case 'user':
      return adminTx(context, 'کاربر', 'User');
    default:
      return adminTx(context, 'نامشخص', 'Unknown');
  }
}

enum _BulkUserAction { activate, deactivate, resetPassword }

class _StatusChip extends StatelessWidget {
  final String value;

  const _StatusChip({required this.value});

  @override
  Widget build(BuildContext context) {
    final label = _userStatusLabel(context, value);
    final Color background;
    final Color foreground;
    switch (value) {
      case 'active':
        background = SemanticColorResolver.positive(context).withValues(alpha: 0.18);
        foreground = SemanticColorResolver.positive(context);
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
        background = SemanticColorResolver.negative(context).withValues(alpha: 0.18);
        foreground = SemanticColorResolver.negative(context);
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
    final label = _userRoleLabel(context, value);
    final Color background;
    final Color foreground;
    switch (value) {
      case 'admin':
        background = Colors.deepPurple.shade100;
        foreground = Colors.deepPurple.shade800;
        break;
      case 'operator':
        background = SemanticColorResolver.info(context).withValues(alpha: 0.18);
        foreground = SemanticColorResolver.info(context);
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: theme.colorScheme.onSurface),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isNotEmpty ? displayName : adminTx(context, 'کاربر بدون نام', 'Unnamed user'),
                          style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                        ),
                        Text(
                          user['email']?.toString() ?? '-',
                          style: context.settingsHub.cardSubtitleStyle(
                            theme.textTheme,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: theme.colorScheme.onSurface),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      unselectedLabelStyle: const TextStyle(fontSize: 12),
                      tabs: [
                        Tab(text: adminTx(context, 'اطلاعات کاربر', 'Profile')),
                        Tab(text: adminTx(context, 'کسب‌وکارها', 'Businesses')),
                        Tab(text: adminTx(context, 'نشست‌ها و فعالیت', 'Sessions')),
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
          _SectionTitle(title: adminTx(context, 'اطلاعات هویتی', 'Identity'), theme: theme),
          _InfoCard(
            children: [
              _InfoRow(label: adminTx(context, 'نام کامل', 'Full name'), value: user['full_name'] ?? '-'),
              _InfoRow(label: adminTx(context, 'ایمیل', 'Email'), value: user['email'] ?? '-'),
              _InfoRow(label: adminTx(context, 'موبایل', 'Mobile'), value: user['mobile'] ?? '-'),
            ],
          ),
          const SizedBox(height: 12),
          _SectionTitle(title: adminTx(context, 'دسترسی', 'Access'), theme: theme),
          _InfoCard(
            children: [
              _InfoRow(
                label: adminTx(context, 'نقش جاری', 'Current role'),
                value: _userRoleLabel(context, user['role']),
              ),
              _InfoRow(
                label: adminTx(context, 'وضعیت', 'Status'),
                value: _userStatusLabel(context, user['status']),
              ),
              _InfoRow(
                label: adminTx(context, 'تاریخ ایجاد', 'Created'),
                value: _UserManagementPageState._formatDate(user['created_at']),
              ),
              _InfoRow(
                label: adminTx(context, 'آخرین ورود', 'Last login'),
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
              adminTx(context, 'کسب‌وکاری برای این کاربر ثبت نشده است.', 'This user has no businesses.'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: businesses.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
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
                        business['name']?.toString() ?? adminTx(context, 'بدون نام', 'Unnamed'),
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
                      label: '${adminTx(context, 'شناسه', 'Id')}: ${business['id'] ?? '-'}',
                    ),
                    if (business['status'] != null)
                      _BusinessMetaChip(
                        icon: Icons.verified_user_outlined,
                        label:
                            '${adminTx(context, 'وضعیت', 'Status')}: ${_userStatusLabel(context, business['status'])}',
                      ),
                    if (business['field'] != null)
                      _BusinessMetaChip(
                        icon: Icons.work_outline,
                        label: '${adminTx(context, 'حوزه', 'Field')}: ${business['field']}',
                      ),
                  ],
                ),
                if (business['created_at'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${adminTx(context, 'عضویت', 'Joined')}: ${_UserManagementPageState._formatDate(business['created_at'])}',
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
          _SectionTitle(title: adminTx(context, 'نشست‌های فعال', 'Active sessions'), theme: theme),
          if (sessions.isEmpty)
            _EmptyInlineState(
              icon: Icons.laptop_chromebook_outlined,
              message: adminTx(context, 'نشستی ثبت نشده است.', 'No sessions recorded.'),
            )
          else
            ...sessions.map((session) => _SessionTile(session: session)),
          const SizedBox(height: 24),
          _SectionTitle(title: adminTx(context, 'آخرین فعالیت‌ها', 'Recent activity'), theme: theme),
          if (audits.isEmpty)
            _EmptyInlineState(
              icon: Icons.timeline_outlined,
              message: adminTx(context, 'رخدادی برای نمایش وجود ندارد.', 'No events to show.'),
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
        style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.primary),
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
      title: Text(map['device']?.toString() ?? adminTx(context, 'دستگاه نامشخص', 'Unknown device')),
      subtitle: Text(
        'IP: ${map['ip'] ?? '-'} · ${adminTx(context, 'آخرین فعالیت', 'Last activity')}: ${_UserManagementPageState._formatDate(map['last_active_at'], showTime: true)}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.logout, size: 18),
        tooltip: adminTx(context, 'خروج از نشست', 'Sign out session'),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(adminTx(context, 'درخواست خروج از نشست ثبت شد', 'Session sign-out was requested'))),
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
      title: Text(map['action']?.toString() ?? adminTx(context, 'اقدام نامشخص', 'Unknown action')),
      subtitle: Text(map['description']?.toString() ?? '-'),
      trailing: Text(
        _UserManagementPageState._formatDate(map['created_at'], showTime: true),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
