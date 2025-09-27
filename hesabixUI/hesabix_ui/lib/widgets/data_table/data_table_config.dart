import 'package:flutter/material.dart';
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
    this.textAlign = TextAlign.end,
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
  final bool enabled;

  const DataTableAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.color,
    this.enabled = true,
  });
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
  
  // Export configuration
  final String? excelEndpoint;
  final String? pdfEndpoint;
  final Map<String, dynamic> Function()? getExportParams;
  
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
  
  // Refresh callback
  final VoidCallback? onRefresh;

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
    this.excelEndpoint,
    this.pdfEndpoint,
    this.getExportParams,
    this.tableId,
    this.enableColumnSettings = true,
    this.showColumnSettingsButton = true,
    this.initialColumnSettings,
    this.onColumnSettingsChanged,
    this.customHeaderActions,
    this.showFiltersButton = false,
    this.onRefresh,
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
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const DataTableResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory DataTableResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final data = json['data'] as Map<String, dynamic>;
    final itemsList = data['items'] as List? ?? [];
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
    
    return DataTableResponse<T>(
      items: itemsList.map((item) => fromJsonT(item as Map<String, dynamic>)).toList(),
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
  final int take;
  final int skip;

  const QueryInfo({
    this.search,
    this.searchFields,
    this.filters,
    this.sortBy,
    this.sortDesc = false,
    this.take = 20,
    this.skip = 0,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'take': take,
      'skip': skip,
      'sort_desc': sortDesc,
    };

    if (search != null && search!.isNotEmpty) {
      json['search'] = search;
      if (searchFields != null && searchFields!.isNotEmpty) {
        json['search_fields'] = searchFields;
      }
    }

    if (sortBy != null && sortBy!.isNotEmpty) {
      json['sort_by'] = sortBy;
    }

    if (filters != null && filters!.isNotEmpty) {
      json['filters'] = filters!.map((f) => f.toJson()).toList();
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
