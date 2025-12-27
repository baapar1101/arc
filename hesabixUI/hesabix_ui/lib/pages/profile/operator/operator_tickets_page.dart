import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/services/saved_filters_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/models/saved_filter.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/support/ticket_details_dialog.dart';

class OperatorTicketsPage extends StatefulWidget {
  final CalendarController? calendarController;
  const OperatorTicketsPage({super.key, this.calendarController});

  @override
  State<OperatorTicketsPage> createState() => _OperatorTicketsPageState();
}

class _OperatorTicketsPageState extends State<OperatorTicketsPage> {
  Set<int> _selectedRows = <int>{};
  
  // Key for accessing DataTable state
  final GlobalKey _dataTableKey = GlobalKey();
  
  // Support data for filters
  final SupportService _supportService = SupportService(ApiClient());
  List<SupportStatus> _statuses = [];
  List<SupportPriority> _priorities = [];
  List<SupportCategory> _categories = [];
  
  // Refresh counter to force data table refresh
  int _refreshCounter = 0;
  
  // Check if current user is superadmin
  bool _isSuperAdmin = false;
  
  // Current user ID for quick actions
  int? _currentUserId;
  
  // Saved filters
  List<SavedFilter> _savedFilters = [];
  SavedFilter? _selectedFilter;
  
  // Additional filters
  bool? _lastMessageFromUser; // null = همه, true = از کاربر, false = از اپراتور

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _checkUserPermissions();
    _loadCurrentUserId();
    _loadSavedFilters();
  }

  // Helper برای setState ایمن
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _loadMetadata() async {
    try {
      final statuses = await _supportService.getStatuses();
      final priorities = await _supportService.getPriorities();
      final categories = await _supportService.getCategories();
      
      _safeSetState(() {
        _statuses = statuses;
        _priorities = priorities;
        _categories = categories;
      });
    } catch (e) {
      // Handle error silently for now, filters will just be empty
    }
  }

  Future<void> _checkUserPermissions() async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.get<Map<String, dynamic>>('/api/v1/auth/me');
      final permissions = response.data?['data']?['permissions'] as Map<String, dynamic>?;
      final isSuperAdmin = permissions?['is_superadmin'] as bool? ?? false;
      
      _safeSetState(() {
        _isSuperAdmin = isSuperAdmin;
      });
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.get<Map<String, dynamic>>('/api/v1/auth/me');
      final userId = response.data?['data']?['id'] as int?;
      
      _safeSetState(() {
        _currentUserId = userId;
      });
      
      // Load default filters after getting user ID
      if (userId != null) {
        _loadSavedFilters();
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadSavedFilters() async {
    try {
      final filters = await SavedFiltersService.getSavedFilters();
      
      // Add default filters if no saved filters exist
      if (filters.isEmpty && _currentUserId != null) {
        final defaultFilters = SavedFiltersService.getDefaultFilters(_currentUserId);
        _safeSetState(() {
          _savedFilters = defaultFilters;
        });
      } else {
        _safeSetState(() {
          _savedFilters = filters;
        });
      }
    } catch (e) {
      // Handle error silently
    }
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
            hintText: 'مثلاً: تیکت‌های من',
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
        // TODO: Get current filters from DataTable
        // For now, create a basic filter
        final filter = SavedFilter(
          name: result,
          filters: _selectedFilter?.filters ?? {},
        );
        
        await SavedFiltersService.saveFilter(filter);
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
      await SavedFiltersService.deleteFilter(filterName);
      await _loadSavedFilters();
      
      if (_selectedFilter?.name == filterName) {
        _safeSetState(() {
          _selectedFilter = null;
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فیلتر حذف شد')),
        );
      }
    }
  }

  Future<void> _assignToMe() async {
    if (_selectedRows.isEmpty || _currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً حداقل یک تیکت انتخاب کنید')),
      );
      return;
    }

    try {
      final result = await _supportService.bulkAssignTickets(
        _selectedRows.toList(),
        _currentUserId!,
      );
      
      _safeSetState(() {
        _selectedRows.clear();
        _refreshCounter++;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result['updated_count']} تیکت به شما تخصیص داده شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در تخصیص تیکت‌ها: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markResolved() async {
    if (_selectedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً حداقل یک تیکت انتخاب کنید')),
      );
      return;
    }

    // پیدا کردن status_id برای "حل شده" (معمولاً 5)
    final resolvedStatus = _statuses.firstWhere(
      (s) => s.name.toLowerCase().contains('حل') || s.name.toLowerCase().contains('resolved'),
      orElse: () => _statuses.firstWhere(
        (s) => s.isFinal == true,
        orElse: () => _statuses.last,
      ),
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
          SnackBar(
            content: Text('${result['updated_count']} تیکت به عنوان حل شده علامت‌گذاری شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در تغییر وضعیت تیکت‌ها: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  void _navigateToTicketDetail(Map<String, dynamic> ticketData) {
    final ticket = SupportTicket.fromJson(ticketData);
    showDialog(
      context: context,
      builder: (context) => TicketDetailsDialog(
        ticket: ticket,
        isOperator: true,
        calendarController: widget.calendarController,
        onTicketUpdated: () {
          // Refresh the data table after ticket update
          _safeSetState(() {
            _refreshCounter++;
          });
        },
      ),
    );
  }

  Future<void> _deleteTicket(int ticketId) async {
    if (!mounted) return;
    
    final t = AppLocalizations.of(context);
    
    // نمایش دیالوگ تأیید
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: const Text('آیا مطمئن هستید که می‌خواهید این تیکت را حذف کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    
    if (confirmed != true || !mounted) return;
    
    try {
      await _supportService.deleteTicket(ticketId);
      
      if (!mounted) return;
      
      // حذف تیکت از selectedRows اگر انتخاب شده بود و refresh
      _safeSetState(() {
        _selectedRows.remove(ticketId);
        _refreshCounter++;
      });
      
      // نمایش پیام موفقیت بعد از setState
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تیکت با موفقیت حذف شد')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا در حذف تیکت: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteSelectedTickets() async {
    if (!mounted) return;
    
    final t = AppLocalizations.of(context);
    
    if (_selectedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هیچ تیکتی انتخاب نشده است')),
      );
      return;
    }
    
    final ticketCount = _selectedRows.length;
    
    // نمایش دیالوگ تأیید
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأیید حذف گروهی'),
        content: Text('آیا مطمئن هستید که می‌خواهید $ticketCount تیکت را حذف کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    
    if (confirmed != true || !mounted) return;
    
    // نمایش loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    try {
      // استخراج شناسه‌های واقعی تیکت‌ها از ردیف‌های انتخاب‌شده
      final tableState = _dataTableKey.currentState as dynamic;
      final selectedItems = (tableState?.getSelectedItems() as List<dynamic>?) ?? <dynamic>[];
      
      final ticketIds = <int>[];
      for (final row in selectedItems) {
        if (row is Map<String, dynamic>) {
          final ticketId = row['id'];
          if (ticketId is int) {
            ticketIds.add(ticketId);
          }
        }
      }
      
      if (ticketIds.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('خطا: شناسه تیکت‌ها یافت نشد'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final result = await _supportService.deleteTickets(ticketIds);
      
      // بستن loading
      if (mounted) Navigator.of(context).pop();
      
      if (!mounted) return;
      
      final successCount = result['success'] as int;
      final failCount = result['failed'] as int;
      
      // پاک کردن انتخاب‌ها و refresh
      _safeSetState(() {
        _selectedRows.clear();
        _refreshCounter++;
      });
      
      // نمایش پیام موفقیت بعد از setState
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$successCount تیکت حذف شد${failCount > 0 ? ' و $failCount تیکت ناموفق بود' : ''}',
            ),
            backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      // بستن loading
      if (mounted) Navigator.of(context).pop();
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا در حذف تیکت‌ها: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
            Column(
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
                // Quick Actions
                if (_selectedRows.isNotEmpty) ...[
                  ElevatedButton.icon(
                    onPressed: _assignToMe,
                    icon: const Icon(Icons.person_add),
                    label: Text('تخصیص به من (${_selectedRows.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                      foregroundColor: theme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _markResolved,
                    icon: const Icon(Icons.check_circle),
                    label: Text('حل شده (${_selectedRows.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade50,
                      foregroundColor: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // دکمه حذف گروهی (فقط برای superadmin)
                if (_isSuperAdmin && _selectedRows.isNotEmpty) ...[
                  ElevatedButton.icon(
                    onPressed: _deleteSelectedTickets,
                    icon: const Icon(Icons.delete_outline),
                    label: Text('حذف (${_selectedRows.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red.shade700,
                    ),
                  ),
                    const SizedBox(width: 8),
                  ],
                ],
                ),
                // Quick Filters
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // فیلتر آخرین پیام از کاربر
                    FilterChip(
                      label: const Text('آخرین پیام از کاربر'),
                      selected: _lastMessageFromUser == true,
                      onSelected: (selected) {
                        _safeSetState(() {
                          _lastMessageFromUser = selected ? true : null;
                        });
                        _refreshCounter++;
                      },
                      avatar: Icon(
                        _lastMessageFromUser == true ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                    ),
                    FilterChip(
                      label: const Text('آخرین پیام از اپراتور'),
                      selected: _lastMessageFromUser == false,
                      onSelected: (selected) {
                        _safeSetState(() {
                          _lastMessageFromUser = selected ? false : null;
                        });
                        _refreshCounter++;
                      },
                      avatar: Icon(
                        _lastMessageFromUser == false ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                    ),
                    if (_lastMessageFromUser != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'پاک کردن فیلتر',
                        onPressed: () {
                          _safeSetState(() {
                            _lastMessageFromUser = null;
                          });
                          _refreshCounter++;
                        },
                      ),
                  ],
                ),
                // Saved Filters
                if (_savedFilters.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ..._savedFilters.map((filter) {
                          final isSelected = _selectedFilter?.name == filter.name;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(filter.name),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  _safeSetState(() {
                                    _selectedFilter = filter;
                                  });
                                  // TODO: Apply filter to DataTable
                                  _refreshCounter++;
                                } else {
                                  _safeSetState(() {
                                    _selectedFilter = null;
                                  });
                                  _refreshCounter++;
                                }
                              },
                              deleteIcon: Icon(
                                Icons.close,
                                size: 18,
                                color: isSelected ? Colors.white : Colors.grey,
                              ),
                              onDeleted: () => _deleteSavedFilter(filter.name),
                            ),
                          );
                        }).toList(),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'ذخیره فیلتر فعلی',
                          onPressed: _saveCurrentFilter,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('ذخیره فیلتر فعلی'),
                        onPressed: _saveCurrentFilter,
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DataTableWidget<Map<String, dynamic>>(
                key: ValueKey('data_table_$_refreshCounter'),
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
                      filterType: ColumnFilterType.multiSelect,
                      filterOptions: _categories.map((category) => FilterOption(
                        value: category.name,
                        label: category.name,
                        description: category.description,
                      )).toList(),
                    ),
                    TextColumn(
                      'priority.name',
                      'اولویت',
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
                      'وضعیت',
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
                    // ستون عملیات (فقط برای superadmin)
                    if (_isSuperAdmin)
                      ActionColumn('actions', 'عملیات', actions: [
                        DataTableAction(
                          icon: Icons.delete_outline,
                          label: 'حذف',
                          onTap: (row) {
                            if (row is Map<String, dynamic>) {
                              final ticketId = row['id'];
                              if (ticketId is int) {
                                _deleteTicket(ticketId);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('خطا: شناسه تیکت نامعتبر است'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          isDestructive: true,
                        ),
                      ]),
                  ],
                  searchFields: ['title', 'description', 'user.first_name', 'user.last_name', 'user.email'],
                  filterFields: ['title', 'user.first_name', 'user.email', 'category.name', 'priority.name', 'status.name', 'assigned_operator.first_name', 'created_at', 'last_message_from_user'],
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
                    _safeSetState(() {
                      _selectedRows = selectedRows;
                    });
                  },
                  getCustomFilters: () {
                    final filters = <FilterItem>[];
                    if (_lastMessageFromUser != null) {
                      filters.add(FilterItem(
                        property: 'last_message_from_user',
                        operator: '==',
                        value: _lastMessageFromUser == true ? 'true' : 'false',
                      ));
                    }
                    return filters;
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
