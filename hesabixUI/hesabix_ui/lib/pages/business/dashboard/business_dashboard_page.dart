import 'package:flutter/material.dart';
import 'package:reorderables/reorderables.dart';
import 'dart:async';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../../services/business_dashboard_service.dart';
import '../../../core/api_client.dart';
import '../../../models/business_dashboard_models.dart';
import '../../../core/fiscal_year_controller.dart';
import '../../../core/calendar_controller.dart';
import '../../../widgets/fiscal_year_switcher.dart';
import '../../../core/auth_store.dart';
import '../../../utils/date_formatters.dart';
import '../../../utils/number_formatters.dart';
import '../../../core/date_utils.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/currency_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/document/document_details_dialog.dart';
import 'quick_links_dashboard_widget.dart';
import 'crm_calendar_dashboard_widget.dart';

typedef DashboardWidgetBuilder = Widget Function(BuildContext, dynamic, DashboardLayoutItem, {VoidCallback? onRefresh});

class BusinessDashboardPage extends StatefulWidget {
  final int businessId;
  final AuthStore? authStore;
  final CalendarController? calendarController;

  const BusinessDashboardPage({super.key, required this.businessId, this.authStore, this.calendarController});

  @override
  State<BusinessDashboardPage> createState() => _BusinessDashboardPageState();
}

class _BusinessDashboardPageState extends State<BusinessDashboardPage> {
  late final FiscalYearController _fiscalController;
  late final BusinessDashboardService _service;

  DashboardDefinitionsResponse? _definitions;
  DashboardLayoutProfile? _layout;
  Map<String, dynamic> _data = <String, dynamic>{};
  bool _loading = true;
  String? _error;
  bool _editMode = false;
  Timer? _saveDebounce;
  double _columnUnitPx = 0;
  String _salesChartType = 'bar'; // bar | line
  String _salesChartGroup = 'day'; // day | week | month
  int? _crmCalendarYear;
  int? _crmCalendarMonth;

  Map<String, dynamic> _dashboardBatchFilters(List<String> keys) {
    final m = <String, dynamic>{'group': _salesChartGroup};
    if (keys.contains('crm_calendar') && _crmCalendarYear != null && _crmCalendarMonth != null) {
      m['crm_calendar_year'] = _crmCalendarYear;
      m['crm_calendar_month'] = _crmCalendarMonth;
    }
    return m;
  }

  void _onCalendarTypeChanged() {
    if (!mounted) return;
    setState(() {
      _crmCalendarYear = null;
      _crmCalendarMonth = null;
    });
    _reloadDataOnly();
  }

  @override
  void initState() {
    super.initState();
    widget.calendarController?.addListener(_onCalendarTypeChanged);
    _init();
  }

  @override
  void dispose() {
    widget.calendarController?.removeListener(_onCalendarTypeChanged);
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _fiscalController = await FiscalYearController.load(widget.businessId);
    final fiscalListSvc = BusinessDashboardService(ApiClient());
    final fiscalYears = await fiscalListSvc.listFiscalYears(widget.businessId);
    await _fiscalController.reconcileWithList(fiscalYears);
    _service = BusinessDashboardService(ApiClient(), fiscalYearController: _fiscalController);
    ApiClient.bindFiscalYear(ValueNotifier<int?>(_fiscalController.fiscalYearId));
    _fiscalController.addListener(() {
      ApiClient.bindFiscalYear(ValueNotifier<int?>(_fiscalController.fiscalYearId));
      _reloadDataOnly();
    });
    await _loadAll();
  }

  String _currentBreakpoint(double width) {
    if (width < 600) return 'xs';
    if (width < 904) return 'sm';
    if (width < 1240) return 'md';
    if (width < 1600) return 'lg';
    return 'xl';
  }

  // Helper methods for responsive values
  double _getPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bp = _currentBreakpoint(width);
    switch (bp) {
      case 'xs':
        return 8.0; // موبایل
      case 'sm':
        return 12.0; // تبلت کوچک
      case 'md':
        return 16.0; // تبلت بزرگ
      case 'lg':
        return 20.0; // دسکتاپ کوچک
      case 'xl':
        return 24.0; // دسکتاپ بزرگ
      default:
        return 16.0;
    }
  }

  double _getGridSpacing(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bp = _currentBreakpoint(width);
    switch (bp) {
      case 'xs':
        return 8.0;
      case 'sm':
        return 10.0;
      case 'md':
        return 12.0;
      case 'lg':
        return 14.0;
      case 'xl':
        return 16.0;
      default:
        return 12.0;
    }
  }

  double _getMinTileUnit(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bp = _currentBreakpoint(width);
    switch (bp) {
      case 'xs':
        return 140.0; // موبایل
      case 'sm':
        return 160.0; // تبلت کوچک
      case 'md':
        return 180.0; // تبلت بزرگ
      case 'lg':
        return 200.0; // دسکتاپ کوچک
      case 'xl':
        return 220.0; // دسکتاپ بزرگ
      default:
        return 180.0;
    }
  }

  TextStyle? _getHeaderTextStyle(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bp = _currentBreakpoint(width);
    final theme = Theme.of(context);
    switch (bp) {
      case 'xs':
        return theme.textTheme.titleLarge; // موبایل
      case 'sm':
        return theme.textTheme.headlineSmall; // تبلت کوچک
      default:
        return theme.textTheme.headlineMedium; // تبلت بزرگ و دسکتاپ
    }
  }

  bool _isMobile(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return _currentBreakpoint(width) == 'xs';
  }

  double _getChartHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bp = _currentBreakpoint(width);
    switch (bp) {
      case 'xs':
        return 200.0; // موبایل
      case 'sm':
        return 220.0; // تبلت کوچک
      case 'md':
        return 240.0; // تبلت بزرگ
      case 'lg':
        return 260.0; // دسکتاپ کوچک
      case 'xl':
        return 280.0; // دسکتاپ بزرگ
      default:
        return 240.0;
    }
  }

  /// داشتن [quick_links] در **اول** ترتیب نمایش (order از ۱ به بعد).
  List<DashboardLayoutItem> _layoutWithQuickLinksFirst(List<DashboardLayoutItem> list) {
    if (!list.any((e) => e.key == 'quick_links')) return list;
    final byOrder = list.toList()..sort((a, b) => a.order.compareTo(b.order));
    final ql = byOrder.where((e) => e.key == 'quick_links').toList();
    final rest = byOrder.where((e) => e.key != 'quick_links').toList();
    final merged = <DashboardLayoutItem>[...ql, ...rest];
    return <DashboardLayoutItem>[
      for (var i = 0; i < merged.length; i++) merged[i].copyWith(order: i + 1),
    ];
  }

  bool _layoutItemsListEqual(List<DashboardLayoutItem> a, List<DashboardLayoutItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.key != y.key ||
          x.order != y.order ||
          x.hidden != y.hidden ||
          x.colSpan != y.colSpan ||
          x.rowSpan != y.rowSpan) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadAll() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final defs = await _definitionsOrLoad();
      if (!context.mounted) return;
      final ctx = context;
      final bp = _currentBreakpoint(MediaQuery.of(ctx).size.width);
      var layout = await _service.getLayoutProfile(businessId: widget.businessId, breakpoint: bp);
      // اطمینان از حضور ویجت‌های جدید پیش‌فرض (مثل نمودار فروش) در چیدمان
      final existingKeys = layout.items.map((e) => e.key).toSet();
      final missingDefaults = defs.items.where((d) => !existingKeys.contains(d.key)).toList();
      var items = List<DashboardLayoutItem>.from(layout.items);
      var mustPersist = false;
      if (missingDefaults.isNotEmpty) {
        int maxOrder = items.fold<int>(0, (acc, it) => it.order > acc ? it.order : acc);
        for (final d in missingDefaults) {
          final dflt = d.defaults[bp] ?? const <String, int>{};
          final colSpan = (dflt['colSpan'] ?? (layout.columns / 2).floor()).clamp(1, layout.columns);
          final rowSpan = dflt['rowSpan'] ?? 2;
          items.add(DashboardLayoutItem(key: d.key, order: ++maxOrder, colSpan: colSpan, rowSpan: rowSpan, hidden: false));
        }
        mustPersist = true;
        if (missingDefaults.any((d) => d.key == 'quick_links')) {
          final next = _layoutWithQuickLinksFirst(items);
          if (!_layoutItemsListEqual(next, items)) {
            items = next;
          }
        }
      } else {
        // یک‌بار: چیدمان‌های قدیمی که quick_links را در انتها دارند → بالای داشبورد
        final prefs = await SharedPreferences.getInstance();
        final mKey = 'dashboard_ql_first_v1_${widget.businessId}';
        if (prefs.getBool(mKey) != true) {
          if (items.any((e) => e.key == 'quick_links')) {
            final next = _layoutWithQuickLinksFirst(items);
            if (!_layoutItemsListEqual(next, items)) {
              items = next;
              mustPersist = true;
            }
          }
          await prefs.setBool(mKey, true);
        }
      }
      if (mustPersist) {
        layout = await _service.putLayoutProfile(businessId: widget.businessId, breakpoint: bp, items: items);
      }
      // فیلتر ویجت‌ها بر اساس دسترسی قبل از درخواست داده
      final visibleItems = layout.items.where((e) => !e.hidden).toList();
      final keys = visibleItems.where((item) {
        // بررسی دسترسی برای هر ویجت
        final widgetDef = defs.items.firstWhere(
          (d) => d.key == item.key,
          orElse: () => DashboardWidgetDefinition(
            key: item.key,
            title: item.key,
            icon: 'widgets',
            version: 1,
            permissionsRequired: const [],
            defaults: const {},
          ),
        );
        return _hasWidgetPermission(widgetDef);
      }).map((e) => e.key).toList();
      
      final data = await _service.getWidgetsBatchData(
        businessId: widget.businessId,
        widgetKeys: keys,
        filters: _dashboardBatchFilters(keys),
      );
      if (!mounted) return;
      setState(() {
        _definitions = defs;
        _layout = layout;
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _reloadDataOnly() async {
    try {
      final layout = _layout;
      final defs = _definitions;
      if (layout == null || defs == null) return;
      
      // فیلتر ویجت‌ها بر اساس دسترسی قبل از درخواست داده
      final visibleItems = layout.items.where((e) => !e.hidden).toList();
      final keys = visibleItems.where((item) {
        // بررسی دسترسی برای هر ویجت
        final widgetDef = defs.items.firstWhere(
          (d) => d.key == item.key,
          orElse: () => DashboardWidgetDefinition(
            key: item.key,
            title: item.key,
            icon: 'widgets',
            version: 1,
            permissionsRequired: const [],
            defaults: const {},
          ),
        );
        return _hasWidgetPermission(widgetDef);
      }).map((e) => e.key).toList();
      
      final data = await _service.getWidgetsBatchData(
        businessId: widget.businessId,
        widgetKeys: keys,
        filters: _dashboardBatchFilters(keys),
      );
      if (!mounted) return;
      setState(() {
        _data = data;
      });
    } catch (_) {}
  }

  Future<DashboardDefinitionsResponse> _definitionsOrLoad() async {
    if (_definitions != null) return _definitions!;
    return await _service.getWidgetDefinitions(widget.businessId);
  }

  void _scheduleSaveLayout() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () async {
      final profile = _layout;
      if (profile == null) return;
      try {
        final updated = await _service.putLayoutProfile(
          businessId: widget.businessId,
          breakpoint: profile.breakpoint,
          items: profile.items,
        );
        if (!mounted) return;
        setState(() {
          _layout = updated;
        });
      } catch (_) {
        if (!mounted) return;
        SnackBarHelper.showError(
          context,
          message: 'ذخیره چیدمان داشبورد انجام نشد. اتصال را بررسی کنید یا دوباره تلاش کنید.',
        );
      }
    });
  }

  void _applyItems(List<DashboardLayoutItem> items) {
    final profile = _layout;
    if (profile == null) return;
    setState(() {
      _layout = DashboardLayoutProfile(
        breakpoint: profile.breakpoint,
        columns: profile.columns,
        items: items,
        version: profile.version,
        updatedAt: profile.updatedAt,
      );
    });
    _scheduleSaveLayout();
  }

  void _reindexAndSave(List<DashboardLayoutItem> items) {
    final sorted = <DashboardLayoutItem>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      sorted.add(it.copyWith(order: i + 1));
    }
    _applyItems(sorted);
  }

  void _moveItemUp(DashboardLayoutItem item) {
    final profile = _layout;
    if (profile == null) return;
    final list = List<DashboardLayoutItem>.from(profile.items);
    final idx = list.indexWhere((e) => e.key == item.key);
    if (idx <= 0) return;
    final tmp = list[idx - 1];
    list[idx - 1] = list[idx];
    list[idx] = tmp;
    _reindexAndSave(list);
  }

  void _moveItemDown(DashboardLayoutItem item) {
    final profile = _layout;
    if (profile == null) return;
    final list = List<DashboardLayoutItem>.from(profile.items);
    final idx = list.indexWhere((e) => e.key == item.key);
    if (idx < 0 || idx >= list.length - 1) return;
    final tmp = list[idx + 1];
    list[idx + 1] = list[idx];
    list[idx] = tmp;
    _reindexAndSave(list);
  }

  void _changeItemWidth(DashboardLayoutItem item, int delta) {
    final profile = _layout;
    if (profile == null) return;
    final list = List<DashboardLayoutItem>.from(profile.items);
    final idx = list.indexWhere((e) => e.key == item.key);
    if (idx < 0) return;
    final newSpan = (item.colSpan + delta).clamp(1, profile.columns);
    list[idx] = item.copyWith(colSpan: newSpan);
    _applyItems(list);
  }

  void _hideItem(DashboardLayoutItem item, {required bool hidden}) {
    final profile = _layout;
    if (profile == null) return;
    final list = List<DashboardLayoutItem>.from(profile.items);
    final idx = list.indexWhere((e) => e.key == item.key);
    if (idx < 0) return;
    list[idx] = item.copyWith(hidden: hidden);
    _applyItems(list);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('خطا در بارگذاری داشبورد:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadAll, child: Text(t.retry)),
          ],
        ),
      );
    }

    final layout = _layout!;
    final items = List<DashboardLayoutItem>.from(layout.items)..sort((a, b) => a.order.compareTo(b.order));
    final visible = items.where((e) => !e.hidden).toList();
    final crossAxisCount = layout.columns;
    final padding = _getPadding(context);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          _buildHeaderRow(t),
          SizedBox(height: _isMobile(context) ? 12 : 16),
          if (!_editMode)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final spacing = _getGridSpacing(context);
                  final minTileUnit = _getMinTileUnit(context);
                  double unit = (totalWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
                  if (unit <= 0) {
                    unit = minTileUnit;
                  } else if (unit < minTileUnit) {
                    unit = minTileUnit;
                  }
                  if (unit > 0 && _columnUnitPx != unit) {
                    _columnUnitPx = unit;
                  }
                  final children = <Widget>[];
                  for (final it in visible) {
                    final w = (unit * it.colSpan) + spacing * (it.colSpan - 1);
                    final cw = w > totalWidth ? totalWidth : (w < unit ? unit : w);
                    children.add(AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      key: ValueKey('dash_item_view_${it.key}'),
                      width: cw,
                      child: _buildGridTile(it, crossAxisCount),
                    ));
                  }
                  return SingleChildScrollView(
                    child: Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: children,
                    ),
                  );
                },
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final spacing = _getGridSpacing(context);
                  final minTileUnit = _getMinTileUnit(context);
                  double unit = (totalWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
                  if (unit <= 0) {
                    unit = minTileUnit;
                  } else if (unit < minTileUnit) {
                    unit = minTileUnit;
                  }
                  // ذخیره آخرین اندازه واحد ستون برای رزایز اسنپی
                  if (unit > 0 && _columnUnitPx != unit) {
                    _columnUnitPx = unit;
                  }

                  final children = <Widget>[];
                  for (final it in visible) {
                    final w = (unit * it.colSpan) + spacing * (it.colSpan - 1);
                    final cw = w > totalWidth ? totalWidth : (w < unit ? unit : w);
                    children.add(AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      key: ValueKey('dash_item_${it.key}'),
                      width: cw,
                      child: _buildGridTile(it, crossAxisCount),
                    ));
                  }

          return SingleChildScrollView(
                    child: Stack(
                      children: [
                        // خطوط راهنمای ستون‌ها در حالت ویرایش
                if (_editMode)
                  SizedBox(
                            width: totalWidth,
                            child: CustomPaint(
                              painter: _GridGuidesPainter(
                                columns: crossAxisCount,
                                unitWidth: unit,
                                spacing: spacing,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                              ),
                      child: SizedBox(height: children.isEmpty ? 0 : 1), // ارتفاع حداقلی برای render
                            ),
                          ),
                        ReorderableWrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          needsLongPressDraggable: true,
                          onReorder: (oldIndex, newIndex) {
                            final list = List<DashboardLayoutItem>.from(visible);
                            final moved = list.removeAt(oldIndex);
                            list.insert(newIndex, moved);
                            final profile = _layout!;
                            final newItems = <DashboardLayoutItem>[];
                            final visibleKeys = list.map((e) => e.key).toSet();
                            newItems.addAll(list);
                            for (final it in profile.items) {
                              if (!visibleKeys.contains(it.key) && it.hidden == false) continue;
                              if (it.hidden) newItems.add(it);
                            }
                            _reindexAndSave(newItems);
                          },
                          children: children,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_editMode) ...[
            const SizedBox(height: 12),
            _buildHiddenSection(),
          ],
        ],
      ),
    );
  }

  /// بررسی اینکه آیا کاربر دسترسی به یک ویجت دارد یا نه
  bool _hasWidgetPermission(DashboardWidgetDefinition widgetDef) {
    final authStore = widget.authStore;
    if (authStore == null) {
      // اگر authStore موجود نیست، برای سازگاری با کدهای قدیمی، true برمی‌گردانیم
      return true;
    }
    
    // اگر مالک کسب و کار است، دسترسی کامل دارد
    if (authStore.currentBusiness?.isOwner == true) {
      return true;
    }
    
    // اگر ویجت permission خاصی نیاز ندارد، نمایش داده می‌شود
    if (widgetDef.permissionsRequired.isEmpty) {
      return true;
    }
    
    // بررسی هر permission
    for (final permStr in widgetDef.permissionsRequired) {
      // Parse permission string (مثل "invoices.view" -> section="invoices", action="view")
      if (!permStr.contains('.')) {
        // اگر فرمت صحیح نیست، از آن عبور می‌کنیم (برای سازگاری)
        continue;
      }
      
      final parts = permStr.split('.');
      if (parts.length < 2) {
        continue;
      }
      
      final section = parts[0];
      final action = parts[1];
      
      // بررسی دسترسی
      if (!authStore.hasBusinessPermission(section, action)) {
        return false;
      }
    }
    
    return true;
  }

  Widget _buildGridTile(DashboardLayoutItem item, int totalColumns) {
    // بررسی دسترسی قبل از نمایش ویجت
    if (_definitions != null) {
      final widgetDef = _definitions!.items.firstWhere(
        (d) => d.key == item.key,
        orElse: () => DashboardWidgetDefinition(
          key: item.key,
          title: item.key,
          icon: 'widgets',
          version: 1,
          permissionsRequired: const [],
          defaults: const {},
        ),
      );
      
      if (!_hasWidgetPermission(widgetDef)) {
        // اگر کاربر دسترسی ندارد، ویجت را نمایش نمی‌دهیم
        return const SizedBox.shrink();
      }
    }
    
    final data = _data[item.key];
    if (data == null) {
      return _buildCard(
        title: _titleForKey(item.key),
        trailing: _editMode
            ? const Icon(Icons.tune)
            : IconButton(
                tooltip: 'بازخوانی',
                icon: const Icon(Icons.refresh),
                onPressed: _reloadDataOnly,
              ),
        child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final builder = _getWidgetBuilder(item.key);
    if (builder == null) {
      return _buildCard(
        title: 'ویجت ناشناخته: ${item.key}',
        child: Center(child: Text('این ویجت ثبت نشده است')),
      );
    }
    final trailing = _editMode
        ? PopupMenuButton<String>(
            tooltip: 'ویرایش',
            onSelected: (v) {
              if (v == 'w+1') _changeItemWidth(item, 1);
              if (v == 'w-1') _changeItemWidth(item, -1);
              if (v == 'up') _moveItemUp(item);
              if (v == 'down') _moveItemDown(item);
              if (v == 'hide') _hideItem(item, hidden: true);
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'w+1', child: Row(children: const [Icon(Icons.open_in_full, size: 18), SizedBox(width: 8), Text('افزایش عرض')],)),
              PopupMenuItem(value: 'w-1', child: Row(children: const [Icon(Icons.close_fullscreen, size: 18), SizedBox(width: 8), Text('کاهش عرض')],)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'up', child: Row(children: const [Icon(Icons.arrow_upward, size: 18), SizedBox(width: 8), Text('بالا')],)),
              PopupMenuItem(value: 'down', child: Row(children: const [Icon(Icons.arrow_downward, size: 18), SizedBox(width: 8), Text('پایین')],)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'hide', child: Row(children: const [Icon(Icons.visibility_off, size: 18), SizedBox(width: 8), Text('پنهان کردن')],)),
            ],
            icon: const Icon(Icons.tune),
          )
        : IconButton(
            tooltip: 'بازخوانی',
            icon: const Icon(Icons.refresh),
            onPressed: _reloadDataOnly,
          );
    // برای ویجت top_selling_products، کل _data را پاس می‌دهیم چون به تنظیمات و فیلترها نیاز دارد
    final widgetData = item.key == 'top_selling_products' ? _data : data;
    final card = _buildCard(
      title: _titleForKey(item.key),
      trailing: trailing,
      child: builder(context, widgetData, item, onRefresh: _reloadDataOnly),
    );
    if (!_editMode) return card;
    // دستگیره رزایز افقی در حالت ویرایش (لبه راست کارت)
    return Stack(
      children: [
        // سایه ملایم برای کارت در حالت ویرایش
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: card,
        ),
        // دستگیره رزایز
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) => _resizeItemByDx(item, details.delta.dx),
                child: Container(
                  width: 10,
                  height: double.infinity,
                  color: Colors.transparent,
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(AppLocalizations t) {
    final isMobile = _isMobile(context);
    final headerStyle = _getHeaderTextStyle(context);
    
    // Fiscal Year Widget
    final fiscalYearWidget = FutureBuilder<List<Map<String, dynamic>>>(
      future: _service.listFiscalYears(widget.businessId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timeline, size: isMobile ? 14 : 16),
              SizedBox(width: isMobile ? 4 : 6),
              FiscalYearSwitcher(
                controller: _fiscalController,
                fiscalYears: items,
                onChanged: _reloadDataOnly,
              ),
            ],
          ),
        );
      },
    );

    // Edit mode buttons
    final editButtons = _editMode
        ? [
            IconButton(
              tooltip: 'افزودن ویجت',
              onPressed: _showAddWidgetDialog,
              icon: const Icon(Icons.add_box_outlined),
              iconSize: isMobile ? 20 : 24,
            ),
            IconButton(
              tooltip: 'بازنشانی چیدمان',
              onPressed: _resetLayoutToDefaults,
              icon: const Icon(Icons.restore),
              iconSize: isMobile ? 20 : 24,
            ),
            if ((widget.authStore?.currentBusiness?.isOwner ?? false))
              IconButton(
                tooltip: 'انتشار چیدمان پیش‌فرض کسب‌وکار',
                onPressed: _publishBusinessDefaultLayout,
                icon: const Icon(Icons.publish),
                iconSize: isMobile ? 20 : 24,
              ),
          ]
        : <Widget>[];

    // Edit/Check button
    final editToggleButton = IconButton(
      tooltip: _editMode ? 'خروج از ویرایش' : 'ویرایش چیدمان',
      onPressed: () => setState(() => _editMode = !_editMode),
      icon: Icon(_editMode ? Icons.check : Icons.edit),
      iconSize: isMobile ? 20 : 24,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.businessDashboard,
                  style: headerStyle,
                ),
              ),
              editToggleButton,
            ],
          ),
          SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: fiscalYearWidget,
          ),
          if (editButtons.isNotEmpty) ...[
            SizedBox(height: 8),
            Row(
              children: editButtons,
            ),
          ],
        ],
      );
    } else {
      // دسکتاپ/تبلت: Row layout
      return Row(
        children: [
          Expanded(
            child: Text(
              t.businessDashboard,
              style: headerStyle,
            ),
          ),
          ...editButtons,
          const SizedBox(width: 8),
          fiscalYearWidget,
          const SizedBox(width: 8),
          editToggleButton,
        ],
      );
    }
  }

  // ====== Widget Registry ======
  DashboardWidgetBuilder? _getWidgetBuilder(String key) {
    switch (key) {
      case 'latest_sales_invoices':
        return _latestSalesInvoicesWidget;
      case 'sales_bar_chart':
        return _salesBarChartWidget;
      case 'checks_today':
        return _checksTodayWidget;
      case 'checks_tomorrow':
        return _checksTomorrowWidget;
      case 'checks_this_month':
        return _checksThisMonthWidget;
      case 'top_selling_products':
        return _topSellingProductsWidget;
      case 'checks_overdue':
        return _checksOverdueWidget;
      case 'latest_receipts_payments':
        return _latestReceiptsPaymentsWidget;
      case 'debtors_summary':
        return _debtorsSummaryWidget;
      case 'creditors_summary':
        return _creditorsSummaryWidget;
      case 'latest_purchase_invoices':
        return _latestPurchaseInvoicesWidget;
      case 'top_customers':
        return _topCustomersWidget;
      case 'top_suppliers':
        return _topSuppliersWidget;
      case 'pnl_summary':
        return _pnlSummaryWidget;
      case 'quick_links':
        return _quickLinksWidget;
      case 'crm_calendar':
        return _crmCalendarWidget;
      default:
        return null;
    }
  }

  Map<String, DashboardWidgetBuilder> get _widgetFactory => <String, DashboardWidgetBuilder>{
        'latest_sales_invoices': _latestSalesInvoicesWidget,
        'sales_bar_chart': _salesBarChartWidget,
        'checks_today': _checksTodayWidget,
        'checks_tomorrow': _checksTomorrowWidget,
        'checks_this_month': _checksThisMonthWidget,
        'top_selling_products': _topSellingProductsWidget,
        'checks_overdue': _checksOverdueWidget,
        'latest_receipts_payments': _latestReceiptsPaymentsWidget,
        'debtors_summary': _debtorsSummaryWidget,
        'creditors_summary': _creditorsSummaryWidget,
        'latest_purchase_invoices': _latestPurchaseInvoicesWidget,
        'top_customers': _topCustomersWidget,
        'top_suppliers': _topSuppliersWidget,
        'pnl_summary': _pnlSummaryWidget,
        'quick_links': _quickLinksWidget,
        'crm_calendar': _crmCalendarWidget,
      };

  Widget _quickLinksWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    return QuickLinksDashboardBody(
      businessId: widget.businessId,
      data: data,
      editMode: _editMode,
      onRefresh: onRefresh ?? () {},
      onOpenEditor: () async {
        await showQuickLinksEditorDialog(
          context: context,
          businessId: widget.businessId,
          service: _service,
          onSaved: () {
            _reloadDataOnly();
          },
        );
      },
    );
  }

  Widget _crmCalendarWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final isJalali = widget.calendarController?.isJalali ?? true;
    return CrmCalendarDashboardWidget(
      data: data,
      isJalali: isJalali,
      onMonthChanged: (y, m) {
        setState(() {
          _crmCalendarYear = y;
          _crmCalendarMonth = m;
        });
        _reloadDataOnly();
      },
    );
  }

  Widget _buildChecksWidget(BuildContext context, dynamic data, String title, VoidCallback? onRefresh) {
    final theme = Theme.of(context);
    final Map<String, dynamic> payload = (data is Map<String, dynamic>) ? data : const <String, dynamic>{};
    final List<Map<String, dynamic>> checks = (payload['items'] is List) 
        ? List<Map<String, dynamic>>.from(payload['items'] as List) 
        : const <Map<String, dynamic>>[];
    final Map<String, dynamic> totalsByCurrency = Map<String, dynamic>.from(payload['totals_by_currency'] ?? {});
    final int count = (payload['count'] as int?) ?? checks.length;

    if (checks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'چک‌ای یافت نشد',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    // Build summary header with totals
    Widget? summaryWidget;
    if (totalsByCurrency.isNotEmpty) {
      final summaryText = StringBuffer();
      totalsByCurrency.forEach((currencyCode, amount) {
        if (summaryText.isNotEmpty) summaryText.write(' + ');
        summaryText.write('${formatWithThousands(amount as num)} $currencyCode');
      });
      summaryWidget = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'مجموع: $summaryText ($count چک)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summaryWidget != null) summaryWidget,
        Expanded(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: checks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final check = checks[index];
              final checkNumber = '${check['check_number'] ?? '-'}';
              final personName = check['person_name'] as String?;
              final amount = (check['amount'] as num?) ?? 0;
              final currencyCode = (check['currency_code'] ?? '').toString();
              final type = (check['type'] ?? '').toString();
              final status = (check['status'] ?? '').toString();
              final dueDate = check['due_date'] as String?;
              
              final typeText = type == 'received' ? 'دریافتی' : type == 'transferred' ? 'پرداختنی' : type;
              final statusText = _getCheckStatusText(status);
              
              final subtitle = StringBuffer();
              if (personName != null && personName.isNotEmpty) {
                subtitle.write(personName);
                subtitle.write(' • ');
              }
              subtitle.write(typeText);
              if (statusText.isNotEmpty) {
                subtitle.write(' • ');
                subtitle.write(statusText);
              }
              if (dueDate != null) {
                final formattedDate = DateFormatters.formatServerDateOnly(dueDate);
                subtitle.write(' • ');
                subtitle.write(formattedDate);
              }

              return ListTile(
                dense: true,
                leading: Icon(
                  type == 'received' ? Icons.account_balance_wallet : Icons.account_balance,
                  color: type == 'received' 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.error,
                ),
                title: Text(checkNumber),
                subtitle: Text(subtitle.toString()),
                trailing: Text(
                  currencyCode.isNotEmpty ? '${formatWithThousands(amount)} $currencyCode' : formatWithThousands(amount),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  // Navigate to checks page with filter or check detail
                  final checkId = check['id'] as int?;
                  if (checkId != null) {
                    // TODO: Navigate to check detail or checks page with filter
                    // Navigator.of(context).pushNamed('/business/${widget.businessId}/checks', arguments: {'check_id': checkId});
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _checksTodayWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    return _buildChecksWidget(context, data, 'چک‌های امروز', onRefresh);
  }

  Widget _checksTomorrowWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    return _buildChecksWidget(context, data, 'چک‌های فردا', onRefresh);
  }

  Widget _checksThisMonthWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    return _buildChecksWidget(context, data, 'چک‌های این ماه', onRefresh);
  }

  Widget _checksOverdueWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    return _buildChecksWidget(context, data, 'چک‌های سررسید گذشته', onRefresh);
  }

  Widget _latestReceiptsPaymentsWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    final calendarController = widget.calendarController;
    final isJalali = calendarController?.isJalali ?? true;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text('داده‌ای یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return SizedBox(
      height: 300,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final it = items[index];
          final code = '${it['code'] ?? '-'}';
          final docType = it['document_type']?.toString() ?? '';
          final typeName = it['document_type_name'] ?? (docType == 'receipt' ? 'دریافت' : 'پرداخت');
          DateTime? dateTime;
          try {
            final dateStr = it['document_date']?.toString();
            if (dateStr != null && dateStr.isNotEmpty) dateTime = DateTime.parse(dateStr.split('T')[0]);
          } catch (_) {}
          final date = dateTime != null ? HesabixDateUtils.formatForDisplay(dateTime, isJalali) : DateFormatters.formatServerDateOnly(it['document_date']);
          final totalAmount = (it['total_amount'] as num?) ?? 0;
          final currencyCode = (it['currency_code'] ?? '').toString();
          final personNames = it['person_names_str'] ?? it['person_names'] ?? '';
          return ListTile(
            dense: true,
            leading: Icon(
              docType == 'receipt' ? Icons.call_received : Icons.call_made,
              color: docType == 'receipt' ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
            title: Text(code),
            subtitle: Text('$typeName • $date${personNames.toString().isNotEmpty ? ' • $personNames' : ''}'),
            trailing: Text(
              currencyCode.isNotEmpty ? '${formatWithThousands(totalAmount)} $currencyCode' : formatWithThousands(totalAmount),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            onTap: () {
              final docId = it['id'] as int?;
              if (docId != null && calendarController != null) {
                showDialog(
                  context: context,
                  builder: (_) => DocumentDetailsDialog(
                    documentId: docId,
                    calendarController: calendarController,
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _debtorsSummaryWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final payload = (data is Map<String, dynamic>) ? data : const <String, dynamic>{};
    final items = (payload['items'] is List) ? List<Map<String, dynamic>>.from(payload['items'] as List) : <Map<String, dynamic>>[];
    final summary = payload['summary'] is Map ? Map<String, dynamic>.from(payload['summary'] as Map) : <String, dynamic>{};
    final totalDebt = (summary['total_debt'] as num?) ?? 0.0;
    final totalCount = (summary['total_count'] as int?) ?? 0;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('بدهکاری یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (totalCount == 0 && totalDebt == 0)
                Text('جمع بدهکاران: ۰', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (totalCount > 0 || totalDebt != 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'جمع $totalCount بدهکار: ${formatWithThousands(totalDebt)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = items[index];
              final name = p['alias_name'] ?? '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
              final balance = (p['balance'] as num?) ?? 0;
              final absBalance = balance < 0 ? -balance : balance;
              return ListTile(
                dense: true,
                leading: Icon(Icons.person_outline, color: theme.colorScheme.error),
                title: Text(name.isEmpty ? 'نامشخص' : name),
                trailing: Text(
                  formatWithThousands(absBalance),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.error),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _creditorsSummaryWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final payload = (data is Map<String, dynamic>) ? data : const <String, dynamic>{};
    final items = (payload['items'] is List) ? List<Map<String, dynamic>>.from(payload['items'] as List) : <Map<String, dynamic>>[];
    final summary = payload['summary'] is Map ? Map<String, dynamic>.from(payload['summary'] as Map) : <String, dynamic>{};
    final totalCredit = (summary['total_credit'] as num?) ?? 0.0;
    final totalCount = (summary['total_count'] as int?) ?? 0;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('بستانکاری یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (totalCount == 0 && totalCredit == 0)
                Text('جمع بستانکاران: ۰', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (totalCount > 0 || totalCredit != 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'جمع $totalCount بستانکار: ${formatWithThousands(totalCredit)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = items[index];
              final name = p['alias_name'] ?? '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
              final balance = (p['balance'] as num?) ?? 0;
              return ListTile(
                dense: true,
                leading: Icon(Icons.group_outlined, color: theme.colorScheme.primary),
                title: Text(name.isEmpty ? 'نامشخص' : name),
                trailing: Text(
                  formatWithThousands(balance),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _latestPurchaseInvoicesWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    final calendarController = widget.calendarController;
    final isJalali = calendarController?.isJalali ?? true;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text('داده‌ای یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return SizedBox(
      height: 300,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final it = items[index];
          final code = '${it['code'] ?? '-'}';
          DateTime? dateTime;
          try {
            final dateStr = it['document_date']?.toString();
            if (dateStr != null && dateStr.isNotEmpty) dateTime = DateTime.parse(dateStr);
          } catch (_) {}
          final date = dateTime != null ? HesabixDateUtils.formatForDisplay(dateTime, isJalali) : DateFormatters.formatServerDateOnly(it['document_date']);
          final net = formatWithThousands(it['net_amount']);
          final currency = (it['currency_code'] ?? '').toString();
          final itemsCount = (it['items_count'] ?? 0) as int;
          final subtitle = '$date • ${currency.isNotEmpty ? currency : '—'} • اقلام: $itemsCount';
          return ListTile(
            dense: true,
            leading: const Icon(Icons.shopping_cart),
            title: Text(code),
            subtitle: Text(subtitle),
            trailing: Text(
              currency.isNotEmpty ? '$net $currency' : net,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            onTap: () {
              final invoiceId = it['id'] as int?;
              if (invoiceId != null && calendarController != null) {
                showDialog(
                  context: context,
                  builder: (_) => DocumentDetailsDialog(
                    documentId: invoiceId,
                    calendarController: calendarController,
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _topCustomersWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final payload = (data is Map<String, dynamic>) ? data : const <String, dynamic>{};
    final items = (payload['items'] is List) ? List<Map<String, dynamic>>.from(payload['items'] as List) : const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text('داده‌ای یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final it = items[index];
        final name = it['alias_name'] ?? it['person_name'] ?? 'نامشخص';
        final totalSales = (it['total_sales'] as num?) ?? 0;
        final invoiceCount = (it['invoice_count'] as int?) ?? 0;
        return ListTile(
          dense: true,
          leading: Icon(Icons.star_outline, color: theme.colorScheme.primary),
          title: Text(name),
          subtitle: Text('$invoiceCount فاکتور'),
          trailing: Text(
            formatWithThousands(totalSales),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }

  Widget _topSuppliersWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final payload = (data is Map<String, dynamic>) ? data : const <String, dynamic>{};
    final items = (payload['items'] is List) ? List<Map<String, dynamic>>.from(payload['items'] as List) : const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text('داده‌ای یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final it = items[index];
        final name = it['alias_name'] ?? it['person_name'] ?? 'نامشخص';
        final totalPurchases = (it['total_purchases'] as num?) ?? 0;
        final invoiceCount = (it['invoice_count'] as int?) ?? 0;
        return ListTile(
          dense: true,
          leading: Icon(Icons.local_shipping_outlined, color: theme.colorScheme.primary),
          title: Text(name),
          subtitle: Text('$invoiceCount فاکتور'),
          trailing: Text(
            formatWithThousands(totalPurchases),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }

  Widget _pnlSummaryWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final payload = (data is Map<String, dynamic>) ? data : const <String, dynamic>{};
    final summary = payload['summary'] is Map ? Map<String, dynamic>.from(payload['summary'] as Map) : <String, dynamic>{};
    final totalRevenue = (summary['total_revenue'] as num?) ?? 0.0;
    final totalExpense = (summary['total_expense'] as num?) ?? 0.0;
    final netProfitLoss = (summary['net_profit_loss'] as num?) ?? 0.0;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPnlRow(theme, 'درآمد', totalRevenue, theme.colorScheme.primary),
          const SizedBox(height: 8),
          _buildPnlRow(theme, 'هزینه', totalExpense, theme.colorScheme.error),
          const Divider(height: 24),
          _buildPnlRow(theme, netProfitLoss >= 0 ? 'سود خالص' : 'زیان خالص', netProfitLoss, netProfitLoss >= 0 ? theme.colorScheme.primary : theme.colorScheme.error, isBold: true),
        ],
      ),
    );
  }

  Widget _buildPnlRow(ThemeData theme, String label, num value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
        Text(formatWithThousands(value), style: theme.textTheme.bodyLarge?.copyWith(color: color, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
      ],
    );
  }

  Widget _latestSalesInvoicesWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    final calendarController = widget.calendarController;
    final isJalali = calendarController?.isJalali ?? true;
    
    return items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text('داده‌ای یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            )
          : Container(
              height: 300, // ارتفاع فیکس
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final it = items[index];
                  final code = '${it['code'] ?? '-'}';
                  // Parse تاریخ از ISO format و فرمت بر اساس تقویم کاربر
                  DateTime? dateTime;
                  try {
                    final dateStr = it['document_date']?.toString();
                    if (dateStr != null && dateStr.isNotEmpty) {
                      // Try parsing as ISO format (supports both YYYY-MM-DD and full ISO)
                      dateTime = DateTime.parse(dateStr);
                    }
                  } catch (e) {
                    // در صورت خطا، از فرمت قبلی استفاده می‌کنیم
                  }
                  final date = dateTime != null 
                      ? HesabixDateUtils.formatForDisplay(dateTime, isJalali)
                      : DateFormatters.formatServerDateOnly(it['document_date']);
                  final net = formatWithThousands(it['net_amount']);
                  final currency = (it['currency_code'] ?? '').toString();
                  final itemsCount = (it['items_count'] ?? 0) as int;
                  final subtitle = StringBuffer()
                    ..write(date)
                    ..write(' • ')
                    ..write(currency.isNotEmpty ? currency : '—')
                    ..write(' • ')
                    ..write('اقلام: $itemsCount');
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.receipt_long),
                    title: Text(code),
                    subtitle: Text(subtitle.toString()),
                    trailing: Text(
                      currency.isNotEmpty ? '$net $currency' : net,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      final invoiceId = it['id'] as int?;
                      if (invoiceId != null && calendarController != null) {
                        showDialog(
                          context: context,
                          builder: (_) => DocumentDetailsDialog(
                            documentId: invoiceId,
                            calendarController: calendarController,
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            );
  }

  Widget _salesBarChartWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final Map<String, dynamic> payload = (data is Map<String, dynamic>) ? data : const <String, dynamic>{};
    final List<Map<String, dynamic>> items = (payload['items'] is List) ? List<Map<String, dynamic>>.from(payload['items']) : const <Map<String, dynamic>>[];
    String currentRange = (payload['range'] ?? 'week').toString();
    String currentGroup = (payload['group'] ?? _salesChartGroup).toString();
    _salesChartGroup = currentGroup; // sync with server if needed

    Future<void> _reloadWith(Map<String, dynamic> filters) async {
      try {
        final d = await _service.getWidgetsBatchData(
          businessId: widget.businessId,
          widgetKeys: const ['sales_bar_chart'],
          filters: {
            ...filters,
            'group': _salesChartGroup,
          },
        );
        if (!mounted) return;
        setState(() {
          _data['sales_bar_chart'] = d['sales_bar_chart'];
        });
      } catch (_) {}
    }

    Widget _filters() {
      final isMobile = _isMobile(context);
      final spacing = isMobile ? 6.0 : 8.0;
      final runSpacing = isMobile ? 6.0 : 8.0;
      
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
        child: Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            ChoiceChip(
              label: Text('این هفته', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              selected: currentRange == 'week',
              onSelected: (_) => _reloadWith({'range': 'week'}),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
            ChoiceChip(
              label: Text('این ماه', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              selected: currentRange == 'month',
              onSelected: (_) => _reloadWith({'range': 'month'}),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
            ChoiceChip(
              label: Text('سال مالی', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              selected: currentRange == 'fiscal',
              onSelected: (_) => _reloadWith({'range': 'fiscal'}),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
            ActionChip(
              label: Text('بازه سفارشی', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              onPressed: () async {
                final picked = await _pickCustomRange(context);
                if (picked != null) {
                  _reloadWith({'range': 'custom', 'from': picked.$1, 'to': picked.$2});
                }
              },
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            // Chart type
            ChoiceChip(
              label: Text('میله‌ای', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              selected: _salesChartType == 'bar',
              onSelected: (_) => setState(() => _salesChartType = 'bar'),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
            ChoiceChip(
              label: Text('خطی', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              selected: _salesChartType == 'line',
              onSelected: (_) => setState(() => _salesChartType = 'line'),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            ChoiceChip(
              label: Text('روزانه', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              selected: _salesChartGroup == 'day',
              onSelected: (_) async {
                setState(() => _salesChartGroup = 'day');
                await _reloadWith({'range': currentRange});
              },
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
            ChoiceChip(
              label: Text('هفتگی', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              selected: _salesChartGroup == 'week',
              onSelected: (_) async {
                setState(() => _salesChartGroup = 'week');
                await _reloadWith({'range': currentRange});
              },
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
            ChoiceChip(
              label: Text('ماهانه', style: TextStyle(fontSize: isMobile ? 12 : 14)),
              selected: _salesChartGroup == 'month',
              onSelected: (_) async {
                setState(() => _salesChartGroup = 'month');
                await _reloadWith({'range': currentRange});
              },
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            ),
          ],
        ),
      );
    }

    final List<Map<String, dynamic>> grouped = items; // already grouped by server (or daily for day)
    final isMobile = _isMobile(context);
    final bars = <BarChartGroupData>[];
    final points = <FlSpot>[];
    double maxY = 0;
    final barWidth = isMobile ? 10.0 : 12.0;
    
    // رنگ اصلی نمودار با کنتراست بهتر
    final primaryColor = theme.colorScheme.primary;
    final chartColor = primaryColor.withValues(alpha: 0.85);
    
    for (int i = 0; i < grouped.length; i++) {
      final it = grouped[i];
      final amount = (it['amount'] as num?)?.toDouble() ?? 0;
      if (amount > maxY) maxY = amount;
      bars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: amount,
              width: barWidth,
              color: chartColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
      points.add(FlSpot(i.toDouble(), amount));
    }
    if (maxY <= 0) maxY = 1;

    String _labelForIndex(int i) {
      if (i < 0 || i >= grouped.length) return '';
      final item = grouped[i];
      final key = (item['key'] ?? item['date'] ?? '').toString();
      // key may be iso day, week key (yyyy-ww), or month key (yyyy-mm)
      try {
        if (_salesChartGroup == 'month') {
          final parts = key.split('-');
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          if (widget.calendarController?.isJalali == true) {
            // convert first day of that month to jalali month label
            final d = DateTime(year, month, 1);
            final j = Jalali.fromDateTime(d);
            return _jalaliMonthName(j.month);
          }
          return _gregorianMonthName(month);
        } else if (_salesChartGroup == 'week') {
          // key format: yyyy-ww; show 'Wxx'
          final ww = key.split('-').last;
          return 'هفته $ww';
        } else {
          // day: key is iso date
          final d = DateTime.parse(key);
          if (widget.calendarController?.isJalali == true) {
            final j = Jalali.fromDateTime(d);
            return '${j.day}';
          }
          return d.day.toString();
        }
      } catch (_) {
        return key;
      }
    }

    final chartHeight = _getChartHeight(context);
    final isMobileChart = _isMobile(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isMobileChart ? 8 : 12, 8, isMobileChart ? 8 : 12, 4),
          child: _filters(),
        ),
        SizedBox(
          height: chartHeight,
            child: Padding(
            padding: EdgeInsets.fromLTRB(isMobileChart ? 4 : 8, 0, isMobileChart ? 4 : 8, 8),
            child: grouped.isEmpty
                ? Center(child: Text('داده‌ای برای نمایش نیست', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                : (_salesChartType == 'bar'
                    ? BarChart(
                        BarChartData(
                          gridData: FlGridData(
                            show: true,
                            horizontalInterval: maxY / 4,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: theme.colorScheme.outline.withValues(alpha: 0.15),
                                strokeWidth: 1,
                                dashArray: [4, 4],
                              );
                            },
                          ),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: isMobile ? 35 : 40,
                                interval: maxY / 4,
                                getTitlesWidget: (value, meta) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    formatWithThousands(value, decimalPlaces: 0),
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontSize: isMobileChart ? 11 : 13,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _labelForIndex(value.toInt()),
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontSize: isMobileChart ? 11 : 13,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: bars,
                          alignment: BarChartAlignment.spaceBetween,
                          maxY: maxY * 1.2,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (group) {
                                // استفاده از رنگ پس‌زمینه سطح با کنتراست مناسب
                                return theme.colorScheme.surfaceContainerHighest;
                              },
                              tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              tooltipMargin: 8,
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final value = rod.toY;
                                return BarTooltipItem(
                                  formatWithThousands(value, decimalPlaces: 0),
                                  TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: theme.textTheme.bodyMedium?.fontSize ?? 14,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            horizontalInterval: maxY / 4,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: theme.colorScheme.outline.withValues(alpha: 0.15),
                                strokeWidth: 1,
                                dashArray: [4, 4],
                              );
                            },
                          ),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: isMobileChart ? 35 : 40,
                                interval: maxY / 4,
                                getTitlesWidget: (value, meta) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    formatWithThousands(value, decimalPlaces: 0),
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontSize: isMobileChart ? 11 : 13,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _labelForIndex(value.toInt()),
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontSize: isMobileChart ? 11 : 13,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              isCurved: true,
                              color: chartColor,
                              barWidth: isMobileChart ? 2.5 : 3.5,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, barData, index) {
                                  return FlDotCirclePainter(
                                    radius: isMobileChart ? 3 : 4,
                                    color: chartColor,
                                    strokeWidth: 2,
                                    strokeColor: theme.colorScheme.surface,
                                  );
                                },
                              ),
                              spots: points,
                              belowBarData: BarAreaData(
                                show: true,
                                color: chartColor.withValues(alpha: 0.1),
                              ),
                            ),
                          ],
                          minY: 0,
                          maxY: maxY * 1.2,
                          lineTouchData: LineTouchData(
                            enabled: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (touchedSpot) {
                                // استفاده از رنگ پس‌زمینه سطح با کنتراست مناسب
                                return theme.colorScheme.surfaceContainerHighest;
                              },
                              tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              tooltipMargin: 8,
                              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                return touchedSpots.map((LineBarSpot touchedSpot) {
                                  final value = touchedSpot.y;
                                  return LineTooltipItem(
                                    formatWithThousands(value, decimalPlaces: 0),
                                    TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: theme.textTheme.bodyMedium?.fontSize ?? 14,
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        ),
                      )),
          ),
        ),
      ],
    );
  }

  Widget _topSellingProductsWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    // data در اینجا همان _data است (کل Map) که از _buildGridTile پاس داده شده
    return _TopSellingProductsWidgetContent(
      businessId: widget.businessId,
      data: data,
      service: _service,
      onRefresh: onRefresh,
      onDataUpdate: (updatedData) {
        if (mounted) {
          setState(() {
            // فقط کلید top_selling_products را به‌روزرسانی کن
            _data['top_selling_products'] = updatedData['top_selling_products'];
          });
        }
      },
    );
  }

  String _getCheckStatusText(String status) {
    switch (status) {
      case 'RECEIVED_ON_HAND':
        return 'در دست';
      case 'DEPOSITED':
        return 'سپرده';
      case 'ENDORSED':
        return 'واگذار شده';
      case 'RETURNED':
        return 'عودت';
      case 'BOUNCED':
        return 'برگشت';
      case 'TRANSFERRED_ISSUED':
        return 'صادر شده';
      case 'CLEARED':
        return 'پاس شده';
      case 'CANCELLED':
        return 'ابطال';
      default:
        return '';
    }
  }

  // Pick custom date range; returns iso from/to
  Future<(String, String)?> _pickCustomRange(BuildContext context) async {
    if (!context.mounted) return null;
    final ctx = context;
    final now = DateTime.now();
    final from = await showAdaptiveDatePicker(
      context: ctx,
      calendarController: widget.calendarController,
      initialDate: now,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: 'انتخاب تاریخ شروع',
    );
    if (from == null) return null;
    if (!ctx.mounted) return null;
    final to = await showAdaptiveDatePicker(
      context: ctx,
      calendarController: widget.calendarController,
      initialDate: from,
      firstDate: from,
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: 'انتخاب تاریخ پایان',
    );
    if (to == null) return null;
    final a = from.isBefore(to) ? from : to;
    final b = from.isBefore(to) ? to : from;
    return (_isoDate(a), _isoDate(b));
  }

  Widget _buildCard({required String title, Widget? trailing, required Widget child}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                if (trailing != null) trailing,
              ],
            ),
          ),
          // در محیط Wrap/Flow نباید از Expanded استفاده کنیم
          child,
        ],
      ),
    );
  }

  Widget _buildHiddenSection() {
    final profile = _layout;
    if (profile == null) return const SizedBox.shrink();
    final hidden = profile.items.where((e) => e.hidden).toList();
    if (hidden.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ویجت‌های پنهان', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: hidden.map((it) {
                return InputChip(
                  label: Text(_titleForKey(it.key)),
                  avatar: const Icon(Icons.widgets, size: 18),
                  onPressed: () => _hideItem(it, hidden: false),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddWidgetDialog() async {
    if (_definitions == null || _layout == null) return;
    final defs = _definitions!;
    final profile = _layout!;
    final rows = List<DashboardWidgetDefinition>.from(defs.items);
    String query = '';
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('افزودن ویجت'),
          content: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setSt) {
                // فیلتر بر اساس جستجو و دسترسی
                final filtered = rows.where((d) {
                  // فیلتر بر اساس جستجو
                  if (query.trim().isNotEmpty) {
                    final q = query.toLowerCase();
                    if (!d.title.toLowerCase().contains(q) && !d.key.toLowerCase().contains(q)) {
                      return false;
                    }
                  }
                  
                  // بررسی دسترسی
                  final authStore = widget.authStore;
                  if (authStore == null) {
                    return true; // برای سازگاری با کدهای قدیمی
                  }
                  
                  // اگر مالک کسب و کار است، دسترسی کامل دارد
                  if (authStore.currentBusiness?.isOwner == true) {
                    return true;
                  }
                  
                  // اگر ویجت permission خاصی نیاز ندارد، نمایش داده می‌شود
                  if (d.permissionsRequired.isEmpty) {
                    return true;
                  }
                  
                  // بررسی هر permission
                  for (final permStr in d.permissionsRequired) {
                    if (!permStr.contains('.')) {
                      continue;
                    }
                    
                    final parts = permStr.split('.');
                    if (parts.length < 2) {
                      continue;
                    }
                    
                    final section = parts[0];
                    final action = parts[1];
                    
                    if (!authStore.hasBusinessPermission(section, action)) {
                      return false;
                    }
                  }
                  
                  return true;
                }).toList();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'جست‌وجوی ویجت...'),
                      onChanged: (v) => setSt(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    if (filtered.isEmpty)
                      const Expanded(child: Center(child: Text('ویجت جدیدی برای افزودن موجود نیست.')))
                    else
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final d = filtered[index];
                            final existing = profile.items.where((it) => it.key == d.key).toList();
                            DashboardLayoutItem? existingItem = existing.isNotEmpty ? existing.first : null;
                            final isVisible = existingItem != null && !existingItem.hidden;
                            final isHidden = existingItem != null && existingItem.hidden;
                            final status = isVisible ? 'در حال نمایش' : (isHidden ? 'پنهان' : 'افزوده نشده');
                            return ListTile(
                              leading: const Icon(Icons.widgets_outlined),
                              title: Text(d.title),
                              subtitle: Text('${d.key} • $status'),
                              trailing: isVisible
                                  ? const SizedBox.shrink()
                                  : ElevatedButton(
                                      onPressed: () async {
                                        if (isHidden) {
                                          _hideItem(existingItem, hidden: false);
                                        } else {
                                          _addWidgets([d.key]);
                                        }
                                        if (context.mounted) Navigator.pop(context);
                                      },
                                      child: Text(isHidden ? 'نمایش' : 'افزودن'),
                                    ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
        );
      },
    );
    if (!mounted) return;
  }

  void _addWidgets(List<String> keys) async {
    if (keys.isEmpty || _definitions == null || _layout == null) return;
    final defs = _definitions!;
    final profile = _layout!;
    final bp = profile.breakpoint;
    final list = List<DashboardLayoutItem>.from(profile.items);
    var maxOrder = 0;
    for (final it in list) {
      if (it.order > maxOrder) maxOrder = it.order;
    }
    for (final k in keys) {
      final def = defs.items.firstWhere((d) => d.key == k, orElse: () => DashboardWidgetDefinition(
        key: k, title: k, icon: 'widgets', version: 1, permissionsRequired: const [], defaults: const {},
      ));
      final dflt = def.defaults[bp] ?? const {};
      final colSpan = (dflt['colSpan'] ?? (profile.columns / 2).floor()).clamp(1, profile.columns);
      final rowSpan = dflt['rowSpan'] ?? 2;
      // اگر موجود است ولی hidden بود → آشکار کن
      final idxExisting = list.indexWhere((e) => e.key == k);
      if (idxExisting >= 0) {
        list[idxExisting] = list[idxExisting].copyWith(hidden: false, colSpan: colSpan, rowSpan: rowSpan);
      } else {
        maxOrder += 1;
        list.add(DashboardLayoutItem(key: k, order: maxOrder, colSpan: colSpan, rowSpan: rowSpan, hidden: false));
      }
    }
    _applyItems(list);
    // داده‌ی ویجت‌های جدید
    try {
      final newData = await _service.getWidgetsBatchData(
        businessId: widget.businessId,
        widgetKeys: keys,
        filters: _dashboardBatchFilters(keys),
      );
      if (!mounted) return;
      setState(() {
        _data.addAll(newData);
      });
    } catch (_) {}
  }

  Future<void> _resetLayoutToDefaults() async {
    if (_definitions == null || _layout == null) return;
    final defs = _definitions!;
    final profile = _layout!;
    final bp = profile.breakpoint;
    final columns = profile.columns;
    // تلاش برای دریافت پیش‌فرض کسب‌وکار
    try {
      final businessDefault = await _service.getBusinessDefaultLayout(businessId: widget.businessId, breakpoint: bp);
      if (businessDefault != null && businessDefault.items.isNotEmpty) {
        setState(() {
          _layout = businessDefault;
        });
        final keys = businessDefault.items.where((e) => !e.hidden).map((e) => e.key).toList();
        final data = await _service.getWidgetsBatchData(
          businessId: widget.businessId,
          widgetKeys: keys,
          filters: _dashboardBatchFilters(keys),
        );
        if (!mounted) return;
        setState(() => _data = data);
        _scheduleSaveLayout();
        return;
      }
    } catch (_) {
      // fallback به پیش‌فرض سیستم
    }
    int order = 1;
    final items = <DashboardLayoutItem>[];
    for (final d in defs.items) {
      final dflt = d.defaults[bp] ?? const {};
      final colSpan = (dflt['colSpan'] ?? (columns / 2).floor()).clamp(1, columns);
      final rowSpan = dflt['rowSpan'] ?? 2;
      items.add(DashboardLayoutItem(key: d.key, order: order++, colSpan: colSpan, rowSpan: rowSpan, hidden: false));
    }
    _applyItems(items);
    // بازخوانی داده‌ها
    final keys = items.where((e) => !e.hidden).map((e) => e.key).toList();
    try {
      final data = await _service.getWidgetsBatchData(
        businessId: widget.businessId,
        widgetKeys: keys,
        filters: _dashboardBatchFilters(keys),
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (_) {}
  }

  Future<void> _publishBusinessDefaultLayout() async {
    final profile = _layout;
    if (profile == null) return;
    try {
      await _service.putBusinessDefaultLayout(
        businessId: widget.businessId,
        breakpoint: profile.breakpoint,
        items: profile.items,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'چیدمان پیش‌فرض کسب‌وکار منتشر شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در انتشار: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  String _titleForKey(String key) {
    switch (key) {
      case 'latest_sales_invoices':
        return 'آخرین فاکتورهای فروش';
      case 'sales_bar_chart':
        return 'نمودار فروش';
      case 'checks_today':
        return 'چک‌های امروز';
      case 'checks_tomorrow':
        return 'چک‌های فردا';
      case 'checks_this_month':
        return 'چک‌های این ماه';
      case 'top_selling_products':
        return 'کالاهای پرفروش';
      case 'checks_overdue':
        return 'چک‌های سررسید گذشته';
      case 'latest_receipts_payments':
        return 'آخرین دریافت و پرداخت‌ها';
      case 'debtors_summary':
        return 'خلاصه بدهکاران';
      case 'creditors_summary':
        return 'خلاصه بستانکاران';
      case 'latest_purchase_invoices':
        return 'آخرین فاکتورهای خرید';
      case 'top_customers':
        return 'بهترین مشتریان';
      case 'top_suppliers':
        return 'بهترین تأمین‌کنندگان';
      case 'pnl_summary':
        return 'خلاصه سود و زیان';
      case 'quick_links':
        return 'دسترسی سریع';
      case 'crm_calendar':
        return 'تقویم CRM';
      default:
        return key;
    }
  }

  // old formatters removed; using DateFormatters and number_formatters

  // --- Resize helpers ---
  void _resizeItemByDx(DashboardLayoutItem item, double dx) {
    final profile = _layout;
    if (profile == null || _columnUnitPx <= 0) return;
    // هر ستون موثر: unit + spacing به جز آخرین ستون
    final spacing = _getGridSpacing(context);
    final colPixel = _columnUnitPx + spacing;
    // برآورد تعداد ستون‌های جدید بر اساس جابجایی
    final deltaCols = (dx / colPixel).round();
    if (deltaCols == 0) return;
    _changeItemWidth(item, deltaCols);
  }
}

String _jalaliMonthName(int m) {
  const months = [
    '',
    'فروردین','اردیبهشت','خرداد','تیر','مرداد','شهریور',
    'مهر','آبان','آذر','دی','بهمن','اسفند'
  ];
  if (m >= 1 && m <= 12) return months[m];
  return '$m';
}

String _gregorianMonthName(int m) {
  const months = [
    '',
    'ژانویه','فوریه','مارس','آوریل','مه','ژوئن',
    'ژوئیه','اوت','سپتامبر','اکتبر','نوامبر','دسامبر'
  ];
  if (m >= 1 && m <= 12) return months[m];
  return '$m';
}

String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _TopSellingProductsWidgetContent extends StatefulWidget {
  final int businessId;
  final dynamic data;
  final BusinessDashboardService service;
  final VoidCallback? onRefresh;
  final Function(Map<String, dynamic>)? onDataUpdate;

  const _TopSellingProductsWidgetContent({
    required this.businessId,
    required this.data,
    required this.service,
    this.onRefresh,
    this.onDataUpdate,
  });

  @override
  State<_TopSellingProductsWidgetContent> createState() => _TopSellingProductsWidgetContentState();
}

class _TopSellingProductsWidgetContentState extends State<_TopSellingProductsWidgetContent> {
  static const String _settingsKey = 'top_selling_products_settings';
  
  String _calculationType = 'amount'; // 'amount' | 'quantity'
  String _viewType = 'bar'; // 'bar' | 'pie' | 'list'
  int _limit = 10;
  int? _currencyId; // ارز انتخاب شده (فقط برای calculation_type == 'amount')

  bool _settingsLoaded = false;
  bool _loading = false;
  bool _currenciesLoaded = false;
  Map<String, dynamic> _localData = {};
  List<Map<String, dynamic>> _currencies = [];
  late CurrencyService _currencyService;

  // Helper methods for responsive values
  String _currentBreakpoint(double width) {
    if (width < 600) return 'xs';
    if (width < 904) return 'sm';
    if (width < 1240) return 'md';
    if (width < 1600) return 'lg';
    return 'xl';
  }

  bool _isMobile(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return _currentBreakpoint(width) == 'xs';
  }

  double _getChartHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bp = _currentBreakpoint(width);
    switch (bp) {
      case 'xs':
        return 220.0; // موبایل
      case 'sm':
        return 240.0; // تبلت کوچک
      case 'md':
        return 260.0; // تبلت بزرگ
      case 'lg':
        return 280.0; // دسکتاپ کوچک
      case 'xl':
        return 300.0; // دسکتاپ بزرگ
      default:
        return 280.0;
    }
  }

  @override
  void initState() {
    super.initState();
    _currencyService = CurrencyService(ApiClient());
    
    // کپی داده‌های اولیه از parent
    // widget.data در واقع همان _data[item.key] است که می‌تواند یک Map باشد یا مستقیماً داده ویجت
    if (widget.data is Map) {
      // اگر widget.data یک Map است، باید بررسی کنیم که آیا خودش داده است یا یک Map با کلید top_selling_products
      final dataMap = widget.data as Map;
      if (dataMap.containsKey('top_selling_products')) {
        // widget.data همان _data است که کلید top_selling_products دارد
        _localData = Map<String, dynamic>.from(dataMap);
      } else if (dataMap.containsKey('items')) {
        // widget.data مستقیماً داده ویجت است
        _localData = {'top_selling_products': dataMap};
      } else {
        // داده اولیه را در کلید صحیح قرار بده
        _localData = {'top_selling_products': dataMap};
      }
    } else if (widget.data != null) {
      // اگر widget.data یک شیء دیگر است، آن را در کلید صحیح قرار بده
      _localData = {'top_selling_products': widget.data};
    } else {
      _localData = <String, dynamic>{};
    }
    
    // بارگذاری ارزها و تنظیمات
    _loadCurrencies().then((_) {
      // اگر داده موجود است، از آن استفاده کن و فقط تنظیمات را بارگذاری کن
      // در غیر این صورت بعد از بارگذاری تنظیمات، داده را از سرور بگیر
      final hasInitialData = _localData['top_selling_products'] != null;
      if (hasInitialData) {
        // داده موجود است، فقط تنظیمات را بارگذاری کن
        _loadSettingsWithoutReload();
      } else {
        // داده موجود نیست، بعد از بارگذاری تنظیمات، داده را از سرور بگیر
        _loadSettings();
      }
    });
  }
  
  Future<void> _loadCurrencies() async {
    try {
      final currencies = await _currencyService.listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _currencies = currencies;
        _currenciesLoaded = true;
        
        // اگر محاسبه مقداری است و ارزی انتخاب نشده و ارز پیش‌فرض موجود است، آن را انتخاب کن
        if (_calculationType == 'amount' && _currencyId == null && currencies.isNotEmpty) {
          final defaultCurrency = currencies.firstWhere(
            (currency) => currency['is_default'] == true,
            orElse: () => currencies.first,
          );
          _currencyId = defaultCurrency['id'] as int?;
          // تنظیمات را ذخیره کن
          _saveSettings();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currenciesLoaded = true;
      });
    }
  }
  
  Future<void> _loadSettingsWithoutReload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('$_settingsKey${widget.businessId}');
      if (settingsJson != null) {
        final parts = settingsJson.split('|');
        if (parts.length >= 3) {
          setState(() {
            _calculationType = parts[0];
            _viewType = parts[1];
            _limit = int.tryParse(parts[2]) ?? 10;
            // اگر currency_id هم ذخیره شده بود، آن را بخوان
            if (parts.length >= 4 && parts[3].isNotEmpty) {
              _currencyId = int.tryParse(parts[3]);
            }
            _settingsLoaded = true;
          });
        } else {
          _settingsLoaded = true;
        }
      } else {
        _settingsLoaded = true;
      }
    } catch (_) {
      _settingsLoaded = true;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('$_settingsKey${widget.businessId}');
      if (settingsJson != null) {
        // در Flutter از jsonDecode استفاده می‌کنیم
        // اما برای سادگی، از String.split استفاده می‌کنیم یا یک Map ساده
        final parts = settingsJson.split('|');
        if (parts.length >= 3) {
          setState(() {
            _calculationType = parts[0];
            _viewType = parts[1];
            _limit = int.tryParse(parts[2]) ?? 10;
            // اگر currency_id هم ذخیره شده بود، آن را بخوان
            if (parts.length >= 4 && parts[3].isNotEmpty) {
              _currencyId = int.tryParse(parts[3]);
            }
            _settingsLoaded = true;
          });
        } else {
          _settingsLoaded = true;
        }
      } else {
        _settingsLoaded = true;
      }
      
      // اگر داده موجود است، نیازی به reload نیست
      final hasData = _localData['top_selling_products'] != null;
      if (!hasData) {
        _reloadData();
      }
    } catch (_) {
      _settingsLoaded = true;
      final hasData = _localData['top_selling_products'] != null;
      if (!hasData) {
        _reloadData();
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = '$_calculationType|$_viewType|$_limit|${_currencyId ?? ''}';
      await prefs.setString('$_settingsKey${widget.businessId}', settingsJson);
    } catch (_) {}
  }

  Future<void> _reloadData() async {
    if (!_settingsLoaded) return;
    setState(() => _loading = true);
    try {
      final filters = <String, dynamic>{
        'calculation_type': _calculationType,
        'limit': _limit,
      };
      // اگر محاسبه مقداری است و ارزی انتخاب شده، آن را به فیلتر اضافه کن
      if (_calculationType == 'amount' && _currencyId != null) {
        filters['currency_id'] = _currencyId;
      }
      
      final d = await widget.service.getWidgetsBatchData(
        businessId: widget.businessId,
        widgetKeys: const ['top_selling_products'],
        filters: filters,
      );
      if (!mounted) return;
      setState(() {
        _localData['top_selling_products'] = d['top_selling_products'];
        _loading = false;
      });
      // به‌روزرسانی داده در parent
      if (widget.onDataUpdate != null) {
        widget.onDataUpdate!(_localData);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Map<String, dynamic> payload = (_localData['top_selling_products'] != null)
        ? (_localData['top_selling_products'] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(_localData['top_selling_products'] as Map)
            : const <String, dynamic>{}
        : const <String, dynamic>{};
    
    final List<Map<String, dynamic>> items = (payload['items'] is List)
        ? List<Map<String, dynamic>>.from(payload['items'])
        : const <Map<String, dynamic>>[];

    if (_loading || !_settingsLoaded || !_currenciesLoaded) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }

    Future<void> _changeCalculationType(String type) async {
      setState(() => _calculationType = type);
      // اگر به تعدادی تغییر کرد، ارز را پاک کن
      if (type == 'quantity') {
        _currencyId = null;
      } else if (type == 'amount' && _currencyId == null && _currencies.isNotEmpty) {
        // اگر به مقداری تغییر کرد و ارزی انتخاب نشده، ارز پیش‌فرض را انتخاب کن
        final defaultCurrency = _currencies.firstWhere(
          (currency) => currency['is_default'] == true,
          orElse: () => _currencies.first,
        );
        _currencyId = defaultCurrency['id'] as int?;
      }
      await _saveSettings();
      await _reloadData();
    }

    Future<void> _changeViewType(String type) async {
      setState(() => _viewType = type);
      await _saveSettings();
    }

    Future<void> _changeLimit(int limit) async {
      setState(() => _limit = limit);
      await _saveSettings();
      await _reloadData();
    }

    Future<void> _changeCurrency(int? currencyId) async {
      setState(() => _currencyId = currencyId);
      await _saveSettings();
      await _reloadData();
    }

    Widget _buildFilters() {
      final isMobile = _isMobile(context);
      final spacing = isMobile ? 6.0 : 8.0;
      final runSpacing = isMobile ? 6.0 : 8.0;
      final padding = isMobile ? 8.0 : 12.0;
      
      return Padding(
        padding: EdgeInsets.fromLTRB(padding, 8, padding, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: runSpacing,
              children: [
                // نوع محاسبه
                ChoiceChip(
                  label: Text('مقداری', style: TextStyle(fontSize: isMobile ? 12 : 14)),
                  selected: _calculationType == 'amount',
                  onSelected: (_) => _changeCalculationType('amount'),
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
                ),
                ChoiceChip(
                  label: Text('تعدادی', style: TextStyle(fontSize: isMobile ? 12 : 14)),
                  selected: _calculationType == 'quantity',
                  onSelected: (_) => _changeCalculationType('quantity'),
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
                ),
                SizedBox(width: isMobile ? 8 : 12),
                // نوع نمایش
                ChoiceChip(
                  label: Text('میله‌ای', style: TextStyle(fontSize: isMobile ? 12 : 14)),
                  selected: _viewType == 'bar',
                  onSelected: (_) => _changeViewType('bar'),
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
                ),
                ChoiceChip(
                  label: Text('دایره‌ای', style: TextStyle(fontSize: isMobile ? 12 : 14)),
                  selected: _viewType == 'pie',
                  onSelected: (_) => _changeViewType('pie'),
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
                ),
                ChoiceChip(
                  label: Text('لیست', style: TextStyle(fontSize: isMobile ? 12 : 14)),
                  selected: _viewType == 'list',
                  onSelected: (_) => _changeViewType('list'),
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
                ),
              ],
            ),
            SizedBox(height: isMobile ? 6 : 8),
            Wrap(
              spacing: isMobile ? 8 : 16,
              runSpacing: isMobile ? 6 : 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (isMobile)
                  // موبایل: Column layout
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('تعداد کالا: ', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: _limit.clamp(1, 50),
                            items: [5, 10, 15, 20, 25, 30].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                            onChanged: (v) {
                              if (v != null) _changeLimit(v);
                            },
                            style: const TextStyle(fontSize: 12),
                            isDense: true,
                          ),
                        ],
                      ),
                      // انتخاب ارز (فقط برای محاسبه مقداری)
                      if (_calculationType == 'amount' && _currenciesLoaded) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('ارز: ', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: _currencyId,
                              items: _currencies.map((currency) {
                                final id = currency['id'] as int;
                                final code = currency['code'] as String? ?? '';
                                final title = currency['title'] as String? ?? '';
                                final isDefault = currency['is_default'] == true;
                                return DropdownMenuItem<int>(
                                  value: id,
                                  child: Text(
                                    isDefault ? '$code (پیش‌فرض)' : (title.isNotEmpty ? title : code),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) {
                                _changeCurrency(v);
                              },
                              hint: const Text('انتخاب ارز', style: TextStyle(fontSize: 12)),
                              style: const TextStyle(fontSize: 12),
                              isDense: true,
                            ),
                          ],
                        ),
                      ],
                    ],
                  )
                else
                  // دسکتاپ/تبلت: Row layout
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('تعداد کالا: '),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _limit.clamp(1, 50),
                        items: [5, 10, 15, 20, 25, 30].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                        onChanged: (v) {
                          if (v != null) _changeLimit(v);
                        },
                      ),
                      // انتخاب ارز (فقط برای محاسبه مقداری)
                      if (_calculationType == 'amount' && _currenciesLoaded) ...[
                        const SizedBox(width: 16),
                        const Text('ارز: '),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _currencyId,
                          items: _currencies.map((currency) {
                            final id = currency['id'] as int;
                            final code = currency['code'] as String? ?? '';
                            final title = currency['title'] as String? ?? '';
                            final isDefault = currency['is_default'] == true;
                            return DropdownMenuItem<int>(
                              value: id,
                              child: Text(isDefault ? '$code (پیش‌فرض)' : (title.isNotEmpty ? title : code)),
                            );
                          }).toList(),
                          onChanged: (v) {
                            _changeCurrency(v);
                          },
                          hint: const Text('انتخاب ارز'),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
    }

    Widget _buildBarChart() {
      if (items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text('داده‌ای برای نمایش نیست', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        );
      }

      final bars = <BarChartGroupData>[];
      double maxY = 0;
      final List<String> labels = [];

      // رنگ اصلی نمودار با کنتراست بهتر
      final primaryColor = theme.colorScheme.primary;
      final chartColor = primaryColor.withValues(alpha: 0.85);

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final value = _calculationType == 'quantity'
            ? (item['total_quantity'] as num?)?.toDouble() ?? 0.0
            : (item['total_amount'] as num?)?.toDouble() ?? 0.0;
        
        if (value > maxY) maxY = value;
        
        labels.add(item['product_name'] ?? '${item['product_code'] ?? ''}');
        
        bars.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: value,
                width: 16,
                color: chartColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
      }

      if (maxY <= 0) maxY = 1;

      final chartHeight = _getChartHeight(context);
      final isMobile = _isMobile(context);
      
      return SizedBox(
        height: chartHeight,
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 4.0 : 8.0),
          child: BarChart(
            BarChartData(
              gridData: FlGridData(
                show: true,
                horizontalInterval: maxY / 4,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  );
                },
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: isMobile ? 40 : 50,
                    interval: maxY / 4,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        formatWithThousands(value, decimalPlaces: _calculationType == 'quantity' ? 0 : 2),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: isMobile ? 11 : 13,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: isMobile ? 50 : 60,
                          child: Text(
                            labels[idx],
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontSize: isMobile ? 11 : 13,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                    reservedSize: isMobile ? 60 : 80,
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              barGroups: bars,
              alignment: BarChartAlignment.spaceBetween,
              maxY: maxY * 1.2,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) {
                    // استفاده از رنگ پس‌زمینه سطح با کنتراست مناسب
                    return theme.colorScheme.surfaceContainerHighest;
                  },
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  tooltipMargin: 8,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final value = rod.toY;
                    return BarTooltipItem(
                      formatWithThousands(value, decimalPlaces: _calculationType == 'quantity' ? 0 : 2),
                      TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: theme.textTheme.bodyMedium?.fontSize ?? 14,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget _buildPieChart() {
      if (items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text('داده‌ای برای نمایش نیست', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        );
      }

      // پالت رنگ بهبود یافته برای نمودار دایره‌ای با کنتراست و خوانایی بهتر
      final colors = [
        theme.colorScheme.primary,
        theme.colorScheme.secondary,
        theme.colorScheme.tertiary,
        const Color(0xFF4CAF50), // سبز
        const Color(0xFF2196F3), // آبی
        const Color(0xFFFF9800), // نارنجی
        const Color(0xFF9C27B0), // بنفش
        const Color(0xFF00BCD4), // فیروزه‌ای
        const Color(0xFFE91E63), // صورتی
        const Color(0xFF3F51B5), // نیلی
        const Color(0xFFFFC107), // زرد
        const Color(0xFF795548), // قهوه‌ای
      ];

      double total = 0;
      final List<Map<String, dynamic>> chartData = [];
      
      for (final item in items) {
        final value = _calculationType == 'quantity'
            ? (item['total_quantity'] as num?)?.toDouble() ?? 0.0
            : (item['total_amount'] as num?)?.toDouble() ?? 0.0;
        total += value;
        chartData.add({
          'value': value,
          'label': item['product_name'] ?? '${item['product_code'] ?? ''}',
          'item': item,
        });
      }

      if (total <= 0) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text('داده‌ای برای نمایش نیست', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        );
      }

      final sections = <PieChartSectionData>[];
      for (int i = 0; i < chartData.length; i++) {
        final data = chartData[i];
        final percent = (data['value'] as double) / total * 100;
        final sectionColor = colors[i % colors.length];
        // تعیین رنگ متن بر اساس روشنایی رنگ پس‌زمینه
        final luminance = sectionColor.computeLuminance();
        final textColor = luminance > 0.5 ? Colors.black87 : Colors.white;
        
        sections.add(
          PieChartSectionData(
            value: data['value'] as double,
            title: percent > 5 ? '${percent.toStringAsFixed(1)}%' : '',
            color: sectionColor,
            radius: 80,
            titleStyle: theme.textTheme.labelMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        );
      }

      final chartHeight = _getChartHeight(context);
      final isMobile = _isMobile(context);
      
      if (isMobile) {
        // موبایل: Column layout (پای چارت بالا، لیست پایین)
        return SizedBox(
          height: chartHeight,
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 30,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 3,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chartData.length,
                  itemBuilder: (context, index) {
                    final data = chartData[index];
                    final value = data['value'] as double;
                    final label = data['label'] as String;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: colors[index % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.87),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            formatWithThousands(value, decimalPlaces: _calculationType == 'quantity' ? 0 : 2),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      } else {
        // دسکتاپ/تبلت: Row layout
        return SizedBox(
          height: chartHeight,
          child: Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 40,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chartData.length,
                  itemBuilder: (context, index) {
                    final data = chartData[index];
                    final value = data['value'] as double;
                    final label = data['label'] as String;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colors[index % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.87),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatWithThousands(value, decimalPlaces: _calculationType == 'quantity' ? 0 : 2),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    }

    Widget _buildList() {
      if (items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text('داده‌ای برای نمایش نیست', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        );
      }

      return ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final productName = item['product_name'] as String? ?? '';
          final productCode = item['product_code'] as String? ?? '';
          final value = _calculationType == 'quantity'
              ? (item['total_quantity'] as num?)?.toDouble() ?? 0.0
              : (item['total_amount'] as num?)?.toDouble() ?? 0.0;
          
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                '${index + 1}',
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            title: Text(productName.isNotEmpty ? productName : productCode),
            subtitle: productCode.isNotEmpty && productName != productCode ? Text(productCode) : null,
            trailing: Text(
              formatWithThousands(value, decimalPlaces: _calculationType == 'quantity' ? 0 : 2),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilters(),
        Expanded(
          child: _viewType == 'bar'
              ? _buildBarChart()
              : _viewType == 'pie'
                  ? _buildPieChart()
                  : _buildList(),
        ),
      ],
    );
  }
}

class _GridGuidesPainter extends CustomPainter {
  final int columns;
  final double unitWidth;
  final double spacing;
  final Color color;

  _GridGuidesPainter({
    required this.columns,
    required this.unitWidth,
    required this.spacing,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    double x = 0;
    for (int i = 0; i < columns; i++) {
      // رسم نوار خیلی کم‌رنگ برای هر ستون
      final rect = Rect.fromLTWH(x, 0, unitWidth, size.height <= 0 ? 2000 : size.height);
      canvas.drawRect(rect, paint);
      x += unitWidth + spacing;
    }
  }

  @override
  bool shouldRepaint(covariant _GridGuidesPainter oldDelegate) {
    return oldDelegate.columns != columns ||
        oldDelegate.unitWidth != unitWidth ||
        oldDelegate.spacing != spacing ||
        oldDelegate.color != color;
  }
}
