import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../services/product_service.dart';
import '../../services/price_list_service.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/data_table/helpers/file_saver.dart';
import '../../widgets/person/file_picker_bridge.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/number_normalizer.dart'
    show toEnglishDigits, EnglishDigitsFormatter, ThousandsSeparatorInputFormatter;
import '../../utils/snackbar_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/api_datetime_display.dart';

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
  static const _cardLayoutBreakpoint = 820.0;

  final _searchController = TextEditingController();
  final _productService = ProductService();
  final _priceListService = PriceListService();
  final _tableVScroll = ScrollController();
  final _tableHScroll = ScrollController();

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
    _tableVScroll.dispose();
    _tableHScroll.dispose();
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

  bool _useCardLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width < _cardLayoutBreakpoint;
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
      await FileSaver.saveBytes(bytes, fname);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.operationSuccessful);
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
  }

  InputDecoration _priceDecoration(BuildContext context, {String? label, String? hint}) {
    final cs = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(10);
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.38),
      labelText: label,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.35)),
      ),
    );
  }

  List<TextInputFormatter> get _priceInputFormatters => [
        const EnglishDigitsFormatter(),
        FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d*')),
        const ThousandsSeparatorInputFormatter(),
      ];

  Widget _buildPriceField({
    required BuildContext context,
    required TextEditingController controller,
    required bool enabled,
    String? label,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: _priceInputFormatters,
      decoration: _priceDecoration(context, label: label),
    );
  }

  Widget _buildPriceListCell(
    BuildContext context, {
    required TextEditingController controller,
    required bool enabled,
    String? updatedAtDisplay,
  }) {
    final theme = Theme.of(context);
    final d = updatedAtDisplay?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: 136,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: _priceInputFormatters,
              decoration: _priceDecoration(context),
            ),
            if (d != null && d.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  d,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
              Icon(Icons.inventory_2_outlined, size: 56, color: cs.outline),
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

  Widget _buildPaginationFooter(BuildContext context, AppLocalizations t, bool hasMore, bool hasPrev) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _paginationSummary(t),
              style: style,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: t.bulkProductPricesSheetPrev,
            onPressed: !hasPrev || _loading
                ? null
                : () {
                    _skip = (_skip - _pageSize).clamp(0, 1 << 30);
                    _loadPage();
                  },
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            tooltip: t.bulkProductPricesSheetNext,
            onPressed: !hasMore || _loading
                ? null
                : () {
                    _skip += _pageSize;
                    _loadPage();
                  },
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pad = ResponsiveHelper.getPadding(context);
    final narrow = _useCardLayout(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.bulkProductPricesSheetSearchSection,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.bulkProductPricesSheetSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            if (narrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surface.withValues(alpha: 0.72),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      hintText: t.bulkProductPricesSheetSearch,
                      prefixIcon: const Icon(Icons.search_rounded, size: 22),
                    ),
                    onSubmitted: (_) {
                      _skip = 0;
                      _loadPage();
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _loading
                              ? null
                              : () {
                                  _skip = 0;
                                  _loadPage();
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
                                  _searchController.clear();
                                  _skip = 0;
                                  _loadPage();
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cs.surface.withValues(alpha: 0.72),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        hintText: t.bulkProductPricesSheetSearch,
                        prefixIcon: const Icon(Icons.search_rounded, size: 22),
                      ),
                      onSubmitted: (_) {
                        _skip = 0;
                        _loadPage();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: _loading
                        ? null
                        : () {
                            _skip = 0;
                            _loadPage();
                          },
                    icon: const Icon(Icons.search_rounded, size: 20),
                    label: Text(t.bulkProductPricesSheetSearch),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            _searchController.clear();
                            _skip = 0;
                            _loadPage();
                          },
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    label: Text(t.bulkProductPricesSheetClearSearch),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            Text(
              t.bulkProductPricesSheetPriceListsForColumns,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              t.bulkProductPricesSheetSelectListsHint,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _priceLists.map((pl) {
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
                  label: Text(name, overflow: TextOverflow.ellipsis),
                  selected: sel,
                  showCheckmark: false,
                  onSelected: _loading ? null : (v) => _togglePriceList(id, v),
                );
              }).toList(),
            ),
            if (_priceListsLoadError != null) ...[
              const SizedBox(height: 12),
              Text(
                _priceListsLoadError!,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _loadPriceLists,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(t.retry),
                ),
              ),
            ],
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text(
                  t.bulkProductPricesSheetGuideTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                leading: Icon(Icons.help_outline_rounded, color: cs.primary, size: 22),
                children: [
                  Text(
                    t.bulkProductPricesSheetExcelHint,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileProductCard(
    BuildContext context,
    AppLocalizations t,
    Map<String, dynamic> row,
    bool canEdit,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final spacing = ResponsiveHelper.getGridSpacing(context);
    final id = _parseId(row['id']);
    if (id == null) return const SizedBox.shrink();
    final sc = _salesControllers[id];
    final pc = _purchaseControllers[id];
    final code = row['code']?.toString() ?? '';
    final name = row['name']?.toString() ?? '';

    return Card(
      margin: EdgeInsets.only(bottom: spacing),
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    code.isEmpty ? '—' : code,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name.isEmpty ? '—' : name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (sc != null && pc != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.salesPrice,
                          style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        _buildPriceField(context: context, controller: sc, enabled: canEdit),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.purchasePrice,
                          style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        _buildPriceField(context: context, controller: pc, enabled: canEdit),
                      ],
                    ),
                  ),
                ],
              ),
            if (_columnOrder.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                t.bulkProductPricesSheetPriceListPrices,
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              ..._columnOrder.map((piid) {
                final key = _piKey(id, piid);
                final c = _priceItemControllers[key];
                final lbl = _columnLabels[piid] ?? '$piid';
                final updated = _priceItemUpdatedAt[key];
                if (c == null) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(lbl, style: theme.textTheme.bodySmall)),
                        Text('—', style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline)),
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        lbl,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                      ),
                      const SizedBox(height: 6),
                      _buildPriceField(context: context, controller: c, enabled: canEdit),
                      if (updated != null && updated.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            updated.trim(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable(BuildContext context, AppLocalizations t, bool canEdit) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scrollbar(
      controller: _tableVScroll,
      thumbVisibility: ResponsiveHelper.isDesktop(context),
      child: SingleChildScrollView(
        controller: _tableVScroll,
        child: Scrollbar(
          controller: _tableHScroll,
          thumbVisibility: ResponsiveHelper.isDesktop(context),
          notificationPredicate: (n) => n.depth == 1,
          child: SingleChildScrollView(
            controller: _tableHScroll,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.sizeOf(context).width - ResponsiveHelper.getPadding(context) * 2,
              ),
              child: DataTableTheme(
                data: DataTableThemeData(
                  headingRowHeight: 46,
                  dataRowMinHeight: 72,
                  horizontalMargin: 18,
                  columnSpacing: 20,
                  dividerThickness: 0.6,
                  headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh.withValues(alpha: 0.85)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
                  ),
                ),
                child: DataTable(
                  clipBehavior: Clip.antiAlias,
                  columns: [
                    DataColumn(
                      label: Text(
                        t.bulkProductPricesSheetCode,
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 200,
                        child: Text(
                          t.bulkProductPricesSheetName,
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(t.salesPrice, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    DataColumn(
                      label: Text(t.purchasePrice, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    ..._columnOrder.map(
                      (piid) => DataColumn(
                        label: SizedBox(
                          width: 132,
                          child: Text(
                            _columnLabels[piid] ?? '$piid',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: _rows.where((r) => _parseId(r['id']) != null).map((row) {
                    final id = _parseId(row['id'])!;
                    final sc = _salesControllers[id];
                    final pc = _purchaseControllers[id];
                    if (sc == null || pc == null) {
                      return DataRow(
                        cells: [
                          DataCell(Text(row['code']?.toString() ?? '')),
                          DataCell(Text(row['name']?.toString() ?? '')),
                          const DataCell(Text('')),
                          const DataCell(Text('')),
                          ..._columnOrder.map((_) => const DataCell(Text(''))),
                        ],
                      );
                    }
                    return DataRow(
                      cells: [
                        DataCell(Text(row['code']?.toString() ?? '', style: theme.textTheme.bodyMedium)),
                        DataCell(
                          SizedBox(
                            width: 208,
                            child: Text(
                              row['name']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(width: 148, child: _buildPriceField(context: context, controller: sc, enabled: canEdit)),
                        ),
                        DataCell(
                          SizedBox(width: 148, child: _buildPriceField(context: context, controller: pc, enabled: canEdit)),
                        ),
                        ..._columnOrder.map((piid) {
                          final key = _piKey(id, piid);
                          final c = _priceItemControllers[key];
                          if (c == null) {
                            return const DataCell(Text('—'));
                          }
                          final updated = _priceItemUpdatedAt[key];
                          return DataCell(
                            _buildPriceListCell(
                              context,
                              controller: c,
                              enabled: canEdit,
                              updatedAtDisplay: updated,
                            ),
                          );
                        }),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
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
        if (canEdit)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 10),
            child: FilledButton.icon(
              onPressed: _loading ? null : _savePage,
              icon: const Icon(Icons.save_outlined, size: 20),
              label: Text(t.bulkProductPricesSheetSave),
            ),
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
            if (v == 'save') {
              _savePage();
            } else if (v == 'import') {
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
            PopupMenuItem(
              value: 'save',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.save_outlined),
                title: Text(t.bulkProductPricesSheetSave),
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
        appBar: AppBar(title: Text(t.bulkProductPricesSheetTitle)),
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
    final cardLayout = _useCardLayout(context);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(t.bulkProductPricesSheetTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: _buildAppBarActions(t, canEdit, compactToolbar),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                AbsorbPointer(
                  absorbing: _loading,
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(outerPad, outerPad, outerPad, 8),
                        sliver: SliverToBoxAdapter(
                          child: _buildFilterCard(context, t),
                        ),
                      ),
                      if (_loadError != null)
                        SliverToBoxAdapter(child: _buildErrorBanner(context, t)),
                      if (cardLayout && !_loading)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(outerPad, 0, outerPad, outerPad),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.grid_view_rounded, size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      t.bulkProductPricesSheetTableSection,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ..._rows.map((row) => _buildMobileProductCard(context, t, row, canEdit)),
                                if (_rows.isEmpty) SizedBox(height: MediaQuery.sizeOf(context).height * 0.15, child: _buildEmptyState(context, t)),
                                _buildPaginationFooter(context, t, hasMore, hasPrev),
                              ],
                            ),
                          ),
                        ),
                      if (!cardLayout && !_loading)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(outerPad, 0, outerPad, outerPad),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.table_rows_rounded, size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      t.bulkProductPricesSheetTableSection,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 1680),
                                    child: _rows.isEmpty ? _buildEmptyState(context, t) : _buildDesktopTable(context, t, canEdit),
                                  ),
                                ),
                                _buildPaginationFooter(context, t, hasMore, hasPrev),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_loading)
                  Positioned.fill(
                    child: Material(
                      color: cs.scrim.withValues(alpha: 0.18),
                      child: Center(
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(strokeWidth: 3),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  t.loading,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
