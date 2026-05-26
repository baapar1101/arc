import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/warehouse_service.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../core/calendar_controller.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/data_table/data_table.dart';
import '../../core/api_client.dart';
import '../../utils/error_extractor.dart';
import '../../core/date_utils.dart';
import '../../widgets/jalali_date_picker.dart';
import '../../utils/responsive_helper.dart';

String _rowKey(int? productId, int? warehouseId) => '${productId ?? 0}:${warehouseId ?? 0}';

/// برچسب موجودی سیستم در انبارگردانی (فقط حواله‌های posted)
const String _kStockCountSystemQtyLabel = 'موجودی سیستم (انبار posted)';

double? _tryParseNum(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  // پشتیبانی از اعداد با جداکننده هزارگان
  final normalized = s.replaceAll(',', '').replaceAll('٬', '').replaceAll(' ', '');
  return double.tryParse(normalized);
}

class _StockCountRowVm {
  final Map<String, dynamic> raw;
  final TextEditingController physicalCtrl;
  final FocusNode physicalFocus;

  _StockCountRowVm({
    required this.raw,
    required this.physicalCtrl,
    required this.physicalFocus,
  });

  int? get productId => (raw['product_id'] as num?)?.toInt();
  int? get warehouseId => (raw['warehouse_id'] as num?)?.toInt();
  String get key => _rowKey(productId, warehouseId);
}

class StockCountPage extends StatefulWidget {
  final int businessId;
  final CalendarController? calendarController;
  
  const StockCountPage({
    super.key,
    required this.businessId,
    this.calendarController,
  });

  @override
  State<StockCountPage> createState() => _StockCountPageState();
}

class _StockCountPageState extends State<StockCountPage> {
  final _svc = WarehouseService();
  final _stockCountCodeController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();
  
  bool _loading = false;
  bool _calculating = false;
  List<_StockCountRowVm> _rows = <_StockCountRowVm>[];
  final Map<String, _StockCountRowVm> _rowVmByKey = <String, _StockCountRowVm>{};
  Map<String, Map<String, dynamic>> _calculatedByKey = <String, Map<String, dynamic>>{};
  DateTime? _asOfDate;
  int? _selectedWarehouseId;
  Map<String, dynamic>? _selectedProduct;
  Map<String, dynamic>? _summary;
  String _stockCountCode = '';
  bool _onlyDifferences = false;
  bool _onlyWithWarehouseHistory = false;

  Timer? _draftAutoSaveTimer;
  String? _lastDraftSnapshot;
  bool _draftRestorePromptDone = false;

  static const int _draftSchemaVersion = 1;

  String get _draftStorageKey => 'stock_count_draft_${widget.businessId}';

  @override
  void initState() {
    super.initState();
    _asOfDate = DateTime.now();
    _generateStockCountCode();
    _startDraftAutoSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptRestoreDraftIfNeeded();
    });
  }

  void _startDraftAutoSave() {
    _draftAutoSaveTimer?.cancel();
    _draftAutoSaveTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _loading || _calculating) return;
      if (_rows.isEmpty) return;
      await _persistDraftIfChanged();
    });
  }

  Map<String, dynamic> _buildDraftPayload() {
    final items = _rows.map((r) {
      return <String, dynamic>{
        'raw': Map<String, dynamic>.from(r.raw),
        'physical_text': r.physicalCtrl.text,
      };
    }).toList();

    final calculated = <String, dynamic>{};
    for (final e in _calculatedByKey.entries) {
      calculated[e.key] = Map<String, dynamic>.from(e.value);
    }

    return <String, dynamic>{
      'v': _draftSchemaVersion,
      'saved_at': DateTime.now().toIso8601String(),
      'as_of_date': _asOfDate?.toIso8601String(),
      'warehouse_id': _selectedWarehouseId,
      'product': _selectedProduct == null ? null : Map<String, dynamic>.from(_selectedProduct!),
      'stock_count_code': _stockCountCodeController.text,
      'notes': _notesController.text,
      'search': _searchController.text,
      'only_differences': _onlyDifferences,
      'only_with_warehouse_history': _onlyWithWarehouseHistory,
      'items': items,
      'calculated_by_key': calculated,
      'summary': _summary == null ? null : Map<String, dynamic>.from(_summary!),
    };
  }

  Future<void> _persistDraftIfChanged() async {
    try {
      final snapshot = jsonEncode(_buildDraftPayload());
      if (snapshot == _lastDraftSnapshot) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftStorageKey, snapshot);
      _lastDraftSnapshot = snapshot;
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftStorageKey);
      _lastDraftSnapshot = null;
    } catch (_) {}
  }

  Future<void> _promptRestoreDraftIfNeeded() async {
    if (_draftRestorePromptDone || !mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftStorageKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final ver = decoded['v'];
      if (ver is! int || ver != _draftSchemaVersion) return;

      final items = decoded['items'];
      if (items is! List || items.isEmpty) return;

      if (!mounted) return;
      _draftRestorePromptDone = true;

      final savedAt = decoded['saved_at'] as String?;
      final subtitle = savedAt == null
          ? 'می‌توانید همان شمارش را ادامه دهید یا از نو شروع کنید.'
          : 'آخرین ذخیرهٔ خودکار: $savedAt\nمی‌توانید همان شمارش را ادامه دهید یا از نو شروع کنید.';

      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('انبارگردانی ناتمام'),
          content: Text(subtitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('discard'),
              child: const Text('شروع جدید'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('resume'),
              child: const Text('ادامه'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (choice == 'resume') {
        await _restoreDraft(decoded);
      } else if (choice == 'discard') {
        await _clearDraft();
      }
    } catch (_) {}
  }

  Future<void> _restoreDraft(Map<String, dynamic> decoded) async {
    final itemsRaw = decoded['items'];
    if (itemsRaw is! List || itemsRaw.isEmpty) return;

    for (final r in _rows) {
      r.physicalCtrl.dispose();
      r.physicalFocus.dispose();
    }

    DateTime? asOf;
    final asStr = decoded['as_of_date'] as String?;
    if (asStr != null && asStr.isNotEmpty) {
      asOf = DateTime.tryParse(asStr) ?? DateTime.tryParse(asStr.split('T').first);
    }

    final wh = decoded['warehouse_id'];
    final prod = decoded['product'];
    Map<String, dynamic>? productMap;
    if (prod is Map) {
      productMap = Map<String, dynamic>.from(prod);
    }

    final calculatedRaw = decoded['calculated_by_key'];
    final calculated = <String, Map<String, dynamic>>{};
    if (calculatedRaw is Map) {
      for (final e in calculatedRaw.entries) {
        final k = e.key.toString();
        final v = e.value;
        if (v is Map) {
          calculated[k] = Map<String, dynamic>.from(v);
        }
      }
    }

    Map<String, dynamic>? summary;
    final s = decoded['summary'];
    if (s is Map) {
      summary = Map<String, dynamic>.from(s);
    }

    final newRows = <_StockCountRowVm>[];
    for (final entry in itemsRaw) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final rawItem = m['raw'];
      final physicalText = (m['physical_text'] ?? '').toString();
      if (rawItem is! Map) continue;
      final rawMap = Map<String, dynamic>.from(rawItem);
      final ctrl = TextEditingController(text: physicalText);
      final pid = (rawMap['product_id'] as num?)?.toInt();
      final wid = (rawMap['warehouse_id'] as num?)?.toInt();
      final focus = FocusNode(debugLabel: 'stockcount:$pid:$wid');
      newRows.add(_StockCountRowVm(raw: rawMap, physicalCtrl: ctrl, physicalFocus: focus));
    }

    if (newRows.isEmpty) return;

    if (!mounted) return;
    int? warehouseId;
    if (wh != null) {
      warehouseId = wh is int ? wh : int.tryParse(wh.toString());
    }
    setState(() {
      _asOfDate = asOf ?? _asOfDate;
      _selectedWarehouseId = warehouseId;
      _selectedProduct = productMap;
      _stockCountCodeController.text = (decoded['stock_count_code'] ?? '').toString();
      _notesController.text = (decoded['notes'] ?? '').toString();
      _searchController.text = (decoded['search'] ?? '').toString();
      _onlyDifferences = decoded['only_differences'] == true;
      _onlyWithWarehouseHistory = decoded['only_with_warehouse_history'] == true;
      _rows = newRows;
      _rowVmByKey
        ..clear()
        ..addEntries(newRows.map((r) => MapEntry(r.key, r)));
      _calculatedByKey = calculated;
      _summary = summary;
    });

    _lastDraftSnapshot = jsonEncode(_buildDraftPayload());
  }

  @override
  void dispose() {
    _draftAutoSaveTimer?.cancel();
    for (final r in _rows) {
      r.physicalCtrl.dispose();
      r.physicalFocus.dispose();
    }
    _searchController.dispose();
    _stockCountCodeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _generateStockCountCode() {
    final now = DateTime.now();
    _stockCountCode = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    _stockCountCodeController.text = _stockCountCode;
  }

  Future<void> _startStockCount() async {
    if (_asOfDate == null) {
      _showError('لطفاً تاریخ شمارش را انتخاب کنید');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await _svc.startStockCount(
        businessId: widget.businessId,
        warehouseId: _selectedWarehouseId,
        productIds: _selectedProduct != null && _selectedProduct!['id'] != null
            ? [_selectedProduct!['id'] as int]
            : null,
        asOfDate: _asOfDate!.toIso8601String().split('T')[0],
        onlyWithWarehouseHistory: _onlyWithWarehouseHistory,
      );
      
      final items = List<Map<String, dynamic>>.from(res['items'] ?? const []);

      // قبل از dispose، شمارش فیزیکیِ قبلی را با کلید همان کالا/انبار نگه می‌داریم تا با موجودی تازهٔ سیستم ادغام شود.
      final previousPhysicalByKey = <String, String>{};
      for (final r in _rows) {
        previousPhysicalByKey[r.key] = r.physicalCtrl.text;
      }

      // پاک‌سازی state قبلی
      for (final r in _rows) {
        r.physicalCtrl.dispose();
        r.physicalFocus.dispose();
      }

      final newRows = <_StockCountRowVm>[];
      for (final it in items) {
        final pid = (it['product_id'] as num?)?.toInt();
        final wid = (it['warehouse_id'] as num?)?.toInt();
        final rowKey = _rowKey(pid, wid);
        final physicalQty = (it['physical_quantity'] as num?)?.toDouble();
        final preserved = previousPhysicalByKey[rowKey];
        final initialPhysical = preserved ??
            (physicalQty?.toString() ?? '');
        final ctrl = TextEditingController(text: initialPhysical);
        final focus = FocusNode(debugLabel: 'stockcount:${it['product_id']}:${it['warehouse_id']}');
        newRows.add(_StockCountRowVm(raw: it, physicalCtrl: ctrl, physicalFocus: focus));
      }

      if (!mounted) return;
      setState(() {
        _rows = newRows;
        _rowVmByKey
          ..clear()
          ..addEntries(newRows.map((r) => MapEntry(r.key, r)));
        _calculatedByKey = <String, Map<String, dynamic>>{};
        _summary = null;
        _onlyDifferences = false;
        _searchController.text = '';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _persistDraftIfChanged();
      });
    } catch (e) {
      if (!mounted) return;
      _showError(
        'خطا در بارگذاری: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _calculateDifferences() async {
    if (_rows.isEmpty) {
      _showError('ابتدا لیست محصولات را بارگذاری کنید');
      return;
    }

    // بررسی اینکه همه موجودی‌های فیزیکی وارد شده‌اند
    final missing = _rows.where((r) => _tryParseNum(r.physicalCtrl.text) == null).toList();
    if (missing.isNotEmpty) {
      _showError('لطفاً موجودی فیزیکی همه محصولات را وارد کنید (می‌توانید از گزینه «کپی سیستم → فیزیکی» استفاده کنید)');
      return;
    }

    setState(() => _calculating = true);
    try {
      final itemsToCalculate = _rows.map((r) {
        final item = r.raw;
        final physical = _tryParseNum(r.physicalCtrl.text) ?? 0.0;
        return {
          'product_id': item['product_id'],
          'warehouse_id': item['warehouse_id'],
          'physical_quantity': physical,
        };
      }).toList();

      final res = await _svc.calculateStockCountDifferences(
        businessId: widget.businessId,
        items: itemsToCalculate,
        asOfDate: _asOfDate?.toIso8601String().split('T').first,
      );
      
      final calculatedItems = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      final map = <String, Map<String, dynamic>>{};
      for (final it in calculatedItems) {
        final pid = (it['product_id'] as num?)?.toInt();
        final wid = (it['warehouse_id'] as num?)?.toInt();
        final key = _rowKey(pid, wid);
        map[key] = it;
        final vm = _rowVmByKey[key];
        if (vm != null && it['system_quantity'] != null) {
          vm.raw['system_quantity'] = it['system_quantity'];
        }
      }
      if (!mounted) return;
      setState(() {
        _calculatedByKey = map;
        _summary = res['summary'] as Map<String, dynamic>?;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _persistDraftIfChanged();
      });
    } catch (e) {
      if (!mounted) return;
      _showError(
        'خطا در محاسبه تفاوت‌ها: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) {
        setState(() => _calculating = false);
      }
    }
  }

  Future<void> _createAdjustment() async {
    if (_calculatedByKey.isEmpty) {
      _showError('ابتدا تفاوت‌ها را محاسبه کنید');
      return;
    }

    final calculatedItems = _calculatedByKey.values.toList();
    final itemsWithDifference = calculatedItems.where((item) => item['difference'] != 0).toList();
    if (itemsWithDifference.isEmpty) {
      _showError('هیچ تفاوتی برای ایجاد حواله تعدیل وجود ندارد');
      return;
    }

    if (_stockCountCodeController.text.trim().isEmpty) {
      _showError('لطفاً کد انبار گردانی را وارد کنید');
      return;
    }

    if (_asOfDate == null) {
      _showError('لطفاً تاریخ شمارش را انتخاب کنید');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تایید ایجاد حواله تعدیل'),
        content: Text(
          'آیا از ایجاد حواله تعدیل برای ${itemsWithDifference.length} محصول با تفاوت اطمینان دارید؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تایید'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _svc.createStockCountAdjustment(
        businessId: widget.businessId,
        stockCountCode: _stockCountCodeController.text.trim(),
        stockCountDate: _asOfDate!.toIso8601String().split('T')[0],
        items: calculatedItems,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;
      
      _showSuccess('حواله تعدیل با موفقیت ایجاد شد');

      await _clearDraft();
      
      // هدایت به صفحه لیست حواله‌های انبار
      context.go('/business/${widget.businessId}/warehouse-docs');
    } catch (e) {
      if (!mounted) return;
      _showError(
        'خطا در ایجاد حواله تعدیل: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  List<_StockCountRowVm> _visibleRows() {
    final q = _searchController.text.trim();
    final lowerQ = q.toLowerCase();
    Iterable<_StockCountRowVm> base = _rows;

    if (q.isNotEmpty) {
      base = base.where((r) {
        final code = (r.raw['product_code'] ?? '').toString().toLowerCase();
        final name = (r.raw['product_name'] ?? '').toString().toLowerCase();
        final wh = (r.raw['warehouse_name'] ?? '').toString().toLowerCase();
        return code.contains(lowerQ) || name.contains(lowerQ) || wh.contains(lowerQ);
      });
    }

    if (_onlyDifferences && _calculatedByKey.isNotEmpty) {
      base = base.where((r) {
        final calc = _calculatedByKey[r.key];
        final diff = (calc?['difference'] as num?)?.toDouble() ?? 0.0;
        return diff != 0.0;
      });
    }

    return base.toList();
  }

  void _fillAllPhysicalWithSystem() {
    for (final r in _rows) {
      final systemQty = (r.raw['system_quantity'] as num?)?.toDouble();
      if (systemQty == null) continue;
      r.physicalCtrl.text = systemQty.toString();
    }
    // اگر قبلاً محاسبه شده، نتایج دیگر معتبر نیستند
    if (_calculatedByKey.isNotEmpty) {
      setState(() {
        _calculatedByKey = <String, Map<String, dynamic>>{};
        _summary = null;
      });
    }
    setState(() {}); // refresh UI
  }

  void _clearAllPhysical() {
    for (final r in _rows) {
      r.physicalCtrl.clear();
    }
    if (_calculatedByKey.isNotEmpty) {
      setState(() {
        _calculatedByKey = <String, Map<String, dynamic>>{};
        _summary = null;
      });
    }
    setState(() {});
  }

  DataTableConfig<Map<String, dynamic>> _buildDesktopTableConfig() {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_stock_count',
      tableId: 'stock_count_desktop_local',
      title: 'اقلام انبارگردانی',
      showSearch: true,
      showFilters: false,
      // همهٔ اقلام در یک اسکرول صفحه؛ بدون صفحه‌بندی محلی
      showPagination: false,
      persistPageSize: false,
      defaultPageSize: 100000,
      showColumnSearch: false,
      showExportButtons: false,
      enableSorting: false,
      enableGlobalSearch: true,
      searchFields: const ['product_code', 'product_name', 'warehouse_name'],
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      minTableWidth: ResponsiveHelper.wideFormDialogMaxWidth,
      columns: [
        TextColumn(
          'product_code',
          'کد',
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          formatter: (row) => (row as Map<String, dynamic>)['product_code']?.toString() ?? '-',
        ),
        TextColumn(
          'product_name',
          'نام محصول',
          width: ColumnWidth.large,
          sortable: false,
          searchable: false,
          formatter: (row) => (row as Map<String, dynamic>)['product_name']?.toString() ?? '-',
        ),
        TextColumn(
          'warehouse_name',
          'انبار',
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_name']?.toString() ?? '-',
        ),
        NumberColumn(
          'system_quantity',
          _kStockCountSystemQtyLabel,
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          formatter: (row) {
            final m = row as Map<String, dynamic>;
            final v = (m['system_quantity'] as num?)?.toDouble() ?? 0.0;
            return formatWithThousands(v);
          },
        ),
        CustomColumn(
          'physical_quantity',
          'موجودی فیزیکی',
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          builder: (row, index) {
            final m = row as Map<String, dynamic>;
            final pid = (m['product_id'] as num?)?.toInt();
            final wid = (m['warehouse_id'] as num?)?.toInt();
            final key = _rowKey(pid, wid);
            final vm = _rowVmByKey[key];
            final cs = Theme.of(context).colorScheme;

            if (vm == null) {
              return const SizedBox.shrink();
            }
            return SizedBox(
              width: 200,
              child: TextField(
                controller: vm.physicalCtrl,
                focusNode: vm.physicalFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\\.,٬\\s-]')),
                ],
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'کپی سیستم → فیزیکی',
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () {
                      final systemQty = (m['system_quantity'] as num?)?.toDouble();
                      if (systemQty == null) return;
                      vm.physicalCtrl.text = systemQty.toString();
                      if (_calculatedByKey.isNotEmpty) {
                        setState(() {
                          _calculatedByKey = <String, Map<String, dynamic>>{};
                          _summary = null;
                        });
                      }
                    },
                  ),
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.2),
                  filled: true,
                ),
                onChanged: (_) {
                  if (_calculatedByKey.isNotEmpty) {
                    setState(() {
                      _calculatedByKey = <String, Map<String, dynamic>>{};
                      _summary = null;
                    });
                  }
                },
              ),
            );
          },
        ),
        CustomColumn(
          'difference',
          'تفاوت',
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          builder: (row, index) {
            final m = row as Map<String, dynamic>;
            final pid = (m['product_id'] as num?)?.toInt();
            final wid = (m['warehouse_id'] as num?)?.toInt();
            final key = _rowKey(pid, wid);
            final diff = (_calculatedByKey[key]?['difference'] as num?)?.toDouble();
            Color? c;
            if (diff != null) {
              if (diff > 0) c = Colors.green;
              if (diff < 0) c = Colors.red;
            }
            return Text(
              diff == null ? '-' : formatWithThousands(diff),
              textAlign: TextAlign.center,
              style: TextStyle(color: c, fontWeight: diff != null && diff != 0 ? FontWeight.w700 : FontWeight.w400),
            );
          },
        ),
        TextColumn(
          'unit',
          'واحد',
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          formatter: (row) => (row as Map<String, dynamic>)['unit']?.toString() ?? '-',
        ),
      ],
      rowColorBuilder: (row, index) {
        final m = row as Map<String, dynamic>;
        final pid = (m['product_id'] as num?)?.toInt();
        final wid = (m['warehouse_id'] as num?)?.toInt();
        final key = _rowKey(pid, wid);
        final diff = (_calculatedByKey[key]?['difference'] as num?)?.toDouble() ?? 0.0;
        if (diff == 0) return null;
        return diff > 0 ? Colors.green.withValues(alpha: 0.05) : Colors.red.withValues(alpha: 0.05);
      },
      expandBodyHeightToFitRows: true,
    );
  }

  Widget _buildStepHeader(bool isMobile) {
    int step = 1;
    if (_rows.isNotEmpty) step = 2;
    if (_calculatedByKey.isNotEmpty) step = 3;

    Widget chip(String label, int idx) {
      final active = idx == step;
      final done = idx < step;
      final cs = Theme.of(context).colorScheme;
      return Chip(
        label: Text(label),
        avatar: done
            ? Icon(Icons.check_circle, size: 18, color: cs.primary)
            : Icon(active ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
        backgroundColor: active ? cs.primaryContainer : cs.surfaceContainerHighest,
        labelStyle: TextStyle(
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مراحل انبارگردانی', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip('۱) فیلتر و بارگذاری', 1),
                chip('۲) ثبت موجودی فیزیکی', 2),
                chip('۳) محاسبه و ایجاد حواله', 3),
              ],
            ),
            if (isMobile) const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersCard(bool isMobile) {
    final dateField = widget.calendarController != null
        ? DateInputField(
            value: _asOfDate,
            onChanged: (date) => setState(() => _asOfDate = date),
            labelText: 'تاریخ شمارش',
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            calendarController: widget.calendarController!,
            isDense: true,
          )
        : TextFormField(
            decoration: const InputDecoration(
              labelText: 'تاریخ شمارش',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            readOnly: true,
            controller: TextEditingController(
              text: _asOfDate != null
                  ? HesabixDateUtils.formatForDisplay(
                      _asOfDate,
                      widget.calendarController?.isJalali ??
                          ApiClient.getCalendarController()?.isJalali ??
                          true,
                    )
                  : '',
            ),
            onTap: () async {
              final date = await showAdaptiveDatePicker(
                context: context,
                calendarController: widget.calendarController,
                initialDate: _asOfDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                setState(() => _asOfDate = date);
              }
            },
          );

    final warehouseField = WarehouseComboboxWidget(
      businessId: widget.businessId,
      selectedWarehouseId: _selectedWarehouseId,
      onChanged: (id) => setState(() => _selectedWarehouseId = id),
      label: 'انبار (اختیاری)',
      height: 56,
    );

    final productField = ProductComboboxWidget(
      businessId: widget.businessId,
      selectedProduct: _selectedProduct,
      onChanged: (product) => setState(() => _selectedProduct = product),
      label: 'محصول (اختیاری)',
    );

    final loadButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.search),
        label: Text(_loading ? 'در حال بارگذاری...' : 'بارگذاری لیست محصولات'),
        onPressed: _loading ? null : _startStockCount,
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('فیلترها', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            FilterChip(
              label: const Text('فقط کالاهای دارای سابقه حواله در انبار'),
              selected: _onlyWithWarehouseHistory,
              onSelected: _loading
                  ? null
                  : (selected) {
                      setState(() => _onlyWithWarehouseHistory = selected);
                    },
            ),
            const SizedBox(height: 12),
            if (isMobile) ...[
              SizedBox(height: 56, child: dateField),
              const SizedBox(height: 12),
              SizedBox(height: 56, child: warehouseField),
              const SizedBox(height: 12),
              SizedBox(height: 56, child: productField),
              const SizedBox(height: 12),
              loadButton,
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: SizedBox(height: 56, child: dateField)),
                  const SizedBox(width: 16),
                  Expanded(child: warehouseField),
                  const SizedBox(width: 16),
                  Expanded(child: SizedBox(height: 56, child: Align(alignment: Alignment.centerLeft, child: productField))),
                ],
              ),
              const SizedBox(height: 12),
              loadButton,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < ResponsiveHelper.shellPersistentNavMinWidth;
    return Scaffold(
      appBar: AppBar(
        title: const Text('انبار گردانی'),
        actions: [
          if (_rows.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startStockCount,
              tooltip: 'بارگذاری مجدد از سرور ($_kStockCountSystemQtyLabel به‌روز؛ شمارش فیزیکی قبلی برای هر کالا حفظ می‌شود)',
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed(
                [
                  _buildStepHeader(isMobile),
                  const SizedBox(height: 12),
                  _buildFiltersCard(isMobile),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
          if (_rows.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('اطلاعات انبار گردانی', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _stockCountCodeController,
                          decoration: const InputDecoration(
                            labelText: 'کد انبار گردانی',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            labelText: 'یادداشت (اختیاری)',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_rows.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ListenableBuilder(
                                listenable: _searchController,
                                builder: (context, _) {
                                  return Text(
                                    'لیست محصولات (${_visibleRows().length}/${_rows.length})',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  );
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: 'کپی موجودی سیستم → فیزیکی (برای همه)',
                              onPressed: _rows.isEmpty ? null : _fillAllPhysicalWithSystem,
                              icon: const Icon(Icons.content_copy),
                            ),
                            IconButton(
                              tooltip: 'پاک کردن همه موجودی‌های فیزیکی',
                              onPressed: _rows.isEmpty ? null : _clearAllPhysical,
                              icon: const Icon(Icons.clear_all),
                            ),
                            const SizedBox(width: 8),
                            if (_calculatedByKey.isEmpty)
                              FilledButton.icon(
                                icon: const Icon(Icons.calculate),
                                label: Text(isMobile ? 'محاسبه' : 'محاسبه تفاوت‌ها'),
                                onPressed: _calculating ? null : _calculateDifferences,
                              )
                            else
                              FilledButton.icon(
                                icon: const Icon(Icons.add),
                                label: Text(isMobile ? 'ایجاد حواله' : 'ایجاد حواله تعدیل'),
                                onPressed: _loading ? null : _createAdjustment,
                              ),
                          ],
                        ),
                        if (isMobile) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  decoration: const InputDecoration(
                                    labelText: 'جستجو (کد/نام/انبار)',
                                    prefixIcon: Icon(Icons.search),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                child: ListenableBuilder(
                                  listenable: _searchController,
                                  builder: (context, _) {
                                    if (_searchController.text.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return IconButton(
                                      tooltip: 'پاک کردن جستجو',
                                      icon: const Icon(Icons.close),
                                      onPressed: () => _searchController.clear(),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilterChip(
                              label: const Text('فقط موارد اختلاف‌دار'),
                              selected: _onlyDifferences,
                              onSelected: (_calculatedByKey.isEmpty)
                                  ? null
                                  : (v) {
                                      setState(() => _onlyDifferences = v);
                                    },
                            ),
                            if (_calculatedByKey.isEmpty)
                              Text(
                                'برای فعال شدن این فیلتر ابتدا محاسبه را انجام دهید.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        if (_summary != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                _buildSummaryItem('کل', '${_summary!['total_items']}'),
                                _buildSummaryItem('با تفاوت', '${_summary!['items_with_difference']}'),
                                _buildSummaryItem('افزایش', '${_summary!['items_increased']}'),
                                _buildSummaryItem('کاهش', '${_summary!['items_decreased']}'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_rows.isNotEmpty && isMobile)
            ListenableBuilder(
              listenable: _searchController,
              builder: (context, _) {
                final visibleRows = _visibleRows();
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: visibleRows.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final row = visibleRows[index];
                      final calc = _calculatedByKey[row.key];
                      return _StockCountRowCard(
                        row: row,
                        calculated: calc,
                        onCopySystemToPhysical: () {
                          final systemQty =
                              (row.raw['system_quantity'] as num?)?.toDouble();
                          if (systemQty == null) return;
                          row.physicalCtrl.text = systemQty.toString();
                          if (_calculatedByKey.isNotEmpty) {
                            setState(() {
                              _calculatedByKey =
                                  <String, Map<String, dynamic>>{};
                              _summary = null;
                            });
                          }
                        },
                        onEditingChanged: () {
                          if (_calculatedByKey.isNotEmpty) {
                            setState(() {
                              _calculatedByKey =
                                  <String, Map<String, dynamic>>{};
                              _summary = null;
                            });
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          if (_rows.isNotEmpty && !isMobile)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverToBoxAdapter(
                child: DataTableWidget<Map<String, dynamic>>(
                  config: _buildDesktopTableConfig(),
                  fromJson: (json) => json,
                  localRawItems: _rows.map((r) => r.raw).toList(),
                  localSummary: null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _StockCountRowCard extends StatelessWidget {
  final _StockCountRowVm row;
  final Map<String, dynamic>? calculated;
  final VoidCallback onCopySystemToPhysical;
  final VoidCallback onEditingChanged;

  const _StockCountRowCard({
    required this.row,
    required this.calculated,
    required this.onCopySystemToPhysical,
    required this.onEditingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final code = row.raw['product_code']?.toString() ?? '-';
    final name = row.raw['product_name']?.toString() ?? '-';
    final wh = row.raw['warehouse_name']?.toString() ?? '-';
    final unit = row.raw['unit']?.toString() ?? '-';
    final systemQty = (row.raw['system_quantity'] as num?)?.toDouble() ?? 0.0;
    final diff = (calculated?['difference'] as num?)?.toDouble();

    Color? diffColor;
    if (diff != null) {
      if (diff > 0) diffColor = Colors.green;
      if (diff < 0) diffColor = Colors.red;
    }

    final bg = (diff == null || diff == 0)
        ? cs.surface
        : (diff > 0 ? Colors.green.withValues(alpha: 0.06) : Colors.red.withValues(alpha: 0.06));

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$code - $name',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'کپی سیستم → فیزیکی',
                  onPressed: onCopySystemToPhysical,
                  icon: const Icon(Icons.content_copy, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('انبار: $wh', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _kv(context, _kStockCountSystemQtyLabel, formatWithThousands(systemQty))),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: row.physicalCtrl,
                    focusNode: row.physicalFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,٬\s-]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'موجودی فیزیکی',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => onEditingChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _kv(context, 'واحد', unit)),
                const SizedBox(width: 12),
                Expanded(
                  child: _kv(
                    context,
                    'تفاوت',
                    diff == null ? '-' : formatWithThousands(diff),
                    valueStyle: TextStyle(color: diffColor, fontWeight: diff != null && diff != 0 ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {TextStyle? valueStyle}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(v, style: valueStyle ?? theme.textTheme.bodyMedium),
      ],
    );
  }
}


