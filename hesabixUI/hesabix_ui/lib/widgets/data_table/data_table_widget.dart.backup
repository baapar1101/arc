import 'dart:async';
import 'package:flutter/foundation.dart';
import 'helpers/file_saver.dart';
// import 'dart:html' as html; // Not available on Linux
import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'data_table_config.dart';
import 'data_table_search_dialog.dart';
import 'column_settings_dialog.dart';
import 'helpers/data_table_utils.dart';
import 'helpers/column_settings_service.dart';

/// Main reusable data table widget
class DataTableWidget<T> extends StatefulWidget {
  final DataTableConfig<T> config;
  final T Function(Map<String, dynamic>) fromJson;
  final CalendarController? calendarController;
  final VoidCallback? onRefresh;

  const DataTableWidget({
    super.key,
    required this.config,
    required this.fromJson,
    this.calendarController,
    this.onRefresh,
  });

  @override
  State<DataTableWidget<T>> createState() => _DataTableWidgetState<T>();
}

class _DataTableWidgetState<T> extends State<DataTableWidget<T>> {
  // Data state
  List<T> _items = [];
  bool _loadingList = false;
  String? _error;

  // Pagination state
  int _page = 1;
  int _limit = 20;
  int _total = 0;
  int _totalPages = 0;

  // Search state
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  // Column search state
  final Map<String, String> _columnSearchValues = {};
  final Map<String, String> _columnSearchTypes = {};
  final Map<String, TextEditingController> _columnSearchControllers = {};
  
  // Enhanced filter state
  final Map<String, List<String>> _columnMultiSelectValues = {};
  final Map<String, DateTime?> _columnDateFromValues = {};
  final Map<String, DateTime?> _columnDateToValues = {};

  // Sorting state
  String? _sortBy;
  bool _sortDesc = false;

  // Row selection state
  final Set<int> _selectedRows = <int>{};
  bool _isExporting = false;
  
  // Column settings state
  ColumnSettings? _columnSettings;
  List<DataTableColumn> _visibleColumns = [];
  bool _isLoadingColumnSettings = false;
  
  // Scroll controller for horizontal scrolling
  late ScrollController _horizontalScrollController;
  
  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _limit = widget.config.defaultPageSize;
    _setupSearchListener();
    _loadColumnSettings();
    _fetchData();
  }

  /// Public method to refresh the data table
  void refresh() {
    _fetchData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _horizontalScrollController.dispose();
    for (var controller in _columnSearchControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setupSearchListener() {
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(widget.config.searchDebounce ?? const Duration(milliseconds: 500), () {
        _page = 1;
        _fetchData();
      });
    });
  }

  Future<void> _loadColumnSettings() async {
    if (!widget.config.enableColumnSettings) {
      _visibleColumns = List.from(widget.config.columns);
      return;
    }

    setState(() {
      _isLoadingColumnSettings = true;
    });

    try {
      final tableId = widget.config.effectiveTableId;
      final savedSettings = await ColumnSettingsService.getColumnSettings(tableId);
      
      ColumnSettings effectiveSettings;
      if (savedSettings != null) {
        effectiveSettings = ColumnSettingsService.mergeWithDefaults(
          savedSettings,
          widget.config.columnKeys,
        );
      } else if (widget.config.initialColumnSettings != null) {
        effectiveSettings = ColumnSettingsService.mergeWithDefaults(
          widget.config.initialColumnSettings,
          widget.config.columnKeys,
        );
      } else {
        effectiveSettings = ColumnSettingsService.getDefaultSettings(widget.config.columnKeys);
      }

      setState(() {
        _columnSettings = effectiveSettings;
        _visibleColumns = _getVisibleColumnsFromSettings(effectiveSettings);
      });
    } catch (e) {
      debugPrint('Error loading column settings: $e');
      setState(() {
        _visibleColumns = List.from(widget.config.columns);
      });
    } finally {
      setState(() {
        _isLoadingColumnSettings = false;
      });
    }
  }

  List<DataTableColumn> _getVisibleColumnsFromSettings(ColumnSettings settings) {
    final visibleColumns = <DataTableColumn>[];
    
    // Add columns in the order specified by settings
    for (final key in settings.columnOrder) {
      final column = widget.config.getColumnByKey(key);
      if (column != null && settings.visibleColumns.contains(key)) {
        visibleColumns.add(column);
      }
    }
    
    return visibleColumns;
  }

  Future<void> _fetchData() async {
    setState(() => _loadingList = true);
    _error = null;

    try {
      final api = ApiClient();
      
      // Build QueryInfo payload
      final queryInfo = QueryInfo(
        take: _limit,
        skip: (_page - 1) * _limit,
        sortDesc: _sortDesc,
        sortBy: _sortBy,
        search: _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null,
        searchFields: widget.config.searchFields.isNotEmpty ? widget.config.searchFields : null,
        filters: _buildFilters(),
      );

      // Add additional parameters
      final requestData = queryInfo.toJson();
      if (widget.config.additionalParams != null) {
        requestData.addAll(widget.config.additionalParams!);
      }

      final res = await api.post<Map<String, dynamic>>(widget.config.endpoint, data: requestData);
      final body = res.data;
      
      if (body is Map<String, dynamic>) {
        final response = DataTableResponse<T>.fromJson(body, widget.fromJson);
        
        setState(() {
          _items = response.items;
          _page = response.page;
          _limit = response.limit;
          _total = response.total;
          _totalPages = response.totalPages;
          _selectedRows.clear(); // Clear selection when data changes
        });
        
        // Call the refresh callback if provided
        if (widget.onRefresh != null) {
          widget.onRefresh!();
        } else if (widget.config.onRefresh != null) {
          widget.config.onRefresh!();
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() => _loadingList = false);
    }
  }

  List<FilterItem> _buildFilters() {
    final filters = <FilterItem>[];

    // Text search filters
    for (var entry in _columnSearchValues.entries) {
      final columnName = entry.key;
      final searchValue = entry.value.trim();
      final searchType = _columnSearchTypes[columnName] ?? '*';
      
      if (searchValue.isNotEmpty) {
        filters.add(DataTableUtils.createColumnFilter(
          columnName,
          searchValue,
          searchType,
        ));
      }
    }

    // Multi-select filters
    for (var entry in _columnMultiSelectValues.entries) {
      final columnName = entry.key;
      final selectedValues = entry.value;
      
      if (selectedValues.isNotEmpty) {
        filters.add(DataTableUtils.createMultiSelectFilter(
          columnName,
          selectedValues,
        ));
      }
    }

    // Date range filters
    for (var entry in _columnDateFromValues.entries) {
      final columnName = entry.key;
      final fromDate = entry.value;
      final toDate = _columnDateToValues[columnName];
      
      if (fromDate != null && toDate != null) {
        filters.addAll(DataTableUtils.createDateRangeFilter(
          columnName,
          fromDate,
          toDate,
        ));
      }
    }

    return filters;
  }

  void _openColumnSearchDialog(String columnName, String columnLabel) {
    // Get column configuration
    final column = widget.config.getColumnByKey(columnName);
    final filterType = column?.filterType;
    final filterOptions = column?.filterOptions;

    // Initialize controller if not exists
    if (!_columnSearchControllers.containsKey(columnName)) {
      _columnSearchControllers[columnName] = TextEditingController(
        text: _columnSearchValues[columnName] ?? '',
      );
    }
    
    // Initialize search type if not exists
    _columnSearchTypes[columnName] ??= '*';

    showDialog(
      context: context,
      builder: (context) => DataTableSearchDialog(
        columnName: columnName,
        columnLabel: columnLabel,
        searchValue: _columnSearchValues[columnName] ?? '',
        searchType: _columnSearchTypes[columnName] ?? '*',
        filterType: filterType,
        filterOptions: filterOptions,
        calendarController: widget.calendarController,
        onApply: (value, type) {
          setState(() {
            _columnSearchValues[columnName] = value;
            _columnSearchTypes[columnName] = type;
          });
          _page = 1;
          _fetchData();
        },
        onApplyMultiSelect: (values) {
          setState(() {
            _columnMultiSelectValues[columnName] = values;
          });
          _page = 1;
          _fetchData();
        },
        onApplyDateRange: (fromDate, toDate) {
          setState(() {
            _columnDateFromValues[columnName] = fromDate;
            _columnDateToValues[columnName] = toDate;
          });
          _page = 1;
          _fetchData();
        },
        onClear: () {
          setState(() {
            _columnSearchValues.remove(columnName);
            _columnSearchTypes.remove(columnName);
            _columnMultiSelectValues.remove(columnName);
            _columnDateFromValues.remove(columnName);
            _columnDateToValues.remove(columnName);
            _columnSearchControllers[columnName]?.clear();
          });
          _page = 1;
          _fetchData();
        },
      ),
    );
  }


  bool _hasActiveFilters() {
    return _searchCtrl.text.isNotEmpty || 
           _columnSearchValues.isNotEmpty ||
           _columnMultiSelectValues.isNotEmpty ||
           _columnDateFromValues.isNotEmpty;
  }

  void _clearAllFilters() {
    setState(() {
      _searchCtrl.clear();
      _sortBy = null;
      _sortDesc = false;
      _columnSearchValues.clear();
      _columnSearchTypes.clear();
      _columnMultiSelectValues.clear();
      _columnDateFromValues.clear();
      _columnDateToValues.clear();
      _selectedRows.clear();
      for (var controller in _columnSearchControllers.values) {
        controller.clear();
      }
    });
    _page = 1;
    _fetchData();
    // Call the callback if provided
    if (widget.config.onRowSelectionChanged != null) {
      widget.config.onRowSelectionChanged!(_selectedRows);
    }
  }

  void _sortByColumn(String column) {
    setState(() {
      if (_sortBy == column) {
        _sortDesc = !_sortDesc;
      } else {
        _sortBy = column;
        _sortDesc = false;
      }
    });
    _fetchData();
  }

  void _toggleRowSelection(int rowIndex) {
    if (!widget.config.enableRowSelection) return;
    
    setState(() {
      if (widget.config.enableMultiRowSelection) {
        if (_selectedRows.contains(rowIndex)) {
          _selectedRows.remove(rowIndex);
        } else {
          _selectedRows.add(rowIndex);
        }
      } else {
        _selectedRows.clear();
        _selectedRows.add(rowIndex);
      }
    });
    
    if (widget.config.onRowSelectionChanged != null) {
      widget.config.onRowSelectionChanged!(_selectedRows);
    }
  }

  void _selectAllRows() {
    if (!widget.config.enableRowSelection || !widget.config.enableMultiRowSelection) return;
    
    setState(() {
      _selectedRows.clear();
      for (int i = 0; i < _items.length; i++) {
        _selectedRows.add(i);
      }
    });
    
    if (widget.config.onRowSelectionChanged != null) {
      widget.config.onRowSelectionChanged!(_selectedRows);
    }
  }

  void _clearRowSelection() {
    if (!widget.config.enableRowSelection) return;
    
    setState(() {
      _selectedRows.clear();
    });
    
    if (widget.config.onRowSelectionChanged != null) {
      widget.config.onRowSelectionChanged!(_selectedRows);
    }
  }

  Future<void> _openColumnSettingsDialog() async {
    if (!widget.config.enableColumnSettings || _columnSettings == null) return;

    final result = await showDialog<ColumnSettings>(
      context: context,
      builder: (context) => ColumnSettingsDialog(
        columns: widget.config.columns,
        currentSettings: _columnSettings!,
        tableTitle: widget.config.title ?? 'Table',
      ),
    );

    if (result != null) {
      await _saveColumnSettings(result);
    }
  }

  Future<void> _saveColumnSettings(ColumnSettings settings) async {
    if (!widget.config.enableColumnSettings) return;

    try {
      // Ensure at least one column is visible
      final validatedSettings = _validateColumnSettings(settings);
      
      final tableId = widget.config.effectiveTableId;
      await ColumnSettingsService.saveColumnSettings(tableId, validatedSettings);
      
      setState(() {
        _columnSettings = validatedSettings;
        _visibleColumns = _getVisibleColumnsFromSettings(validatedSettings);
      });

      // Call the callback if provided
      if (widget.config.onColumnSettingsChanged != null) {
        widget.config.onColumnSettingsChanged!(validatedSettings);
      }
    } catch (e) {
      debugPrint('Error saving column settings: $e');
      if (mounted) {
        final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('${t.error}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  ColumnSettings _validateColumnSettings(ColumnSettings settings) {
    // Ensure at least one column is visible
    if (settings.visibleColumns.isEmpty && widget.config.columns.isNotEmpty) {
      return settings.copyWith(
        visibleColumns: [widget.config.columns.first.key],
        columnOrder: [widget.config.columns.first.key],
      );
    }
    return settings;
  }

  Future<void> _exportData(String format, bool selectedOnly) async {
    if (widget.config.excelEndpoint == null && widget.config.pdfEndpoint == null) {
      return;
    }

    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;

    setState(() {
      _isExporting = true;
    });

    try {
      final api = ApiClient();
      final endpoint = format == 'excel' 
          ? widget.config.excelEndpoint! 
          : widget.config.pdfEndpoint!;
      
      // Build QueryInfo object
      final filters = <Map<String, dynamic>>[];
      
      // Add column filters
      _columnSearchValues.forEach((column, value) {
        if (value.isNotEmpty) {
          final searchType = _columnSearchTypes[column] ?? 'contains';
          String operator;
          switch (searchType) {
            case 'contains':
              operator = '*';
              break;
            case 'startsWith':
              operator = '*?';
              break;
            case 'endsWith':
              operator = '?*';
              break;
            case 'exactMatch':
              operator = '=';
              break;
            default:
              operator = '*';
          }
          filters.add({
            'property': column,
            'operator': operator,
            'value': value,
          });
        }
      });


      final queryInfo = {
        'sort_by': _sortBy,
        'sort_desc': _sortDesc,
        'take': _limit,
        'skip': (_page - 1) * _limit,
        'search': _searchCtrl.text.isNotEmpty ? _searchCtrl.text : null,
        'search_fields': _searchCtrl.text.isNotEmpty && widget.config.searchFields.isNotEmpty 
            ? widget.config.searchFields 
            : null,
        'filters': filters.isNotEmpty ? filters : null,
      };

      final params = <String, dynamic>{
        'selected_only': selectedOnly,
      };

      // Add selected row indices if exporting selected only
      if (selectedOnly && _selectedRows.isNotEmpty) {
        params['selected_indices'] = _selectedRows.toList();
      }

      // Add export columns in current visible order (excluding ActionColumn)
      final columnsToShow = widget.config.enableColumnSettings && _visibleColumns.isNotEmpty
          ? _visibleColumns
          : widget.config.columns;
      final dataColumnsToShow = columnsToShow.where((c) => c is! ActionColumn).toList();
      params['export_columns'] = dataColumnsToShow.map((c) => {
        'key': c.key,
        'label': c.label,
      }).toList();

      // Add custom export parameters if provided
      if (widget.config.getExportParams != null) {
        final customParams = widget.config.getExportParams!();
        params.addAll(customParams);
      }

      final response = await api.post(
        endpoint,
        data: {
          ...queryInfo,
          ...params,
        },
        options: Options(
          headers: {
            'X-Calendar-Type': 'jalali', // Send Jalali calendar type
            'Accept-Language': Localizations.localeOf(context).languageCode, // Send locale
          },
        ),
        responseType: ResponseType.bytes, // Both PDF and Excel now return binary data
      );

      if (response.data != null) {
        // Determine filename from Content-Disposition header if present
        String? contentDisposition = response.headers.value('content-disposition');
        String filename = 'export_${DateTime.now().millisecondsSinceEpoch}.${format == 'pdf' ? 'pdf' : 'xlsx'}';
        if (contentDisposition != null) {
          try {
            final parts = contentDisposition.split(';').map((s) => s.trim());
            for (final p in parts) {
              if (p.toLowerCase().startsWith('filename=')) {
                var name = p.substring('filename='.length).trim();
                if (name.startsWith('"') && name.endsWith('"') && name.length >= 2) {
                  name = name.substring(1, name.length - 1);
                }
                if (name.isNotEmpty) {
                  filename = name;
                }
                break;
              }
            }
          } catch (_) {
            // Fallback to default filename
          }
        }
        final expectedExt = format == 'pdf' ? '.pdf' : '.xlsx';
        if (!filename.toLowerCase().endsWith(expectedExt)) {
          filename = '$filename$expectedExt';
        }

        if (format == 'pdf') {
          await _downloadPdf(response.data, filename);
        } else if (format == 'excel') {
          await _downloadExcel(response.data, filename);
        }
        
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text(t.exportSuccess),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('${t.exportError}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // Cross-platform save using conditional FileSaver
  Future<void> _saveBytesToDownloads(dynamic data, String filename) async {
    List<int> bytes;
    if (data is List<int>) {
      bytes = data;
    } else if (data is Uint8List) {
      bytes = data.toList();
    } else {
      throw Exception('Unsupported binary data type: ${data.runtimeType}');
    }
    await FileSaver.saveBytes(bytes, filename);
  }

  Future<void> _downloadPdf(dynamic data, String filename) async {
    await _saveBytesToDownloads(data, filename);
  }

  Future<void> _downloadExcel(dynamic data, String filename) async {
    await _saveBytesToDownloads(data, filename);
  }


  @override
  Widget build(BuildContext context) {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    final theme = Theme.of(context);

    return Card(
      elevation: widget.config.boxShadow != null ? 2 : 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: widget.config.borderRadius ?? BorderRadius.circular(12),
      ),
      child: Container(
        padding: widget.config.padding ?? const EdgeInsets.all(16),
        margin: widget.config.margin,
        decoration: BoxDecoration(
          color: widget.config.backgroundColor,
          borderRadius: widget.config.borderRadius ?? BorderRadius.circular(12),
          border: widget.config.showBorder 
              ? Border.all(
                  color: widget.config.borderColor ?? theme.dividerColor,
                  width: widget.config.borderWidth ?? 1.0,
                )
              : null,
        ),
        child: Column(
          children: [
            // Header
            if (widget.config.title != null) ...[
              _buildHeader(t, theme),
              const SizedBox(height: 16),
            ],
            
            // Search
            if (widget.config.showSearch) ...[
              _buildSearch(t, theme),
              const SizedBox(height: 12),
            ],
            
            // Active Filters
            if (widget.config.showActiveFilters) ...[
              ActiveFiltersWidget(
                columnSearchValues: _columnSearchValues,
                columnSearchTypes: _columnSearchTypes,
                columnMultiSelectValues: _columnMultiSelectValues,
                columnDateFromValues: _columnDateFromValues,
                columnDateToValues: _columnDateToValues,
                fromDate: null,
                toDate: null,
                columns: widget.config.columns,
                calendarController: widget.calendarController,
                onRemoveColumnFilter: (columnName) {
                  setState(() {
                    _columnSearchValues.remove(columnName);
                    _columnSearchTypes.remove(columnName);
                    _columnMultiSelectValues.remove(columnName);
                    _columnDateFromValues.remove(columnName);
                    _columnDateToValues.remove(columnName);
                    _columnSearchControllers[columnName]?.clear();
                  });
                  _page = 1;
                  _fetchData();
                },
                onClearAll: _clearAllFilters,
              ),
              const SizedBox(height: 10),
            ],
            
            // Data Table
            Expanded(
              child: _buildDataTable(t, theme),
            ),
            
            // Footer with Pagination
            if (widget.config.showPagination) ...[
              const SizedBox(height: 12),
              _buildFooter(t, theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, ThemeData theme) {
    return Row(
      children: [
        if (widget.config.showBackButton) ...[
          Tooltip(
            message: MaterialLocalizations.of(context).backButtonTooltip,
            child: IconButton(
              onPressed: widget.config.onBack ?? () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (widget.config.showTableIcon) ...[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.table_chart, 
              color: theme.colorScheme.onPrimaryContainer, 
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Text(
          widget.config.title!,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (widget.config.subtitle != null) ...[
          const SizedBox(width: 8),
          Text(
            widget.config.subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const Spacer(),
        
        
        // Clear filters button (only show when filters are applied)
        if (widget.config.showClearFiltersButton && _hasActiveFilters()) ...[
          Tooltip(
            message: t.clear,
            child: IconButton(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.clear_all),
              tooltip: t.clear,
            ),
          ),
          const SizedBox(width: 4),
        ],
        
        // Export buttons
        if (widget.config.excelEndpoint != null || widget.config.pdfEndpoint != null) ...[
          _buildExportButtons(t, theme),
          const SizedBox(width: 8),
        ],
        
        // Custom header actions
        if (widget.config.customHeaderActions != null) ...[
          const SizedBox(width: 8),
          ...widget.config.customHeaderActions!,
        ],
        
        // Actions menu
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'عملیات',
          onSelected: (value) {
            switch (value) {
              case 'refresh':
                _fetchData();
                break;
              case 'columnSettings':
                _openColumnSettingsDialog();
                break;
            }
          },
          itemBuilder: (context) => [
            if (widget.config.showRefreshButton)
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    const Icon(Icons.refresh, size: 20),
                    const SizedBox(width: 8),
                    Text(t.refresh),
                  ],
                ),
              ),
            if (widget.config.showColumnSettingsButton && widget.config.enableColumnSettings)
              PopupMenuItem(
                value: 'columnSettings',
                enabled: !_isLoadingColumnSettings,
                child: Row(
                  children: [
                    _isLoadingColumnSettings
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.view_column, size: 20),
                    const SizedBox(width: 8),
                    Text(t.columnSettings),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildExportButtons(AppLocalizations t, ThemeData theme) {
    return _buildExportButton(t, theme);
  }

  Widget _buildExportButton(
    AppLocalizations t,
    ThemeData theme,
  ) {
    return Tooltip(
      message: t.export,
      child: GestureDetector(
        onTap: () => _showExportOptions(t, theme),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: _isExporting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                )
              : Icon(
                  Icons.download,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }

  void _showExportOptions(
    AppLocalizations t,
    ThemeData theme,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.download, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    t.export,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Excel options
            if (widget.config.excelEndpoint != null) ...[
              ListTile(
                leading: Icon(Icons.table_chart, color: Colors.green[600]),
                title: Text(t.exportToExcel),
                subtitle: Text(t.exportAll),
                onTap: () {
                  Navigator.pop(context);
                  _exportData('excel', false);
                },
              ),
              
              if (widget.config.enableRowSelection && _selectedRows.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.table_chart, color: theme.colorScheme.primary),
                  title: Text(t.exportToExcel),
                  subtitle: Text(t.exportSelected),
                  onTap: () {
                    Navigator.pop(context);
                    _exportData('excel', true);
                  },
                ),
            ],
            
            // PDF options
            if (widget.config.pdfEndpoint != null) ...[
              if (widget.config.excelEndpoint != null) const Divider(height: 1),
              
              ListTile(
                leading: Icon(Icons.picture_as_pdf, color: Colors.red[600]),
                title: Text(t.exportToPdf),
                subtitle: Text(t.exportAll),
                onTap: () {
                  Navigator.pop(context);
                  _exportData('pdf', false);
                },
              ),
              
              if (widget.config.enableRowSelection && _selectedRows.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.picture_as_pdf, color: theme.colorScheme.primary),
                  title: Text(t.exportToPdf),
                  subtitle: Text(t.exportSelected),
                  onTap: () {
                    Navigator.pop(context);
                    _exportData('pdf', true);
                  },
                ),
            ],
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(AppLocalizations t, ThemeData theme) {
    // Always show footer if pagination is enabled
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Results info
          Text(
            '${t.showing} ${((_page - 1) * _limit) + 1} ${t.to} ${(_page * _limit).clamp(0, _total)} ${t.ofText} $_total ${t.results}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          
          // Page size selector
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.recordsPerPage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _limit,
                items: widget.config.pageSizeOptions.map((size) {
                  return DropdownMenuItem(
                    value: size,
                    child: Text(size.toString()),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _limit = value;
                      _page = 1;
                    });
                    _fetchData();
                  }
                },
                style: theme.textTheme.bodySmall,
                underline: const SizedBox.shrink(),
                isDense: true,
              ),
            ],
          ),
          const SizedBox(width: 16),
          
          // Pagination controls (only show if more than 1 page)
          if (_totalPages > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // First page
                IconButton(
                  onPressed: _page > 1 ? () {
                    setState(() => _page = 1);
                    _fetchData();
                  } : null,
                  icon: const Icon(Icons.first_page),
                  iconSize: 20,
                  tooltip: t.firstPage,
                ),
                
                // Previous page
                IconButton(
                  onPressed: _page > 1 ? () {
                    setState(() => _page--);
                    _fetchData();
                  } : null,
                  icon: const Icon(Icons.chevron_left),
                  iconSize: 20,
                  tooltip: t.previousPage,
                ),
                
                // Page numbers
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$_page / $_totalPages',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                
                // Next page
                IconButton(
                  onPressed: _page < _totalPages ? () {
                    setState(() => _page++);
                    _fetchData();
                  } : null,
                  icon: const Icon(Icons.chevron_right),
                  iconSize: 20,
                  tooltip: t.nextPage,
                ),
                
                // Last page
                IconButton(
                  onPressed: _page < _totalPages ? () {
                    setState(() => _page = _totalPages);
                    _fetchData();
                  } : null,
                  icon: const Icon(Icons.last_page),
                  iconSize: 20,
                  tooltip: t.lastPage,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSearch(AppLocalizations t, ThemeData theme) {
    return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: t.searchInNameEmail,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ),
        ],
      );
  }

  Widget _buildDataTable(AppLocalizations t, ThemeData theme) {
    if (_loadingList) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.config.loadingWidget != null)
              widget.config.loadingWidget!
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              widget.config.loadingMessage ?? t.loading,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.config.errorWidget != null)
              widget.config.errorWidget!
            else
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
            const SizedBox(height: 16),
            Text(
              widget.config.errorMessage ?? t.dataLoadingError,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _fetchData,
              icon: const Icon(Icons.refresh),
              label: Text(t.refresh),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.config.emptyStateWidget != null)
              widget.config.emptyStateWidget!
            else
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            const SizedBox(height: 16),
            Text(
              widget.config.emptyStateMessage ?? t.noDataFound,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    // Build columns list
    final List<DataColumn2> columns = [];
    
    // Add selection column if enabled (first)
    if (widget.config.enableRowSelection) {
      columns.add(DataColumn2(
        label: widget.config.enableMultiRowSelection
            ? Checkbox(
                value: _selectedRows.length == _items.length && _items.isNotEmpty,
                tristate: true,
                onChanged: (value) {
                  if (value == true) {
                    _selectAllRows();
                  } else {
                    _clearRowSelection();
                  }
                },
              )
            : const SizedBox.shrink(),
        size: ColumnSize.S,
        fixedWidth: 50.0,
      ));
    }
    
    // Add row number column if enabled (second)
    if (widget.config.showRowNumbers) {
      columns.add(DataColumn2(
        label: Text(
          '#',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        size: ColumnSize.S,
        fixedWidth: 60.0,
      ));
    }
    
    // Resolve action column (if defined in config)
    ActionColumn? actionColumn;
    for (final c in widget.config.columns) {
      if (c is ActionColumn) {
        actionColumn = c;
        break;
      }
    }

    // Fixed action column immediately after selection and row number columns
    if (actionColumn != null) {
      columns.add(DataColumn2(
        label: Text(
          actionColumn.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        size: ColumnSize.S,
        fixedWidth: 80.0,
      ));
    }

    // Add data columns (use visible columns if column settings are enabled), excluding ActionColumn
    final columnsToShow = widget.config.enableColumnSettings && _visibleColumns.isNotEmpty
        ? _visibleColumns
        : widget.config.columns;
    final dataColumnsToShow = columnsToShow.where((c) => c is! ActionColumn).toList();
    
    columns.addAll(dataColumnsToShow.map((column) {
      return DataColumn2(
        label: _ColumnHeaderWithSearch(
          text: column.label,
          sortBy: column.key,
          currentSort: _sortBy,
          sortDesc: _sortDesc,
          onSort: widget.config.enableSorting ? _sortByColumn : (_) { },
          onSearch: widget.config.showColumnSearch && column.searchable
              ? () => _openColumnSearchDialog(column.key, column.label)
              : () { },
          hasActiveFilter: _columnSearchValues.containsKey(column.key),
          enabled: widget.config.enableSorting && column.sortable,
        ),
        size: DataTableUtils.getColumnSize(column.width),
        fixedWidth: DataTableUtils.getColumnWidth(column.width),
      );
    }));

    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      child: DataTable2(
        columnSpacing: 8,
        horizontalMargin: 8,
        minWidth: widget.config.minTableWidth ?? 600,
        horizontalScrollController: _horizontalScrollController,
        columns: columns,
      rows: _items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final isSelected = _selectedRows.contains(index);
        
        // Build cells list
        final List<DataCell> cells = [];
        
        // Add selection cell if enabled (first)
        if (widget.config.enableRowSelection) {
          cells.add(DataCell(
            Checkbox(
              value: isSelected,
              onChanged: (value) => _toggleRowSelection(index),
            ),
          ));
        }
        
        // Add row number cell if enabled (second)
        if (widget.config.showRowNumbers) {
          cells.add(DataCell(
            Text(
              '${((_page - 1) * _limit) + index + 1}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ));
        }
        
        // 3) Fixed action cell (immediately after selection and row number)
        // Resolve action column once (same logic as header)
        ActionColumn? actionColumn;
        for (final c in widget.config.columns) {
          if (c is ActionColumn) {
            actionColumn = c;
            break;
          }
        }
        if (actionColumn != null) {
          cells.add(DataCell(
            _buildActionButtons(item, actionColumn),
          ));
        }

        // 4) Add data cells
        if (widget.config.customRowBuilder != null) {
          cells.add(DataCell(
            widget.config.customRowBuilder!(item) ?? const SizedBox.shrink(),
          ));
        } else {
          final columnsToShow = widget.config.enableColumnSettings && _visibleColumns.isNotEmpty
              ? _visibleColumns
              : widget.config.columns;
          final dataColumnsToShow = columnsToShow.where((c) => c is! ActionColumn).toList();
              
          cells.addAll(dataColumnsToShow.map((column) {
            return DataCell(
              _buildCellContent(item, column, index),
            );
          }));
        }
        
        return DataRow2(
          selected: isSelected,
          onTap: widget.config.onRowTap != null 
              ? () => widget.config.onRowTap!(item)
              : null,
          onDoubleTap: widget.config.onRowDoubleTap != null 
              ? () => widget.config.onRowDoubleTap!(item)
              : null,
          cells: cells,
        );
      }).toList(),
      ),
    );
  }

  Widget _buildCellContent(dynamic item, DataTableColumn column, int index) {
    // 1) Custom widget builder takes precedence
    if (column is CustomColumn && column.builder != null) {
      return column.builder!(item, index);
    }
    
    // 2) Action column
    if (column is ActionColumn) {
      return _buildActionButtons(item, column);
    }

    // 3) If a formatter is provided on the column, call it with the full item
    // This allows working with strongly-typed objects (not just Map)
    if (column is TextColumn && column.formatter != null) {
      final text = column.formatter!(item) ?? '';
      return Text(
        text,
        textAlign: _getTextAlign(column),
        maxLines: _getMaxLines(column),
        overflow: _getOverflow(column),
      );
    }
    if (column is NumberColumn && column.formatter != null) {
      final text = column.formatter!(item) ?? '';
      return Text(
        text,
        textAlign: _getTextAlign(column),
        maxLines: _getMaxLines(column),
        overflow: _getOverflow(column),
      );
    }
    if (column is DateColumn && column.formatter != null) {
      final text = column.formatter!(item) ?? '';
      return Text(
        text,
        textAlign: _getTextAlign(column),
        maxLines: _getMaxLines(column),
        overflow: _getOverflow(column),
      );
    }

    // 4) Fallback: get property value from Map items by key
    final value = DataTableUtils.getCellValue(item, column.key);
    final formattedValue = DataTableUtils.formatCellValue(value, column);
    return Text(
      formattedValue,
      textAlign: _getTextAlign(column),
      maxLines: _getMaxLines(column),
      overflow: _getOverflow(column),
    );
  }

  Widget _buildActionButtons(dynamic item, ActionColumn column) {
    if (column.actions.isEmpty) return const SizedBox.shrink();
    
    return PopupMenuButton<int>(
      tooltip: column.label,
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (index) {
        final action = column.actions[index];
        if (action.enabled) action.onTap(item);
      },
      itemBuilder: (context) {
        return List.generate(column.actions.length, (index) {
          final action = column.actions[index];
          return PopupMenuItem<int>(
            value: index,
            enabled: action.enabled,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  color: action.isDestructive 
                      ? Theme.of(context).colorScheme.error
                      : (action.color ?? Theme.of(context).iconTheme.color),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(action.label),
              ],
            ),
          );
        });
      },
    );
  }

  TextAlign _getTextAlign(DataTableColumn column) {
    if (column is NumberColumn) return column.textAlign;
    if (column is DateColumn) return column.textAlign;
    if (column is TextColumn && column.textAlign != null) return column.textAlign!;
    return TextAlign.start;
  }

  int? _getMaxLines(DataTableColumn column) {
    if (column is TextColumn) return column.maxLines;
    return null;
  }

  TextOverflow? _getOverflow(DataTableColumn column) {
    if (column is TextColumn && column.overflow != null) {
      return column.overflow! ? TextOverflow.ellipsis : null;
    }
    return null;
  }
}

/// Column header with search functionality
class _ColumnHeaderWithSearch extends StatelessWidget {
  final String text;
  final String sortBy;
  final String? currentSort;
  final bool sortDesc;
  final Function(String) onSort;
  final VoidCallback onSearch;
  final bool hasActiveFilter;
  final bool enabled;

  const _ColumnHeaderWithSearch({
    required this.text,
    required this.sortBy,
    required this.currentSort,
    required this.sortDesc,
    required this.onSort,
    required this.onSearch,
    required this.hasActiveFilter,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = currentSort == sortBy;
    
    return InkWell(
      onTap: enabled ? () => onSort(sortBy) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        text,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (enabled) ...[
                      const SizedBox(width: 4),
                      if (isActive)
                        Icon(
                          sortDesc ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 16,
                          color: theme.colorScheme.primary,
                        )
                      else
                        Icon(
                          Icons.unfold_more,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Search button
              InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: hasActiveFilter 
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: hasActiveFilter 
                        ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3))
                        : null,
                  ),
                  child: Icon(
                    Icons.search,
                    size: 14,
                    color: hasActiveFilter 
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
