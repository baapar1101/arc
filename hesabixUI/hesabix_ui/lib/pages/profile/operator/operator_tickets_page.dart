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
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/support/ticket_details_dialog.dart';
import 'package:hesabix_ui/services/support_realtime_service.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/operator_command_palette.dart';
import 'package:hesabix_ui/widgets/support/operator_inbox_list.dart';
import 'package:hesabix_ui/widgets/support/operator_inbox_splitter.dart';

enum OperatorInboxDisplayMode { list, table }

/// Breakpoint for split inbox + detail workspace.
const kOperatorSplitBreakpoint = 960.0;

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
  bool _selectionMode = false;

  SupportTicket? _selectedTicket;
  bool _selectedTicketLoading = false;
  int? _selectedTicketId;

  SupportRealtimeService? _realtime;
  Timer? _pollTimer;
  DateTime? _lastRealtimeAt;
  DateTime? _lastRefreshBump;
  Timer? _refreshThrottle;

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final wide = MediaQuery.sizeOf(context).width >= kOperatorSplitBreakpoint;
        if (wide) {
          _openTicketInSplitView(ticketId);
        } else {
          context.push('/user/profile/operator/tickets/$ticketId');
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _refreshThrottle?.cancel();
    _realtime?.disconnect();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Soft backup refresh. Skip when realtime events arrived recently.
    _pollTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (!mounted) return;
      final last = _lastRealtimeAt;
      if (last != null && DateTime.now().difference(last) < const Duration(seconds: 45)) {
        return;
      }
      _bumpRefresh(immediate: true);
    });
  }

  void _bumpRefresh({bool immediate = false}) {
    if (!mounted) return;
    if (immediate) {
      setState(() => _refreshCounter++);
      _lastRefreshBump = DateTime.now();
      return;
    }
    final last = _lastRefreshBump;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 2)) {
      _refreshThrottle?.cancel();
      _refreshThrottle = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _refreshCounter++);
        _lastRefreshBump = DateTime.now();
      });
      return;
    }
    setState(() => _refreshCounter++);
    _lastRefreshBump = DateTime.now();
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
        _lastRealtimeAt = DateTime.now();
        // Silent list refresh (OperatorInboxList keeps items visible).
        _bumpRefresh();
        final eventTicketId = event['ticket_id'];
        if (eventTicketId is int && eventTicketId == _selectedTicketId) {
          _reloadSelectedTicket();
        }
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
        _selectionMode = false;
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
      _bumpRefresh();
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
    if (_statuses.isEmpty) return;
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
        _selectionMode = false;
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

  bool get _isWide => MediaQuery.sizeOf(context).width >= kOperatorSplitBreakpoint;

  void _navigateToTicketDetail(Map<String, dynamic> ticketData) {
    final ticketId = ticketData['id'];
    if (ticketId is! int) return;
    if (_isWide) {
      _openTicketInSplitView(ticketId);
      return;
    }
    context.push('/user/profile/operator/tickets/$ticketId');
  }

  Future<void> _openTicketInSplitView(int ticketId) async {
    if (_selectedTicketId == ticketId && _selectedTicket != null) return;
    final previousId = _selectedTicketId;
    _safeSetState(() {
      _selectedTicketId = ticketId;
      _selectedTicket = null;
      _selectedTicketLoading = true;
    });
    if (previousId != null && previousId != ticketId) {
      _realtime?.unsubscribeTicket(previousId);
    }
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
        onRefresh: _bumpRefresh,
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
        onOpenTicket: (id) {
          if (_isWide) {
            _openTicketInSplitView(id);
          } else {
            context.push('/user/profile/operator/tickets/$id');
          }
        },
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

  Widget _buildInboxList() {
    final selectionOn = _selectionMode || _selectedRows.isNotEmpty;
    return OperatorInboxList(
      view: _inboxView,
      currentUserId: _currentUserId,
      selectedTicketId: _selectedTicketId,
      refreshToken: _refreshCounter,
      calendarController: widget.calendarController,
      extraFilters: _extraFilters(),
      onTicketTap: _navigateToTicketDetail,
      selectionEnabled: selectionOn,
      selectedIds: _selectedRows,
      onSelectionChanged: (ids) => _safeSetState(() {
        _selectedRows = ids;
        if (ids.isEmpty) _selectionMode = false;
      }),
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
                    final useSplit = constraints.maxWidth >= kOperatorSplitBreakpoint;
                    // Split workspace always uses dense list; table is full-width only.
                    if (useSplit) {
                      return OperatorInboxSplitter(
                        left: _buildInboxList(),
                        right: _buildSplitDetailPanel(),
                      );
                    }
                    if (_displayMode == OperatorInboxDisplayMode.table) {
                      return _buildTicketsTable();
                    }
                    return _buildInboxList();
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
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.support_agent, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  t.operatorPanel,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _selectionMode ? 'لغو انتخاب' : 'انتخاب چندتایی',
                  icon: Icon(
                    _selectionMode ? Icons.checklist_rtl : Icons.checklist,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _safeSetState(() {
                    _selectionMode = !_selectionMode;
                    if (!_selectionMode) _selectedRows.clear();
                  }),
                ),
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
                  onPressed: _bumpRefresh,
                ),
                IconButton(
                  tooltip: 'داشبورد',
                  icon: const Icon(Icons.dashboard_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.push('/user/profile/operator/dashboard'),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
                          child: ChoiceChip(
                            avatar: Icon(view.icon, size: 14),
                            label: Text(view.label, style: const TextStyle(fontSize: 11)),
                            selected: selected,
                            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            labelPadding: const EdgeInsets.only(left: 2, right: 4),
                            onSelected: (_) => _safeSetState(() => _inboxView = view),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Hide table toggle in narrow split contexts — still available on mobile full-width.
                SegmentedButton<OperatorInboxDisplayMode>(
                  segments: const [
                    ButtonSegment(
                      value: OperatorInboxDisplayMode.list,
                      icon: Icon(Icons.view_list, size: 16),
                      tooltip: 'لیست',
                    ),
                    ButtonSegment(
                      value: OperatorInboxDisplayMode.table,
                      icon: Icon(Icons.table_rows, size: 16),
                      tooltip: 'جدول',
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
                    Text(
                      '${_selectedRows.length} انتخاب‌شده',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _assignToMe,
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: const Text('تخصیص به من'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: _markResolved,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('حل‌شده'),
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
                        label: const Text('حذف'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () => _safeSetState(() {
                        _selectedRows.clear();
                        _selectionMode = false;
                      }),
                      child: const Text('لغو'),
                    ),
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
            Icon(Icons.inbox_outlined, size: 44, color: theme.colorScheme.outlineVariant),
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
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return TicketDetailsDialog(
      key: ValueKey(_selectedTicket!.id),
      ticket: _selectedTicket!,
      isOperator: true,
      calendarController: widget.calendarController,
      displayMode: TicketDetailDisplayMode.embedded,
      onTicketUpdated: () {
        _bumpRefresh();
        _reloadSelectedTicket();
      },
    );
  }

  Widget _buildTicketsTable() {
    // Soft refresh: do NOT remount via ValueKey on every counter tick.
    return DataTableWidget<Map<String, dynamic>>(
      key: const ValueKey('operator_tickets_table'),
      config: DataTableConfig<Map<String, dynamic>>(
        title: null,
        endpoint: '/api/v1/support/operator/tickets/search',
        columns: [
          TextColumn('title', 'عنوان', sortable: true, searchable: true, width: ColumnWidth.large),
          TextColumn('user.first_name', 'کاربر', sortable: true, searchable: true, width: ColumnWidth.medium),
          TextColumn(
            'category.name',
            'دسته',
            sortable: true,
            width: ColumnWidth.medium,
            filterType: ColumnFilterType.multiSelect,
            filterOptions: _categories.map((c) => FilterOption(value: c.name, label: c.name)).toList(),
          ),
          TextColumn(
            'priority.name',
            'اولویت',
            sortable: true,
            width: ColumnWidth.small,
            filterType: ColumnFilterType.multiSelect,
            filterOptions: _priorities.map((p) => FilterOption(value: p.name, label: p.name)).toList(),
          ),
          TextColumn(
            'status.name',
            'وضعیت',
            sortable: true,
            width: ColumnWidth.small,
            filterType: ColumnFilterType.multiSelect,
            filterOptions: _statuses.map((s) => FilterOption(value: s.name, label: s.name)).toList(),
          ),
          TextColumn('assigned_operator.first_name', 'اپراتور', sortable: true, width: ColumnWidth.medium),
          DateColumn('updated_at', 'بروزرسانی', sortable: true, width: ColumnWidth.medium, showTime: false),
          TextColumn(
            'sla',
            'SLA',
            sortable: false,
            searchable: false,
            width: ColumnWidth.small,
            formatter: (item) => item is Map<String, dynamic> ? slaStatusLabel(slaStatusFromRow(item)) : '',
          ),
        ],
        searchFields: operatorInboxSearchFields,
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
