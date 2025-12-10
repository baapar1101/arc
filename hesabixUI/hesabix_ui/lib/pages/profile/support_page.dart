import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import '../../core/date_utils.dart';
import '../../utils/date_formatters.dart';
import 'package:hesabix_ui/widgets/support/ticket_details_dialog.dart';
import 'create_ticket_page.dart';

class SupportPage extends StatefulWidget {
  final CalendarController? calendarController;
  const SupportPage({super.key, this.calendarController});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  Set<int> _selectedRows = <int>{};
  
  // Support data for filters
  final SupportService _supportService = SupportService(ApiClient());
  List<SupportStatus> _statuses = [];
  List<SupportPriority> _priorities = [];
  bool _metadataLoading = false;
  String? _metadataError;
  
  // Refresh counter to force data table refresh
  int _refreshCounter = 0;

  // Mobile / card-view state
  bool _mobileCardView = true;
  bool _showMobileFilters = false;
  bool _ticketsLoading = false;
  String? _ticketsError;
  bool _ticketsEverLoaded = false;
  final TextEditingController _searchController = TextEditingController();
  List<SupportTicket> _tickets = <SupportTicket>[];
  int _ticketPage = 1;
  final int _ticketPageSize = 20;
  int _ticketsTotal = 0;
  bool _hasMoreTickets = true;
  int? _selectedStatusId;
  int? _selectedPriorityId;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    setState(() {
      _metadataLoading = true;
      _metadataError = null;
    });
    try {
      final statuses = await _supportService.getStatuses();
      final priorities = await _supportService.getPriorities();
      
      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _priorities = priorities;
        _metadataLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading support metadata: $e');
      if (!mounted) return;
      setState(() {
        _metadataLoading = false;
        _metadataError = e.toString();
      });
    }
  }


  void _navigateToCreateTicket() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CreateTicketPage(),
    );
    
    if (result == true) {
      // Refresh the data table after successful ticket creation
      setState(() {
        _refreshCounter++;
      });
    }
  }

  void _navigateToTicketDetail(Map<String, dynamic> ticketData) {
    final ticket = SupportTicket.fromJson(ticketData);
    showDialog(
      context: context,
      builder: (context) => TicketDetailsDialog(
        ticket: ticket,
        isOperator: false,
        onTicketUpdated: () {
          // Refresh the data table if needed
          setState(() {});
        },
      ),
    );
  }

  Future<void> _loadTickets({bool showSpinner = true}) async {
    if (!_hasMoreTickets && _ticketPage > 1) {
      return;
    }

    if (showSpinner) {
      setState(() {
        _ticketsLoading = true;
        _ticketsError = null;
      });
    }
    try {
      final query = QueryInfo(
        search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        searchFields: const ['title', 'description'],
        sortBy: 'created_at',
        sortDesc: true,
        take: _ticketPageSize,
        skip: (_ticketPage - 1) * _ticketPageSize,
        filters: [
          if (_selectedStatusId != null)
            FilterItem(property: 'status_id', operator: '==', value: _selectedStatusId),
          if (_selectedPriorityId != null)
            FilterItem(property: 'priority_id', operator: '==', value: _selectedPriorityId),
        ],
      ).toJson();
      final result = await _supportService.searchUserTickets(query);
      if (!mounted) return;
      setState(() {
        if (_ticketPage == 1) {
          _tickets = result.items;
        } else {
          _tickets = <SupportTicket>[..._tickets, ...result.items];
        }
        _ticketsTotal = result.total;
        final loadedCount = _tickets.length;
        _hasMoreTickets = loadedCount < _ticketsTotal && result.items.isNotEmpty;
        if (_hasMoreTickets) {
          _ticketPage += 1;
        }
        _ticketsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ticketsError = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _ticketsLoading = false;
      });
    }
  }

  String _statusLabelFor(SupportTicket ticket) {
    final status = _statuses.where((s) => s.id == ticket.statusId).cast<SupportStatus?>().firstWhere(
          (s) => s != null,
          orElse: () => null,
        );
    return status?.name ?? '';
  }

  Color? _statusColorFor(SupportTicket ticket) {
    final status = _statuses.where((s) => s.id == ticket.statusId).cast<SupportStatus?>().firstWhere(
          (s) => s != null,
          orElse: () => null,
        );
    if (status?.color == null) return null;
    return _parseHexColor(status!.color!);
  }

  String _priorityLabelFor(SupportTicket ticket) {
    final pr = _priorities.where((p) => p.id == ticket.priorityId).cast<SupportPriority?>().firstWhere(
          (p) => p != null,
          orElse: () => null,
        );
    return pr?.name ?? '';
  }

  Color? _priorityColorFor(SupportTicket ticket) {
    final pr = _priorities.where((p) => p.id == ticket.priorityId).cast<SupportPriority?>().firstWhere(
          (p) => p != null,
          orElse: () => null,
        );
    if (pr?.color == null) return null;
    return _parseHexColor(pr!.color!);
  }

  Color _chipBackground(Color base) {
    return base.withOpacity(0.12);
  }

  Color? _parseHexColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  String _formatTicketDate(DateTime dateTime) {
    try {
      // استفاده از HesabixDateUtils در صورت وجود calendarController
      if (widget.calendarController != null) {
        return HesabixDateUtils.formatDateTime(dateTime, widget.calendarController!.isJalali);
      }
      return DateFormatters.formatServerDateTime(dateTime.toIso8601String());
    } catch (_) {
      return DateFormatters.formatServerDateTime(dateTime.toIso8601String());
    }
  }

  Widget _buildMobileHeader(AppLocalizations t, ThemeData theme, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.supportTickets,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (isMobile)
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.view_list_rounded),
                    label: const Text('لیست'),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    icon: const Icon(Icons.table_chart),
                    label: const Text('جدول'),
                  ),
                ],
                selected: <bool>{_mobileCardView},
                onSelectionChanged: (values) {
                  setState(() {
                    _mobileCardView = values.first;
                    if (_mobileCardView && !_ticketsEverLoaded && !_ticketsLoading) {
                      _ticketsEverLoaded = true;
                      _loadTickets();
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (!isMobile)
          Text(
            'در این بخش می‌توانید همه تیکت‌های پشتیبانی خود را ببینید، جست‌وجو و بر اساس وضعیت و اولویت فیلتر کنید.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildTicketsEmptyState(AppLocalizations t, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.support_agent_outlined,
            size: 72,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
          ),
          const SizedBox(height: 16),
          Text(
            t.noTickets,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اگر سوال یا مشکلی دارید، اولین تیکت خود را ثبت کنید تا تیم پشتیبانی کنار شما باشد.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _navigateToCreateTicket,
            icon: const Icon(Icons.add),
            label: Text(t.newTicket),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFilters(AppLocalizations t, ThemeData theme) {
    if (_statuses.isEmpty && _priorities.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(top: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'فیلترهای سریع',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (_statuses.isNotEmpty) ...[
              Text(
                t.status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('همه'),
                      selected: _selectedStatusId == null,
                      onSelected: (_) {
                        setState(() {
                          _selectedStatusId = null;
                          _ticketPage = 1;
                          _hasMoreTickets = true;
                        });
                        _loadTickets(showSpinner: true);
                      },
                    ),
                    const SizedBox(width: 6),
                    ..._statuses.map((s) {
                      final color = s.color != null ? _parseHexColor(s.color!) : null;
                      final selected = _selectedStatusId == s.id;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: FilterChip(
                          label: Text(s.name),
                          selected: selected,
                          onSelected: (_) {
                            setState(() {
                              _selectedStatusId = selected ? null : s.id;
                              _ticketPage = 1;
                              _hasMoreTickets = true;
                            });
                            _loadTickets(showSpinner: true);
                          },
                          avatar: color != null
                              ? CircleAvatar(
                                  backgroundColor: _chipBackground(color),
                                  child: Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: color,
                                  ),
                                )
                              : null,
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_priorities.isNotEmpty) ...[
              Text(
                t.priority,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('همه'),
                      selected: _selectedPriorityId == null,
                      onSelected: (_) {
                        setState(() {
                          _selectedPriorityId = null;
                          _ticketPage = 1;
                          _hasMoreTickets = true;
                        });
                        _loadTickets(showSpinner: true);
                      },
                    ),
                    const SizedBox(width: 6),
                    ..._priorities.map((p) {
                      final color = p.color != null ? _parseHexColor(p.color!) : null;
                      final selected = _selectedPriorityId == p.id;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: FilterChip(
                          label: Text(p.name),
                          selected: selected,
                          onSelected: (_) {
                            setState(() {
                              _selectedPriorityId = selected ? null : p.id;
                              _ticketPage = 1;
                              _hasMoreTickets = true;
                            });
                            _loadTickets(showSpinner: true);
                          },
                          avatar: color != null
                              ? CircleAvatar(
                                  backgroundColor: _chipBackground(color),
                                  child: Icon(
                                    Icons.flag,
                                    size: 14,
                                    color: color,
                                  ),
                                )
                              : null,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSearch(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: t.search,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                    });
                    _loadTickets(showSpinner: false);
                  },
                ),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          setState(() {
            _ticketPage = 1;
            _hasMoreTickets = true;
          });
          _loadTickets();
        },
      ),
    );
  }

  Widget _buildMobileFiltersToggle(AppLocalizations t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            visualDensity: VisualDensity.compact,
            shape: const StadiumBorder(),
          ),
          onPressed: () {
            setState(() {
              _showMobileFilters = !_showMobileFilters;
            });
          },
          icon: Icon(
            _showMobileFilters ? Icons.filter_alt_off : Icons.filter_list,
            size: 18,
          ),
          label: Text(_showMobileFilters ? 'مخفی کردن فیلترها' : 'نمایش فیلترها'),
        ),
      ),
    );
  }

  Widget _buildMobileTicketsList(AppLocalizations t, ThemeData theme) {
    if (_ticketsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ticketsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              t.ticketLoadingError,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loadTickets,
              icon: const Icon(Icons.refresh),
              label: Text(t.refresh),
            ),
          ],
        ),
      );
    }

    final tickets = _tickets;
    if (tickets.isEmpty) {
      return _buildTicketsEmptyState(t, theme);
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _ticketPage = 1;
          _hasMoreTickets = true;
        });
        await _loadTickets(showSpinner: false);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 200 &&
              !_ticketsLoading &&
              _hasMoreTickets) {
            _loadTickets(showSpinner: false);
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 12, bottom: 80),
          itemCount: tickets.length + (_hasMoreTickets ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= tickets.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              );
            }

            final ticket = tickets[index];
            final statusLabel = _statusLabelFor(ticket);
            final statusColor = _statusColorFor(ticket) ?? theme.colorScheme.primary;
            final priorityLabel = _priorityLabelFor(ticket);
            final priorityColor = _priorityColorFor(ticket) ?? theme.colorScheme.secondary;
            final updatedLabel = _formatTicketDate(ticket.updatedAt);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _navigateToTicketDetail(ticket.toJson()),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              ticket.title,
                              style: theme.textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(
                              statusLabel.isEmpty ? t.status : statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            backgroundColor: _chipBackground(statusColor),
                            side: BorderSide(color: statusColor.withOpacity(0.5)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (ticket.description.isNotEmpty) ...[
                        Text(
                          ticket.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Icon(
                            Icons.flag,
                            size: 16,
                            color: priorityColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            priorityLabel.isEmpty ? t.priority : priorityLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: priorityColor,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            updatedLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 700;

    // در موبایل و نمای کارت، لود تیکت‌ها را به‌صورت تنبل انجام بده
    if (isMobile && _mobileCardView && !_ticketsEverLoaded && !_ticketsLoading) {
      _ticketsEverLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ticketPage = 1;
        _hasMoreTickets = true;
        _loadTickets();
      });
    }

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: isMobile && _mobileCardView
          ? FloatingActionButton.extended(
              onPressed: _navigateToCreateTicket,
              icon: const Icon(Icons.add),
              label: Text(t.newTicket),
            )
          : null,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 8.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMobileHeader(t, theme, isMobile),
            if (isMobile) _buildMobileSearch(t),
            if (isMobile) _buildMobileFiltersToggle(t, theme),
            if (isMobile)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _buildMobileFilters(t, theme),
                crossFadeState: _showMobileFilters ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            const SizedBox(height: 12),
            if (_metadataError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'خطا در بارگذاری فهرست وضعیت‌ها و اولویت‌ها. فیلترهای پیشرفته ممکن است کامل نباشند.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: (!isMobile || !_mobileCardView)
                  ? DataTableWidget<Map<String, dynamic>>(
                      key: ValueKey('data_table_$_refreshCounter'),
                      config: DataTableConfig<Map<String, dynamic>>(
                        title: t.supportTickets,
                        subtitle: 'جدول پیشرفته برای جست‌وجو، فیلتر و مرتب‌سازی همه تیکت‌ها',
                        endpoint: '/api/v1/support/search',
                        columns: [
                          TextColumn(
                            'title',
                            t.ticketTitle,
                            sortable: true,
                            searchable: true,
                            width: ColumnWidth.large,
                          ),
                          TextColumn(
                            'category.name',
                            t.category,
                            sortable: true,
                            searchable: true,
                            width: ColumnWidth.medium,
                          ),
                          TextColumn(
                            'priority.name',
                            t.priority,
                            sortable: true,
                            searchable: true,
                            width: ColumnWidth.small,
                            filterType: ColumnFilterType.multiSelect,
                            filterOptions: _priorities
                                .map(
                                  (priority) => FilterOption(
                                    value: priority.name,
                                    label: priority.name,
                                    description: priority.description,
                                    color: priority.color != null ? _parseHexColor(priority.color!) : null,
                                  ),
                                )
                                .toList(),
                          ),
                          TextColumn(
                            'status.name',
                            t.status,
                            sortable: true,
                            searchable: true,
                            width: ColumnWidth.small,
                            filterType: ColumnFilterType.multiSelect,
                            filterOptions: _statuses
                                .map(
                                  (status) => FilterOption(
                                    value: status.name,
                                    label: status.name,
                                    description: status.description,
                                    color: status.color != null ? _parseHexColor(status.color!) : null,
                                  ),
                                )
                                .toList(),
                          ),
                          DateColumn(
                            'created_at',
                            t.ticketCreatedAt,
                            sortable: true,
                            searchable: true,
                            width: ColumnWidth.medium,
                            showTime: false,
                          ),
                          DateColumn(
                            'updated_at',
                            t.ticketUpdatedAt,
                            sortable: true,
                            searchable: true,
                            width: ColumnWidth.medium,
                            showTime: false,
                          ),
                        ],
                        searchFields: const ['title', 'description'],
                        filterFields: const ['title', 'category.name', 'priority.name', 'status.name', 'created_at'],
                        dateRangeField: 'created_at',
                        showSearch: true,
                        showFilters: true,
                        showColumnSearch: true,
                        showPagination: true,
                        showActiveFilters: true,
                        enableSorting: true,
                        enableGlobalSearch: true,
                        enableDateRangeFilter: true,
                        showRowNumbers: true,
                        enableRowSelection: true,
                        enableMultiRowSelection: true,
                        selectedRows: _selectedRows,
                        onRowSelectionChanged: (selectedRows) {
                          setState(() {
                            _selectedRows = selectedRows;
                          });
                        },
                        defaultPageSize: 20,
                        pageSizeOptions: const [10, 20, 50, 100],
                        showFiltersButton: false,
                        showClearFiltersButton: true,
                        emptyStateMessage: t.noTickets,
                        emptyStateWidget: _buildTicketsEmptyState(t, theme),
                        loadingMessage: t.loadingTickets,
                        errorMessage: t.ticketLoadingError,
                        enableHorizontalScroll: true,
                        minTableWidth: 720,
                        showBorder: true,
                        borderRadius: BorderRadius.circular(8),
                        padding: const EdgeInsets.all(8),
                        onRowTap: (ticketData) => _navigateToTicketDetail(ticketData),
                        customHeaderActions: [
                          Tooltip(
                            message: t.newTicket,
                            child: FilledButton.icon(
                              onPressed: _navigateToCreateTicket,
                              icon: const Icon(Icons.add),
                              label: Text(t.newTicket),
                            ),
                          ),
                        ],
                      ),
                      fromJson: (json) => json,
                      calendarController: widget.calendarController,
                    )
                  : _buildMobileTicketsList(t, theme),
            ),
          ],
        ),
      ),
    );
  }

}


