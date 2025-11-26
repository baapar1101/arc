import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'data_table_config.dart';
import 'helpers/data_table_utils.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/services/category_service.dart';
import 'package:hesabix_ui/core/api_client.dart';

/// Dialog for column search
class DataTableSearchDialog extends StatefulWidget {
  final String columnName;
  final String columnLabel;
  final String searchValue;
  final String searchType;
  final ColumnFilterType? filterType;
  final List<FilterOption>? filterOptions;
  final Function(String value, String type) onApply;
  final Function(List<String> values)? onApplyMultiSelect;
  final Function(DateTime? fromDate, DateTime? toDate)? onApplyDateRange;
  final Function(List<String> categoryIds)? onApplyCategoryTree;
  final VoidCallback onClear;
  final CalendarController? calendarController;
  final int? businessId;

  const DataTableSearchDialog({
    super.key,
    required this.columnName,
    required this.columnLabel,
    required this.searchValue,
    required this.searchType,
    this.filterType,
    this.filterOptions,
    required this.onApply,
    this.onApplyMultiSelect,
    this.onApplyDateRange,
    this.onApplyCategoryTree,
    required this.onClear,
    this.calendarController,
    this.businessId,
  });

  @override
  State<DataTableSearchDialog> createState() => _DataTableSearchDialogState();
}

class _DataTableSearchDialogState extends State<DataTableSearchDialog> {
  late TextEditingController _controller;
  late String _selectedType;
  final Set<String> _selectedValues = <String>{};
  final Set<String> _selectedCategoryIds = <String>{};
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchValue);
    _selectedType = widget.searchType;
    // Enable/disable Apply button reactively on text changes
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(_getFilterIcon(), color: theme.primaryColor, size: 20),
          const SizedBox(width: 8),
          Text(_getFilterTitle(t)),
        ],
      ),
      content: widget.filterType == ColumnFilterType.categoryTree
          ? SizedBox(
              width: 600,
              height: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _buildFilterContent(t, theme),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildFilterContent(t, theme),
            ),
      actions: _buildFilterActions(t),
    );
  }

  IconData _getFilterIcon() {
    switch (widget.filterType) {
      case ColumnFilterType.dateRange:
        return Icons.date_range;
      case ColumnFilterType.multiSelect:
        return Icons.checklist;
      case ColumnFilterType.categoryTree:
        return Icons.account_tree;
      default:
        return Icons.search;
    }
  }

  String _getFilterTitle(AppLocalizations t) {
    switch (widget.filterType) {
      case ColumnFilterType.dateRange:
        return t.dateRangeFilter;
      case ColumnFilterType.multiSelect:
        return t.multiSelectFilter;
      case ColumnFilterType.categoryTree:
        return 'فیلتر دسته‌بندی درختی';
      default:
        return t.searchInColumn(widget.columnLabel);
    }
  }

  List<Widget> _buildFilterContent(AppLocalizations t, ThemeData theme) {
    switch (widget.filterType) {
      case ColumnFilterType.dateRange:
        return _buildDateRangeContent(t, theme);
      case ColumnFilterType.multiSelect:
        return _buildMultiSelectContent(t, theme);
      case ColumnFilterType.categoryTree:
        return _buildCategoryTreeContent(t, theme);
      default:
        return _buildTextFilterContent(t, theme);
    }
  }

  List<Widget> _buildTextFilterContent(AppLocalizations t, ThemeData theme) {
    return [
      // Search type dropdown
      DropdownButtonFormField<String>(
        initialValue: _selectedType,
        decoration: InputDecoration(
          labelText: t.searchType,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          DropdownMenuItem(value: '*', child: Text(t.contains)),
          DropdownMenuItem(value: '*?', child: Text(t.startsWith)),
          DropdownMenuItem(value: '?*', child: Text(t.endsWith)),
          DropdownMenuItem(value: '=', child: Text(t.exactMatch)),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _selectedType = value;
            });
          }
        },
      ),
      const SizedBox(height: 16),
      // Search value input
      TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: t.searchValue,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        autofocus: true,
      ),
    ];
  }

  List<Widget> _buildDateRangeContent(AppLocalizations t, ThemeData theme) {
    final isJalali = widget.calendarController?.isJalali ?? false;
    
    return [
      // From date
      ListTile(
        leading: const Icon(Icons.calendar_today),
        title: Text(t.dateFrom),
        subtitle: Text(_fromDate != null 
            ? HesabixDateUtils.formatForDisplay(_fromDate!, isJalali)
            : t.selectDate),
        onTap: () => _selectFromDate(t, isJalali),
      ),
      // To date
      ListTile(
        leading: const Icon(Icons.calendar_today),
        title: Text(t.dateTo),
        subtitle: Text(_toDate != null 
            ? HesabixDateUtils.formatForDisplay(_toDate!, isJalali)
            : t.selectDate),
        onTap: () => _selectToDate(t, isJalali),
      ),
    ];
  }

  List<Widget> _buildMultiSelectContent(AppLocalizations t, ThemeData theme) {
    if (widget.filterOptions == null || widget.filterOptions!.isEmpty) {
      return [
        Text(
          t.noFilterOptionsAvailable,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    return [
      Text(
        t.selectFilterOptions,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      ...widget.filterOptions!.map((option) => CheckboxListTile(
        title: Row(
          children: [
            if (option.icon != null) ...[
              Icon(
                option.icon,
                size: 16,
                color: option.color,
              ),
              const SizedBox(width: 8),
            ],
            Text(option.label),
          ],
        ),
        subtitle: option.description != null 
            ? Text(option.description!) 
            : null,
        value: _selectedValues.contains(option.value),
        onChanged: (bool? value) {
          setState(() {
            if (value == true) {
              _selectedValues.add(option.value);
            } else {
              _selectedValues.remove(option.value);
            }
          });
        },
      )),
    ];
  }

  List<Widget> _buildCategoryTreeContent(AppLocalizations t, ThemeData theme) {
    if (widget.businessId == null) {
      return [
        Text(
          'برای استفاده از فیلتر دسته‌بندی، businessId لازم است',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    return [
      Text(
        'انتخاب دسته‌بندی (کالاهای زیرمجموعه‌ها نیز نمایش داده می‌شوند)',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: _CategoryTreeFilterWidget(
          key: const ValueKey('category_tree_filter'),
          businessId: widget.businessId!,
          selectedCategoryIds: _selectedCategoryIds,
          onSelectionChanged: (selectedIds) {
            setState(() {
              _selectedCategoryIds.clear();
              _selectedCategoryIds.addAll(selectedIds);
            });
          },
        ),
      ),
    ];
  }

  List<Widget> _buildFilterActions(AppLocalizations t) {
    final hasActiveFilter = _hasActiveFilter();
    
    return [
      TextButton(
        onPressed: () {
          context.pop();
        },
        child: Text(t.cancel),
      ),
      if (hasActiveFilter)
        TextButton(
          onPressed: () {
            widget.onClear();
            context.pop();
          },
          child: Text(t.clear),
        ),
      FilledButton(
        onPressed: _canApplyFilter() ? _applyFilter : null,
        child: Text(_getApplyButtonText(t)),
      ),
    ];
  }

  bool _hasActiveFilter() {
    switch (widget.filterType) {
      case ColumnFilterType.dateRange:
        return _fromDate != null || _toDate != null;
      case ColumnFilterType.multiSelect:
        return _selectedValues.isNotEmpty;
      case ColumnFilterType.categoryTree:
        return _selectedCategoryIds.isNotEmpty;
      default:
        return widget.searchValue.isNotEmpty;
    }
  }

  bool _canApplyFilter() {
    switch (widget.filterType) {
      case ColumnFilterType.dateRange:
        return _fromDate != null && _toDate != null;
      case ColumnFilterType.multiSelect:
        return _selectedValues.isNotEmpty;
      case ColumnFilterType.categoryTree:
        return _selectedCategoryIds.isNotEmpty;
      default:
        return _controller.text.trim().isNotEmpty;
    }
  }

  String _getApplyButtonText(AppLocalizations t) {
    switch (widget.filterType) {
      case ColumnFilterType.dateRange:
        return t.applyFilter;
      case ColumnFilterType.multiSelect:
        return t.applyFilter;
      case ColumnFilterType.categoryTree:
        return t.applyFilter;
      default:
        return t.applyColumnFilter;
    }
  }

  void _applyFilter() {
    switch (widget.filterType) {
      case ColumnFilterType.dateRange:
        if (widget.onApplyDateRange != null) {
          widget.onApplyDateRange!(_fromDate, _toDate);
        }
        break;
      case ColumnFilterType.multiSelect:
        if (widget.onApplyMultiSelect != null) {
          widget.onApplyMultiSelect!(_selectedValues.toList());
        }
        break;
      case ColumnFilterType.categoryTree:
        if (widget.onApplyCategoryTree != null) {
          widget.onApplyCategoryTree!(_selectedCategoryIds.toList());
        }
        break;
      default:
        widget.onApply(_controller.text.trim(), _selectedType);
        break;
    }
            context.pop();
  }

  Future<void> _selectFromDate(AppLocalizations t, bool isJalali) async {
    final currentContext = context;
    final date = isJalali 
        ? await showJalaliDatePicker(
            // ignore: use_build_context_synchronously
            context: currentContext,
            initialDate: _fromDate ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            helpText: t.dateFrom,
          )
        : await showDatePicker(
            // ignore: use_build_context_synchronously
            context: currentContext,
            initialDate: _fromDate ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
    if (date != null && mounted) {
      setState(() {
        _fromDate = date;
      });
    }
  }

  Future<void> _selectToDate(AppLocalizations t, bool isJalali) async {
    final currentContext = context;
    final date = isJalali 
        ? await showJalaliDatePicker(
            // ignore: use_build_context_synchronously
            context: currentContext,
            initialDate: _toDate ?? _fromDate ?? DateTime.now(),
            firstDate: _fromDate ?? DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            helpText: t.dateTo,
          )
        : await showDatePicker(
            // ignore: use_build_context_synchronously
            context: currentContext,
            initialDate: _toDate ?? _fromDate ?? DateTime.now(),
            firstDate: _fromDate ?? DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
    if (date != null && mounted) {
      setState(() {
        _toDate = date;
      });
    }
  }
}

/// Dialog for date range filter
class DataTableDateRangeDialog extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  final Function(DateTime? from, DateTime? to) onApply;
  final VoidCallback onClear;

  const DataTableDateRangeDialog({
    super.key,
    this.fromDate,
    this.toDate,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<DataTableDateRangeDialog> createState() => _DataTableDateRangeDialogState();
}

class _DataTableDateRangeDialogState extends State<DataTableDateRangeDialog> {
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _fromDate = widget.fromDate;
    _toDate = widget.toDate;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.date_range, color: theme.primaryColor, size: 20),
          const SizedBox(width: 8),
          Text(t.dateRangeFilter),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // From date
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(t.dateFrom),
            subtitle: Text(_fromDate != null 
                ? DateFormat('yyyy/MM/dd').format(_fromDate!)
                : t.selectDate),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _fromDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setState(() {
                  _fromDate = date;
                });
              }
            },
          ),
          // To date
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(t.dateTo),
            subtitle: Text(_toDate != null 
                ? DateFormat('yyyy/MM/dd').format(_toDate!)
                : t.selectDate),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _toDate ?? _fromDate ?? DateTime.now(),
                firstDate: _fromDate ?? DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setState(() {
                  _toDate = date;
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            context.pop();
          },
          child: Text(t.cancel),
        ),
        if (widget.fromDate != null || widget.toDate != null)
          TextButton(
            onPressed: () {
              widget.onClear();
              context.pop();
            },
            child: Text(t.clear),
          ),
        FilledButton(
          onPressed: _fromDate != null && _toDate != null
              ? () {
                  widget.onApply(_fromDate, _toDate);
                  context.pop();
                }
              : null,
          child: Text(t.applyFilter),
        ),
      ],
    );
  }
}

/// Widget for active filters display
class ActiveFiltersWidget extends StatelessWidget {
  final Map<String, String> columnSearchValues;
  final Map<String, String> columnSearchTypes;
  final Map<String, List<String>> columnMultiSelectValues;
  final Map<String, DateTime?> columnDateFromValues;
  final Map<String, DateTime?> columnDateToValues;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<DataTableColumn> columns;
  final void Function(String columnName) onRemoveColumnFilter;
  final VoidCallback onClearAll;
  final CalendarController? calendarController;

  const ActiveFiltersWidget({
    super.key,
    required this.columnSearchValues,
    required this.columnSearchTypes,
    required this.columnMultiSelectValues,
    required this.columnDateFromValues,
    required this.columnDateToValues,
    this.fromDate,
    this.toDate,
    required this.columns,
    required this.onRemoveColumnFilter,
    required this.onClearAll,
    this.calendarController,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    
    final hasFilters = columnSearchValues.isNotEmpty || 
                      columnMultiSelectValues.isNotEmpty ||
                      columnDateFromValues.isNotEmpty ||
                      (fromDate != null && toDate != null);

    if (!hasFilters) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt, color: theme.primaryColor, size: 16),
              const SizedBox(width: 8),
              Text(
                t.activeFilters,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.primaryColor,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onClearAll,
                child: Text(t.clear),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 3,
            children: [
              // Text search filters
              ...columnSearchValues.entries.map((entry) {
                final columnName = entry.key;
                final searchValue = entry.value;
                final searchType = columnSearchTypes[columnName] ?? '*';
                final columnLabel = DataTableUtils.getColumnLabel(columnName, columns);
                final typeLabel = DataTableUtils.getSearchOperatorLabel(searchType);
                
                return Chip(
                  label: Text('$columnLabel: $searchValue ($typeLabel)'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => onRemoveColumnFilter(columnName),
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                  deleteIconColor: theme.primaryColor,
                  labelStyle: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 12,
                  ),
                );
              }),
              
              // Multi-select filters (including category tree)
              ...columnMultiSelectValues.entries.map((entry) {
                final columnName = entry.key;
                final selectedValues = entry.value;
                // بررسی اینکه آیا این فیلتر category_id است (که برای category_name استفاده می‌شود)
                final isCategoryId = columnName == 'category_id';
                final categoryNameColumn = columns.where((col) => col.key == 'category_name').firstOrNull;
                final isCategoryTree = isCategoryId || 
                    (categoryNameColumn != null && categoryNameColumn.filterType == ColumnFilterType.categoryTree);
                final columnLabel = isCategoryTree 
                    ? 'دسته‌بندی' 
                    : DataTableUtils.getColumnLabel(columnName, columns);
                final filterOptions = DataTableUtils.getColumnFilterOptions(columnName, columns);
                
                String displayText = '$columnLabel: ';
                if (filterOptions != null && !isCategoryTree) {
                  final selectedLabels = selectedValues.map((value) {
                    final option = filterOptions.firstWhere(
                      (opt) => opt.value == value,
                      orElse: () => FilterOption(value: value, label: value),
                    );
                    return option.label;
                  }).join(', ');
                  displayText += selectedLabels;
                } else if (isCategoryTree) {
                  displayText += '${selectedValues.length} دسته‌بندی انتخاب شده';
                } else {
                  displayText += selectedValues.join(', ');
                }
                
                return Chip(
                  label: Text(displayText),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    // اگر category_id است، category_name را نیز پاک کن
                    if (columnName == 'category_id') {
                      onRemoveColumnFilter('category_name');
                    }
                    onRemoveColumnFilter(columnName);
                  },
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                  deleteIconColor: theme.primaryColor,
                  labelStyle: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 12,
                  ),
                );
              }),
              
              // Date range filters
              ...columnDateFromValues.entries.map((entry) {
                final columnName = entry.key;
                final fromDate = entry.value;
                final toDate = columnDateToValues[columnName];
                final columnLabel = DataTableUtils.getColumnLabel(columnName, columns);
                
                if (fromDate != null && toDate != null) {
                  return Chip(
                    label: Text('$columnLabel: ${HesabixDateUtils.formatForDisplay(fromDate, calendarController?.isJalali ?? false)} - ${HesabixDateUtils.formatForDisplay(toDate, calendarController?.isJalali ?? false)}'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => onRemoveColumnFilter(columnName),
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                    deleteIconColor: theme.primaryColor,
                    labelStyle: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 12,
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
              
              // Legacy date range filter
              if (fromDate != null && toDate != null)
                Chip(
                  label: Text('${t.dateFrom}: ${HesabixDateUtils.formatForDisplay(fromDate!, calendarController?.isJalali ?? false)} - ${t.dateTo}: ${HesabixDateUtils.formatForDisplay(toDate!, calendarController?.isJalali ?? false)}'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => onClearAll(),
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                  deleteIconColor: theme.primaryColor,
                  labelStyle: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ویجت فیلتر درختی دسته‌بندی
class _CategoryTreeFilterWidget extends StatefulWidget {
  final int businessId;
  final Set<String> selectedCategoryIds;
  final ValueChanged<Set<String>> onSelectionChanged;

  const _CategoryTreeFilterWidget({
    super.key,
    required this.businessId,
    required this.selectedCategoryIds,
    required this.onSelectionChanged,
  });

  @override
  State<_CategoryTreeFilterWidget> createState() => _CategoryTreeFilterWidgetState();
}

class _CategoryTreeFilterWidgetState extends State<_CategoryTreeFilterWidget> {
  late final CategoryService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tree = const <Map<String, dynamic>>[];
  final Set<int> _expandedNodes = <int>{};
  String _searchQuery = '';
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _service = CategoryService(ApiClient());
    _selectedIds = Set<String>.from(widget.selectedCategoryIds);
    _fetch();
  }

  @override
  void didUpdateWidget(_CategoryTreeFilterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // فقط اگر selectedCategoryIds واقعاً از parent تغییر کرده باشد (نه از داخل widget)
    // این از پاک شدن انتخاب‌ها هنگام تغییر جستجو جلوگیری می‌کند
    // مقایسه عمیق برای تشخیص تغییر واقعی
    final oldSet = Set<String>.from(oldWidget.selectedCategoryIds);
    final newSet = Set<String>.from(widget.selectedCategoryIds);
    
    // اگر newSet خالی‌تر از oldSet شده یا آیتم‌هایی که در oldSet بودند در newSet نیستند
    // یعنی از parent پاک شده و باید به‌روزرسانی شود
    // اما اگر newSet بزرگ‌تر شده یا فقط آیتم‌های جدید اضافه شده، یعنی از داخل widget تغییر کرده
    // و باید حفظ شود
    if (!_setsEqual(oldSet, newSet)) {
      // اگر newSet کوچکتر شده یا آیتم‌هایی که در oldSet بودند در newSet نیستند
      // یعنی از parent پاک شده
      final removedItems = oldSet.difference(newSet);
      if (removedItems.isNotEmpty) {
        // آیتم‌هایی که از parent پاک شده‌اند را از _selectedIds نیز حذف کن
        setState(() {
          _selectedIds.removeAll(removedItems);
        });
      }
      // آیتم‌های جدید که از parent اضافه شده‌اند را اضافه کن
      final addedItems = newSet.difference(oldSet);
      if (addedItems.isNotEmpty) {
        setState(() {
          _selectedIds.addAll(addedItems);
        });
      }
    }
  }

  bool _setsEqual(Set<String> set1, Set<String> set2) {
    if (set1.length != set2.length) return false;
    return set1.containsAll(set2) && set2.containsAll(set1);
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.getTree(businessId: widget.businessId);
      setState(() {
        _tree = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// جمع‌آوری تمام ID های نودهایی که فرزند دارند
  Set<int> _collectAllNodeIdsWithChildren(List<Map<String, dynamic>> nodes) {
    final Set<int> ids = {};
    for (final node in nodes) {
      final id = node['id'] as int?;
      if (id == null) continue;
      
      final children = (node['children'] as List?)?.cast<dynamic>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const <Map<String, dynamic>>[];
      
      if (children.isNotEmpty) {
        ids.add(id);
        ids.addAll(_collectAllNodeIdsWithChildren(children));
      }
    }
    return ids;
  }

  /// باز کردن همه نودهای درخت
  void _expandAll() {
    setState(() {
      _expandedNodes.addAll(_collectAllNodeIdsWithChildren(_tree));
    });
  }

  /// بستن همه نودهای درخت
  void _collapseAll() {
    setState(() {
      _expandedNodes.clear();
    });
  }

  /// فیلتر کردن درخت بر اساس جستجو
  List<Map<String, dynamic>> _filterTree(List<Map<String, dynamic>> nodes, String query) {
    if (query.isEmpty) return nodes;
    final q = query.toLowerCase();
    List<Map<String, dynamic>> result = [];
    for (final node in nodes) {
      final current = Map<String, dynamic>.from(node);
      final label = (current['label'] ?? current['title'] ?? current['name'] ?? '').toString();
      final children = (current['children'] as List?)?.cast<dynamic>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const <Map<String, dynamic>>[];
      final filteredChildren = _filterTree(children, query);
      final matches = label.toLowerCase().contains(q);
      if (matches || filteredChildren.isNotEmpty) {
        current['children'] = filteredChildren;
        result.add(current);
        // اگر این نود مطابقت دارد، آن را باز کن
        final id = current['id'] as int?;
        if (id != null && matches) {
          _expandedNodes.add(id);
        }
      }
    }
    return result;
  }

  /// جمع‌آوری تمام ID های فرزندان یک نود
  Set<int> _collectAllDescendantIds(Map<String, dynamic> node) {
    final Set<int> ids = {};
    final id = node['id'] as int?;
    if (id != null) {
      ids.add(id);
    }
    final children = (node['children'] as List?)?.cast<dynamic>()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ?? const <Map<String, dynamic>>[];
    for (final child in children) {
      ids.addAll(_collectAllDescendantIds(child));
    }
    return ids;
  }

  void _toggleCategorySelection(int? categoryId, bool? value) {
    if (categoryId == null) return;
    
    // ایجاد یک کپی جدید از selectedIds
    final newSelection = Set<String>.from(_selectedIds);
    final categoryIdStr = categoryId.toString();
    
    if (value == true) {
      // پیدا کردن نود در درخت
      Map<String, dynamic>? findNodeInTree(List<Map<String, dynamic>> nodes) {
        for (final node in nodes) {
          if ((node['id'] as int?) == categoryId) {
            return node;
          }
          final children = (node['children'] as List?)?.cast<dynamic>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ?? const <Map<String, dynamic>>[];
          final found = findNodeInTree(children);
          if (found != null) return found;
        }
        return null;
      }
      
      final node = findNodeInTree(_tree);
      if (node != null) {
        // اضافه کردن خود نود و تمام فرزندانش
        final allIds = _collectAllDescendantIds(node);
        for (final id in allIds) {
          newSelection.add(id.toString());
        }
      } else {
        newSelection.add(categoryIdStr);
      }
    } else {
      newSelection.remove(categoryIdStr);
      // حذف تمام فرزندان نیز
      final node = findNode(_tree, categoryId);
      if (node != null) {
        final allIds = _collectAllDescendantIds(node);
        for (final id in allIds) {
          newSelection.remove(id.toString());
        }
      }
    }
    
    // به‌روزرسانی state و فراخوانی callback
    setState(() {
      _selectedIds = newSelection;
    });
    widget.onSelectionChanged(newSelection);
  }

  Map<String, dynamic>? findNode(List<Map<String, dynamic>> nodes, int targetId) {
    for (final node in nodes) {
      if ((node['id'] as int?) == targetId) {
        return node;
      }
      final children = (node['children'] as List?)?.cast<dynamic>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const <Map<String, dynamic>>[];
      final found = findNode(children, targetId);
      if (found != null) return found;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredTree = _searchQuery.isEmpty ? _tree : _filterTree(_tree, _searchQuery);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('خطا: $_error'));
    }

    return Column(
      children: [
        // جستجو
        TextField(
          decoration: const InputDecoration(
            hintText: 'جستجو در دسته‌بندی‌ها...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) {
            // فقط _searchQuery را تغییر بده، _selectedIds را حفظ کن
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        const SizedBox(height: 8),
        // دکمه‌های باز/بسته کردن
        Row(
          children: [
            TextButton.icon(
              onPressed: _expandAll,
              icon: const Icon(Icons.unfold_more, size: 16),
              label: const Text('باز کردن همه'),
            ),
            TextButton.icon(
              onPressed: _collapseAll,
              icon: const Icon(Icons.unfold_less, size: 16),
              label: const Text('بستن همه'),
            ),
            const Spacer(),
            Text(
              '${_selectedIds.length} مورد انتخاب شده',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const Divider(),
        // درخت دسته‌بندی
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: _buildTreeNodes(filteredTree, 0),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTreeNodes(List<Map<String, dynamic>> items, int level) {
    final List<Widget> widgets = [];
    
    for (final item in items) {
      final id = item['id'] as int?;
      final label = (item['label'] ?? item['title'] ?? item['name'] ?? '').toString();
      final children = (item['children'] as List?)?.cast<dynamic>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const <Map<String, dynamic>>[];
      final isExpanded = id != null && _expandedNodes.contains(id);
      final hasChildren = children.isNotEmpty;
      final isSelected = id != null && _selectedIds.contains(id.toString());

      widgets.add(
        _CategoryTreeNodeWidget(
          id: id,
          label: label,
          level: level,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          isSelected: isSelected,
          onToggleExpand: hasChildren ? () {
            setState(() {
              if (isExpanded) {
                _expandedNodes.remove(id);
              } else {
                _expandedNodes.add(id!);
              }
            });
          } : null,
          onToggleSelection: (value) => _toggleCategorySelection(id, value),
        ),
      );
      
      if (isExpanded && hasChildren) {
        widgets.addAll(_buildTreeNodes(children, level + 1));
      }
    }
    
    return widgets;
  }
}

/// ویجت نمایش یک نود دسته‌بندی در درخت
class _CategoryTreeNodeWidget extends StatelessWidget {
  final int? id;
  final String label;
  final int level;
  final bool isExpanded;
  final bool hasChildren;
  final bool isSelected;
  final VoidCallback? onToggleExpand;
  final ValueChanged<bool?> onToggleSelection;

  const _CategoryTreeNodeWidget({
    required this.id,
    required this.label,
    required this.level,
    required this.isExpanded,
    required this.hasChildren,
    required this.isSelected,
    this.onToggleExpand,
    required this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = level * 24.0;
    final lineColor = theme.colorScheme.outline.withValues(alpha: 0.3);
    
    return Container(
      padding: EdgeInsets.only(
        right: indent + 12,
        left: 12,
        top: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: isSelected 
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        border: Border(
          right: level > 0
              ? BorderSide(
                  color: lineColor,
                  width: 1,
                )
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
            // آیکون باز/بسته کردن
            SizedBox(
              width: 24,
              child: hasChildren
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 20,
                      onPressed: onToggleExpand,
                      icon: Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_left,
                        color: theme.colorScheme.onSurface,
                      ),
                    )
                  : const SizedBox(width: 24),
            ),
            
            const SizedBox(width: 8),
            
            // چک باکس انتخاب
            GestureDetector(
              onTap: () {
                onToggleSelection(!isSelected);
              },
              child: Checkbox(
                value: isSelected,
                onChanged: (value) {
                  onToggleSelection(value);
                },
              ),
            ),
            
            const SizedBox(width: 8),
            
            // آیکون دسته‌بندی
            Icon(
              hasChildren ? Icons.folder : Icons.category,
              size: 20,
              color: hasChildren
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            
            const SizedBox(width: 12),
            
            // نام دسته‌بندی
            Expanded(
              child: GestureDetector(
                onTap: () {
                  onToggleSelection(!isSelected);
                },
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: hasChildren ? FontWeight.w600 : FontWeight.normal,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }
}
