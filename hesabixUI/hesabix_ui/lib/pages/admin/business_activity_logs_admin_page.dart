import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/admin_activity_log_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'admin_compact_scaffold.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// صفحه‌ی پنل سوپرادمین برای مشاهده‌ی لاگ فعالیت همه‌ی کسب‌وکارها.
///
/// فیلترها: بازه تاریخ (شمسی/میلادی)، کسب‌وکار، کاربر (محدود به اعضای آن کسب‌وکار)،
/// دسته فعالیت، نوع موجودیت، نوع عمل، جستجوی متنی روی توضیحات.
///
/// صفحه‌بندی به‌صورت کامل سمت سرور انجام می‌شود (DataTableWidget با httpMethod=POST
/// و افزودن additionalParams به payload).
class BusinessActivityLogsAdminPage extends StatefulWidget {
  const BusinessActivityLogsAdminPage({super.key});

  @override
  State<BusinessActivityLogsAdminPage> createState() =>
      _BusinessActivityLogsAdminPageState();
}

class _BusinessActivityLogsAdminPageState
    extends State<BusinessActivityLogsAdminPage> {
  late final AdminActivityLogService _service;
  CalendarController? _calendarController;

  // Filter state
  DateTime? _startDate;
  DateTime? _endDate;
  Map<String, dynamic>? _selectedBusiness; // {id, name}
  Map<String, dynamic>? _selectedUser; // {id, full_name, email, mobile}
  String? _selectedCategory;
  String? _selectedAction;
  String? _selectedEntityType;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';

  // Static + dynamic options
  List<String> _categoryOptions = const [];
  List<String> _actionOptions = const [];
  List<String> _entityTypeOptions = const [];

  bool _optionsLoaded = false;

  @override
  void initState() {
    super.initState();
    _service = AdminActivityLogService(ApiClient());
    _endDate = DateTime.now();
    _startDate = DateTime.now().subtract(const Duration(days: 30));
    _initCalendar();
    _loadOptions();
  }

  Future<void> _initCalendar() async {
    try {
      final c = await CalendarController.load();
      if (mounted) setState(() => _calendarController = c);
    } catch (_) {
      // optional
    }
  }

  Future<void> _loadOptions() async {
    try {
      final opts = await _service.getFilterOptions();
      if (!mounted) return;
      setState(() {
        _categoryOptions = opts['categories'] ?? const [];
        _actionOptions = opts['actions'] ?? const [];
        _entityTypeOptions = opts['entity_types'] ?? const [];
        _optionsLoaded = true;
      });
    } catch (_) {
      // در صورت خطا با لیست‌های خالی ادامه می‌دهیم؛ کاربر می‌تواند از دکمه refresh استفاده کند.
      if (mounted) setState(() => _optionsLoaded = true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------- Filter helpers ----------------

  Map<String, dynamic> _buildAdditionalParams() {
    return <String, dynamic>{
      if (_startDate != null) 'start_date': _startDate!.toIso8601String(),
      if (_endDate != null) 'end_date': _endDate!.toIso8601String(),
      if (_selectedBusiness != null && _selectedBusiness!['id'] != null)
        'business_id': _selectedBusiness!['id'],
      if (_selectedUser != null && _selectedUser!['id'] != null)
        'user_id': _selectedUser!['id'],
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty)
        'category': _selectedCategory,
      if (_selectedAction != null && _selectedAction!.isNotEmpty)
        'action': _selectedAction,
      if (_selectedEntityType != null && _selectedEntityType!.isNotEmpty)
        'entity_type': _selectedEntityType,
      if (_appliedSearch.trim().isNotEmpty) 'search': _appliedSearch.trim(),
    };
  }

  void _refreshTable() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (_appliedSearch != value) {
        setState(() => _appliedSearch = value);
      }
    });
  }

  void _clearAllFilters() {
    setState(() {
      _startDate = DateTime.now().subtract(const Duration(days: 30));
      _endDate = DateTime.now();
      _selectedBusiness = null;
      _selectedUser = null;
      _selectedCategory = null;
      _selectedAction = null;
      _selectedEntityType = null;
      _appliedSearch = '';
      _searchCtrl.clear();
    });
  }

  // ---------------- Pickers ----------------

  Future<void> _pickBusiness() async {
    final selected = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => _SearchPickerDialog(
        title: adminTx(context, 'انتخاب کسب‌وکار', 'Choose a business'),
        searchHint: adminTx(context, 'جستجوی نام کسب‌وکار...', 'Search business name...'),
        fetcher: (q) => _service.searchBusinesses(query: q),
        itemTitle: (item) => (item['name'] ?? '').toString(),
        itemSubtitle: (item) {
          final type = item['business_type']?.toString();
          return type == null || type.isEmpty
              ? adminTx(context, 'شناسه: ${item['id']}', 'Id: ${item['id']}')
              : adminTx(context, '$type • شناسه: ${item['id']}', '$type • Id: ${item['id']}');
        },
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedBusiness = selected;
        // اگر کسب‌وکار عوض شد، کاربر انتخابی را خالی کنیم تا با لیست اعضای جدید هماهنگ شود.
        _selectedUser = null;
      });
    }
  }

  Future<void> _pickUser() async {
    final businessId = _selectedBusiness?['id'] as int?;
    final selected = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => _SearchPickerDialog(
        title: businessId == null
            ? adminTx(context, 'انتخاب کاربر (همه کاربران)', 'Choose a user (all users)')
            : adminTx(context, 'انتخاب کاربر عضو کسب‌وکار', 'Choose a business member'),
        searchHint: adminTx(context, 'نام/ایمیل/موبایل...', 'Name, email, or mobile...'),
        fetcher: (q) =>
            _service.searchUsers(query: q, businessId: businessId),
        itemTitle: (item) => (item['full_name'] ?? '').toString(),
        itemSubtitle: (item) {
          final email = item['email']?.toString();
          final mobile = item['mobile']?.toString();
          final parts = <String>[];
          if (email != null && email.isNotEmpty) parts.add(email);
          if (mobile != null && mobile.isNotEmpty) parts.add(mobile);
          return parts.isEmpty ? adminTx(context, 'شناسه: ${item['id']}', 'Id: ${item['id']}') : parts.join(' • ');
        },
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedUser = selected);
    }
  }

  // ---------------- Detail dialog ----------------

  Future<void> _showDetail(int logId) async {
    try {
      final detail = await _service.getLogDetail(logId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _LogDetailDialog(log: detail),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminTx(context, 'خطا در دریافت جزئیات: $e', 'Could not load details: $e'))),
      );
    }
  }

  // ---------------- Labels ----------------

  String _categoryLabel(String? c) {
    if (c == null) return '';
    final m = {
      'accounting': adminTx(context, 'حسابداری', 'Accounting'),
      'warehouse': adminTx(context, 'انبار', 'Warehouse'),
      'product': adminTx(context, 'کالا', 'Product'),
      'person': adminTx(context, 'شخص', 'Person'),
      'business': adminTx(context, 'کسب و کار', 'Business'),
      'user': adminTx(context, 'کاربر', 'User'),
      'settings': adminTx(context, 'تنظیمات', 'Settings'),
      'invoice': adminTx(context, 'فاکتور', 'Invoice'),
      'document': adminTx(context, 'سند', 'Document'),
      'workflow': adminTx(context, 'گردش کار', 'Workflow'),
      'marketplace': adminTx(context, 'مارکت‌پلیس', 'Marketplace'),
      'storage': adminTx(context, 'ذخیره‌سازی', 'Storage'),
      'payment': adminTx(context, 'پرداخت', 'Payment'),
      'wallet': adminTx(context, 'کیف پول', 'Wallet'),
      'warranty': adminTx(context, 'گارانتی', 'Warranty'),
      'ai': adminTx(context, 'هوش مصنوعی', 'AI'),
      'support': adminTx(context, 'پشتیبانی', 'Support'),
      'other': adminTx(context, 'سایر', 'Other'),
    };
    return m[c] ?? c;
  }

  String _actionLabel(String? a) {
    if (a == null) return '';
    final m = {
      'create': adminTx(context, 'ایجاد', 'Create'),
      'update': adminTx(context, 'ویرایش', 'Edit'),
      'delete': adminTx(context, 'حذف', 'Delete'),
      'post': adminTx(context, 'ثبت', 'Post'),
      'cancel': adminTx(context, 'لغو', 'Cancel'),
      'approve': adminTx(context, 'تایید', 'Approve'),
      'reject': adminTx(context, 'رد', 'Reject'),
      'export': adminTx(context, 'خروجی', 'Export'),
      'import': adminTx(context, 'ورودی', 'Import'),
      'login': adminTx(context, 'ورود', 'Sign in'),
      'logout': adminTx(context, 'خروج', 'Sign out'),
      'logout_all': adminTx(context, 'خروج از همه', 'Sign out everywhere'),
      'login_failed': adminTx(context, 'ورود ناموفق', 'Failed sign-in'),
      'password_change': adminTx(context, 'تغییر رمز', 'Password change'),
      'execute': adminTx(context, 'اجرا', 'Run'),
      'execute_failed': adminTx(context, 'اجرا ناموفق', 'Run failed'),
      'restart_service': adminTx(context, 'راه‌اندازی مجدد', 'Restart'),
    };
    return m[a] ?? a;
  }

  Color _categoryColor(String? c) {
    if (c == null) return Colors.grey;
    final m = <String, Color>{
      'accounting': SemanticColorResolver.info(context),
      'warehouse': SemanticColorResolver.warning(context),
      'product': SemanticColorResolver.positive(context),
      'person': Colors.purple,
      'business': Colors.indigo,
      'user': SemanticColorResolver.negative(context),
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
    return m[c] ?? Colors.grey;
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    final dt = value is DateTime ? value : DateTime.tryParse(value.toString());
    if (dt == null) return value.toString();
    final isJalali = _calendarController?.isJalali ?? false;
    return HesabixDateUtils.formatForDisplay(dt, isJalali);
  }

  // ---------------- DataTable config ----------------

  DataTableConfig<Map<String, dynamic>> _buildTableConfig() {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/admin/activity-logs/table',
      title: adminTx(context, 'لاگ کسب و کارها', 'Business activity'),
      subtitle: adminTx(context, 'مشاهده فعالیت کاربران در همه کسب و کارها', 'User activity across businesses'),
      httpMethod: 'POST',
      // صفحه‌بندی سمت سرور
      showPagination: true,
      defaultPageSize: 50,
      pageSizeOptions: const [25, 50, 100, 200],
      defaultSortBy: 'created_at',
      defaultSortDesc: true,
      // فیلترها از طریق additionalParams
      additionalParams: _buildAdditionalParams(),
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showSearch: false, // جستجو را خودمان بالای کارت داریم تا روی description اعمال شود
      showExportButtons: false,
      showActiveFilters: false,
      showClearFiltersButton: false,
      enableDateRangeFilter: false,
      expandBodyHeightToFitRows: false,
      onRowTap: (item) {
        final id = (item as Map<String, dynamic>)['id'];
        if (id is int) _showDetail(id);
      },
      columns: [
        DateColumn(
          'created_at',
          adminTx(context, 'تاریخ و زمان', 'Date and time'),
          width: ColumnWidth.medium,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return _formatDate(m['created_at']);
          },
        ),
        TextColumn(
          'business_name',
          adminTx(context, 'کسب و کار', 'Business'),
          width: ColumnWidth.medium,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final name = m['business_name']?.toString();
            if (name == null || name.isEmpty) return '-';
            return name;
          },
        ),
        TextColumn(
          'user_name',
          adminTx(context, 'کاربر', 'User'),
          width: ColumnWidth.medium,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final name = m['user_name']?.toString();
            final email = m['user_email']?.toString();
            final mobile = m['user_mobile']?.toString();
            if (name != null && name.isNotEmpty) return name;
            if (email != null && email.isNotEmpty) return email;
            if (mobile != null && mobile.isNotEmpty) return mobile;
            return adminTx(context, 'نامشخص', 'Unknown');
          },
        ),
        CustomColumn(
          'category',
          adminTx(context, 'دسته فعالیت', 'Category'),
          width: ColumnWidth.small,
          builder: (item, _) {
            final m = item as Map<String, dynamic>;
            final cat = m['category']?.toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _categoryColor(cat).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _categoryLabel(cat),
                  style: TextStyle(
                    color: _categoryColor(cat),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        ),
        TextColumn(
          'action',
          adminTx(context, 'نوع عمل', 'Action'),
          width: ColumnWidth.small,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return _actionLabel(m['action']?.toString());
          },
        ),
        TextColumn(
          'description',
          adminTx(context, 'توضیحات', 'Description'),
          width: ColumnWidth.large,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return m['description']?.toString() ?? '';
          },
        ),
        TextColumn(
          'entity_info',
          adminTx(context, 'موجودیت', 'Entity'),
          width: ColumnWidth.medium,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final t = m['entity_type']?.toString();
            final id = m['entity_id'];
            if (t != null && t.isNotEmpty && id != null) {
              return '$t #$id';
            }
            return '-';
          },
        ),
        ActionColumn(
          'actions',
          '',
          width: ColumnWidth.small,
          actions: [
            DataTableAction(
              icon: Icons.info_outline,
              label: adminTx(context, 'جزئیات', 'Details'),
              onTap: (item) {
                final m = item as Map<String, dynamic>;
                final id = m['id'];
                if (id is int) _showDetail(id);
              },
            ),
          ],
        ),
      ],
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final calendar = _calendarController;

    return AdminCompactScaffold(
      title: adminTx(context, 'لاگ کسب‌وکارها', 'Business activity logs'),
      subtitle: adminTx(context, 'رویدادهای ثبت‌شده در کسب‌وکارها', 'Events recorded in businesses'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: adminTx(context, 'بروزرسانی', 'Refresh'),
          onPressed: _refreshTable,
        ),
      ],
      body: calendar == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFiltersCard(cs, calendar),
                if (!_optionsLoaded) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DataTableWidget<Map<String, dynamic>>(
                      // ValueKey از روی همه‌ی فیلترهای فعال تا با تغییر فیلتر، widget rebuild و
                      // refetch با additionalParams جدید انجام شود.
                      key: ValueKey(_buildAdditionalParams().toString()),
                      config: _buildTableConfig(),
                      calendarController: _calendarController,
                      fromJson: (json) =>
                          Map<String, dynamic>.from(json as Map),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFiltersCard(ColorScheme cs, CalendarController calendar) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  adminTx(context, 'فیلترها', 'Filters'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _clearAllFilters,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: Text(adminTx(context, 'پاک کردن فیلترها', 'Clear filters')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 170,
                  child: DateInputField(
                    labelText: adminTx(context, 'از تاریخ', 'From'),
                    value: _startDate,
                    calendarController: calendar,
                    onChanged: (d) => setState(() => _startDate = d),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DateInputField(
                    labelText: adminTx(context, 'تا تاریخ', 'To'),
                    value: _endDate,
                    calendarController: calendar,
                    onChanged: (d) => setState(() => _endDate = d),
                  ),
                ),
                _PickerField(
                  label: adminTx(context, 'کسب و کار', 'Business'),
                  icon: Icons.business_outlined,
                  selectedLabel: _selectedBusiness?['name']?.toString(),
                  onTap: _pickBusiness,
                  onClear: _selectedBusiness == null
                      ? null
                      : () => setState(() {
                            _selectedBusiness = null;
                            _selectedUser = null;
                          }),
                ),
                _PickerField(
                  label: adminTx(context, 'کاربر', 'User'),
                  icon: Icons.person_outline,
                  selectedLabel: _selectedUser?['full_name']?.toString(),
                  onTap: _pickUser,
                  onClear: _selectedUser == null
                      ? null
                      : () => setState(() => _selectedUser = null),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'دسته فعالیت', 'Category'),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(adminTx(context, 'همه', 'All')),
                      ),
                      ..._categoryOptions.map(
                        (c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(_categoryLabel(c)),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCategory = v),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _selectedAction,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'نوع عمل', 'Action'),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(adminTx(context, 'همه', 'All')),
                      ),
                      ..._actionOptions.map(
                        (a) => DropdownMenuItem<String>(
                          value: a,
                          child: Text(_actionLabel(a)),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedAction = v),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _selectedEntityType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'نوع موجودیت', 'Entity type'),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(adminTx(context, 'همه', 'All')),
                      ),
                      ..._entityTypeOptions.map(
                        (t) => DropdownMenuItem<String>(
                          value: t,
                          child: Text(t),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedEntityType = v),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'جستجو در توضیحات', 'Search descriptions'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearchChanged('');
                              },
                            ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    onChanged: _onSearchChanged,
                    onSubmitted: (v) {
                      _searchDebounce?.cancel();
                      setState(() => _appliedSearch = v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// فیلد قابل کلیک برای انتخاب کسب‌وکار/کاربر؛ با ظاهر مشابه TextField.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.selectedLabel,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final IconData icon;
  final String? selectedLabel;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = selectedLabel != null && selectedLabel!.trim().isNotEmpty;
    return SizedBox(
      width: 220,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: hasValue && onClear != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: onClear,
                  )
                : const Icon(Icons.arrow_drop_down),
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: Text(
            hasValue ? selectedLabel! : adminTx(context, 'همه', 'All'),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              color: hasValue
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// دیالوگ جستجوی autocomplete برای کسب‌وکار/کاربر.
class _SearchPickerDialog extends StatefulWidget {
  const _SearchPickerDialog({
    required this.title,
    required this.searchHint,
    required this.fetcher,
    required this.itemTitle,
    required this.itemSubtitle,
  });

  final String title;
  final String searchHint;
  final Future<List<Map<String, dynamic>>> Function(String query) fetcher;
  final String Function(Map<String, dynamic> item) itemTitle;
  final String Function(Map<String, dynamic> item) itemSubtitle;

  @override
  State<_SearchPickerDialog> createState() => _SearchPickerDialogState();
}

class _SearchPickerDialogState extends State<_SearchPickerDialog> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _items = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _runFetch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runFetch(value);
    });
  }

  Future<void> _runFetch(String query) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.fetcher(query);
      if (!mounted) return;
      setState(() {
        _items = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: _onChanged,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(adminTx(context, 'خطا: $_error', '$_error'),
            style: TextStyle(color: SemanticColorResolver.negative(context))),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(adminTx(context, 'نتیجه‌ای یافت نشد', 'No results')));
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final item = _items[i];
        return ListTile(
          title: Text(widget.itemTitle(item)),
          subtitle: Text(
            widget.itemSubtitle(item),
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => Navigator.of(context).pop(item),
        );
      },
    );
  }
}

/// نمایش جزئیات یک رکورد لاگ همراه با before/after/extra info.
class _LogDetailDialog extends StatelessWidget {
  const _LogDetailDialog({required this.log});

  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      adminTx(context, 'جزئیات لاگ #${log['id'] ?? ''}', 'Log #${log['id'] ?? ''}'),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv(adminTx(context, 'توضیحات', 'Description'), log['description']?.toString()),
                    _kv(adminTx(context, 'کسب و کار', 'Business'),
                        '${log['business_name'] ?? '-'} (#${log['business_id'] ?? '-'})'),
                    _kv(adminTx(context, 'کاربر', 'User'),
                        '${log['user_name'] ?? '-'} (#${log['user_id'] ?? '-'})'),
                    _kv(adminTx(context, 'دسته', 'Category'), log['category']?.toString()),
                    _kv(adminTx(context, 'عمل', 'Action'), log['action']?.toString()),
                    _kv(
                      adminTx(context, 'موجودیت', 'Entity'),
                      log['entity_type'] == null
                          ? null
                          : '${log['entity_type']} #${log['entity_id'] ?? '-'}',
                    ),
                    _kv(adminTx(context, 'تاریخ', 'Date'), log['created_at']?.toString()),
                    const SizedBox(height: 8),
                    _jsonBlock(adminTx(context, 'قبل از تغییر', 'Before'), log['before_data']),
                    _jsonBlock(adminTx(context, 'بعد از تغییر', 'After'), log['after_data']),
                    _jsonBlock(adminTx(context, 'اطلاعات اضافی', 'Extra'), log['extra_info']),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String key, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              key,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(
              value == null || value.isEmpty ? '-' : value,
            ),
          ),
        ],
      ),
    );
  }

  Widget _jsonBlock(String title, dynamic value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
            ),
            child: SelectableText(
              _prettyJson(value),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _prettyJson(dynamic value) {
    try {
      // ساده و بدون وابستگی اضافه؛ json.encode داخلی خوب کار می‌کند.
      // ignore: import_of_legacy_library_into_null_safe
      const indent = '  ';
      return _formatNested(value, '', indent);
    } catch (_) {
      return value.toString();
    }
  }

  static String _formatNested(dynamic value, String prefix, String indent) {
    if (value is Map) {
      if (value.isEmpty) return '{}';
      final buf = StringBuffer('{\n');
      final entries = value.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        buf.write(prefix + indent);
        buf.write('"${e.key}": ');
        buf.write(_formatNested(e.value, prefix + indent, indent));
        if (i < entries.length - 1) buf.write(',');
        buf.write('\n');
      }
      buf.write('$prefix}');
      return buf.toString();
    }
    if (value is List) {
      if (value.isEmpty) return '[]';
      final buf = StringBuffer('[\n');
      for (var i = 0; i < value.length; i++) {
        buf.write(prefix + indent);
        buf.write(_formatNested(value[i], prefix + indent, indent));
        if (i < value.length - 1) buf.write(',');
        buf.write('\n');
      }
      buf.write('$prefix]');
      return buf.toString();
    }
    if (value is String) {
      return '"$value"';
    }
    if (value == null) return 'null';
    return value.toString();
  }
}
