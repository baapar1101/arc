import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../services/product_service.dart';
import '../../services/price_list_service.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/person/file_picker_bridge.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/number_normalizer.dart'
    show toEnglishDigits, EnglishDigitsFormatter, ThousandsSeparatorInputFormatter;
import '../../utils/snackbar_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/api_datetime_display.dart';
import '../../widgets/business_subpage_back_leading.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';

/// ویرایش گسترده قیمت پایه و (اختیاری) قیمت‌های لیست قیمت، با صفحه‌بندی.
class ProductBulkPricesSheetPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ProductBulkPricesSheetPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<ProductBulkPricesSheetPage> createState() => _ProductBulkPricesSheetPageState();
}

class _ProductBulkPricesSheetPageState extends State<ProductBulkPricesSheetPage> {
  static const _pageSize = 40;
  static const _priceColWidth = 152.0;
  static const _codeColWidth = 100.0;
  static const _nameColMinWidth = 176.0;
  static const _headingRowHeight = 52.0;
  static const _dataRowHeight = 52.0;
  static const _tableHMargin = 10.0;

  final _searchController = TextEditingController();
  final _productService = ProductService();
  final _priceListService = PriceListService();
  final _priceListChipsScroll = ScrollController();

  int _skip = 0;
  int? _totalCount;
  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _rows = [];

  List<Map<String, dynamic>> _priceLists = [];
  String? _priceListsLoadError;
  List<int> _selectedPriceListIds = [];

  final Map<int, TextEditingController> _salesControllers = {};
  final Map<int, TextEditingController> _purchaseControllers = {};
  final Map<int, String> _initialSales = {};
  final Map<int, String> _initialPurchase = {};

  final List<int> _columnOrder = [];
  final Map<int, String> _columnLabels = {};
  final Map<String, String> _priceItemInitial = {};
  final Map<String, TextEditingController> _priceItemControllers = {};
  final Map<String, String> _priceItemUpdatedAt = {};

  @override
  void dispose() {
    _searchController.dispose();
    _priceListChipsScroll.dispose();
    _disposeRowControllers();
    _disposePriceItemControllers();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPriceLists();
    _loadPage();
  }

  Future<void> _loadPriceLists() async {
    try {
      final res = await _priceListService.listPriceLists(
        businessId: widget.businessId,
        limit: 100,
      );
      final raw = res['items'];
      if (!mounted) return;
      setState(() {
        _priceListsLoadError = null;
        _priceLists = raw is List
            ? raw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
      });
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      setState(() {
        _priceLists = [];
        _priceListsLoadError = ErrorExtractor.extractErrorMessage(e, t);
      });
    }
  }

  String _piKey(int productId, int priceItemId) => '${productId}_$priceItemId';

  String _fmtBase(dynamic v) {
    if (v == null) return '';
    num? n;
    if (v is num) {
      n = v;
    } else {
      final s = toEnglishDigits(v.toString()).replaceAll(',', '').trim();
      if (s.isEmpty) return '';
      n = num.tryParse(s);
    }
    if (n == null) return '';
    return formatWithThousands(n.toDouble(), decimalPlaces: 0);
  }

  void _disposeRowControllers() {
    for (final c in _salesControllers.values) {
      c.dispose();
    }
    for (final c in _purchaseControllers.values) {
      c.dispose();
    }
    _salesControllers.clear();
    _purchaseControllers.clear();
    _initialSales.clear();
    _initialPurchase.clear();
  }

  void _disposePriceItemControllers() {
    for (final c in _priceItemControllers.values) {
      c.dispose();
    }
    _priceItemControllers.clear();
    _priceItemInitial.clear();
    _priceItemUpdatedAt.clear();
    _columnOrder.clear();
    _columnLabels.clear();
  }

  int? _parseId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  void _ingestPriceItems(List<Map<String, dynamic>> items) {
    final tuples = <({int id, String label})>[];
    final seen = <int>{};
    for (final it in items) {
      final piid = _parseId(it['price_item_id']);
      if (piid == null || piid == 0 || seen.contains(piid)) continue;
      seen.add(piid);
      final pl = it['price_list_name']?.toString() ?? '';
      final cc = it['currency_code']?.toString() ?? '';
      final tn = it['tier_name']?.toString() ?? '';
      tuples.add((id: piid, label: '$pl · $cc · $tn'));
    }
    tuples.sort((a, b) => a.label.compareTo(b.label));
    for (final t in tuples) {
      _columnOrder.add(t.id);
      _columnLabels[t.id] = t.label;
    }
    for (final it in items) {
      final piid = _parseId(it['price_item_id']);
      final pid = _parseId(it['product_id']);
      if (piid == null || pid == null) continue;
      final key = _piKey(pid, piid);
      final s = _fmtBase(it['price']);
      _priceItemInitial[key] = s;
      _priceItemControllers[key] = TextEditingController(text: s);
      _priceItemUpdatedAt[key] = resolveApiDateTimeDisplay(Map<String, dynamic>.from(it), 'updated_at');
    }
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final body = await _productService.searchProductsRaw(
        businessId: widget.businessId,
        searchQuery: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        limit: _pageSize,
        skip: _skip,
        searchFields: const ['code', 'name'],
      );
      final rawItems = body['items'];
      final items = rawItems is List
          ? rawItems.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      final tc = body['total_count'];
      int? total;
      if (tc is int) {
        total = tc;
      } else if (tc is num) {
        total = tc.toInt();
      }

      final productIds = <int>[];
      for (final row in items) {
        final id = _parseId(row['id']);
        if (id != null) productIds.add(id);
      }

      var piItems = <Map<String, dynamic>>[];
      if (_selectedPriceListIds.isNotEmpty && productIds.isNotEmpty) {
        piItems = await _productService.fetchBulkPriceSheetItems(
          businessId: widget.businessId,
          productIds: productIds,
          priceListIds: List<int>.from(_selectedPriceListIds),
        );
      }

      if (!mounted) return;
      setState(() {
        _disposeRowControllers();
        _disposePriceItemControllers();

        _rows = items;
        _totalCount = total;

        for (final row in _rows) {
          final id = _parseId(row['id']);
          if (id == null) continue;
          final s = _fmtBase(row['base_sales_price']);
          final p = _fmtBase(row['base_purchase_price']);
          _initialSales[id] = s;
          _initialPurchase[id] = p;
          _salesControllers[id] = TextEditingController(text: s);
          _purchaseControllers[id] = TextEditingController(text: p);
        }

        _ingestPriceItems(piItems);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      setState(() {
        _loading = false;
        _loadError = ErrorExtractor.extractErrorMessage(e, t);
      });
    }
  }

  double? _parseCell(String raw) {
    final t = toEnglishDigits(raw).replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  bool _isDirtyText(String current, String initial) => current.trim() != initial.trim();

  int _dirtyCellCount() {
    var n = 0;
    for (final row in _rows) {
      final id = _parseId(row['id']);
      if (id == null) continue;
      final sc = _salesControllers[id];
      final pc = _purchaseControllers[id];
      if (sc != null && _isDirtyText(sc.text, _initialSales[id] ?? '')) n++;
      if (pc != null && _isDirtyText(pc.text, _initialPurchase[id] ?? '')) n++;
      for (final piid in _columnOrder) {
        final key = _piKey(id, piid);
        final c = _priceItemControllers[key];
        if (c != null && _isDirtyText(c.text, _priceItemInitial[key] ?? '')) n++;
      }
    }
    return n;
  }

  List<Map<String, dynamic>> _collectDirtyItems() {
    final out = <Map<String, dynamic>>[];
    for (final row in _rows) {
      final id = _parseId(row['id']);
      if (id == null) continue;
      final sc = _salesControllers[id];
      final pc = _purchaseControllers[id];
      if (sc == null || pc == null) continue;
      final curS = sc.text.trim();
      final curP = pc.text.trim();
      final iniS = _initialSales[id] ?? '';
      final iniP = _initialPurchase[id] ?? '';

      final map = <String, dynamic>{'product_id': id};
      var any = false;

      if (curS != iniS) {
        final v = _parseCell(curS);
        if (v != null) {
          map['base_sales_price'] = v;
          any = true;
        } else if (curS.isEmpty && iniS.isNotEmpty) {
          map['clear_base_sales_price'] = true;
          any = true;
        }
      }
      if (curP != iniP) {
        final v = _parseCell(curP);
        if (v != null) {
          map['base_purchase_price'] = v;
          any = true;
        } else if (curP.isEmpty && iniP.isNotEmpty) {
          map['clear_base_purchase_price'] = true;
          any = true;
        }
      }

      final updates = <Map<String, dynamic>>[];
      for (final piid in _columnOrder) {
        final key = _piKey(id, piid);
        final c = _priceItemControllers[key];
        if (c == null) continue;
        final cur = c.text.trim();
        final ini = _priceItemInitial[key] ?? '';
        if (cur != ini) {
          final v = _parseCell(cur);
          if (v != null) {
            updates.add({'price_item_id': piid, 'price': v});
            any = true;
          }
        }
      }
      if (updates.isNotEmpty) {
        map['price_item_updates'] = updates;
      }

      if (any) {
        out.add(map);
      }
    }
    return out;
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (_collectDirtyItems().isEmpty) return true;
    final t = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.bulkProductPricesSheetUnsavedTitle),
        content: Text(t.bulkProductPricesSheetUnsavedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.bulkProductPricesSheetDiscardChanges),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _runAfterDirtyCheck(VoidCallback action) async {
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    action();
  }

  Future<void> _savePage() async {
    final t = AppLocalizations.of(context);
    final items = _collectDirtyItems();
    if (items.isEmpty) {
      SnackBarHelper.show(context, message: t.bulkProductPricesSheetNoChanges);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _productService.applyBulkProductPriceSheet(
        businessId: widget.businessId,
        items: items,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: res['message']?.toString() ?? t.operationSuccessful,
      );
      await _loadPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.extractErrorMessage(e, t));
    }
  }

  Future<void> _exportExcel() async {
    final t = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      final bytes = await _productService.exportBulkPriceSheetExcel(
        businessId: widget.businessId,
        search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        searchFields: const ['code', 'name'],
        priceListIds: List<int>.from(_selectedPriceListIds),
      );
      if (!mounted) return;
      if (bytes.isEmpty) {
        SnackBarHelper.show(context, message: t.templateDownloadError);
        return;
      }
      final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final fname = 'bulk_prices_sheet_${widget.businessId}_$ts.xlsx';
      final result = await BytesExportService.export(
        bytes: bytes,
        filename: fname,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      BytesExportService.showFeedback(
        context,
        result,
        successOverride: t.operationSuccessful,
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.extractErrorMessage(e, t));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importExcel() async {
    final t = AppLocalizations.of(context);
    try {
      final picked = await FilePickerBridge.pickExcel();
      if (picked == null || picked.bytes.isEmpty) return;
      setState(() => _loading = true);
      final res = await _productService.importBulkPriceSheetExcel(
        businessId: widget.businessId,
        fileBytes: picked.bytes,
        filename: picked.name,
      );
      if (!mounted) return;
      final msg = res['message']?.toString() ?? t.operationSuccessful;
      final errs = res['errors'];
      final tail = (errs is List && errs.isNotEmpty)
          ? '\n${errs.take(8).map((e) => e.toString()).join('\n')}'
          : '';
      SnackBarHelper.showSuccess(context, message: '$msg$tail');
      await _loadPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.extractErrorMessage(e, t));
    }
  }

  void _togglePriceList(int listId, bool selected) {
    _runAfterDirtyCheck(() {
      setState(() {
        if (selected) {
          if (!_selectedPriceListIds.contains(listId)) {
            _selectedPriceListIds = [..._selectedPriceListIds, listId];
          }
        } else {
          _selectedPriceListIds = [..._selectedPriceListIds]..remove(listId);
        }
        _skip = 0;
      });
      _loadPage();
    });
  }

  List<TextInputFormatter> get _priceInputFormatters => [
        const EnglishDigitsFormatter(),
        FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d*')),
        const ThousandsSeparatorInputFormatter(),
      ];

  (String title, String subtitle) _splitColumnLabel(String label) {
    final parts = label.split(' · ').where((p) => p.trim().isNotEmpty).toList();
    if (parts.length < 2) return (label, '');
    return (parts.first, parts.sublist(1).join(' · '));
  }

  double _tableMinWidth() {
    final priceCols = 2 + _columnOrder.length;
    return _codeColWidth +
        _nameColMinWidth +
        _priceColWidth * priceCols +
        _tableHMargin * 2 +
        8;
  }

  Widget _buildSheetPriceField({
    required BuildContext context,
    required TextEditingController controller,
    required String initial,
    required bool enabled,
    String? tooltip,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dirty = _isDirtyText(controller.text, initial);
    final field = TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: _priceInputFormatters,
      textAlign: TextAlign.end,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: dirty ? FontWeight.w700 : FontWeight.w500,
        color: dirty ? cs.tertiary : null,
      ),
      onChanged: (_) {
        if (mounted) setState(() {});
      },
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: dirty ? cs.tertiaryContainer.withValues(alpha: 0.55) : cs.surface,
        hintText: '—',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: cs.outline),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: dirty ? cs.tertiary.withValues(alpha: 0.7) : cs.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.primary, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.28)),
        ),
      ),
    );
    final d = tooltip?.trim();
    if (d == null || d.isEmpty) return field;
    return Tooltip(message: d, waitDuration: const Duration(milliseconds: 400), child: field);
  }

  Widget _buildErrorBanner(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Material(
        color: cs.errorContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: cs.error, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _loadError!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
                ),
              ),
              IconButton(
                tooltip: t.retry,
                onPressed: _loading ? null : _loadPage,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.grid_on_outlined, size: 56, color: cs.outline),
              const SizedBox(height: 16),
              Text(
                t.bulkProductPricesSheetNoRows,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                t.bulkProductPricesSheetNoRowsHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _paginationSummary(AppLocalizations t) {
    final total = _totalCount;
    final from = _rows.isEmpty ? 0 : _skip + 1;
    final to = _skip + _rows.length;
    final pageNo = (_skip ~/ _pageSize) + 1;
    if (total != null) {
      return '${t.bulkProductPricesSheetPageLabel} $pageNo · $from–$to ${t.totalProducts}: $total';
    }
    return '${t.bulkProductPricesSheetPageLabel} $pageNo · $from–$to';
  }

  void _showExcelHelp(AppLocalizations t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.bulkProductPricesSheetGuideTitle),
        content: SingleChildScrollView(
          child: Text(t.bulkProductPricesSheetExcelHint, style: Theme.of(ctx).textTheme.bodyMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }

  Widget _headerLabel(BuildContext context, String title, {String? subtitle, bool numeric = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Align(
      alignment: numeric ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Column(
        crossAxisAlignment: numeric ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = ResponsiveHelper.isMobile(context);

    return Material(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 10 : 14, 10, compact ? 10 : 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: cs.surfaceContainerLowest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      hintText: t.bulkProductPricesSheetSearch,
                      prefixIcon: const Icon(Icons.search_rounded, size: 22),
                      suffixIcon: IconButton(
                        tooltip: t.bulkProductPricesSheetHelpTooltip,
                        onPressed: () => _showExcelHelp(t),
                        icon: const Icon(Icons.help_outline_rounded),
                      ),
                    ),
                    onSubmitted: (_) {
                      _runAfterDirtyCheck(() {
                        _skip = 0;
                        _loadPage();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _loading
                              ? null
                              : () {
                                  _runAfterDirtyCheck(() {
                                    _skip = 0;
                                    _loadPage();
                                  });
                                },
                          icon: const Icon(Icons.search_rounded, size: 20),
                          label: Text(t.bulkProductPricesSheetSearch),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () {
                                  _runAfterDirtyCheck(() {
                                    _searchController.clear();
                                    _skip = 0;
                                    _loadPage();
                                  });
                                },
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          label: Text(t.bulkProductPricesSheetClearSearch),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: cs.surfaceContainerLowest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        hintText: t.bulkProductPricesSheetSearch,
                        prefixIcon: const Icon(Icons.search_rounded, size: 22),
                      ),
                      onSubmitted: (_) {
                        _runAfterDirtyCheck(() {
                          _skip = 0;
                          _loadPage();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _loading
                        ? null
                        : () {
                            _runAfterDirtyCheck(() {
                              _skip = 0;
                              _loadPage();
                            });
                          },
                    icon: const Icon(Icons.search_rounded, size: 20),
                    label: Text(t.bulkProductPricesSheetSearch),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            _runAfterDirtyCheck(() {
                              _searchController.clear();
                              _skip = 0;
                              _loadPage();
                            });
                          },
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    label: Text(t.bulkProductPricesSheetClearSearch),
                  ),
                  IconButton(
                    tooltip: t.bulkProductPricesSheetHelpTooltip,
                    onPressed: () => _showExcelHelp(t),
                    icon: const Icon(Icons.help_outline_rounded),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.view_column_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.bulkProductPricesSheetPriceListsForColumns,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_priceLists.isEmpty && _priceListsLoadError == null)
              Text(
                t.bulkProductPricesSheetNoPriceLists,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              )
            else
              SizedBox(
                height: 40,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: Scrollbar(
                    controller: _priceListChipsScroll,
                    thumbVisibility: _priceLists.length > 4,
                    child: ListView.separated(
                      controller: _priceListChipsScroll,
                      scrollDirection: Axis.horizontal,
                      itemCount: _priceLists.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final pl = _priceLists[i];
                        final id = _parseId(pl['id']);
                        if (id == null) return const SizedBox.shrink();
                        final name = pl['name']?.toString() ?? '—';
                        final sel = _selectedPriceListIds.contains(id);
                        return FilterChip(
                          avatar: Icon(
                            sel ? Icons.check_circle_rounded : Icons.list_alt_rounded,
                            size: 18,
                            color: sel ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                          ),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          ),
                          selected: sel,
                          showCheckmark: false,
                          onSelected: _loading ? null : (v) => _togglePriceList(id, v),
                        );
                      },
                    ),
                  ),
                ),
              ),
            if (_priceListsLoadError != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _priceListsLoadError!,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loadPriceLists,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(t.retry),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpreadsheet(BuildContext context, AppLocalizations t, bool canEdit) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headingStyle = theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);

    if (_rows.isEmpty) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildEmptyState(context, t);
    }

    final columns = <DataColumn2>[
      DataColumn2(
        label: _headerLabel(context, t.bulkProductPricesSheetCode),
        fixedWidth: _codeColWidth,
      ),
      DataColumn2(
        label: _headerLabel(context, t.bulkProductPricesSheetName),
        size: ColumnSize.L,
        minWidth: _nameColMinWidth,
      ),
      DataColumn2(
        label: _headerLabel(context, t.salesPrice, numeric: true),
        numeric: true,
        fixedWidth: _priceColWidth,
      ),
      DataColumn2(
        label: _headerLabel(context, t.purchasePrice, numeric: true),
        numeric: true,
        fixedWidth: _priceColWidth,
      ),
      ..._columnOrder.map((piid) {
        final raw = _columnLabels[piid] ?? '$piid';
        final split = _splitColumnLabel(raw);
        return DataColumn2(
          label: Tooltip(
            message: raw,
            child: _headerLabel(context, split.$1, subtitle: split.$2, numeric: true),
          ),
          numeric: true,
          fixedWidth: _priceColWidth,
        );
      }),
    ];

    final rows = _rows.where((r) => _parseId(r['id']) != null).toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: DataTable2(
        key: ValueKey('bulk-price-grid-$_skip-${_columnOrder.length}-${rows.length}'),
        columns: columns,
        rows: [
          for (var i = 0; i < rows.length; i++)
            _buildDataRow(context, canEdit, rows[i], i),
        ],
        minWidth: _tableMinWidth(),
        isHorizontalScrollBarVisible: true,
        isVerticalScrollBarVisible: true,
        showCheckboxColumn: false,
        headingRowHeight: _headingRowHeight,
        dataRowHeight: _dataRowHeight,
        bottomMargin: 16,
        horizontalMargin: _tableHMargin,
        columnSpacing: 8,
        dividerThickness: 0.6,
        headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
        fixedColumnsColor: cs.surface,
        fixedCornerColor: cs.surfaceContainerHigh,
        fixedLeftColumns: 2,
        headingTextStyle: headingStyle,
        border: TableBorder(
          horizontalInside: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
          verticalInside: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
    );
  }

  DataRow2 _buildDataRow(
    BuildContext context,
    bool canEdit,
    Map<String, dynamic> row,
    int index,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final id = _parseId(row['id'])!;
    final sc = _salesControllers[id];
    final pc = _purchaseControllers[id];
    final zebra = index.isOdd ? cs.surfaceContainerLowest.withValues(alpha: 0.7) : null;

    if (sc == null || pc == null) {
      return DataRow2(
        color: WidgetStateProperty.all(zebra),
        cells: [
          DataCell(Text(row['code']?.toString() ?? '')),
          DataCell(Text(row['name']?.toString() ?? '')),
          const DataCell(Text('')),
          const DataCell(Text('')),
          ..._columnOrder.map((_) => const DataCell(Text(''))),
        ],
      );
    }

    return DataRow2(
      color: WidgetStateProperty.all(zebra),
      cells: [
        DataCell(
          Text(
            row['code']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(
          Text(
            row['name']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
          ),
        ),
        DataCell(
          _buildSheetPriceField(
            context: context,
            controller: sc,
            initial: _initialSales[id] ?? '',
            enabled: canEdit,
          ),
        ),
        DataCell(
          _buildSheetPriceField(
            context: context,
            controller: pc,
            initial: _initialPurchase[id] ?? '',
            enabled: canEdit,
          ),
        ),
        ..._columnOrder.map((piid) {
          final key = _piKey(id, piid);
          final c = _priceItemControllers[key];
          if (c == null) {
            return DataCell(
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text('—', style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline)),
              ),
            );
          }
          return DataCell(
            _buildSheetPriceField(
              context: context,
              controller: c,
              initial: _priceItemInitial[key] ?? '',
              enabled: canEdit,
              tooltip: _priceItemUpdatedAt[key],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFooterBar(
    BuildContext context,
    AppLocalizations t,
    bool canEdit,
    bool hasMore,
    bool hasPrev,
    int dirtyCount,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = ResponsiveHelper.isMobile(context);

    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: cs.shadow.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _paginationSummary(t),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (dirtyCount > 0 && !compact) ...[
                const SizedBox(width: 8),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.edit_outlined, size: 16, color: cs.onTertiaryContainer),
                  label: Text(t.bulkProductPricesSheetDirtyCount(dirtyCount)),
                  backgroundColor: cs.tertiaryContainer,
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide.none,
                ),
              ],
              if (canEdit) ...[
                const SizedBox(width: 8),
                if (compact)
                  IconButton.filled(
                    tooltip: dirtyCount > 0
                        ? t.bulkProductPricesSheetDirtyCount(dirtyCount)
                        : t.bulkProductPricesSheetSave,
                    onPressed: _loading ? null : _savePage,
                    icon: Badge(
                      isLabelVisible: dirtyCount > 0,
                      label: Text('$dirtyCount'),
                      child: const Icon(Icons.save_outlined, size: 20),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _loading ? null : _savePage,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(t.bulkProductPricesSheetSave),
                  ),
              ],
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: t.bulkProductPricesSheetPrev,
                onPressed: !hasPrev || _loading
                    ? null
                    : () {
                        _runAfterDirtyCheck(() {
                          _skip = (_skip - _pageSize).clamp(0, 1 << 30);
                          _loadPage();
                        });
                      },
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: t.bulkProductPricesSheetNext,
                onPressed: !hasMore || _loading
                    ? null
                    : () {
                        _runAfterDirtyCheck(() {
                          _skip += _pageSize;
                          _loadPage();
                        });
                      },
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions(AppLocalizations t, bool canEdit, bool compact) {
    if (!compact) {
      return [
        IconButton(
          tooltip: t.bulkProductPricesSheetExportExcel,
          onPressed: _loading ? null : _exportExcel,
          icon: const Icon(Icons.download_outlined),
        ),
        if (canEdit)
          IconButton(
            tooltip: t.bulkProductPricesSheetImportExcel,
            onPressed: _loading ? null : _importExcel,
            icon: const Icon(Icons.upload_outlined),
          ),
      ];
    }

    final actions = <Widget>[
      IconButton(
        tooltip: t.bulkProductPricesSheetExportExcel,
        onPressed: _loading ? null : _exportExcel,
        icon: const Icon(Icons.download_outlined),
      ),
    ];
    if (canEdit) {
      actions.add(
        PopupMenuButton<String>(
          tooltip: t.bulkProductPricesSheetMoreActions,
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            if (v == 'import') {
              _importExcel();
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'import',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(t.bulkProductPricesSheetImportExcel),
              ),
            ),
          ],
        ),
      );
    }
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!widget.authStore.hasBusinessPermission('products', 'view')) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.bulkProductPricesSheetTitle),
          leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 48, color: cs.outline),
                const SizedBox(height: 16),
                Text(t.noProductsReadAccess, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ),
      );
    }

    final canEdit = widget.authStore.hasBusinessPermission('products', 'edit');
    final hasMore = (_totalCount != null && _skip + _rows.length < _totalCount!) ||
        (_totalCount == null && _rows.length == _pageSize);
    final hasPrev = _skip > 0;
    final outerPad = ResponsiveHelper.getPadding(context);
    final compactToolbar = ResponsiveHelper.isMobile(context);
    final dirtyCount = _dirtyCellCount();

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(t.bulkProductPricesSheetTitle),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: _buildAppBarActions(t, canEdit, compactToolbar),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(outerPad, 8, outerPad, 8),
            child: _buildToolbar(context, t),
          ),
          if (_loadError != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: outerPad),
              child: _buildErrorBanner(context, t),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(outerPad, 0, outerPad, 0),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                color: cs.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading)
                      const LinearProgressIndicator(minHeight: 2),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      child: Row(
                        children: [
                          Icon(Icons.table_rows_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.bulkProductPricesSheetTableSection,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (!compactToolbar)
                            Flexible(
                              child: Text(
                                t.bulkProductPricesSheetSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: _loading,
                        child: _buildSpreadsheet(context, t, canEdit),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildFooterBar(context, t, canEdit, hasMore, hasPrev, dirtyCount),
        ],
      ),
    );
  }
}
