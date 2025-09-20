import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'ticket_detail_page.dart';
import 'create_ticket_page.dart';

class SupportPage extends StatefulWidget {
  final CalendarController? calendarController;
  const SupportPage({super.key, this.calendarController});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  Set<int> _selectedRows = <int>{};

  @override
  void initState() {
    super.initState();
  }


  void _navigateToCreateTicket() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateTicketPage(),
      ),
    );
    
    if (result == true) {
      // Refresh will be handled by DataTableWidget
    }
  }

  void _navigateToTicketDetail(Map<String, dynamic> ticketData) {
    final ticket = SupportTicket.fromJson(ticketData);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TicketDetailPage(ticket: ticket),
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
                    ),
                    TextColumn(
                      'status.name',
                      t.status,
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.small,
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


