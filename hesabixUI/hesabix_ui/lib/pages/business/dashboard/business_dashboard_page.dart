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
import 'package:fl_chart/fl_chart.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';

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
  static const double _gridSpacingPx = 12.0;
  String _salesChartType = 'bar'; // bar | line
  String _salesChartGroup = 'day'; // day | week | month

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _fiscalController = await FiscalYearController.load();
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

  Future<void> _loadAll() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final defs = await _definitionsOrLoad();
      final bp = _currentBreakpoint(MediaQuery.of(context).size.width);
      var layout = await _service.getLayoutProfile(businessId: widget.businessId, breakpoint: bp);
      // اطمینان از حضور ویجت‌های جدید پیش‌فرض (مثل نمودار فروش) در چیدمان
      final existingKeys = layout.items.map((e) => e.key).toSet();
      final missingDefaults = defs.items.where((d) => !existingKeys.contains(d.key)).toList();
      if (missingDefaults.isNotEmpty) {
        final items = List<DashboardLayoutItem>.from(layout.items);
        int maxOrder = items.fold<int>(0, (acc, it) => it.order > acc ? it.order : acc);
        for (final d in missingDefaults) {
          final dflt = d.defaults[bp] ?? const <String, int>{};
          final colSpan = (dflt['colSpan'] ?? (layout.columns / 2).floor()).clamp(1, layout.columns);
          final rowSpan = dflt['rowSpan'] ?? 2;
          items.add(DashboardLayoutItem(key: d.key, order: ++maxOrder, colSpan: colSpan, rowSpan: rowSpan, hidden: false));
        }
        // ذخیره و جایگزینی layout
        layout = await _service.putLayoutProfile(businessId: widget.businessId, breakpoint: bp, items: items);
      }
      final keys = layout.items.where((e) => !e.hidden).map((e) => e.key).toList();
      final data = await _service.getWidgetsBatchData(
        businessId: widget.businessId,
        widgetKeys: keys,
        filters: {'group': _salesChartGroup},
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
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reloadDataOnly() async {
    try {
      final layout = _layout;
      if (layout == null) return;
      final keys = layout.items.where((e) => !e.hidden).map((e) => e.key).toList();
      final data = await _service.getWidgetsBatchData(businessId: widget.businessId, widgetKeys: keys);
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
        // ignore save errors silently for now
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

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildHeaderRow(t),
          const SizedBox(height: 16),
          if (!_editMode)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  double unit = (totalWidth - (crossAxisCount - 1) * _gridSpacingPx) / crossAxisCount;
                  const double minTileUnit = 180; // حداقل عرض یک ستون برای جلوگیری از صفر/منفی
                  if (unit <= 0) {
                    // ignore: avoid_print
                    print('[DASH][WARN] unit<=0 totalWidth=$totalWidth columns=$crossAxisCount spacing=$_gridSpacingPx');
                    unit = minTileUnit;
                  } else if (unit < minTileUnit) {
                    // ignore: avoid_print
                    print('[DASH][INFO] unit too small -> clamped to $minTileUnit (was $unit)');
                    unit = minTileUnit;
                  }
                  if (unit > 0 && _columnUnitPx != unit) {
                    _columnUnitPx = unit;
                  }
                  final children = <Widget>[];
                  for (final it in visible) {
                    final w = (unit * it.colSpan) + _gridSpacingPx * (it.colSpan - 1);
                    final cw = w > totalWidth ? totalWidth : (w < unit ? unit : w);
                    // ignore: avoid_print
                    print('[DASH] view child key=${it.key} colSpan=${it.colSpan} -> width=$w clamped=$cw unit=$unit totalWidth=$totalWidth');
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
                      spacing: _gridSpacingPx,
                      runSpacing: _gridSpacingPx,
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
                  double unit = (totalWidth - (crossAxisCount - 1) * _gridSpacingPx) / crossAxisCount;
                  const double minTileUnit = 180;
                  if (unit <= 0) {
                    // ignore: avoid_print
                    print('[DASH][WARN] unit<=0 totalWidth=$totalWidth columns=$crossAxisCount spacing=$_gridSpacingPx');
                    unit = minTileUnit;
                  } else if (unit < minTileUnit) {
                    // ignore: avoid_print
                    print('[DASH][INFO] unit too small -> clamped to $minTileUnit (was $unit)');
                    unit = minTileUnit;
                  }
                  // ذخیره آخرین اندازه واحد ستون برای رزایز اسنپی
                  if (unit > 0 && _columnUnitPx != unit) {
                    _columnUnitPx = unit;
                  }

                  final children = <Widget>[];
                  for (final it in visible) {
                    final w = (unit * it.colSpan) + _gridSpacingPx * (it.colSpan - 1);
                    final cw = w > totalWidth ? totalWidth : (w < unit ? unit : w);
                    // ignore: avoid_print
                    print('[DASH] edit child key=${it.key} colSpan=${it.colSpan} -> width=$w clamped=$cw unit=$unit totalWidth=$totalWidth');
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
                                spacing: _gridSpacingPx,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                              ),
                      child: SizedBox(height: children.isEmpty ? 0 : 1), // ارتفاع حداقلی برای render
                            ),
                          ),
                        ReorderableWrap(
                          spacing: _gridSpacingPx,
                          runSpacing: _gridSpacingPx,
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

  Widget _buildGridTile(DashboardLayoutItem item, int totalColumns) {
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
    final builder = _widgetFactory[item.key];
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
    final card = _buildCard(
      title: _titleForKey(item.key),
      trailing: trailing,
      child: builder(context, data, item, onRefresh: _reloadDataOnly),
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
    return Row(
      children: [
        Expanded(
          child: Text(
            t.businessDashboard,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        if (_editMode) ...[
          IconButton(
            tooltip: 'افزودن ویجت',
            onPressed: _showAddWidgetDialog,
            icon: const Icon(Icons.add_box_outlined),
          ),
          IconButton(
            tooltip: 'بازنشانی چیدمان',
            onPressed: _resetLayoutToDefaults,
            icon: const Icon(Icons.restore),
          ),
          if ((widget.authStore?.currentBusiness?.isOwner ?? false))
            IconButton(
              tooltip: 'انتشار چیدمان پیش‌فرض کسب‌وکار',
              onPressed: _publishBusinessDefaultLayout,
              icon: const Icon(Icons.publish),
            ),
        ],
        FutureBuilder<List<Map<String, dynamic>>>(
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timeline, size: 16),
                  const SizedBox(width: 6),
                  FiscalYearSwitcher(
                    controller: _fiscalController,
                    fiscalYears: items,
                    onChanged: _reloadDataOnly,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: _editMode ? 'خروج از ویرایش' : 'ویرایش چیدمان',
          onPressed: () => setState(() => _editMode = !_editMode),
          icon: Icon(_editMode ? Icons.check : Icons.edit),
        ),
      ],
    );
  }

  // ====== Widget Registry ======
  Map<String, DashboardWidgetBuilder> get _widgetFactory => <String, DashboardWidgetBuilder>{
        'latest_sales_invoices': _latestSalesInvoicesWidget,
        'sales_bar_chart': _salesBarChartWidget,
      };

  Widget _latestSalesInvoicesWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    return items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text('داده‌ای یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            )
          : ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final it = items[index];
                final code = '${it['code'] ?? '-'}';
                final date = DateFormatters.formatServerDateOnly(it['document_date']);
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
                    // TODO: ناوبری به صفحه فاکتور در صورت نیاز
                  },
                );
              },
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
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('این هفته'),
            selected: currentRange == 'week',
            onSelected: (_) => _reloadWith({'range': 'week'}),
          ),
          ChoiceChip(
            label: const Text('این ماه'),
            selected: currentRange == 'month',
            onSelected: (_) => _reloadWith({'range': 'month'}),
          ),
          ChoiceChip(
            label: const Text('سال مالی'),
            selected: currentRange == 'fiscal',
            onSelected: (_) => _reloadWith({'range': 'fiscal'}),
          ),
          ActionChip(
            label: const Text('بازه سفارشی'),
            onPressed: () async {
              final picked = await _pickCustomRange(context);
              if (picked != null) {
                _reloadWith({'range': 'custom', 'from': picked.$1, 'to': picked.$2});
              }
            },
          ),
          const SizedBox(width: 12),
          // Chart type
          ChoiceChip(
            label: const Text('میله‌ای'),
            selected: _salesChartType == 'bar',
            onSelected: (_) => setState(() => _salesChartType = 'bar'),
          ),
          ChoiceChip(
            label: const Text('خطی'),
            selected: _salesChartType == 'line',
            onSelected: (_) => setState(() => _salesChartType = 'line'),
          ),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('روزانه'),
            selected: _salesChartGroup == 'day',
            onSelected: (_) async {
              setState(() => _salesChartGroup = 'day');
              await _reloadWith({'range': currentRange});
            },
          ),
          ChoiceChip(
            label: const Text('هفتگی'),
            selected: _salesChartGroup == 'week',
            onSelected: (_) async {
              setState(() => _salesChartGroup = 'week');
              await _reloadWith({'range': currentRange});
            },
          ),
          ChoiceChip(
            label: const Text('ماهانه'),
            selected: _salesChartGroup == 'month',
            onSelected: (_) async {
              setState(() => _salesChartGroup = 'month');
              await _reloadWith({'range': currentRange});
            },
          ),
        ],
      );
    }

    final List<Map<String, dynamic>> grouped = items; // already grouped by server (or daily for day)
    final bars = <BarChartGroupData>[];
    final points = <FlSpot>[];
    double maxY = 0;
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
              width: 12,
              color: theme.colorScheme.primary,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _filters(),
        ),
        SizedBox(
          height: 240,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: grouped.isEmpty
                ? Center(child: Text('داده‌ای برای نمایش نیست', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                : (_salesChartType == 'bar'
                    ? BarChart(
                        BarChartData(
                          gridData: FlGridData(show: true, horizontalInterval: maxY / 4),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: maxY / 4,
                                getTitlesWidget: (value, meta) => Text(formatWithThousands(value, decimalPlaces: 0), style: theme.textTheme.labelSmall),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(_labelForIndex(value.toInt()), style: theme.textTheme.labelSmall),
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
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          gridData: FlGridData(show: true, horizontalInterval: maxY / 4),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: maxY / 4,
                                getTitlesWidget: (value, meta) => Text(formatWithThousands(value, decimalPlaces: 0), style: theme.textTheme.labelSmall),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(_labelForIndex(value.toInt()), style: theme.textTheme.labelSmall),
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
                              color: theme.colorScheme.primary,
                              barWidth: 3,
                              dotData: FlDotData(show: false),
                              spots: points,
                            ),
                          ],
                          minY: 0,
                          maxY: maxY * 1.2,
                        ),
                      )),
          ),
        ),
      ],
    );
  }

  // Pick custom date range; returns iso from/to
  Future<(String, String)?> _pickCustomRange(BuildContext context) async {
    final isJalali = widget.calendarController?.isJalali == true;
    if (isJalali) {
      try {
        final now = DateTime.now();
        final from = await showJalaliDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(now.year - 10, 1, 1),
          lastDate: DateTime(now.year + 10, 12, 31),
          helpText: 'انتخاب تاریخ شروع',
        );
        if (from == null) return null;
        final to = await showJalaliDatePicker(
          context: context,
          initialDate: from,
          firstDate: from,
          lastDate: DateTime(now.year + 10, 12, 31),
          helpText: 'انتخاب تاریخ پایان',
        );
        if (to == null) return null;
        final a = from.isBefore(to) ? from : to;
        final b = from.isBefore(to) ? to : from;
        return (_isoDate(a), _isoDate(b));
      } catch (_) {/* fallback below */}
    }
    // Gregorian fallback
    DateTime? from = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (from == null) return null;
    DateTime? to = await showDatePicker(
      context: context,
      initialDate: from,
      firstDate: from,
      lastDate: DateTime(2100),
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
                bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.08)),
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
                final filtered = rows.where((d) {
                  if (query.trim().isEmpty) return true;
                  final q = query.toLowerCase();
                  return d.title.toLowerCase().contains(q) || d.key.toLowerCase().contains(q);
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
                                        if (isHidden && existingItem != null) {
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
      final newData = await _service.getWidgetsBatchData(businessId: widget.businessId, widgetKeys: keys);
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
        final data = await _service.getWidgetsBatchData(businessId: widget.businessId, widgetKeys: keys);
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
      final data = await _service.getWidgetsBatchData(businessId: widget.businessId, widgetKeys: keys);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('چیدمان پیش‌فرض کسب‌وکار منتشر شد')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در انتشار: $e')));
    }
  }

  String _titleForKey(String key) {
    switch (key) {
      case 'latest_sales_invoices':
        return 'آخرین فاکتورهای فروش';
      case 'sales_bar_chart':
        return 'نمودار فروش';
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
    final colPixel = _columnUnitPx + _gridSpacingPx;
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
