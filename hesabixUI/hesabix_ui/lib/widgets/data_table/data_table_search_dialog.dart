import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'data_table_config.dart';
import 'helpers/data_table_utils.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';

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
  final VoidCallback onClear;
  final CalendarController? calendarController;

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
    required this.onClear,
    this.calendarController,
  });

  @override
  State<DataTableSearchDialog> createState() => _DataTableSearchDialogState();
}

class _DataTableSearchDialogState extends State<DataTableSearchDialog> {
  late TextEditingController _controller;
  late String _selectedType;
  Set<String> _selectedValues = <String>{};
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchValue);
    _selectedType = widget.searchType;
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
      content: Column(
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
      default:
        return _buildTextFilterContent(t, theme);
    }
  }

  List<Widget> _buildTextFilterContent(AppLocalizations t, ThemeData theme) {
    return [
      // Search type dropdown
      DropdownButtonFormField<String>(
        value: _selectedType,
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
        onTap: () async {
          final date = isJalali 
              ? await showJalaliDatePicker(
                  context: context,
                  initialDate: _fromDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  helpText: t.dateFrom,
                )
              : await showDatePicker(
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
            ? HesabixDateUtils.formatForDisplay(_toDate!, isJalali)
            : t.selectDate),
        onTap: () async {
          final date = isJalali 
              ? await showJalaliDatePicker(
                  context: context,
                  initialDate: _toDate ?? _fromDate ?? DateTime.now(),
                  firstDate: _fromDate ?? DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  helpText: t.dateTo,
                )
              : await showDatePicker(
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

  List<Widget> _buildFilterActions(AppLocalizations t) {
    final hasActiveFilter = _hasActiveFilter();
    
    return [
      TextButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        child: Text(t.cancel),
      ),
      if (hasActiveFilter)
        TextButton(
          onPressed: () {
            widget.onClear();
            Navigator.of(context).pop();
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
      default:
        widget.onApply(_controller.text.trim(), _selectedType);
        break;
    }
    Navigator.of(context).pop();
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
            Navigator.of(context).pop();
          },
          child: Text(t.cancel),
        ),
        if (widget.fromDate != null || widget.toDate != null)
          TextButton(
            onPressed: () {
              widget.onClear();
              Navigator.of(context).pop();
            },
            child: Text(t.clear),
          ),
        FilledButton(
          onPressed: _fromDate != null && _toDate != null
              ? () {
                  widget.onApply(_fromDate, _toDate);
                  Navigator.of(context).pop();
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
              
              // Multi-select filters
              ...columnMultiSelectValues.entries.map((entry) {
                final columnName = entry.key;
                final selectedValues = entry.value;
                final columnLabel = DataTableUtils.getColumnLabel(columnName, columns);
                final filterOptions = DataTableUtils.getColumnFilterOptions(columnName, columns);
                
                String displayText = '$columnLabel: ';
                if (filterOptions != null) {
                  final selectedLabels = selectedValues.map((value) {
                    final option = filterOptions.firstWhere(
                      (opt) => opt.value == value,
                      orElse: () => FilterOption(value: value, label: value),
                    );
                    return option.label;
                  }).join(', ');
                  displayText += selectedLabels;
                } else {
                  displayText += selectedValues.join(', ');
                }
                
                return Chip(
                  label: Text(displayText),
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
