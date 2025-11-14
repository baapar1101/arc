import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;
import 'package:flutter/foundation.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/report_template_service.dart';
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
  // Multi-sort: first item is primary sort
  final List<_SortSpec> _multiSort = <_SortSpec>[];

  // Row selection state
  final Set<int> _selectedRows = <int>{};
  bool _isExporting = false;
  int? _templateIdForExport;
  // Report templates (for PDF export)
  List<Map<String, dynamic>> _availableTemplates = const [];
  bool _loadingTemplates = false;
  int? _selectedTemplateIdFromList;
  // Auto-fit
  bool _autoFitApplied = false;
  
  // Column settings state
  ColumnSettings? _columnSettings;
  List<DataTableColumn> _visibleColumns = [];
  bool _isLoadingColumnSettings = false;
  
  // Scroll controller for horizontal scrolling
  late ScrollController _horizontalScrollController;
  
  // Density (row height)
  bool _dense = false;
  
  // Keyboard focus and navigation
  final FocusNode _tableFocusNode = FocusNode(debugLabel: 'DataTableFocus');
  int _activeRowIndex = -1;
  int? _lastSelectedRowIndex;
  
  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _limit = widget.config.defaultPageSize;
    // Initialize default sort if provided
    if (widget.config.enableSorting) {
      _sortBy = widget.config.defaultSortBy;
      _sortDesc = widget.config.defaultSortDesc;
    }
    _setupSearchListener();
    _loadColumnSettings();
    _loadDensityPreference();
    _fetchData();
  }

  /// Public method to refresh the data table
  void refresh() {
    _fetchData();
  }

  // Public helpers for external widgets (via GlobalKey)
  List<int> getSelectedRowIndices() {
    return _selectedRows.toList();
  }

  List<T> getSelectedItems() {
    if (_selectedRows.isEmpty) return const [];
    final list = <T>[];
    for (final i in _selectedRows) {
      if (i >= 0 && i < _items.length) {
        list.add(_items[i]);
      }
    }
    return list;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _horizontalScrollController.dispose();
    _tableFocusNode.dispose();
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

  Future<void> _loadDensityPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'data_table_density_${widget.config.effectiveTableId}';
      final dense = prefs.getBool(key) ?? false;
      if (mounted) setState(() => _dense = dense);
    } catch (_) {}
  }

  Future<void> _saveDensityPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'data_table_density_${widget.config.effectiveTableId}';
      await prefs.setBool(key, _dense);
    } catch (_) {}
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
    if (mounted) {
      setState(() => _loadingList = true);
    }
    _error = null;

    try {
      final api = ApiClient();
      
      // Build QueryInfo payload
      final queryInfo = QueryInfo(
        take: _limit,
        skip: (_page - 1) * _limit,
        sortDesc: _sortDesc,
        sortBy: _sortBy,
        sorts: _multiSort.isNotEmpty
            ? _multiSort.map((s) => SortItem(by: s.by, desc: s.desc)).toList()
            : null,
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
        
        if (mounted) {
          setState(() {
            _items = response.items;
            _page = response.page;
            _limit = response.limit;
            _total = response.total;
            _totalPages = response.totalPages;
            _selectedRows.clear(); // Clear selection when data changes
            _activeRowIndex = _items.isNotEmpty ? 0 : -1;
            _lastSelectedRowIndex = null;
          });
        }
        
        // Auto-fit columns on first load if configured
        await _maybeAutoFitColumns();
        
        // Call the refresh callback if provided
        if (widget.onRefresh != null) {
          widget.onRefresh!();
        } else if (widget.config.onRefresh != null) {
          widget.config.onRefresh!();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loadingList = false);
      }
    }
  }
  
  Future<void> _maybeAutoFitColumns() async {
    // Conditions:
    // - Feature enabled
    // - We have items to sample
    // - Apply only once per widget lifecycle
    if (!_autoFitApplied &&
        widget.config.enableColumnSettings &&
        widget.config.autoFitColumnsOnFirstLoad &&
        _items.isNotEmpty) {
      // Ensure we have column settings to update
      ColumnSettings settings = _columnSettings ??
          ColumnSettingsService.getDefaultSettings(widget.config.columnKeys);
      // Respect user widths: only apply if no widths are set yet
      if (settings.columnWidths.isNotEmpty) {
        _autoFitApplied = true;
        return;
      }
      // Build styles and parameters
      final theme = Theme.of(context);
      final headerTextStyle = theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ) ??
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
      final cellTextStyle =
          theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
      final minWidth = 96.0;
      // Columns to show (exclude action)
      final columnsToShow = widget.config.enableColumnSettings && _visibleColumns.isNotEmpty
          ? _visibleColumns
          : widget.config.columns;
      final dataColumns = columnsToShow.where((c) => c is! ActionColumn).toList();
      // Compute widths
      final Map<String, double> computed = {};
      for (final column in dataColumns) {
        final affordancePadding = _getHeaderAffordancePadding(column);
        final width = _autoFitColumnWidth(
          column,
          headerTextStyle,
          cellTextStyle,
          minWidth,
          affordancePadding,
          sampleCountOverride: widget.config.autoFitSampleRows,
        );
        computed[column.key] = width;
      }
      // Update and save
      final updated = settings.copyWith(
        columnWidths: {
          ...settings.columnWidths,
          ...computed,
        },
      );
      try {
        await ColumnSettingsService.saveColumnSettings(
          widget.config.effectiveTableId,
          updated,
        );
        if (mounted) {
          setState(() {
            _columnSettings = updated;
            _visibleColumns = _getVisibleColumnsFromSettings(updated);
            _autoFitApplied = true;
          });
        } else {
          _autoFitApplied = true;
        }
      } catch (_) {
        _autoFitApplied = true;
      }
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

  void _sortByColumnInternal(String column, {required bool additive}) {
    setState(() {
      if (!additive) {
        if (_sortBy == column) {
          _sortDesc = !_sortDesc;
        } else {
          _sortBy = column;
          _sortDesc = false;
        }
        _multiSort
          ..clear()
          ..add(_SortSpec(by: _sortBy!, desc: _sortDesc));
      } else {
        final existingIndex = _multiSort.indexWhere((s) => s.by == column);
        if (existingIndex >= 0) {
          final existing = _multiSort[existingIndex];
          _multiSort[existingIndex] = existing.copyWith(desc: !existing.desc);
        } else {
          _multiSort.add(_SortSpec(by: column, desc: false));
        }
        if (_multiSort.isNotEmpty) {
          _sortBy = _multiSort.first.by;
          _sortDesc = _multiSort.first.desc;
        }
      }
    });
    _page = 1;
    _fetchData();
  }

  void _toggleRowSelection(int rowIndex) {
    if (!widget.config.enableRowSelection) return;
    
    setState(() {
      final bool isShift = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);

      if (widget.config.enableMultiRowSelection && isShift && _lastSelectedRowIndex != null) {
        final int start = math.min(_lastSelectedRowIndex!, rowIndex);
        final int end = math.max(_lastSelectedRowIndex!, rowIndex);
        for (int i = start; i <= end; i++) {
          _selectedRows.add(i);
        }
      } else {
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
        _lastSelectedRowIndex = rowIndex;
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
      // Optional report template for PDF
      if (format == 'pdf' && _templateIdForExport != null) {
        params['template_id'] = _templateIdForExport;
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
            // Calendar type based on current locale
            'X-Calendar-Type': (() {
              final loc = Localizations.localeOf(context);
              final lang = (loc.languageCode).toLowerCase();
              return (lang == 'fa') ? 'jalali' : 'gregorian';
            })(),
            // Send full locale code if available (e.g., fa-IR)
            'Accept-Language': (() {
              final loc = Localizations.localeOf(context);
              final lang = loc.languageCode;
              final country = loc.countryCode;
              return (country != null && country.isNotEmpty) ? '$lang-$country' : lang;
            })(),
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
    Uint8List bytes;
    if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    } else if (data is Uint8List) {
      bytes = data;
    } else {
      throw Exception('Unsupported binary data type: ${data.runtimeType}');
    }
    
    // Use file_saver package for cross-platform file saving
    try {
      final fileSaver = FileSaver.instance;
      final extension = filename.split('.').last;
      await fileSaver.saveFile(
        name: filename,
        bytes: bytes,
        ext: extension,
      );
    } catch (e) {
      print('Error saving file: $e');
      rethrow;
    }
  }

  // Platform-specific download functions for Linux
  Future<void> _downloadPdf(dynamic data, String filename) async {
    try {
      await _saveBytesToDownloads(data, filename);
      print('✅ PDF downloaded successfully: $filename');
    } catch (e) {
      print('❌ Error downloading PDF: $e');
      rethrow;
    }
  }

  Future<void> _downloadExcel(dynamic data, String filename) async {
    try {
      await _saveBytesToDownloads(data, filename);
      print('✅ Excel downloaded successfully: $filename');
    } catch (e) {
      print('❌ Error downloading Excel: $e');
      rethrow;
    }
  }

  // Cache for measured text widths to reduce TextPainter.layout calls
  final Map<String, double> _textWidthCache = <String, double>{};

  // Removed legacy _measureTextWidthDir (replaced with advanced API)

  double _measureTextWidthAdvanced({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required double textScaleFactor,
    required Locale locale,
  }) {
    final key = [
      text,
      style.fontFamily,
      style.fontSize,
      style.fontWeight?.index,
      style.letterSpacing,
      style.height,
      style.fontStyle?.index,
      textDirection.name,
      textScaleFactor.toStringAsFixed(3),
      locale.toLanguageTag(),
    ].join('|');
    final cached = _textWidthCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaleFactor: textScaleFactor,
      locale: locale,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    final width = painter.width;
    if (_textWidthCache.length > 512) {
      _textWidthCache.clear();
    }
    _textWidthCache[key] = width;
    return width;
  }

  double _measureHeaderTextWidth(String text, TextStyle style) {
    final dir = Directionality.of(context);
    final scale = MediaQuery.maybeOf(context)?.textScaleFactor ?? 1.0;
    final locale = Localizations.localeOf(context);
    return _measureTextWidthAdvanced(
      text: text,
      style: style,
      textDirection: dir,
      textScaleFactor: scale,
      locale: locale,
    );
  }

  double _getHeaderAffordancePadding(DataTableColumn column) {
    double padding = 0.0;
    // Container padding (left + right)
    padding += 16.0;
    // Left group: sort icon spacing + icon (always shows when sortable)
    final bool showSortIcon = widget.config.enableSorting && column.sortable;
    if (showSortIcon) {
      padding += 4.0;  // gap between text and icon
      padding += 16.0; // icon width
    }
    // Gap between left group and search button
    padding += 8.0;
    // Search button chip
    final bool showSearch = widget.config.showColumnSearch && column.searchable;
    if (showSearch) {
      padding += 4.0;   // left padding
      padding += 13.0;  // icon
      padding += 4.0;   // right padding
      padding += 2.0;   // border thickness approx
    }
    // Resize handle (gap + handle width)
    if (widget.config.enableColumnSettings) {
      padding += 6.0;   // gap
      padding += 12.0;  // handle
    }
    // Settings menu (gap + icon)
    if (widget.config.enableColumnSettings) {
      padding += 4.0;   // gap
      padding += 16.0;  // icon
    }
    // Safety margin
    padding += 8.0;
    return padding;
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
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.keyJ): const MoveRowIntent(1),
          LogicalKeySet(LogicalKeyboardKey.keyK): const MoveRowIntent(-1),
          LogicalKeySet(LogicalKeyboardKey.arrowDown): const MoveRowIntent(1),
          LogicalKeySet(LogicalKeyboardKey.arrowUp): const MoveRowIntent(-1),
          LogicalKeySet(LogicalKeyboardKey.enter): const ActivateRowIntent(),
          LogicalKeySet(LogicalKeyboardKey.space): const ToggleSelectionIntent(),
          LogicalKeySet(LogicalKeyboardKey.escape): const ClearSelectionIntent(),
          LogicalKeySet(LogicalKeyboardKey.keyA, LogicalKeyboardKey.control): const SelectAllIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            MoveRowIntent: CallbackAction<MoveRowIntent>(onInvoke: (intent) {
              if (_items.isEmpty) return null;
              setState(() {
                final next = (_activeRowIndex == -1 ? 0 : _activeRowIndex) + intent.delta;
                _activeRowIndex = next.clamp(0, _items.length - 1);
              });
              return null;
            }),
            ActivateRowIntent: CallbackAction<ActivateRowIntent>(onInvoke: (intent) {
              if (_activeRowIndex >= 0 && _activeRowIndex < _items.length && widget.config.onRowTap != null) {
                widget.config.onRowTap!(_items[_activeRowIndex]);
              }
              return null;
            }),
            ToggleSelectionIntent: CallbackAction<ToggleSelectionIntent>(onInvoke: (intent) {
              if (widget.config.enableRowSelection && _activeRowIndex >= 0 && _activeRowIndex < _items.length) {
                _toggleRowSelection(_activeRowIndex);
              }
              return null;
            }),
            ClearSelectionIntent: CallbackAction<ClearSelectionIntent>(onInvoke: (intent) {
              _clearRowSelection();
              return null;
            }),
            SelectAllIntent: CallbackAction<SelectAllIntent>(onInvoke: (intent) {
              _selectAllRows();
              return null;
            }),
          },
          child: Focus(
            focusNode: _tableFocusNode,
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
            
            // Selection toolbar
            if (widget.config.enableRowSelection && _selectedRows.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_box, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('${_selectedRows.length} مورد انتخاب شده',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _clearRowSelection,
                      icon: const Icon(Icons.clear),
                      label: const Text('لغو انتخاب'),
                    ),
                  ],
                ),
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
          ),
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
              case 'toggleDensity':
                setState(() {
                  _dense = !_dense;
                });
                _saveDensityPreference();
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
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'toggleDensity',
              child: Row(
                children: [
                  Icon(_dense ? Icons.check_box : Icons.check_box_outline_blank, size: 20),
                  const SizedBox(width: 8),
                  const Text('حالت فشرده'),
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
    Future<void> _ensureTemplatesLoaded() async {
      if (widget.config.pdfEndpoint == null) return;
      if (widget.config.businessId == null || widget.config.reportModuleKey == null) return;
      setState(() => _loadingTemplates = true);
      try {
        final service = ReportTemplateService(ApiClient());
        final list = await service.listTemplates(
          businessId: widget.config.businessId!,
          moduleKey: widget.config.reportModuleKey,
          subtype: widget.config.reportSubtype,
          status: 'published',
        );
        if (mounted) {
          setState(() {
            _availableTemplates = list;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _availableTemplates = const [];
          });
        }
      } finally {
        if (mounted) setState(() => _loadingTemplates = false);
      }
    }
    _ensureTemplatesLoaded();
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
            
            if (widget.config.pdfEndpoint != null) ...[
              if (widget.config.businessId != null && widget.config.reportModuleKey != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _loadingTemplates
                            ? const LinearProgressIndicator(minHeight: 2)
                            : DropdownButtonFormField<int?>(
                                value: _selectedTemplateIdFromList,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.of(context).printTemplatePublished,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                items: [
                                  DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(AppLocalizations.of(context).noCustomTemplate),
                                  ),
                                  ..._availableTemplates.map((tpl) {
                                    final id = (tpl['id'] as num).toInt();
                                    final name = (tpl['name'] ?? 'Template').toString();
                                    final isDefault = tpl['is_default'] == true;
                                    return DropdownMenuItem<int?>(
                                      value: id,
                                      child: Row(
                                        children: [
                                          if (isDefault) const Icon(Icons.star, size: 16),
                                          if (isDefault) const SizedBox(width: 6),
                                          Expanded(child: Text(name)),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedTemplateIdFromList = val;
                                    _templateIdForExport = val;
                                  });
                                },
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: AppLocalizations.of(context).reload,
                        onPressed: _loadingTemplates ? null : _ensureTemplatesLoaded,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
            ],
            
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
          // Footer totals for current page (optional)
          if (widget.config.footerTotals != null && widget.config.footerTotals!.isNotEmpty && _items.isNotEmpty)
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: widget.config.footerTotals!.entries.map((entry) {
                    final colKey = entry.key;
                    final label = entry.value;
                    double sum = 0;
                    for (final it in _items) {
                      try {
                        final v = DataTableUtils.getCellValue(it, colKey);
                        if (v is num) {
                          sum += v.toDouble();
                        } else if (v != null) {
                          final parsed = double.tryParse('$v');
                          if (parsed != null) sum += parsed;
                        }
                      } catch (_) {}
                    }
                    final text = sum.toStringAsFixed(2).replaceAll(RegExp(r'\\.00$'), '');
                    return Container(
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$label:',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          
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
      return Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: 8,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    children: List.generate(5, (i) {
                      return Expanded(
                        child: Container(
                          height: _dense ? 28 : 36,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.config.loadingMessage ?? t.loading, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
        ],
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _fetchData,
                  icon: const Icon(Icons.refresh),
                  label: Text(t.refresh),
                ),
                if (_hasActiveFilters())
                  OutlinedButton.icon(
                    onPressed: _clearAllFilters,
                    icon: const Icon(Icons.filter_alt_off),
                    label: Text(t.clear),
                  ),
              ],
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
    List<DataTableColumn> dataColumnsToShow = columnsToShow.where((c) => c is! ActionColumn).toList();
    // Reorder by pinning if settings available
    if (widget.config.enableColumnSettings && _columnSettings != null) {
      final visibleKeys = _columnSettings!.visibleColumns.toSet();
      final order = _columnSettings!.columnOrder;
      List<String> middleKeys = order.where((k) => visibleKeys.contains(k)).toList();
      final leftKeys = _columnSettings!.pinnedLeft.where((k) => middleKeys.contains(k)).toList();
      final rightKeys = _columnSettings!.pinnedRight.where((k) => middleKeys.contains(k)).toList();
      middleKeys.removeWhere((k) => leftKeys.contains(k) || rightKeys.contains(k));
      List<String> finalOrder = [...leftKeys, ...middleKeys, ...rightKeys];
      final mapByKey = {for (final c in dataColumnsToShow) c.key: c};
      dataColumnsToShow = finalOrder.map((k) => mapByKey[k]).whereType<DataTableColumn>().toList();
    }
    
    columns.addAll(dataColumnsToShow.map((column) {
      final headerTextStyle = theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ) ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
      final double baseWidth = DataTableUtils.getColumnWidth(column.width);
      final double affordancePadding = _getHeaderAffordancePadding(column);
      final double headerTextWidth = _measureHeaderTextWidth(column.label, headerTextStyle) + affordancePadding;
      final double minWidth = 96.0;
      final double defaultWidth = math.max(baseWidth, headerTextWidth);
      final double savedWidth = _columnSettings?.columnWidths[column.key] ?? defaultWidth;
      final double computedWidth = math.max(savedWidth, minWidth);

      return DataColumn2(
        label: _ColumnHeaderWithSearch(
          text: column.label,
          sortBy: column.key,
          currentSort: _sortBy,
          sortDesc: _sortDesc,
          headerTextAlign: widget.config.headerTextAlign ?? TextAlign.center,
          onSort: widget.config.enableSorting
              ? (key, additive) => _sortByColumnInternal(key, additive: additive)
              : (_, __) {},
          onSearch: widget.config.showColumnSearch && column.searchable
              ? () => _openColumnSearchDialog(column.key, column.label)
              : () { },
          hasActiveFilter: _columnSearchValues.containsKey(column.key),
          enabled: widget.config.enableSorting && column.sortable,
          onResizeDrag: widget.config.enableColumnSettings ? (dx) {
            if (_columnSettings == null) return;
            final current = _columnSettings!.columnWidths[column.key] ?? savedWidth;
            final next = math.max(minWidth, current + dx);
            final updated = _columnSettings!.copyWith(
              columnWidths: {
                ..._columnSettings!.columnWidths,
                column.key: next,
              },
            );
            setState(() {
              _columnSettings = updated;
            });
            // Delay saving until drag end to reduce write frequency
          } : null,
          onResizeDragEnd: widget.config.enableColumnSettings ? () {
            if (_columnSettings == null) return;
            ColumnSettingsService.saveColumnSettings(widget.config.effectiveTableId, _columnSettings!);
          } : null,
          onAutoFit: widget.config.enableColumnSettings ? () {
            if (_columnSettings == null) return;
            final headerStyle = headerTextStyle;
            final cellStyle = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
            final width = _autoFitColumnWidth(column, headerStyle, cellStyle, minWidth, affordancePadding);
            final updated = _columnSettings!.copyWith(
              columnWidths: {
                ..._columnSettings!.columnWidths,
                column.key: width,
              },
            );
            setState(() {
              _columnSettings = updated;
            });
            ColumnSettingsService.saveColumnSettings(widget.config.effectiveTableId, updated);
          } : null,
          onPinLeft: widget.config.enableColumnSettings ? () {
            if (_columnSettings == null) return;
            final updated = _columnSettings!.copyWith(
              pinnedLeft: {
                ..._columnSettings!.pinnedLeft,
                column.key,
              }.toList(),
              pinnedRight: _columnSettings!.pinnedRight.where((k) => k != column.key).toList(),
            );
            setState(() {
              _columnSettings = updated;
              _visibleColumns = _getVisibleColumnsFromSettings(updated);
            });
            ColumnSettingsService.saveColumnSettings(widget.config.effectiveTableId, updated);
          } : null,
          onPinRight: widget.config.enableColumnSettings ? () {
            if (_columnSettings == null) return;
            final updated = _columnSettings!.copyWith(
              pinnedRight: {
                ..._columnSettings!.pinnedRight,
                column.key,
              }.toList(),
              pinnedLeft: _columnSettings!.pinnedLeft.where((k) => k != column.key).toList(),
            );
            setState(() {
              _columnSettings = updated;
              _visibleColumns = _getVisibleColumnsFromSettings(updated);
            });
            ColumnSettingsService.saveColumnSettings(widget.config.effectiveTableId, updated);
          } : null,
          onUnpin: widget.config.enableColumnSettings ? () {
            if (_columnSettings == null) return;
            final updated = _columnSettings!.copyWith(
              pinnedLeft: _columnSettings!.pinnedLeft.where((k) => k != column.key).toList(),
              pinnedRight: _columnSettings!.pinnedRight.where((k) => k != column.key).toList(),
            );
            setState(() {
              _columnSettings = updated;
              _visibleColumns = _getVisibleColumnsFromSettings(updated);
            });
            ColumnSettingsService.saveColumnSettings(widget.config.effectiveTableId, updated);
          } : null,
          onHide: widget.config.enableColumnSettings ? () {
            if (_columnSettings == null) return;
            final updated = _columnSettings!.copyWith(
              visibleColumns: _columnSettings!.visibleColumns.where((k) => k != column.key).toList(),
            );
            setState(() {
              _columnSettings = updated;
              _visibleColumns = _getVisibleColumnsFromSettings(updated);
            });
            ColumnSettingsService.saveColumnSettings(widget.config.effectiveTableId, updated);
          } : null,
          onResetColumns: widget.config.enableColumnSettings ? () async {
            final defaults = ColumnSettingsService.getDefaultSettings(widget.config.columnKeys);
            setState(() {
              _columnSettings = defaults;
              _visibleColumns = _getVisibleColumnsFromSettings(defaults);
            });
            await ColumnSettingsService.saveColumnSettings(widget.config.effectiveTableId, defaults);
          } : null,
        ),
        size: DataTableUtils.getColumnSize(column.width),
        fixedWidth: computedWidth,
      );
    }));

    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      child: DataTableTheme(
        data: DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(
            widget.config.headerBackgroundColor ??
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ),
          headingTextStyle: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
          dividerThickness: 0.8,
        ),
        child: DataTable2(
          columnSpacing: 12,
          horizontalMargin: 10,
          minWidth: widget.config.minTableWidth ?? 600,
          horizontalScrollController: _horizontalScrollController,
          headingRowHeight: _dense ? 40 : 44,
          dataRowHeight: _dense ? 38 : 48,
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
          color: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return theme.colorScheme.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered)) {
              return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
            }
            if (index == _activeRowIndex && _tableFocusNode.hasFocus) {
              return theme.colorScheme.primary.withValues(alpha: 0.06);
            }
            // Custom per-row color if provided
            if (widget.config.rowColorBuilder != null) {
              try {
                final c = widget.config.rowColorBuilder!(item, index);
                if (c != null) return c;
              } catch (_) {}
            }
            final Color? base = widget.config.rowBackgroundColor;
            final Color? alt = widget.config.alternateRowBackgroundColor ??
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15);
            return (index % 2 == 1) ? alt : base;
          }),
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
      ),
    );
  }

  Widget _buildCellContent(dynamic item, DataTableColumn column, int index) {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    Alignment _alignmentFor(TextAlign align) {
      switch (align) {
        case TextAlign.left:
          return Alignment.centerLeft;
        case TextAlign.right:
          return Alignment.centerRight;
        case TextAlign.center:
        default:
          return Alignment.center;
      }
    }
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
      final overflow = _getOverflow(column);
       final align = _getTextAlign(column);
      final textWidget = Text(
        text,
        textAlign: align,
        maxLines: _getMaxLines(column),
        overflow: overflow,
      );
      final wrapped = GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.copied)));
        },
        child: Align(alignment: _alignmentFor(align), child: textWidget),
      );
      return (overflow == TextOverflow.ellipsis && text.isNotEmpty)
          ? Tooltip(message: text, child: wrapped)
          : wrapped;
    }
    if (column is NumberColumn && column.formatter != null) {
      final text = column.formatter!(item) ?? '';
      final overflow = _getOverflow(column);
      final align = _getTextAlign(column);
      final textWidget = Text(
        text,
        textAlign: align,
        maxLines: _getMaxLines(column),
        overflow: overflow,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      final wrapped = GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.copied)));
        },
        child: Align(alignment: _alignmentFor(align), child: textWidget),
      );
      return (overflow == TextOverflow.ellipsis && text.isNotEmpty)
          ? Tooltip(message: text, child: wrapped)
          : wrapped;
    }
    if (column is DateColumn && column.formatter != null) {
      final text = column.formatter!(item) ?? '';
      final overflow = _getOverflow(column);
      final align = _getTextAlign(column);
      final textWidget = Text(
        text,
        textAlign: align,
        maxLines: _getMaxLines(column),
        overflow: overflow,
      );
      final wrapped = GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.copied)));
        },
        child: Align(alignment: _alignmentFor(align), child: textWidget),
      );
      return (overflow == TextOverflow.ellipsis && text.isNotEmpty)
          ? Tooltip(message: text, child: wrapped)
          : wrapped;
    }

    // 4) Fallback: get property value from Map items by key
    final value = DataTableUtils.getCellValue(item, column.key);
    final formattedValue = DataTableUtils.formatCellValue(value, column);
    final overflow = _getOverflow(column);
    final align = _getTextAlign(column);
    final textWidget = Text(
      formattedValue,
      textAlign: align,
      maxLines: _getMaxLines(column),
      overflow: overflow,
      style: column is NumberColumn
          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            )
          : null,
    );
    final wrapped = GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: formattedValue));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.copied)));
      },
      child: Align(alignment: _alignmentFor(align), child: textWidget),
    );
    return (overflow == TextOverflow.ellipsis && formattedValue.isNotEmpty)
        ? Tooltip(message: formattedValue, child: wrapped)
        : wrapped;
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
    // Global override if provided in config
    if (widget.config.cellTextAlign != null) {
      return widget.config.cellTextAlign!;
    }
    // Fallbacks to column-specific alignment, then default center
    if (column is TextColumn && column.textAlign != null) return column.textAlign!;
    if (column is NumberColumn) return column.textAlign;
    if (column is DateColumn) return column.textAlign;
    return TextAlign.center;
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

  double _autoFitColumnWidth(
    DataTableColumn column,
    TextStyle headerTextStyle,
    TextStyle cellTextStyle,
    double minWidth,
    double affordancePadding, {
    int? sampleCountOverride,
  }
  ) {
    final double headerWidth = _measureHeaderTextWidth(column.label, headerTextStyle) + affordancePadding;
    final TextDirection dir = Directionality.of(context);
    double maxCellWidth = 0;
    final limit = sampleCountOverride ?? 50;
    final sampleCount = math.min(_items.length, limit);
    for (int i = 0; i < sampleCount; i++) {
      final item = _items[i];
      String text = '';
      if (column is TextColumn && column.formatter != null) {
        text = column.formatter!(item) ?? '';
      } else if (column is NumberColumn && column.formatter != null) {
        text = column.formatter!(item) ?? '';
      } else if (column is DateColumn && column.formatter != null) {
        text = column.formatter!(item) ?? '';
      }
      if (text.isEmpty) continue;
      final scale = MediaQuery.maybeOf(context)?.textScaleFactor ?? 1.0;
      final locale = Localizations.localeOf(context);
      final w = _measureTextWidthAdvanced(
        text: text,
        style: cellTextStyle,
        textDirection: dir,
        textScaleFactor: scale,
        locale: locale,
      );
      if (w > maxCellWidth) maxCellWidth = w;
    }
    // Padding for cell content
    final cellPadding = 32.0;
    final computed = math.max(minWidth, math.max(headerWidth, maxCellWidth + cellPadding));
    return computed;
  }
}

/// Column header with search functionality
class _ColumnHeaderWithSearch extends StatelessWidget {
  final String text;
  final String sortBy;
  final String? currentSort;
  final bool sortDesc;
  final TextAlign headerTextAlign;
  final void Function(String, bool additive) onSort;
  final VoidCallback onSearch;
  final bool hasActiveFilter;
  final bool enabled;
  final void Function(double dx)? onResizeDrag;
  final VoidCallback? onResizeDragEnd;
  final VoidCallback? onPinLeft;
  final VoidCallback? onPinRight;
  final VoidCallback? onUnpin;
  final VoidCallback? onHide;
  final VoidCallback? onResetColumns;
  final VoidCallback? onAutoFit;

  const _ColumnHeaderWithSearch({
    required this.text,
    required this.sortBy,
    required this.currentSort,
    required this.sortDesc,
    required this.headerTextAlign,
    required this.onSort,
    required this.onSearch,
    required this.hasActiveFilter,
    this.enabled = true,
    this.onResizeDrag,
    this.onResizeDragEnd,
    this.onPinLeft,
    this.onPinRight,
    this.onUnpin,
    this.onHide,
    this.onResetColumns,
    this.onAutoFit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = currentSort == sortBy;
    
    Alignment _mapTextAlign(TextAlign align) {
      switch (align) {
        case TextAlign.left:
          return Alignment.centerLeft;
        case TextAlign.right:
          return Alignment.centerRight;
        case TextAlign.center:
        default:
          return Alignment.center;
      }
    }
    
    return Tooltip(
      message: 'کلیک برای مرتب‌سازی • آیکون ذره‌بین برای جستجو • درگ برای تغییر عرض',
      child: InkWell(
        onTap: enabled
            ? () {
                final keys = HardwareKeyboard.instance.logicalKeysPressed;
                final additive = keys.contains(LogicalKeyboardKey.shiftLeft) || keys.contains(LogicalKeyboardKey.shiftRight);
                onSort(sortBy, additive);
              }
            : null,
        overlayColor: WidgetStatePropertyAll(theme.colorScheme.primary.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (isActive || hasActiveFilter)
                  ? theme.colorScheme.primary.withValues(alpha: 0.25)
                  : theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Align(
                  alignment: _mapTextAlign(headerTextAlign),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Tooltip(
                          message: text,
                          waitDuration: const Duration(milliseconds: 400),
                          child: Text(
                            text,
                            textAlign: headerTextAlign,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (enabled) ...[
                        const SizedBox(width: 4),
                        if (isActive)
                          Icon(
                            sortDesc ? Icons.arrow_downward : Icons.arrow_upward,
                            size: 14,
                            color: theme.colorScheme.primary,
                          )
                        else
                          Icon(
                            Icons.unfold_more,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Search button
              Tooltip(
                message: 'جست‌وجوی ستون',
                waitDuration: const Duration(milliseconds: 400),
                child: InkWell(
                  onTap: onSearch,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: hasActiveFilter 
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: hasActiveFilter 
                            ? theme.colorScheme.primary.withValues(alpha: 0.35)
                            : theme.dividerColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      Icons.search,
                      size: 13,
                      color: hasActiveFilter 
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
              if (onResizeDrag != null) ...[
                const SizedBox(width: 6),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) => onResizeDrag!(details.delta.dx),
                    onHorizontalDragEnd: (_) => onResizeDragEnd?.call(),
                    onDoubleTap: onAutoFit,
                    child: Container(
                      width: 12,
                      height: 28,
                      alignment: Alignment.center,
                      child: Container(
                        width: 2,
                        height: 20,
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
              if (onPinLeft != null || onPinRight != null || onUnpin != null || onHide != null) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  tooltip: 'تنظیمات ستون',
                  icon: Icon(Icons.more_vert, size: 16, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  onSelected: (value) {
                    switch (value) {
                      case 'pinLeft':
                        onPinLeft?.call();
                        break;
                      case 'pinRight':
                        onPinRight?.call();
                        break;
                      case 'unpin':
                        onUnpin?.call();
                        break;
                      case 'hide':
                        onHide?.call();
                        break;
                      case 'reset':
                        onResetColumns?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (onPinLeft != null)
                      const PopupMenuItem(value: 'pinLeft', child: Text('پین چپ')),
                    if (onPinRight != null)
                      const PopupMenuItem(value: 'pinRight', child: Text('پین راست')),
                    if (onUnpin != null)
                      const PopupMenuItem(value: 'unpin', child: Text('برداشتن پین')),
                    const PopupMenuDivider(),
                    if (onHide != null)
                      const PopupMenuItem(value: 'hide', child: Text('مخفی کردن ستون')),
                    if (onResetColumns != null) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'reset', child: Text('بازنشانی ستون‌ها')),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Keyboard intents
class MoveRowIntent extends Intent {
  final int delta;
  const MoveRowIntent(this.delta);
}

class ActivateRowIntent extends Intent {
  const ActivateRowIntent();
}

class ToggleSelectionIntent extends Intent {
  const ToggleSelectionIntent();
}

class ClearSelectionIntent extends Intent {
  const ClearSelectionIntent();
}

class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

class _SortSpec {
  final String by;
  final bool desc;
  const _SortSpec({required this.by, required this.desc});
  _SortSpec copyWith({String? by, bool? desc}) => _SortSpec(by: by ?? this.by, desc: desc ?? this.desc);
}
