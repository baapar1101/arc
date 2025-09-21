import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
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
  
  // Refresh counter to force data table refresh
  int _refreshCounter = 0;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final statuses = await _supportService.getStatuses();
      final priorities = await _supportService.getPriorities();
      
      setState(() {
        _statuses = statuses;
        _priorities = priorities;
      });
    } catch (e) {
      // Handle error silently for now, filters will just be empty
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DataTableWidget<Map<String, dynamic>>(
                key: ValueKey('data_table_$_refreshCounter'),
                config: DataTableConfig<Map<String, dynamic>>(
                  title: t.supportTickets,
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
                      filterOptions: _priorities.map((priority) => FilterOption(
                        value: priority.name,
                        label: priority.name,
                        description: priority.description,
                        color: priority.color != null ? Color(int.parse(priority.color!.replaceFirst('#', '0xFF'))) : null,
                      )).toList(),
                    ),
                    TextColumn(
                      'status.name',
                      t.status,
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.small,
                      filterType: ColumnFilterType.multiSelect,
                      filterOptions: _statuses.map((status) => FilterOption(
                        value: status.name,
                        label: status.name,
                        description: status.description,
                        color: status.color != null ? Color(int.parse(status.color!.replaceFirst('#', '0xFF'))) : null,
                      )).toList(),
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
                  searchFields: ['title', 'description'],
                  filterFields: ['title', 'category.name', 'priority.name', 'status.name', 'created_at'],
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
                  loadingMessage: t.loadingTickets,
                  errorMessage: t.ticketLoadingError,
                  enableHorizontalScroll: true,
                  minTableWidth: 800,
                  showBorder: true,
                  borderRadius: BorderRadius.circular(8),
                  padding: const EdgeInsets.all(8),
                  onRowTap: (ticketData) => _navigateToTicketDetail(ticketData),
                  customHeaderActions: [
                    // دکمه ایجاد تیکت جدید
                    Tooltip(
                      message: t.newTicket,
                      child: IconButton(
                        onPressed: _navigateToCreateTicket,
                        icon: const Icon(Icons.add),
                        tooltip: t.newTicket,
                      ),
                    ),
                  ],
                ),
                fromJson: (json) => json,
                calendarController: widget.calendarController,
              ),
            ),
          ],
        ),
      ),
    );
  }

}


