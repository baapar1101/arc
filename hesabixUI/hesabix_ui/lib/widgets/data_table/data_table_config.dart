import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'helpers/column_settings_service.dart';

/// Configuration for data table columns
enum ColumnWidth {
  small,
  medium,
  large,
  extraLarge,
}

/// Types of column filters
enum ColumnFilterType {
  text,           // Text filter (default)
  dateRange,      // Date range filter
  multiSelect,    // Multi-select filter with checkboxes
  categoryTree,   // Category tree filter with hierarchical selection
}

/// Filter option for multi-select filters
class FilterOption {
  final String value;        // Value for API
  final String label;        // Display label
  final String? description; // Additional description
  final IconData? icon;      // Icon
  final Color? color;        // Icon/text color
  
  const FilterOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.color,
  });
}

/// Base class for all column types
abstract class DataTableColumn {
  final String key;
  final String label;
  final bool sortable;
  final bool searchable;
  final ColumnWidth width;
  final String? tooltip;
  final ColumnFilterType? filterType;
  final List<FilterOption>? filterOptions;

  const DataTableColumn({
    required this.key,
    required this.label,
    this.sortable = true,
    this.searchable = true,
    this.width = ColumnWidth.medium,
    this.tooltip,
    this.filterType,
    this.filterOptions,
  });
}

/// Text column configuration
class TextColumn extends DataTableColumn {
  final String? Function(dynamic item)? formatter;
  final TextAlign? textAlign;
  final int? maxLines;
  final bool? overflow;

  const TextColumn(
    String key,
    String label, {
    super.sortable = true,
    super.searchable = true,
    super.width = ColumnWidth.medium,
    super.tooltip,
    super.filterType,
    super.filterOptions,
    this.formatter,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : super(key: key, label: label);
}

/// Number column configuration
class NumberColumn extends DataTableColumn {
  final String? Function(dynamic item)? formatter;
  final TextAlign textAlign;
  final int? decimalPlaces;
  final String? prefix;
  final String? suffix;

  const NumberColumn(
    String key,
    String label, {
    super.sortable = true,
    super.searchable = true,
    super.width = ColumnWidth.medium,
    super.tooltip,
    super.filterType,
    super.filterOptions,
    this.formatter,
    this.textAlign = TextAlign.center,
    this.decimalPlaces,
    this.prefix,
    this.suffix,
  }) : super(key: key, label: label);
}

/// Date column configuration
class DateColumn extends DataTableColumn {
  final String? Function(dynamic item)? formatter;
  final TextAlign textAlign;
  final bool showTime;
  final String? dateFormat;

  const DateColumn(
    String key,
    String label, {
    super.sortable = true,
    super.searchable = true,
    super.width = ColumnWidth.medium,
    super.tooltip,
    super.filterType,
    super.filterOptions,
    this.formatter,
    this.textAlign = TextAlign.center,
    this.showTime = false,
    this.dateFormat,
  }) : super(key: key, label: label);
}

/// Action column configuration
class ActionColumn extends DataTableColumn {
  final List<DataTableAction> actions;
  final bool showOnHover;

  const ActionColumn(
    String key,
    String label, {
    super.sortable = false,
    super.searchable = false,
    super.width = ColumnWidth.small,
    super.tooltip,
    super.filterType,
    super.filterOptions,
    required this.actions,
    this.showOnHover = true,
  }) : super(key: key, label: label);
}

/// Custom column configuration
class CustomColumn extends DataTableColumn {
  final Widget Function(dynamic item, int index)? builder;
  final String? Function(dynamic item)? formatter;

  const CustomColumn(
    String key,
    String label, {
    super.sortable = true,
    super.searchable = true,
    super.width = ColumnWidth.medium,
    super.tooltip,
    super.filterType,
    super.filterOptions,
    this.builder,
    this.formatter,
  }) : super(key: key, label: label);
}

/// Action button configuration
class DataTableAction {
  final IconData icon;
  final String label;
  final void Function(dynamic item) onTap;
  final bool isDestructive;
  final Color? color;
  final dynamic enabled; // bool or bool Function(dynamic item)

  const DataTableAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.color,
    this.enabled = true,
  });

  /// Helper method to get enabled state for an item
  bool isEnabled(dynamic item) {
    if (enabled is bool) {
      return enabled as bool;
    } else if (enabled is bool Function(dynamic)) {
      return (enabled as bool Function(dynamic))(item);
    }
    return true;
  }
}

/// Data table configuration
class DataTableConfig<T> {
  final String endpoint;
  final List<DataTableColumn> columns;
  final List<String> searchFields;
  final List<String> filterFields;
  final String? dateRangeField;
  final String? title;
  final String? subtitle;
  // Header controls
  final bool showBackButton;
  final VoidCallback? onBack;
  final bool showTableIcon;
  final bool showSearch;
  final bool showFilters;
  final bool showPagination;
  final bool showColumnSearch;
  final int defaultPageSize;
  final List<int> pageSizeOptions;
  final bool enableSorting;
  final bool enableGlobalSearch;
  final bool enableDateRangeFilter;
  // Default sort configuration
  final String? defaultSortBy;
  final bool defaultSortDesc;
  final void Function(dynamic item)? onRowTap;
  final void Function(dynamic item)? onRowDoubleTap;
  final Widget? Function(dynamic item)? customRowBuilder;
  final Map<String, dynamic>? additionalParams;
  final Duration? searchDebounce;
  final bool showRefreshButton;
  final bool showClearFiltersButton;
  final String? emptyStateMessage;
  final Widget? emptyStateWidget;
  final String? loadingMessage;
  final Widget? loadingWidget;
  final String? errorMessage;
  final Widget? errorWidget;
  final bool showActiveFilters;
  final bool showColumnHeaders;
  final bool showRowNumbers;
  final bool enableRowSelection;
  final bool enableMultiRowSelection;
  final Set<int>? selectedRows;
  final void Function(Set<int> selectedRows)? onRowSelectionChanged;
  final bool enableHorizontalScroll;
  final double? minTableWidth;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? backgroundColor;
  final Color? headerBackgroundColor;
  final Color? rowBackgroundColor;
  final Color? alternateRowBackgroundColor;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;
  final bool showBorder;
  final Color? borderColor;
  final double? borderWidth;
  final void Function(DateTime? fromDate, DateTime? toDate)? onDateRangeApply;
  final VoidCallback? onDateRangeClear;
  // Custom filters callback
  final List<FilterItem> Function()? getCustomFilters;
  
  // Export configuration
  final String? excelEndpoint;
  final String? pdfEndpoint;
  final Map<String, dynamic> Function()? getExportParams;
  final bool showExportButtons;
  final bool showExcelExport;
  final bool showPdfExport;
  // Report templates scope (for PDF custom templates)
  final int? businessId; // needed to fetch templates
  final String? reportModuleKey;
  final String? reportSubtype;
  
  // Row styling
  final Color? Function(dynamic item, int index)? rowColorBuilder;

  // Footer page totals: map from field key -> label to display
  final Map<String, String>? footerTotals;

  // Column settings configuration
  final String? tableId;
  final bool enableColumnSettings;
  final bool showColumnSettingsButton;
  final ColumnSettings? initialColumnSettings;
  final void Function(ColumnSettings settings)? onColumnSettingsChanged;
  
  // Custom header actions
  final List<Widget>? customHeaderActions;
  
  // Show individual action buttons
  final bool showFiltersButton;
  
  // Alignment configuration
  final TextAlign? cellTextAlign;       // If set, overrides all cell text alignment
  final TextAlign? headerTextAlign;     // If set, overrides all header text alignment

  // Row height configuration (useful for mobile/card-like rows)
  final double? headingRowHeight;
  final double? dataRowHeight;
  
  // Refresh callback
  final VoidCallback? onRefresh;
  
  // Auto-fit configuration
  final bool autoFitColumnsOnFirstLoad;
  final int autoFitSampleRows;
  
  // Auto-fill available width: if true, columns will expand to fill available width
  // when user hasn't customized column widths
  final bool autoFillAvailableWidth;
  
  // HTTP method for data fetching (default: POST)
  final String httpMethod;

  const DataTableConfig({
    required this.endpoint,
    required this.columns,
    this.searchFields = const [],
    this.filterFields = const [],
    this.dateRangeField,
    this.title,
    this.subtitle,
    this.showBackButton = false,
    this.onBack,
    this.showTableIcon = true,
    this.showSearch = true,
    this.showFilters = false,
    this.showPagination = true,
    this.showColumnSearch = true,
    this.defaultPageSize = 20,
    this.pageSizeOptions = const [10, 20, 50, 100],
    this.enableSorting = true,
    this.enableGlobalSearch = true,
    this.enableDateRangeFilter = false,
    this.defaultSortBy,
    this.defaultSortDesc = false,
    this.onRowTap,
    this.onRowDoubleTap,
    this.customRowBuilder,
    this.additionalParams,
    this.searchDebounce = const Duration(milliseconds: 500),
    this.showRefreshButton = true,
    this.showClearFiltersButton = true,
    this.emptyStateMessage,
    this.emptyStateWidget,
    this.loadingMessage,
    this.loadingWidget,
    this.errorMessage,
    this.errorWidget,
    this.showActiveFilters = true,
    this.showColumnHeaders = true,
    this.showRowNumbers = false,
    this.enableRowSelection = false,
    this.enableMultiRowSelection = false,
    this.selectedRows,
    this.onRowSelectionChanged,
    this.enableHorizontalScroll = true,
    this.minTableWidth = 600.0,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.headerBackgroundColor,
    this.rowBackgroundColor,
    this.alternateRowBackgroundColor,
    this.borderRadius,
    this.boxShadow,
    this.showBorder = true,
    this.borderColor,
    this.borderWidth = 1.0,
    this.onDateRangeApply,
    this.onDateRangeClear,
    this.getCustomFilters,
    this.excelEndpoint,
    this.pdfEndpoint,
    this.getExportParams,
    this.showExportButtons = false,
    this.showExcelExport = true,
    this.showPdfExport = true,
    this.businessId,
    this.reportModuleKey,
    this.reportSubtype,
    this.rowColorBuilder,
    this.footerTotals,
    this.tableId,
    this.enableColumnSettings = true,
    this.showColumnSettingsButton = true,
    this.initialColumnSettings,
    this.onColumnSettingsChanged,
    this.customHeaderActions,
    this.showFiltersButton = false,
    this.cellTextAlign,
    this.headerTextAlign,
    this.headingRowHeight,
    this.dataRowHeight,
    this.onRefresh,
    this.autoFitColumnsOnFirstLoad = true,
    this.autoFitSampleRows = 50,
    this.autoFillAvailableWidth = true,
    this.httpMethod = 'POST',
  });

  /// Get column width as double
  double getColumnWidth(ColumnWidth width) {
    switch (width) {
      case ColumnWidth.small:
        return 120.0;
      case ColumnWidth.medium:
        return 180.0;
      case ColumnWidth.large:
        return 250.0;
      case ColumnWidth.extraLarge:
        return 350.0;
    }
  }

  /// Get searchable columns
  List<DataTableColumn> get searchableColumns {
    return columns.where((col) => col.searchable).toList();
  }

  /// Get sortable columns
  List<DataTableColumn> get sortableColumns {
    return columns.where((col) => col.sortable).toList();
  }

  /// Get filterable columns
  List<DataTableColumn> get filterableColumns {
    return columns.where((col) => col.searchable).toList();
  }

  /// Get all column keys
  List<String> get columnKeys {
    return columns.map((col) => col.key).toList();
  }

  /// Get column by key
  DataTableColumn? getColumnByKey(String key) {
    try {
      return columns.firstWhere((col) => col.key == key);
    } catch (e) {
      return null;
    }
  }

  /// Get effective table ID for column settings
  String get effectiveTableId {
    return tableId ?? endpoint.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }
}

/// Data table response model
class DataTableResponse<T> {
  final List<T> items;
  final List<Map<String, dynamic>> rawItems;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const DataTableResponse({
    required this.items,
    required this.rawItems,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory DataTableResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final data = json['data'];
    if (data == null || data is! Map<String, dynamic>) {
      throw FormatException('Invalid response format: missing or invalid "data" field');
    }
    
    final itemsList = data['items'];
    List<dynamic> items;
    if (itemsList == null) {
      items = [];
    } else if (itemsList is List) {
      items = itemsList;
    } else {
      items = [];
    }
    
    // Support both old and new pagination shapes
    final pagination = data['pagination'] as Map<String, dynamic>?;
    final total = pagination != null
        ? (pagination['total'] as num?)?.toInt() ?? 0
        : (data['total'] as num?)?.toInt() ?? 0;
    final page = pagination != null
        ? (pagination['page'] as num?)?.toInt() ?? 1
        : (data['page'] as num?)?.toInt() ?? 1;
    final limit = pagination != null
        ? (pagination['per_page'] as num?)?.toInt() ?? 20
        : (data['limit'] as num?)?.toInt() ?? 20;
    final totalPages = pagination != null
        ? (pagination['total_pages'] as num?)?.toInt() ?? 0
        : (data['total_pages'] as num?)?.toInt() ?? 0;
    
    // Parse items safely
    final parsedItems = <T>[];
    final rawItems = <Map<String, dynamic>>[];
    for (final item in items) {
      try {
        if (item is Map<String, dynamic>) {
          rawItems.add(item);
          parsedItems.add(fromJsonT(item));
        }
      } catch (e) {
        debugPrint('Error parsing item: $e, item: $item');
        // Skip invalid items instead of failing completely
      }
    }
    
    return DataTableResponse<T>(
      items: parsedItems,
      rawItems: rawItems,
      total: total,
      page: page,
      limit: limit,
      totalPages: totalPages,
    );
  }
}

/// Query info model for API requests
class QueryInfo {
  final String? search;
  final List<String>? searchFields;
  final List<FilterItem>? filters;
  final String? sortBy;
  final bool sortDesc;
  final List<SortItem>? sorts;
  final int take;
  final int skip;
  final bool includeInventory;
  final String? inventoryAsOfDate;

  const QueryInfo({
    this.search,
    this.searchFields,
    this.filters,
    this.sortBy,
    this.sortDesc = false,
    this.sorts,
    this.take = 20,
    this.skip = 0,
    this.includeInventory = false,
    this.inventoryAsOfDate,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'take': take,
      'skip': skip,
      'sort_desc': sortDesc,
    };
    if (sortBy != null && sortBy!.isNotEmpty) {
      json['sort_by'] = sortBy;
    }
    if (sorts != null && sorts!.isNotEmpty) {
      json['sort'] = sorts!.map((s) => s.toJson()).toList();
    }

    if (search != null && search!.isNotEmpty) {
      json['search'] = search;
      if (searchFields != null && searchFields!.isNotEmpty) {
        json['search_fields'] = searchFields;
      }
    }

    if (filters != null && filters!.isNotEmpty) {
      json['filters'] = filters!.map((f) => f.toJson()).toList();
    }

    if (includeInventory) {
      json['include_inventory'] = true;
      if (inventoryAsOfDate != null && inventoryAsOfDate!.isNotEmpty) {
        json['inventory_as_of_date'] = inventoryAsOfDate;
      }
    }

    return json;
  }
}

/// Filter item model
class FilterItem {
  final String property;
  final String operator;
  final dynamic value;

  const FilterItem({
    required this.property,
    required this.operator,
    required this.value,
  });

  Map<String, dynamic> toJson() {
    return {
      'property': property,
      'operator': operator,
      'value': value,
    };
  }
}

/// Sort item model (for multi-sort)
class SortItem {
  final String by;
  final bool desc;
  const SortItem({required this.by, this.desc = false});
  Map<String, dynamic> toJson() => {
        'by': by,
        'desc': desc,
      };
}
