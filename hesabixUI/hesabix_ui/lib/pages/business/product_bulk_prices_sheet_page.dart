import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../services/product_service.dart';
import '../../services/price_list_service.dart';
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

  final _searchController = TextEditingController();
  final _productService = ProductService();
  final _priceListService = PriceListService();
  final _scrollController = ScrollController();

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
  /// زمان آخرین به‌روزرسانی هر ردیف لیست قیمت (کلید: productId_priceItemId)
  final Map<String, String> _priceItemUpdatedAt = {};

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
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

  Widget _buildPriceListCell(
    BuildContext context, {
    required TextEditingController controller,
    required bool enabled,
    String? updatedAtDisplay,
  }) {
    final theme = Theme.of(context);
    final d = updatedAtDisplay?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 128,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [
                const EnglishDigitsFormatter(),
                FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d*')),
                const ThousandsSeparatorInputFormatter(),
              ],
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
            if (d != null && d.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.authStore.hasBusinessPermission('products', 'view')) {
      return Scaffold(
        appBar: AppBar(title: Text(t.bulkProductPricesSheetTitle)),
        body: Center(child: Text(t.noProductsReadAccess)),
      );
    }
    final canEdit = widget.authStore.hasBusinessPermission('products', 'edit');
    final hasMore = (_totalCount != null && _skip + _rows.length < _totalCount!) ||
        (_totalCount == null && _rows.length == _pageSize);
    final hasPrev = _skip > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.bulkProductPricesSheetTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (canEdit)
            TextButton.icon(
              onPressed: _loading ? null : _savePage,
              icon: const Icon(Icons.save_outlined),
              label: Text(t.bulkProductPricesSheetSave),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.bulkProductPricesSheetSubtitle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          hintText: t.bulkProductPricesSheetSearch,
                          prefixIcon: const Icon(Icons.search, size: 20),
                        ),
                        onSubmitted: (_) {
                          _skip = 0;
                          _loadPage();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _loading
                          ? null
                          : () {
                              _skip = 0;
                              _loadPage();
                            },
                      child: Text(t.bulkProductPricesSheetSearch),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () {
                              _searchController.clear();
                              _skip = 0;
                              _loadPage();
                            },
                      child: Text(t.bulkProductPricesSheetClearSearch),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(t.bulkProductPricesSheetPriceListsForColumns, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  t.bulkProductPricesSheetSelectListsHint,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _priceLists.map((pl) {
                    final id = _parseId(pl['id']);
                    if (id == null) return const SizedBox.shrink();
                    final name = pl['name']?.toString() ?? '—';
                    final sel = _selectedPriceListIds.contains(id);
                    return FilterChip(
                      label: Text(name, overflow: TextOverflow.ellipsis),
                      selected: sel,
                      onSelected: (v) => _togglePriceList(id, v),
                    );
                  }).toList(),
                ),
                if (_priceListsLoadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _priceListsLoadError!,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _loadPriceLists,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(t.retry),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_totalCount != null)
                      Text(
                        '${t.totalProducts}: $_totalCount',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: t.bulkProductPricesSheetPrev,
                      onPressed: !hasPrev || _loading
                          ? null
                          : () {
                              _skip = (_skip - _pageSize).clamp(0, 1 << 30);
                              _loadPage();
                            },
                      icon: const Icon(Icons.chevron_right),
                    ),
                    IconButton(
                      tooltip: t.bulkProductPricesSheetNext,
                      onPressed: !hasMore || _loading
                          ? null
                          : () {
                              _skip += _pageSize;
                              _loadPage();
                            },
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowHeight: 48,
                          dataRowMinHeight: 76,
                          dataRowMaxHeight: 120,
                          columns: [
                            DataColumn(label: Text(t.bulkProductPricesSheetCode)),
                            DataColumn(label: SizedBox(width: 200, child: Text(t.bulkProductPricesSheetName))),
                            DataColumn(label: Text(t.salesPrice)),
                            DataColumn(label: Text(t.purchasePrice)),
                            ..._columnOrder.map(
                              (piid) => DataColumn(
                                label: SizedBox(
                                  width: 128,
                                  child: Text(
                                    _columnLabels[piid] ?? '$piid',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
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
                                DataCell(Text(row['code']?.toString() ?? '')),
                                DataCell(
                                  SizedBox(
                                    width: 220,
                                    child: Text(row['name']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 140,
                                    child: TextField(
                                      controller: sc,
                                      enabled: canEdit,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        const EnglishDigitsFormatter(),
                                        FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d*')),
                                        const ThousandsSeparatorInputFormatter(),
                                      ],
                                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 140,
                                    child: TextField(
                                      controller: pc,
                                      enabled: canEdit,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        const EnglishDigitsFormatter(),
                                        FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d*')),
                                        const ThousandsSeparatorInputFormatter(),
                                      ],
                                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                    ),
                                  ),
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
        ],
      ),
    );
  }
}
