import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/services/support_tickets_public_config.dart';
import 'package:hesabix_ui/services/support_billing_service.dart';
import 'package:hesabix_ui/services/saved_filters_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/models/saved_filter.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import '../../utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/support/ticket_detail_view.dart';
import 'package:hesabix_ui/widgets/support/ticket_csat_dialog.dart';
import 'package:hesabix_ui/widgets/support/ticket_card.dart';
import 'package:hesabix_ui/widgets/support/user_ticket_list_item.dart';
import 'package:hesabix_ui/widgets/support/user_support_inbox_sidebar.dart';
import 'package:hesabix_ui/widgets/support/user_support_tab_bar.dart';
import 'package:hesabix_ui/widgets/support/user_support_types.dart';
import 'create_ticket_page.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class SupportPage extends StatefulWidget {
  final CalendarController? calendarController;
  const SupportPage({super.key, this.calendarController});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> with WidgetsBindingObserver {
  static const double _sidebarWidth = 320;
  static const double _masterDetailBreakpoint = 768;

  final SupportService _supportService = SupportService(ApiClient());
  final SupportBillingService _billingService = SupportBillingService(ApiClient());
  Map<String, dynamic>? _entitlement;
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
    try {
      final ent = await _billingService.getEntitlement();
      if (!mounted) return;
      setState(() => _entitlement = ent);
      if (ent['can_create_ticket'] != true) {
        final goBilling = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('نیاز به اشتراک پشتیبانی'),
            content: Text(
              ent['reason_code'] == 'quota_exceeded'
                  ? 'سهمیه رایگان ماهانه شما تمام شده است. برای ادامه، اشتراک پشتیبانی تهیه کنید.'
                  : 'برای ثبت تیکت جدید نیاز به اشتراک پشتیبانی دارید.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بستن')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('خرید اشتراک'),
              ),
            ],
          ),
        );
        if (goBilling == true && mounted) {
          context.go('/user/profile/support/billing');
        }
        return;
      }
    } catch (_) {
      // اگر entitlement در دسترس نبود، اجازه بده API بک‌اند تصمیم بگیرد
    }

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

    if (_useMasterDetail) {
      _openTicketInSplitView(ticketId, ticketData);
      return;
    }

    context.push('/user/profile/support/tickets/$ticketId');
  }

  bool get _useMasterDetail =>
      MediaQuery.sizeOf(context).width >= _masterDetailBreakpoint;

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
        sortBy: 'last_message_at',
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
      _maybeAutoSelectFirstTicket();
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

  void _maybeAutoSelectFirstTicket() {
    if (!_useMasterDetail || _selectedTicketId != null || _tickets.isEmpty) return;
    final first = _tickets.first;
    _openTicketInSplitView(first.id, first.toJson());
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchDebounce?.cancel();
      _ticketPage = 1;
      _hasMoreTickets = true;
    });
    _loadTickets(showSpinner: false);
  }

  void _submitSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _ticketPage = 1;
      _hasMoreTickets = true;
    });
    _loadTickets();
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
        title: Text('حذف فیلتر'),
        content: Text('آیا مطمئن هستید که می‌خواهید فیلتر "$filterName" را حذف کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('لغو'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SemanticColorResolver.negative(context)),
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

  Widget _buildChatPane(ThemeData theme) {
    if (_selectedTicketId == null) {
      return ColoredBox(
        color: theme.colorScheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 52, color: theme.colorScheme.outline),
              const SizedBox(height: 14),
              Text('گفتگو را شروع کنید', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'یک تیکت از لیست انتخاب کنید',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    if (_selectedTicketLoading || _selectedTicket == null) {
      return const ColoredBox(
        color: Colors.transparent,
        child: Center(child: CircularProgressIndicator()),
      );
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

  Widget _buildMasterDetailLayout(AppLocalizations t, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _sidebarWidth,
          child: UserSupportInboxSidebar(
            t: t,
            searchController: _searchController,
            activeTab: _activeTab,
            activeFilterCount: _activeFilterCount(),
            onTabChanged: _onTabChanged,
            onSearchChanged: _onSearchChanged,
            onSearchClear: _clearSearch,
            onSearchSubmitted: _submitSearch,
            onOpenFilters: () => _showMobileFiltersBottomSheet(t, theme),
            onCreateTicket: _navigateToCreateTicket,
            onOpenBilling: () => context.go('/user/profile/support/billing'),
            ticketList: _buildTicketsList(t, theme, forSidebar: true),
          ),
        ),
        VerticalDivider(width: 1, color: theme.dividerColor.withValues(alpha: 0.6)),
        Expanded(child: _buildChatPane(theme)),
      ],
    );
  }

  Widget _buildMobileLayout(AppLocalizations t, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t.supportTickets,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'اشتراک و صورتحساب',
                onPressed: () => context.go('/user/profile/support/billing'),
                icon: const Icon(Icons.card_membership_outlined),
              ),
              IconButton(
                onPressed: () => _showMobileFiltersBottomSheet(t, theme),
                icon: Badge(
                  isLabelVisible: _activeFilterCount() > 0,
                  label: Text('${_activeFilterCount()}'),
                  child: const Icon(Icons.tune_rounded),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SearchBar(
            controller: _searchController,
            hintText: 'جست‌وجو در تیکت‌ها…',
            leading: const Icon(Icons.search_rounded, size: 20),
            trailing: [
              ListenableBuilder(
                listenable: _searchController,
                builder: (context, _) {
                  if (_searchController.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: _clearSearch,
                  );
                },
              ),
            ],
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _submitSearch(),
            elevation: WidgetStateProperty.all(0),
            backgroundColor: WidgetStateProperty.all(theme.colorScheme.surfaceContainerHighest),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: UserSupportTabBar(activeTab: _activeTab, onChanged: _onTabChanged),
        ),
        if (_metadataError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              'امکان بارگذاری فیلترها وجود ندارد.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(child: _buildTicketsList(t, theme)),
      ],
    );
  }

  Widget _buildTicketsList(AppLocalizations t, ThemeData theme, {bool forSidebar = false}) {
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

    final useCardView = !forSidebar && _viewMode == UserSupportViewMode.card;
    final bottomPad = forSidebar ? 8.0 : 80.0;
    Widget listContent;

    if (_groupByStatus && _groupedTickets != null && !forSidebar) {
      listContent = ListView.builder(
        padding: EdgeInsets.only(top: 8, bottom: bottomPad),
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
      listContent = ListView.builder(
        padding: EdgeInsets.only(top: forSidebar ? 0 : 8, bottom: bottomPad),
        itemCount: tickets.length + (_hasMoreTickets ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= tickets.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final ticket = tickets[index];
          if (useCardView) {
            return _buildTicketCard(ticket, t, theme);
          }
          return UserTicketListItem(
            ticket: ticket,
            isSelected: ticket.id == _selectedTicketId,
            calendarController: widget.calendarController,
            compact: forSidebar,
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
    final isMobile = MediaQuery.sizeOf(context).width < _masterDetailBreakpoint;

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
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
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
            )
          : null,
      body: isMobile ? _buildMobileLayout(t, theme) : _buildMasterDetailLayout(t, theme),
    );
  }
}

