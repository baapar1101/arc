import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/support/ticket_details_dialog.dart';
import 'package:hesabix_ui/services/support_realtime_service.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/operator_command_palette.dart';
import 'package:hesabix_ui/widgets/support/operator_inbox_list.dart';

enum OperatorInboxDisplayMode { list, table }

class OperatorTicketsPage extends StatefulWidget {
  final CalendarController? calendarController;
  final int? initialTicketId;
  final AuthStore? authStore;
  final OperatorInboxView? initialInboxView;

  const OperatorTicketsPage({
    super.key,
    this.calendarController,
    this.initialTicketId,
    this.authStore,
    this.initialInboxView,
  });

  @override
  State<OperatorTicketsPage> createState() => _OperatorTicketsPageState();
}

class _OperatorTicketsPageState extends State<OperatorTicketsPage> {
  Set<int> _selectedRows = <int>{};
  final SupportService _supportService = SupportService(ApiClient());

  List<SupportStatus> _statuses = [];
  List<SupportPriority> _priorities = [];
  List<SupportCategory> _categories = [];
  int _refreshCounter = 0;
  bool _isSuperAdmin = false;
  int? _currentUserId;
  bool? _lastMessageFromUser;

  SupportTicket? _selectedTicket;
  bool _selectedTicketLoading = false;
  int? _selectedTicketId;

  SupportRealtimeService? _realtime;
  Timer? _pollTimer;

  OperatorInboxView _inboxView = OperatorInboxView.all;
  OperatorInboxDisplayMode _displayMode = OperatorInboxDisplayMode.list;

  @override
  void initState() {
    super.initState();
    if (widget.initialInboxView != null) {
      _inboxView = widget.initialInboxView!;
    }
    _loadMetadata();
    _loadSession();
    _startPolling();
    _connectRealtime();
    final ticketId = widget.initialTicketId;
    if (ticketId != null && ticketId > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openTicketInSplitView(ticketId));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _realtime?.disconnect();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _safeSetState(() => _refreshCounter++);
    });
  }

  void _connectRealtime() {
    final apiKey = widget.authStore?.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _realtime = createSupportRealtimeService();
    _realtime!.connect(
      apiKey: apiKey,
      onEvent: (event) {
        if ('${event['type']}' != 'support') return;
        if (!mounted) return;
        _safeSetState(() => _refreshCounter++);
        if (event['ticket_id'] == _selectedTicketId) _reloadSelectedTicket();
      },
    );
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _loadMetadata() async {
    try {
      final results = await Future.wait([
        _supportService.getStatuses(),
        _supportService.getPriorities(),
        _supportService.getCategories(),
      ]);
      _safeSetState(() {
        _statuses = results[0] as List<SupportStatus>;
        _priorities = results[1] as List<SupportPriority>;
        _categories = results[2] as List<SupportCategory>;
      });
    } catch (_) {}
  }

  Future<void> _loadSession() async {
    try {
      final response = await ApiClient().get<Map<String, dynamic>>('/api/v1/auth/me');
      final data = response.data?['data'] as Map<String, dynamic>?;
      final permissions = data?['permissions'] as Map<String, dynamic>?;
      _safeSetState(() {
        _isSuperAdmin = permissions?['is_superadmin'] as bool? ?? false;
        _currentUserId = data?['id'] as int?;
      });
    } catch (_) {}
  }

  List<FilterItem> _extraFilters() {
    final filters = <FilterItem>[];
    if (_lastMessageFromUser != null) {
      filters.add(FilterItem(
        property: 'last_message_from_user',
        operator: '==',
        value: _lastMessageFromUser == true ? 'true' : 'false',
      ));
    }
    return filters;
  }

  Future<void> _assignToMe() async {
    if (_selectedRows.isEmpty || _currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لطفاً حداقل یک تیکت انتخاب کنید')));
      return;
    }
    try {
      final result = await _supportService.bulkAssignTickets(_selectedRows.toList(), _currentUserId!);
      _safeSetState(() {
        _selectedRows.clear();
        _refreshCounter++;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result['updated_count']} تیکت به شما تخصیص داده شد'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorExtractor.forContext(e, context)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _assignActiveRowToMe(Map<String, dynamic> row) async {
    final ticketId = row['id'];
    if (ticketId is! int || _currentUserId == null) return;
    try {
      await _supportService.assignTicket(ticketId, AssignTicketRequest(operatorId: _currentUserId!));
      _safeSetState(() => _refreshCounter++);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تیکت #$ticketId به شما تخصیص داده شد'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorExtractor.forContext(e, context)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _markResolved() async {
    if (_selectedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لطفاً حداقل یک تیکت انتخاب کنید')));
      return;
    }
    final resolvedStatus = _statuses.firstWhere(
      (s) => s.name.toLowerCase().contains('حل') || s.name.toLowerCase().contains('resolved'),
      orElse: () => _statuses.firstWhere((s) => s.isFinal, orElse: () => _statuses.last),
    );
    try {
      final result = await _supportService.bulkUpdateStatus(
        _selectedRows.toList(),
        resolvedStatus.id,
        assignedOperatorId: _currentUserId,
      );
      _safeSetState(() {
        _selectedRows.clear();
        _refreshCounter++;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result['updated_count']} تیکت حل‌شده شد'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorExtractor.forContext(e, context)), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _navigateToTicketDetail(Map<String, dynamic> ticketData) {
    final ticketId = ticketData['id'];
    if (ticketId is! int) return;
    if (MediaQuery.of(context).size.width >= 900) {
      _openTicketInSplitView(ticketId);
      return;
    }
    showDialog(
      context: context,
      builder: (context) => TicketDetailsDialog(
        ticket: SupportTicket.fromJson(ticketData),
        isOperator: true,
        calendarController: widget.calendarController,
        onTicketUpdated: () => _safeSetState(() => _refreshCounter++),
      ),
    );
  }

  Future<void> _openTicketInSplitView(int ticketId) async {
    _safeSetState(() {
      _selectedTicketId = ticketId;
      _selectedTicket = null;
      _selectedTicketLoading = true;
    });
    _realtime?.subscribeTicket(ticketId);
    try {
      final ticket = await _supportService.getOperatorTicket(ticketId);
      _safeSetState(() {
        _selectedTicket = ticket;
        _selectedTicketLoading = false;
      });
    } catch (e) {
      _safeSetState(() => _selectedTicketLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorExtractor.forContext(e, context)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reloadSelectedTicket() async {
    final id = _selectedTicketId;
    if (id == null) return;
    try {
      final ticket = await _supportService.getOperatorTicket(id);
      _safeSetState(() => _selectedTicket = ticket);
    } catch (_) {}
  }

  Future<void> _deleteTicket(int ticketId) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: const Text('آیا مطمئن هستید که می‌خواهید این تیکت را حذف کنید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _supportService.deleteTicket(ticketId);
      _safeSetState(() {
        _selectedRows.remove(ticketId);
        if (_selectedTicketId == ticketId) {
          _selectedTicketId = null;
          _selectedTicket = null;
        }
        _refreshCounter++;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorExtractor.forContext(e, context)), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCommandPalette() {
    OperatorCommandPalette.show(
      context,
      OperatorCommandPalette(
        onSelectView: (view) => _safeSetState(() => _inboxView = view),
        onRefresh: () => _safeSetState(() => _refreshCounter++),
        onAssignToMe: () {
          if (_selectedTicketId != null) {
            _safeSetState(() => _selectedRows = {_selectedTicketId!});
          }
          _assignToMe();
        },
        onMarkResolved: () {
          if (_selectedTicketId != null) {
            _safeSetState(() => _selectedRows = {_selectedTicketId!});
          }
          _markResolved();
        },
        onOpenTicket: _openTicketInSplitView,
        onGoDashboard: () => context.push('/user/profile/operator/dashboard'),
      ),
    );
  }

  void _showShortcutsHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('میانبرهای صفحه‌کلید'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ctrl+K — پالت دستورات'),
            Text('j / k — حرکت بین ردیف‌ها'),
            Text('Enter / Space — باز کردن تیکت'),
            Text('r — پاسخ / باز کردن'),
            Text('a — تخصیص به من'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK): const _OpenCommandPaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK): const _OpenCommandPaletteIntent(),
      },
      child: Actions(
        actions: {
          _OpenCommandPaletteIntent: CallbackAction<_OpenCommandPaletteIntent>(
            onInvoke: (_) {
              _showCommandPalette();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCompactToolbar(t, theme),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useSplit = constraints.maxWidth >= 960;
                    final inbox = _displayMode == OperatorInboxDisplayMode.list
                        ? OperatorInboxList(
                            view: _inboxView,
                            currentUserId: _currentUserId,
                            selectedTicketId: _selectedTicketId,
                            refreshToken: _refreshCounter,
                            calendarController: widget.calendarController,
                            extraFilters: _extraFilters(),
                            onTicketTap: _navigateToTicketDetail,
                          )
                        : _buildTicketsTable();

                    if (!useSplit) return inbox;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 300, child: inbox),
                        VerticalDivider(width: 1, color: theme.dividerColor),
                        Expanded(child: _buildSplitDetailPanel()),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactToolbar(AppLocalizations t, ThemeData theme) {
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  t.operatorPanel,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'پالت دستورات (Ctrl+K)',
                  icon: const Icon(Icons.search, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: _showCommandPalette,
                ),
                IconButton(
                  tooltip: 'میانبرها',
                  icon: const Icon(Icons.keyboard_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: _showShortcutsHelp,
                ),
                IconButton(
                  tooltip: 'بروزرسانی',
                  icon: const Icon(Icons.refresh, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _safeSetState(() => _refreshCounter++),
                ),
                IconButton(
                  tooltip: 'داشبورد',
                  icon: const Icon(Icons.dashboard_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.push('/user/profile/operator/dashboard'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: OperatorInboxView.values.map((view) {
                        final selected = _inboxView == view;
                        return Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: FilterChip(
                            avatar: Icon(view.icon, size: 14),
                            label: Text(view.label, style: const TextStyle(fontSize: 12)),
                            selected: selected,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onSelected: (_) => _safeSetState(() => _inboxView = view),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<OperatorInboxDisplayMode>(
                  segments: const [
                    ButtonSegment(
                      value: OperatorInboxDisplayMode.list,
                      icon: Icon(Icons.view_list, size: 16),
                    ),
                    ButtonSegment(
                      value: OperatorInboxDisplayMode.table,
                      icon: Icon(Icons.table_rows, size: 16),
                    ),
                  ],
                  selected: {_displayMode},
                  onSelectionChanged: (s) => _safeSetState(() => _displayMode = s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            if (_selectedRows.isNotEmpty) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _assignToMe,
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: Text('تخصیص (${_selectedRows.length})'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: _markResolved,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: Text('حل‌شده (${_selectedRows.length})'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    if (_isSuperAdmin) ...[
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        onPressed: () => _deleteTicket(_selectedRows.first),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: Text('حذف (${_selectedRows.length})'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSplitDetailPanel() {
    final theme = Theme.of(context);
    if (_selectedTicketId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text('تیکتی انتخاب نشده', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'از لیست یک تیکت را انتخاب کنید',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (_selectedTicketLoading || _selectedTicket == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return TicketDetailsDialog(
      key: ValueKey(_selectedTicket!.id),
      ticket: _selectedTicket!,
      isOperator: true,
      calendarController: widget.calendarController,
      displayMode: TicketDetailDisplayMode.embedded,
      onTicketUpdated: () {
        _safeSetState(() => _refreshCounter++);
        _reloadSelectedTicket();
      },
    );
  }

  Widget _buildTicketsTable() {
    return DataTableWidget<Map<String, dynamic>>(
      key: ValueKey('data_table_$_refreshCounter'),
      config: DataTableConfig<Map<String, dynamic>>(
        title: null,
        endpoint: '/api/v1/support/operator/tickets/search',
        columns: [
          TextColumn('title', 'عنوان', sortable: true, searchable: true, width: ColumnWidth.large),
          TextColumn('user.first_name', 'کاربر', sortable: true, searchable: true, width: ColumnWidth.medium),
          TextColumn('category.name', 'دسته', sortable: true, width: ColumnWidth.medium,
              filterType: ColumnFilterType.multiSelect,
              filterOptions: _categories.map((c) => FilterOption(value: c.name, label: c.name)).toList()),
          TextColumn('priority.name', 'اولویت', sortable: true, width: ColumnWidth.small,
              filterType: ColumnFilterType.multiSelect,
              filterOptions: _priorities.map((p) => FilterOption(value: p.name, label: p.name)).toList()),
          TextColumn('status.name', 'وضعیت', sortable: true, width: ColumnWidth.small,
              filterType: ColumnFilterType.multiSelect,
              filterOptions: _statuses.map((s) => FilterOption(value: s.name, label: s.name)).toList()),
          TextColumn('assigned_operator.first_name', 'اپراتور', sortable: true, width: ColumnWidth.medium),
          DateColumn('updated_at', 'بروزرسانی', sortable: true, width: ColumnWidth.medium, showTime: false),
          TextColumn('sla', 'SLA', sortable: false, searchable: false, width: ColumnWidth.small,
              formatter: (item) => item is Map<String, dynamic> ? slaStatusLabel(slaStatusFromRow(item)) : ''),
        ],
        searchFields: ['title', 'description', 'user.first_name', 'user.email'],
        filterFields: ['title', 'category.name', 'priority.name', 'status.name', 'assigned_operator.first_name', 'created_at'],
        dateRangeField: 'created_at',
        showSearch: true,
        showFilters: true,
        showPagination: true,
        enableSorting: true,
        enableGlobalSearch: true,
        enableDateRangeFilter: true,
        enableRowSelection: true,
        enableMultiRowSelection: true,
        selectedRows: _selectedRows,
        onRowSelectionChanged: (rows) => _safeSetState(() => _selectedRows = rows),
        getCustomFilters: _extraFilters,
        defaultPageSize: 20,
        showRefreshButton: true,
        showClearFiltersButton: true,
        emptyStateMessage: 'هیچ تیکتی یافت نشد',
        onRowTap: (ticketData) => _navigateToTicketDetail(ticketData as Map<String, dynamic>),
        onRowShortcutReply: (row) => _navigateToTicketDetail(row as Map<String, dynamic>),
        onRowShortcutAssign: (row) {
          if (row is Map<String, dynamic>) _assignActiveRowToMe(row);
        },
        rowColorBuilder: (item, index) => item is Map<String, dynamic> ? slaRowBackgroundColor(item) : null,
        expandBodyHeightToFitRows: true,
        showBorder: true,
        borderRadius: BorderRadius.circular(8),
        padding: const EdgeInsets.all(8),
      ),
      fromJson: (json) => json,
      calendarController: widget.calendarController,
    );
  }
}

class _OpenCommandPaletteIntent extends Intent {
  const _OpenCommandPaletteIntent();
}
