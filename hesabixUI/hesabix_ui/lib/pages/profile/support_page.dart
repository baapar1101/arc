import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/services/support_tickets_public_config.dart';
import 'package:hesabix_ui/services/saved_filters_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/models/saved_filter.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import '../../utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/support/ticket_details_dialog.dart';
import 'package:hesabix_ui/widgets/support/ticket_detail_view.dart';
import 'package:hesabix_ui/widgets/support/ticket_csat_dialog.dart';
import 'package:hesabix_ui/widgets/support/ticket_card.dart';
import 'package:hesabix_ui/widgets/support/user_ticket_list_item.dart';
import 'package:hesabix_ui/widgets/support/user_support_page_header.dart';
import 'package:hesabix_ui/widgets/support/user_support_tab_bar.dart';
import 'package:hesabix_ui/widgets/support/user_support_types.dart';
import 'create_ticket_page.dart';

class SupportPage extends StatefulWidget {
  final CalendarController? calendarController;
  const SupportPage({super.key, this.calendarController});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> with WidgetsBindingObserver {
  final SupportService _supportService = SupportService(ApiClient());
  bool _supportGateResolved = false;
  SupportTicketsPublicConfig _supportPublic = const SupportTicketsPublicConfig();
  List<SupportStatus> _statuses = [];
  List<SupportPriority> _priorities = [];
  List<SupportCategory> _categories = [];
  bool _metadataLoading = false;
  String? _metadataError;
  
  // Refresh counter to force list refresh after actions
  int _refreshCounter = 0;

  // Ticket list state
  bool _ticketsLoading = false;
  String? _ticketsError;
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
  UserSupportTab _activeTab = UserSupportTab.all;
  
  // View mode
  UserSupportViewMode _viewMode = UserSupportViewMode.compact;
  
  // Saved filters
  List<SavedFilter> _savedFilters = [];
  SavedFilter? _selectedSavedFilter;
  
  // Grouping
  bool _groupByStatus = false;
  Map<String, List<SupportTicket>>? _groupedTickets;

  SupportTicket? _selectedTicket;
  bool _selectedTicketLoading = false;
  int? _selectedTicketId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolveSupportAvailability();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resolveSupportAvailability());
    }
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _resolveSupportAvailability() async {
    final cfg = await SupportTicketsPublicConfig.fetch(ApiClient());
    if (!mounted) return;
    setState(() {
      _supportPublic = cfg;
      _supportGateResolved = true;
    });
    if (cfg.enabledForUsers) {
      _loadMetadata();
      _loadSavedFilters();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ticketPage = 1;
        _hasMoreTickets = true;
        _loadTickets();
      });
    } else if (mounted) {
      setState(() {
        _metadataLoading = false;
      });
    }
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
        _metadataError = ErrorExtractor.forContext(e, context);
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
    final width = MediaQuery.of(context).size.width;
    if (width >= 768) {
      final result = await context.push<bool>('/user/profile/support/new');
      if (result == true && mounted) {
        setState(() {
          _refreshCounter++;
          _ticketPage = 1;
          _hasMoreTickets = true;
          _loadTickets(showSpinner: false);
        });
      }
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CreateTicketPage(),
    );
    
    if (result == true) {
      setState(() {
        _refreshCounter++;
        _ticketPage = 1;
        _hasMoreTickets = true;
        _loadTickets(showSpinner: false);
      });
    }
  }

  void _navigateToTicketDetail(Map<String, dynamic> ticketData) {
    final ticketId = ticketData['id'];
    if (ticketId is! int) return;

    if (MediaQuery.of(context).size.width >= 960) {
      _openTicketInSplitView(ticketId, ticketData);
      return;
    }

    if (MediaQuery.of(context).size.width >= 768) {
      context.push('/user/profile/support/tickets/$ticketId');
      return;
    }

    final ticket = SupportTicket.fromJson(ticketData);
    showDialog(
      context: context,
      builder: (context) => TicketDetailsDialog(
        ticket: ticket,
        isOperator: false,
        calendarController: widget.calendarController,
        onTicketUpdated: _refreshTicketList,
        onRequestCsat: () => _maybeShowCsat(ticketId),
      ),
    );
  }

  void _refreshTicketList() {
    setState(() {
      _refreshCounter++;
      _ticketPage = 1;
      _hasMoreTickets = true;
    });
    _loadTickets(showSpinner: false);
  }

  Future<void> _openTicketInSplitView(int ticketId, [Map<String, dynamic>? row]) async {
    setState(() {
      _selectedTicketId = ticketId;
      _selectedTicket = row != null ? SupportTicket.fromJson(row) : null;
      _selectedTicketLoading = true;
    });
    try {
      final ticket = await _supportService.getTicket(ticketId);
      if (!mounted) return;
      setState(() {
        _selectedTicket = ticket;
        _selectedTicketLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _selectedTicketLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
      );
    }
  }

  Future<void> _maybeShowCsat(int ticketId) async {
    final ok = await TicketCsatDialog.show(context, ticketId);
    if (ok == true) _refreshTicketList();
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

    switch (_activeTab) {
      case UserSupportTab.open:
        final openIds = _statuses.where((s) => !s.isFinal).map((s) => s.id).toList();
        if (openIds.isNotEmpty) {
          filters.add(FilterItem(property: 'status_id', operator: 'in', value: openIds));
        }
        break;
      case UserSupportTab.unread:
        filters.add(const FilterItem(property: 'is_unread_for_user', operator: '==', value: 'true'));
        break;
      case UserSupportTab.waiting:
        filters.add(const FilterItem(property: 'last_message_from_user', operator: '==', value: 'true'));
        break;
      case UserSupportTab.resolved:
        final closedIds = _statuses.where((s) => s.isFinal).map((s) => s.id).toList();
        if (closedIds.isNotEmpty) {
          filters.add(FilterItem(property: 'status_id', operator: 'in', value: closedIds));
        }
        break;
      case UserSupportTab.all:
        break;
    }
    
    return filters;
  }

  void _onTabChanged(UserSupportTab tab) {
    setState(() {
      _activeTab = tab;
      _selectedStatusId = null;
      _selectedPriorityId = null;
      _selectedCategoryId = null;
      _selectedSavedFilter = null;
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
        _ticketsError = ErrorExtractor.forContext(e, context);
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
      _activeTab = UserSupportTab.all;
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

  int _getOpenTicketsCount() {
    final openStatusIds = _statuses.where((s) => !s.isFinal).map((s) => s.id).toSet();
    return _tickets.where((t) => openStatusIds.contains(t.statusId)).length;
  }

  Widget _buildPageHeader(AppLocalizations t, ThemeData theme, bool isMobile) {
    return UserSupportPageHeader(
      t: t,
      openCount: _getOpenTicketsCount(),
      totalCount: _ticketsTotal,
      showCreateButton: !isMobile,
      onCreateTicket: _navigateToCreateTicket,
    );
  }

  Widget _buildTicketsEmptyState(AppLocalizations t, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.support_agent_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              t.noTickets,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'هنوز تیکتی ثبت نکرده‌اید. برای دریافت کمک از تیم پشتیبانی، اولین تیکت خود را ایجاد کنید.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _navigateToCreateTicket,
              icon: const Icon(Icons.add_rounded),
              label: Text(t.newTicket),
            ),
          ],
        ),
      ),
    );
  }

  int _activeFilterCount() {
    return [
      _selectedStatusId != null,
      _selectedPriorityId != null,
      _selectedCategoryId != null,
    ].where((x) => x).length;
  }

  Widget _buildInboxToolbar(AppLocalizations t, ThemeData theme) {
    final filterCount = _activeFilterCount();

    return Row(
      children: [
        Expanded(
          child: SearchBar(
            controller: _searchController,
            hintText: 'جست‌وجو در عنوان و توضیحات…',
            leading: const Icon(Icons.search_rounded, size: 20),
            trailing: [
              ListenableBuilder(
                listenable: _searchController,
                builder: (context, _) {
                  if (_searchController.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchDebounce?.cancel();
                        _ticketPage = 1;
                        _hasMoreTickets = true;
                      });
                      _loadTickets(showSpinner: false);
                    },
                  );
                },
              ),
            ],
            onChanged: _onSearchChanged,
            onSubmitted: (_) {
              _searchDebounce?.cancel();
              setState(() {
                _ticketPage = 1;
                _hasMoreTickets = true;
              });
              _loadTickets();
            },
            elevation: WidgetStateProperty.all(0),
            backgroundColor: WidgetStateProperty.all(theme.colorScheme.surfaceContainerHighest),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
          ),
        ),
        const SizedBox(width: 8),
        Badge(
          isLabelVisible: filterCount > 0,
          label: Text('$filterCount'),
          child: IconButton.filledTonal(
            onPressed: () => _showMobileFiltersBottomSheet(t, theme),
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'فیلترها',
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () {
            setState(() {
              _viewMode = _viewMode == UserSupportViewMode.compact
                  ? UserSupportViewMode.card
                  : UserSupportViewMode.compact;
            });
          },
          icon: Icon(
            _viewMode == UserSupportViewMode.compact
                ? Icons.grid_view_rounded
                : Icons.view_list_rounded,
          ),
          tooltip: _viewMode == UserSupportViewMode.compact ? 'نمای کارت' : 'نمای فشرده',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'گزینه‌های بیشتر',
          onSelected: (value) {
            switch (value) {
              case 'group':
                setState(() {
                  _groupByStatus = !_groupByStatus;
                  _groupedTickets = _groupByStatus ? _groupTicketsByStatus(_tickets) : null;
                });
              case 'clear_filters':
                _clearAllFilters();
              case 'save_filter':
                _saveCurrentFilter();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'group',
              child: Row(
                children: [
                  Icon(
                    _groupByStatus ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Text('گروه‌بندی بر اساس وضعیت'),
                ],
              ),
            ),
            if (_activeFilterCount() > 0)
              const PopupMenuItem(
                value: 'clear_filters',
                child: Row(
                  children: [
                    Icon(Icons.filter_alt_off_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('پاک کردن فیلترها'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'save_filter',
              child: Row(
                children: [
                  Icon(Icons.bookmark_add_outlined, size: 20),
                  SizedBox(width: 10),
                  Text('ذخیره فیلتر فعلی'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSavedFiltersRow(AppLocalizations t, ThemeData theme) {
    if (_savedFilters.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Icon(Icons.bookmark_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          ..._savedFilters.map((filter) {
            final isSelected = _selectedSavedFilter?.name == filter.name;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: InputChip(
                label: Text(filter.name, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                visualDensity: VisualDensity.compact,
                onSelected: (selected) {
                  setState(() {
                    _selectedSavedFilter = selected ? filter : null;
                    _ticketPage = 1;
                    _hasMoreTickets = true;
                  });
                  _loadTickets(showSpinner: true);
                },
                onDeleted: () => _deleteSavedFilter(filter.name),
              ),
            );
          }),
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
        if (_selectedCategoryId != null) filters['category_id'] = _selectedCategoryId;
        
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
            SnackBar(
              content: Text(
                'خطا در ذخیره فیلتر: ${ErrorExtractor.forContext(e, context)}',
              ),
            ),
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

  Widget _buildTicketCard(SupportTicket ticket, AppLocalizations t, ThemeData theme) {
    return TicketCard(
      ticket: ticket,
      calendarController: widget.calendarController,
      onTap: () => _navigateToTicketDetail(ticket.toJson()),
    );
  }

  Widget _buildTicketsPanel(AppLocalizations t, ThemeData theme, Widget list) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: list,
    );
  }

  Widget _buildUserSplitDetail() {
    final theme = Theme.of(context);
    if (_selectedTicketId == null) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text('تیکتی انتخاب نشده', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'از لیست سمت راست یک تیکت را انتخاب کنید',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    if (_selectedTicketLoading || _selectedTicket == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return TicketDetailView(
      key: ValueKey(_selectedTicket!.id),
      ticket: _selectedTicket!,
      isOperator: false,
      calendarController: widget.calendarController,
      displayMode: TicketDetailDisplayMode.embedded,
      onTicketUpdated: () {
        _refreshTicketList();
        _openTicketInSplitView(_selectedTicket!.id);
      },
      onRequestCsat: () => _maybeShowCsat(_selectedTicket!.id),
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
          
          return Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                '$statusName (${statusTickets.length})',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              children: statusTickets.map((ticket) => _buildTicketCard(ticket, t, theme)).toList(),
            ),
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
          return _viewMode == UserSupportViewMode.card
              ? _buildTicketCard(ticket, t, theme)
              : UserTicketListItem(
                  ticket: ticket,
                  isSelected: ticket.id == _selectedTicketId,
                  calendarController: widget.calendarController,
                  onTap: () => _navigateToTicketDetail(ticket.toJson()),
                );
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
        key: ValueKey('tickets_$_refreshCounter'),
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
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 768;

    if (!_supportGateResolved) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_supportPublic.enabledForUsers) {
      final bodyText = _supportPublic.disabledMessage.trim().isEmpty
          ? t.supportTicketsUnavailableBody
          : _supportPublic.disabledMessage;
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.support_agent_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    t.support,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    bodyText,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: _navigateToCreateTicket,
              icon: const Icon(Icons.add_rounded),
              label: Text(t.newTicket),
              elevation: 2,
            )
          : null,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPageHeader(t, theme, isMobile),
            const SizedBox(height: 16),
            UserSupportTabBar(
              activeTab: _activeTab,
              onChanged: _onTabChanged,
            ),
            if (_savedFilters.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildSavedFiltersRow(t, theme),
            ],
            const SizedBox(height: 12),
            _buildInboxToolbar(t, theme),
            if (_metadataError != null) ...[
              const SizedBox(height: 10),
              Material(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'امکان بارگذاری لیست فیلترها وجود ندارد. لطفاً صفحه را رفرش کنید.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useSplit = constraints.maxWidth >= 960;
                  final list = _buildTicketsPanel(t, theme, _buildMobileTicketsList(t, theme));
                  if (!useSplit) return list;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: list),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _buildUserSplitDetail(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

