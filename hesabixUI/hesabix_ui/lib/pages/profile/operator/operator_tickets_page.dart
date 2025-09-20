import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'operator_ticket_detail_page.dart';

class OperatorTicketsPage extends StatefulWidget {
  final CalendarController? calendarController;
  const OperatorTicketsPage({super.key, this.calendarController});

  @override
  State<OperatorTicketsPage> createState() => _OperatorTicketsPageState();
}

class _OperatorTicketsPageState extends State<OperatorTicketsPage> {
  Set<int> _selectedRows = <int>{};

  @override
  void initState() {
    super.initState();
  }


  void _navigateToTicketDetail(Map<String, dynamic> ticketData) {
    final ticket = SupportTicket.fromJson(ticketData);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OperatorTicketDetailPage(ticket: ticket),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  t.operatorPanel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DataTableWidget<Map<String, dynamic>>(
                config: DataTableConfig<Map<String, dynamic>>(
                  title: 'لیست تیکت‌های پشتیبانی - پنل اپراتور',
                  endpoint: '/api/v1/support/operator/tickets/search',
                  columns: [
                    TextColumn(
                      'title',
                      'عنوان',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.large,
                    ),
                    TextColumn(
                      'user.first_name',
                      'نام کاربر',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.medium,
                    ),
                    TextColumn(
                      'user.email',
                      'ایمیل کاربر',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.large,
                    ),
                    TextColumn(
                      'category.name',
                      'دسته‌بندی',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.medium,
                    ),
                    TextColumn(
                      'priority.name',
                      'اولویت',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.small,
                    ),
                    TextColumn(
                      'status.name',
                      'وضعیت',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.small,
                    ),
                    TextColumn(
                      'assigned_operator.first_name',
                      'اپراتور مسئول',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.medium,
                    ),
                    DateColumn(
                      'created_at',
                      'تاریخ ایجاد',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.medium,
                      showTime: false,
                    ),
                    DateColumn(
                      'updated_at',
                      'آخرین بروزرسانی',
                      sortable: true,
                      searchable: true,
                      width: ColumnWidth.medium,
                      showTime: false,
                    ),
                  ],
                  searchFields: ['title', 'description', 'user.first_name', 'user.last_name', 'user.email'],
                  filterFields: ['title', 'user.first_name', 'user.email', 'category.name', 'priority.name', 'status.name', 'assigned_operator.first_name', 'created_at'],
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
                  showRefreshButton: true,
                  showClearFiltersButton: true,
                  emptyStateMessage: 'هیچ تیکتی یافت نشد',
                  loadingMessage: 'در حال بارگذاری تیکت‌ها...',
                  errorMessage: 'خطا در بارگذاری تیکت‌ها',
                  enableHorizontalScroll: true,
                  minTableWidth: 1000,
                  showBorder: true,
                  borderRadius: BorderRadius.circular(8),
                  padding: const EdgeInsets.all(16),
                  onRowTap: (ticketData) => _navigateToTicketDetail(ticketData),
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
