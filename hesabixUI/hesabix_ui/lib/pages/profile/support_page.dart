import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/services/saved_filters_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/models/saved_filter.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import '../../core/date_utils.dart';
import '../../widgets/jalali_date_picker.dart';
import '../../utils/date_formatters.dart';
import 'package:hesabix_ui/widgets/support/ticket_details_dialog.dart';
import 'create_ticket_page.dart';

// View modes enum
enum ViewMode { list, card, table }

// Quick filter types
enum QuickFilterType {
  all,
  open,
  waitingForResponse,
  resolved,
  today,
  thisWeek,
  thisMonth,
  highPriority,
}

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
  List<SupportCategory> _categories = [];
  bool _metadataLoading = false;
  String? _metadataError;
  
  // Refresh counter to force data table refresh
  int _refreshCounter = 0;

  // Mobile state
  bool _ticketsLoading = false;
  String? _ticketsError;
  bool _ticketsEverLoaded = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<SupportTicket> _tickets = <SupportTicket>[];
  int _ticketPage = 1;
  final int _ticketPageSize = 20;
  int _ticketsTotal = 0;
  bool _hasMoreTickets = true;
  
  // Filters
  int? _selectedStatusId;
  int? _selectedPriorityId;
  int? _selectedCategoryId;
  QuickFilterType? _activeQuickFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool? _lastMessageFromUser; // null = همه, true = از کاربر, false = از اپراتور
  bool? _isOpen; // null = همه, true = باز, false = بسته
  
  // View mode
  ViewMode _viewMode = ViewMode.list;
  
  // Saved filters
  List<SavedFilter> _savedFilters = [];
  SavedFilter? _selectedSavedFilter;
  
  // Grouping
  bool _groupByStatus = false;
  Map<String, List<SupportTicket>>? _groupedTickets;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _loadSavedFilters();
  }

  Future<void> _loadMetadata() async {
    setState(() {
      _metadataLoading = true;
      _metadataError = null;
    });
    try {
      final statuses = await _supportService.getStatuses();
      final priorities = await _supportService.getPriorities();
      final categories = await _supportService.getCategories();
      
      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _priorities = priorities;
        _categories = categories.where((c) => c.isActive).toList();
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

  Future<void> _loadSavedFilters() async {
    try {
      final filters = await SavedFiltersService.getSavedFilters(isOperator: false);
      if (!mounted) return;
      setState(() {
        _savedFilters = filters;
      });
    } catch (e) {
      debugPrint('Error loading saved filters: $e');
    }
  }

  void _navigateToCreateTicket() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CreateTicketPage(),
    );
    
    if (result == true) {
      setState(() {
        _refreshCounter++;
        if (_ticketsEverLoaded) {
          _ticketPage = 1;
          _hasMoreTickets = true;
          _loadTickets(showSpinner: false);
        }
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
        calendarController: widget.calendarController,
        onTicketUpdated: () {
          setState(() {
            _refreshCounter++;
            if (_ticketsEverLoaded) {
              _ticketPage = 1;
              _hasMoreTickets = true;
              _loadTickets(showSpinner: false);
            }
          });
        },
      ),
    );
  }

  List<FilterItem> _buildFilters() {
    final filters = <FilterItem>[];
    
    if (_selectedStatusId != null) {
      filters.add(FilterItem(property: 'status_id', operator: '==', value: _selectedStatusId));
    }
    
    if (_selectedPriorityId != null) {
      filters.add(FilterItem(property: 'priority_id', operator: '==', value: _selectedPriorityId));
    }
    
    if (_selectedCategoryId != null) {
      filters.add(FilterItem(property: 'category_id', operator: '==', value: _selectedCategoryId));
    }
    
    if (_dateFrom != null && _dateTo != null) {
      final start = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
      final endExclusive = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day)
          .add(const Duration(days: 1));
      filters.add(FilterItem(property: 'created_at', operator: '>=', value: start.toIso8601String()));
      filters.add(FilterItem(property: 'created_at', operator: '<', value: endExclusive.toIso8601String()));
    }
    
    if (_lastMessageFromUser != null) {
      filters.add(FilterItem(
        property: 'last_message_from_user',
        operator: '==',
        value: _lastMessageFromUser == true ? 'true' : 'false',
      ));
    }
    
    if (_isOpen != null) {
      final openStatusIds = _statuses.where((s) => !s.isFinal).map((s) => s.id).toList();
      if (_isOpen == true) {
        filters.add(FilterItem(property: 'status_id', operator: 'in', value: openStatusIds));
      } else {
        final closedStatusIds = _statuses.where((s) => s.isFinal).map((s) => s.id).toList();
        filters.add(FilterItem(property: 'status_id', operator: 'in', value: closedStatusIds));
      }
    }
    
    return filters;
  }

  void _applyQuickFilter(QuickFilterType filterType) {
    setState(() {
      _activeQuickFilter = _activeQuickFilter == filterType ? null : filterType;
      
      // Reset other filters when applying quick filter
      if (_activeQuickFilter != null) {
        _selectedStatusId = null;
        _selectedPriorityId = null;
        _selectedCategoryId = null;
        _dateFrom = null;
        _dateTo = null;
        _lastMessageFromUser = null;
        _isOpen = null;
        _selectedSavedFilter = null;
      }
      
      // Apply quick filter logic
      switch (_activeQuickFilter) {
        case QuickFilterType.all:
          // No filters
          break;
        case QuickFilterType.open:
          final openStatus = _statuses.firstWhere(
            (s) => s.name.toLowerCase().contains('باز') || s.name.toLowerCase().contains('open'),
            orElse: () => _statuses.firstWhere(
              (s) => !s.isFinal,
              orElse: () => _statuses.first,
            ),
          );
          _selectedStatusId = openStatus.id;
          break;
        case QuickFilterType.waitingForResponse:
          _lastMessageFromUser = true;
          break;
        case QuickFilterType.resolved:
          final resolvedStatus = _statuses.firstWhere(
            (s) => s.name.toLowerCase().contains('حل') || s.name.toLowerCase().contains('resolved'),
            orElse: () => _statuses.firstWhere(
              (s) => s.isFinal,
              orElse: () => _statuses.last,
            ),
          );
          _selectedStatusId = resolvedStatus.id;
          break;
        case QuickFilterType.today:
          final now = DateTime.now();
          _dateFrom = DateTime(now.year, now.month, now.day);
          _dateTo = DateTime(now.year, now.month, now.day);
          break;
        case QuickFilterType.thisWeek:
          final now = DateTime.now();
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          _dateFrom = DateTime(weekStart.year, weekStart.month, weekStart.day);
          _dateTo = DateTime(now.year, now.month, now.day);
          break;
        case QuickFilterType.thisMonth:
          final now = DateTime.now();
          _dateFrom = DateTime(now.year, now.month, 1);
          _dateTo = DateTime(now.year, now.month, now.day);
          break;
        case QuickFilterType.highPriority:
          final highPriority = _priorities.firstWhere(
            (p) => p.name.toLowerCase().contains('بالا') || p.name.toLowerCase().contains('high'),
            orElse: () => _priorities.first,
          );
          _selectedPriorityId = highPriority.id;
          break;
        case null:
          break;
      }
      
      _ticketPage = 1;
      _hasMoreTickets = true;
    });
    _loadTickets(showSpinner: true);
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
      final filters = _buildFilters();
      final query = QueryInfo(
        search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        searchFields: const ['title', 'description'],
        sortBy: 'created_at',
        sortDesc: true,
        take: _ticketPageSize,
        skip: (_ticketPage - 1) * _ticketPageSize,
        filters: filters.isEmpty ? null : filters,
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
        _groupedTickets = _groupByStatus ? _groupTicketsByStatus(_tickets) : null;
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

  Map<String, List<SupportTicket>> _groupTicketsByStatus(List<SupportTicket> tickets) {
    final grouped = <String, List<SupportTicket>>{};
    for (final ticket in tickets) {
      final statusName = _statusLabelFor(ticket);
      if (!grouped.containsKey(statusName)) {
        grouped[statusName] = [];
      }
      grouped[statusName]!.add(ticket);
    }
    return grouped;
  }

  void _clearAllFilters() {
    setState(() {
      _selectedStatusId = null;
      _selectedPriorityId = null;
      _selectedCategoryId = null;
      _activeQuickFilter = null;
      _dateFrom = null;
      _dateTo = null;
      _lastMessageFromUser = null;
      _isOpen = null;
      _selectedSavedFilter = null;
      _ticketPage = 1;
      _hasMoreTickets = true;
    });
    _loadTickets(showSpinner: true);
  }

  String _statusLabelFor(SupportTicket ticket) {
    final status = _statuses.where((s) => s.id == ticket.statusId).cast<SupportStatus?>().firstWhere(
          (s) => s != null,
          orElse: () => null,
        );
    return status?.name ?? 'نامشخص';
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
    return pr?.name ?? 'نامشخص';
  }

  Color? _priorityColorFor(SupportTicket ticket) {
    final pr = _priorities.where((p) => p.id == ticket.priorityId).cast<SupportPriority?>().firstWhere(
          (p) => p != null,
          orElse: () => null,
        );
    if (pr?.color == null) return null;
    return _parseHexColor(pr!.color!);
  }

  String _categoryLabelFor(SupportTicket ticket) {
    final cat = _categories.where((c) => c.id == ticket.categoryId).cast<SupportCategory?>().firstWhere(
          (c) => c != null,
          orElse: () => null,
        );
    return cat?.name ?? 'نامشخص';
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
      final isJalali = widget.calendarController?.isJalali ??
          ApiClient.getCalendarController()?.isJalali ??
          true;
      return HesabixDateUtils.formatDateTime(dateTime, isJalali);
    } catch (_) {
      return DateFormatters.formatServerDateTime(dateTime.toIso8601String());
    }
  }

  int _getOpenTicketsCount() {
    final openStatusIds = _statuses.where((s) => !s.isFinal).map((s) => s.id).toSet();
    return _tickets.where((t) => openStatusIds.contains(t.statusId)).length;
  }

  Widget _buildMobileHeader(AppLocalizations t, ThemeData theme, bool isMobile) {
    final openCount = _getOpenTicketsCount();
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
            if (openCount > 0)
              Badge(
                label: Text('$openCount'),
                backgroundColor: theme.colorScheme.error,
                child: Icon(
                  Icons.support_agent,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isMobile
              ? 'مدیریت و پیگیری درخواست‌های پشتیبانی خود'
              : 'در این بخش می‌توانید همه تیکت‌های پشتیبانی خود را مشاهده کنید، جست‌وجو و بر اساس وضعیت و اولویت فیلتر کنید.',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'هنوز هیچ تیکتی ثبت نکرده‌اید. برای دریافت کمک از تیم پشتیبانی، اولین تیکت خود را ایجاد کنید.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
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

  Widget _buildQuickFilters(AppLocalizations t, ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildQuickFilterChip(t, theme, QuickFilterType.all, 'همه', Icons.list),
          const SizedBox(width: 8),
          _buildQuickFilterChip(t, theme, QuickFilterType.open, 'تیکت‌های باز', Icons.lock_open),
          const SizedBox(width: 8),
          _buildQuickFilterChip(t, theme, QuickFilterType.waitingForResponse, 'در انتظار پاسخ', Icons.schedule),
          const SizedBox(width: 8),
          _buildQuickFilterChip(t, theme, QuickFilterType.resolved, 'حل شده', Icons.check_circle),
          const SizedBox(width: 8),
          _buildQuickFilterChip(t, theme, QuickFilterType.today, 'امروز', Icons.today),
          const SizedBox(width: 8),
          _buildQuickFilterChip(t, theme, QuickFilterType.thisWeek, 'این هفته', Icons.calendar_view_week),
          const SizedBox(width: 8),
          _buildQuickFilterChip(t, theme, QuickFilterType.thisMonth, 'این ماه', Icons.calendar_month),
          const SizedBox(width: 8),
          _buildQuickFilterChip(t, theme, QuickFilterType.highPriority, 'اولویت بالا', Icons.flag),
        ],
      ),
    );
  }

  Widget _buildQuickFilterChip(AppLocalizations t, ThemeData theme, QuickFilterType type, String label, IconData icon) {
    final isSelected = _activeQuickFilter == type;
    return FilterChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _applyQuickFilter(type),
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.onPrimaryContainer,
    );
  }

  Widget _buildSavedFilters(AppLocalizations t, ThemeData theme) {
    if (_savedFilters.isEmpty) return const SizedBox.shrink();
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ..._savedFilters.map((filter) {
            final isSelected = _selectedSavedFilter?.name == filter.name;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(filter.name),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedSavedFilter = filter;
                      // Apply saved filter
                      // TODO: Apply filter logic
                    } else {
                      _selectedSavedFilter = null;
                    }
                    _ticketPage = 1;
                    _hasMoreTickets = true;
                  });
                  _loadTickets(showSpinner: true);
                },
                deleteIcon: Icon(Icons.close, size: 18),
                onDeleted: () => _deleteSavedFilter(filter.name),
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'ذخیره فیلتر فعلی',
            onPressed: _saveCurrentFilter,
          ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentFilter() async {
    if (!mounted) return;
    
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ذخیره فیلتر'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'نام فیلتر',
            hintText: 'مثلاً: تیکت‌های باز',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('لغو'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final filters = <String, dynamic>{};
        if (_selectedStatusId != null) filters['status_id'] = _selectedStatusId;
        if (_selectedPriorityId != null) filters['priority_id'] = _selectedPriorityId;
        if (_selectedCategoryId != null) filters['category_id'] = _selectedCategoryId;
        if (_dateFrom != null && _dateTo != null) {
          filters['date_from'] = _dateFrom!.toIso8601String();
          filters['date_to'] = _dateTo!.toIso8601String();
        }
        
        final filter = SavedFilter(
          name: result,
          filters: filters,
        );
        
        await SavedFiltersService.saveFilter(filter, isOperator: false);
        await _loadSavedFilters();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فیلتر با موفقیت ذخیره شد')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطا در ذخیره فیلتر: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _deleteSavedFilter(String filterName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف فیلتر'),
        content: Text('آیا مطمئن هستید که می‌خواهید فیلتر "$filterName" را حذف کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لغو'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SavedFiltersService.deleteFilter(filterName, isOperator: false);
      await _loadSavedFilters();
      
      if (_selectedSavedFilter?.name == filterName) {
        setState(() {
          _selectedSavedFilter = null;
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فیلتر حذف شد')),
        );
      }
    }
  }

  void _showMobileFiltersBottomSheet(AppLocalizations t, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _buildMobileFiltersBottomSheet(
          t, theme, scrollController,
        ),
      ),
    );
  }

  Widget _buildMobileFiltersBottomSheet(
    AppLocalizations t,
    ThemeData theme,
    ScrollController scrollController,
  ) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.filter_list, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'فیلتر تیکت‌ها',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
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
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              // Category filter
              if (_categories.isNotEmpty) ...[
                Text(
                  t.category,
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
                        selected: _selectedCategoryId == null,
                        onSelected: (_) {
                          setState(() {
                            _selectedCategoryId = null;
                            _ticketPage = 1;
                            _hasMoreTickets = true;
                          });
                          _loadTickets(showSpinner: true);
                        },
                      ),
                      const SizedBox(width: 6),
                      ..._categories.map((c) {
                        final selected = _selectedCategoryId == c.id;
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: FilterChip(
                            label: Text(c.name),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                _selectedCategoryId = selected ? null : c.id;
                                _ticketPage = 1;
                                _hasMoreTickets = true;
                              });
                              _loadTickets(showSpinner: true);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Status filter
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
                                    child: Icon(Icons.circle, size: 10, color: color),
                                  )
                                : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Priority filter
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
                                    child: Icon(Icons.flag, size: 14, color: color),
                                  )
                                : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Date range filter
              Text(
                'بازه زمانی',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final date = await showAdaptiveDatePicker(
                          context: context,
                          calendarController: widget.calendarController,
                          initialDate: _dateFrom ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _dateFrom = date;
                            _ticketPage = 1;
                            _hasMoreTickets = true;
                          });
                          _loadTickets(showSpinner: true);
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_dateFrom != null ? _formatTicketDate(_dateFrom!) : 'از تاریخ'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final date = await showAdaptiveDatePicker(
                          context: context,
                          calendarController: widget.calendarController,
                          initialDate: _dateTo ?? DateTime.now(),
                          firstDate: _dateFrom ?? DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _dateTo = date;
                            _ticketPage = 1;
                            _hasMoreTickets = true;
                          });
                          _loadTickets(showSpinner: true);
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_dateTo != null ? _formatTicketDate(_dateTo!) : 'تا تاریخ'),
                    ),
                  ),
                ],
              ),
              if (_dateFrom != null || _dateTo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _dateFrom = null;
                        _dateTo = null;
                        _ticketPage = 1;
                        _hasMoreTickets = true;
                      });
                      _loadTickets(showSpinner: true);
                    },
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('پاک کردن تاریخ'),
                  ),
                ),
              const SizedBox(height: 16),
              // Advanced filters
              Text(
                'فیلترهای پیشرفته',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('آخرین پیام از کاربر'),
                    selected: _lastMessageFromUser == true,
                    onSelected: (selected) {
                      setState(() {
                        _lastMessageFromUser = selected ? true : null;
                        _ticketPage = 1;
                        _hasMoreTickets = true;
                      });
                      _loadTickets(showSpinner: true);
                    },
                  ),
                  FilterChip(
                    label: const Text('تیکت‌های باز'),
                    selected: _isOpen == true,
                    onSelected: (selected) {
                      setState(() {
                        _isOpen = selected ? true : null;
                        _ticketPage = 1;
                        _hasMoreTickets = true;
                      });
                      _loadTickets(showSpinner: true);
                    },
                  ),
                  FilterChip(
                    label: const Text('تیکت‌های بسته'),
                    selected: _isOpen == false,
                    onSelected: (selected) {
                      setState(() {
                        _isOpen = selected ? false : null;
                        _ticketPage = 1;
                        _hasMoreTickets = true;
                      });
                      _loadTickets(showSpinner: true);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _clearAllFilters();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.clear_all),
                    label: const Text('پاک کردن همه'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _ticketPage = 1;
                        _hasMoreTickets = true;
                      });
                      _loadTickets(showSpinner: true);
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('اعمال فیلتر'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _ticketPage = 1;
        _hasMoreTickets = true;
      });
      _loadTickets(showSpinner: false);
    });
  }

  Widget _buildMobileFilters(AppLocalizations t, ThemeData theme) {
    final activeFiltersCount = [
      _selectedStatusId != null,
      _selectedPriorityId != null,
      _selectedCategoryId != null,
      _dateFrom != null || _dateTo != null,
      _lastMessageFromUser != null,
      _isOpen != null,
    ].where((x) => x).length;
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (activeFiltersCount > 0)
          ActionChip(
            avatar: const Icon(Icons.filter_alt, size: 18),
            label: Text('$activeFiltersCount فیلتر فعال'),
            onPressed: _clearAllFilters,
          ),
        ActionChip(
          avatar: const Icon(Icons.tune, size: 18),
          label: const Text('فیلترهای بیشتر'),
          onPressed: () => _showMobileFiltersBottomSheet(t, theme),
        ),
      ],
    );
  }

  Widget _buildMobileSearch(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: t.search,
          hintText: 'جست‌وجو در عنوان و توضیحات تیکت‌ها...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchDebounce?.cancel();
                      _ticketPage = 1;
                      _hasMoreTickets = true;
                    });
                    _loadTickets(showSpinner: false);
                  },
                ),
        ),
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
        onSubmitted: (_) {
          _searchDebounce?.cancel();
          setState(() {
            _ticketPage = 1;
            _hasMoreTickets = true;
          });
          _loadTickets();
        },
      ),
    );
  }

  Widget _buildViewModeSelector(AppLocalizations t, ThemeData theme) {
    return SegmentedButton<ViewMode>(
      segments: const [
        ButtonSegment(value: ViewMode.list, icon: Icon(Icons.list), label: Text('لیست')),
        ButtonSegment(value: ViewMode.card, icon: Icon(Icons.view_module), label: Text('کارت')),
      ],
      selected: {_viewMode},
      onSelectionChanged: (Set<ViewMode> newSelection) {
        setState(() {
          _viewMode = newSelection.first;
        });
      },
    );
  }

  Widget _buildTicketCard(SupportTicket ticket, AppLocalizations t, ThemeData theme) {
    final statusLabel = _statusLabelFor(ticket);
    final statusColor = _statusColorFor(ticket) ?? theme.colorScheme.primary;
    final priorityLabel = _priorityLabelFor(ticket);
    final priorityColor = _priorityColorFor(ticket) ?? theme.colorScheme.secondary;
    final categoryLabel = _categoryLabelFor(ticket);
    final updatedLabel = _formatTicketDate(ticket.updatedAt);
    final createdLabel = _formatTicketDate(ticket.createdAt);

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (categoryLabel.isNotEmpty && categoryLabel != 'نامشخص')
                          Chip(
                            label: Text(
                              categoryLabel,
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: _chipBackground(statusColor),
                    side: BorderSide(color: statusColor.withOpacity(0.5)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flag, size: 16, color: priorityColor),
                      const SizedBox(width: 4),
                      Text(
                        priorityLabel,
                        style: theme.textTheme.bodySmall?.copyWith(color: priorityColor),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'بروزرسانی: $updatedLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'ایجاد: $createdLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileTicketsList(AppLocalizations t, ThemeData theme) {
    if (_ticketsLoading && _tickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ticketsError != null && _tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
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
    if (tickets.isEmpty && !_ticketsLoading) {
      return _buildTicketsEmptyState(t, theme);
    }

    Widget listContent;
    
    if (_groupByStatus && _groupedTickets != null) {
      // Grouped view
      listContent = ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 80),
        itemCount: _groupedTickets!.length,
        itemBuilder: (context, index) {
          final entry = _groupedTickets!.entries.elementAt(index);
          final statusName = entry.key;
          final statusTickets = entry.value;
          
          return ExpansionTile(
            title: Text('$statusName (${statusTickets.length})'),
            children: statusTickets.map((ticket) => _buildTicketCard(ticket, t, theme)).toList(),
          );
        },
      );
    } else {
      // Normal list view
      listContent = ListView.builder(
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
          return _viewMode == ViewMode.card
              ? _buildTicketCard(ticket, t, theme)
              : _buildTicketCard(ticket, t, theme); // For now, both use card style
        },
      );
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
        child: listContent,
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 768;

    if (isMobile && !_ticketsEverLoaded && !_ticketsLoading) {
      _ticketsEverLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ticketPage = 1;
        _hasMoreTickets = true;
        _loadTickets();
      });
    }

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: isMobile
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
            const SizedBox(height: 16),
            // Quick Filters
            _buildQuickFilters(t, theme),
            const SizedBox(height: 8),
            // Saved Filters
            _buildSavedFilters(t, theme),
            if (isMobile) ...[
              const SizedBox(height: 12),
              _buildMobileSearch(t),
              const SizedBox(height: 12),
              _buildMobileFilters(t, theme),
              const SizedBox(height: 8),
              // View mode selector
              Row(
                children: [
                  Expanded(child: _buildViewModeSelector(t, theme)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(_groupByStatus ? Icons.view_list : Icons.view_module),
                    tooltip: _groupByStatus ? 'نمایش عادی' : 'گروه\u200cبندی بر اساس وضعیت',
                    onPressed: () {
                      setState(() {
                        _groupByStatus = !_groupByStatus;
                        if (_groupByStatus) {
                          _groupedTickets = _groupTicketsByStatus(_tickets);
                        } else {
                          _groupedTickets = null;
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
            if (!isMobile) const SizedBox(height: 8),
            if (_metadataError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'امکان بارگذاری لیست فیلترها وجود ندارد. لطفاً صفحه را رفرش کنید.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: !isMobile
                  ? SingleChildScrollView(
                      child: DataTableWidget<Map<String, dynamic>>(
                        key: ValueKey('data_table_$_refreshCounter'),
                        config: DataTableConfig<Map<String, dynamic>>(
                        title: null,
                        subtitle: null,
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
                            filterType: ColumnFilterType.multiSelect,
                            filterOptions: _categories
                                .map(
                                  (category) => FilterOption(
                                    value: category.name,
                                    label: category.name,
                                    description: category.description,
                                  ),
                                )
                                .toList(),
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
                        expandBodyHeightToFitRows: true,
                        ),
                        fromJson: (json) => json,
                        calendarController: widget.calendarController,
                      ),
                    )
                  : _buildMobileTicketsList(t, theme),
            ),
          ],
        ),
      ),
    );
  }
}
