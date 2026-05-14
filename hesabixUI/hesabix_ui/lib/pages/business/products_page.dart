import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../widgets/product/product_list_category_filter_bar.dart';
import '../../widgets/product/category_tree_widget.dart';
import '../../services/category_service.dart';
import '../../services/list_filter_preferences_service.dart';
import '../../services/report_template_service.dart';
import '../../widgets/product/bulk_price_update_dialog.dart';
import '../../widgets/product/bulk_default_warehouse_dialog.dart';
import '../../widgets/product/product_import_dialog.dart';
import '../../widgets/product/product_unique_instances_tab.dart';
import '../../widgets/product/product_commercial_insights_tab.dart';
import '../../widgets/product/product_label_print_dialog.dart';
import '../../models/warehouse_model.dart';
import '../../widgets/attached_files/attached_files_widget.dart';
import '../../services/business_storage_service.dart';
import '../../core/api_client.dart';
import '../../config/app_config.dart';
import '../../core/auth_store.dart';
import '../../utils/number_formatters.dart';
import '../../utils/date_formatters.dart';
import '../../services/warehouse_service.dart';
import '../../services/price_list_service.dart';
import '../../utils/image_cache.dart';
import 'price_lists_page.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/general_barcode_utils.dart';
import '../../core/date_utils.dart';
import '../../widgets/jalali_date_picker.dart';

class ProductsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ProductsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _InfoTileData {
  final String label;
  final String value;
  final IconData icon;
  
  const _InfoTileData({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _ProductDetailsTabRules {
  final bool showInstancesTab;
  final bool showCommercialTab;
  final bool canReadCommercialInsights;

  const _ProductDetailsTabRules({
    required this.showInstancesTab,
    required this.showCommercialTab,
    required this.canReadCommercialInsights,
  });

  int get dialogTabCount {
    var count = showInstancesTab ? 4 : 3;
    if (showCommercialTab) {
      count++;
    }
    return count;
  }

  static _ProductDetailsTabRules resolve({
    required Map<String, dynamic> product,
    required int? parsedProductId,
    required AuthStore authStore,
  }) {
    final isUniqueProduct = product['inventory_mode']?.toString() == 'unique';
    final canReadInstances = authStore.hasBusinessPermission('inventory', 'read');
    final canReadInvoices = authStore.canReadSection('invoices');
    final hasProductId = parsedProductId != null;

    return _ProductDetailsTabRules(
      showInstancesTab: isUniqueProduct && canReadInstances && hasProductId,
      // این تب را در صورت ذخیره بودن کالا نشان می‌دهیم تا وضعیت عدم دسترسی/عدم eligibility
      // به‌صورت شفاف در خود تب نمایش داده شود.
      showCommercialTab: hasProductId,
      canReadCommercialInsights: canReadInvoices && hasProductId,
    );
  }
}

class _ProductsPageState extends State<ProductsPage> {
  static const _productModuleContext = 'products';
  final GlobalKey _tableKey = GlobalKey();
  late final BusinessStorageService _storageService;
  final ProductImageCache _imageCache = GlobalImageCache.instance;

  List<CategoryNode> _categoryTree = const [];
  bool _categoriesLoading = false;
  int? _quickCategoryFilterId;
  String _priceExportMode = 'base_plus_price_lists';
  List<int> _priceExportPriceListIds = const [];
  int? _priceExportMaxItems;

  @override
  void initState() {
    super.initState();
    _storageService = BusinessStorageService(ApiClient());
    _loadCategoryTreeForFilter();
  }

  Future<void> _loadCategoryTreeForFilter() async {
    setState(() => _categoriesLoading = true);
    Map<String, dynamic>? saved;
    try {
      saved = await ListFilterPreferencesService.load(ListFilterPageIds.products, widget.businessId);
    } catch (_) {}
    int? savedCategoryId;
    if (saved != null) {
      final raw = saved['category_id'];
      if (raw is int) {
        savedCategoryId = raw;
      } else if (raw != null) {
        savedCategoryId = int.tryParse('$raw');
      }
    }
    try {
      final svc = CategoryService(ApiClient());
      final raw = await svc.getCategoriesTree(businessId: widget.businessId);
      if (!mounted) return;
      final tree = raw.map((e) => CategoryNode.fromMap(e)).toList();
      final validSaved =
          savedCategoryId != null && findCategoryNode(tree, savedCategoryId) != null;
      setState(() {
        _categoryTree = tree;
        _categoriesLoading = false;
        if (validSaved) {
          _quickCategoryFilterId = savedCategoryId;
        }
      });
      if (validSaved) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _applyProductCategoryFilter(savedCategoryId, persist: false);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _categoriesLoading = false);
      }
    }
  }

  void _applyProductCategoryFilter(int? categoryId, {required bool persist}) {
    setState(() => _quickCategoryFilterId = categoryId);
    final ids = <int>[];
    if (categoryId != null) {
      final node = findCategoryNode(_categoryTree, categoryId);
      if (node != null) {
        ids.addAll(getAllCategoryIds(node));
      } else {
        ids.add(categoryId);
      }
    }
    try {
      (_tableKey.currentState as dynamic)?.applyCategoryIdFilter(ids);
    } catch (_) {}
    if (persist) {
      if (categoryId == null) {
        unawaited(ListFilterPreferencesService.clear(ListFilterPageIds.products, widget.businessId));
      } else {
        unawaited(ListFilterPreferencesService.save(
          ListFilterPageIds.products,
          widget.businessId,
          <String, dynamic>{'category_id': categoryId},
        ));
      }
    }
  }

  void _onQuickCategoryFilterChanged(int? categoryId) {
    _applyProductCategoryFilter(categoryId, persist: true);
  }

  Future<void> _showProductPriceReportExportDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ProductPriceReportExportDialog(
        businessId: widget.businessId,
        authStore: widget.authStore,
        tableKey: _tableKey,
        initialReportMode: _priceExportMode,
        initialPriceListIds: _priceExportPriceListIds,
        initialLimit: _priceExportMaxItems,
        onSettingsApplied: ({
          required String mode,
          required List<int> priceListIds,
          int? maxItems,
        }) {
          if (!mounted) return;
          setState(() {
            _priceExportMode = mode;
            _priceExportPriceListIds = priceListIds;
            _priceExportMaxItems = maxItems;
          });
        },
      ),
    );
  }

  String? _buildFullImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    final baseUrl = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$baseUrl${imageUrl.startsWith('/') ? imageUrl : '/$imageUrl'}';
  }
  
  String _stringValue(dynamic value, {String fallback = '-'}) {
    if (value == null) return fallback;
    if (value is String) {
      if (value.trim().isEmpty) return fallback;
      return value;
    }
    return value.toString();
  }
  
  /// پارس عدد از پاسخ API (ممکن است به‌صورت رشته از سریالایز Decimal پایدانت برسد).
  num? _parseNumForDisplay(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) {
      final t = value.trim();
      if (t.isEmpty) return null;
      return num.tryParse(t);
    }
    return num.tryParse(value.toString());
  }

  String _formatNumber(dynamic value, {int decimalPlaces = 0}) {
    final n = _parseNumForDisplay(value);
    if (n == null) return '-';
    return formatWithThousands(n, decimalPlaces: decimalPlaces);
  }

  String _formatPercent(dynamic value) {
    final n = _parseNumForDisplay(value);
    if (n == null) return '-';
    final doubleValue = n.toDouble();
    final isInt = doubleValue.truncateToDouble() == doubleValue;
    final formatted = isInt ? doubleValue.toStringAsFixed(0) : doubleValue.toStringAsFixed(2);
    return '$formatted%';
  }
  
  String _instanceStatusFa(String? s) {
    switch (s) {
      case 'available':
        return 'موجود';
      case 'sold':
        return 'فروخته‌شده';
      case 'warranty':
        return 'گارانتی';
      case 'defective':
        return 'معیوب';
      default:
        return s ?? '-';
    }
  }

  Future<void> _bulkPrintUniqueProductLabels() async {
    if (!widget.authStore.hasBusinessPermission('inventory', 'read')) {
      SnackBarHelper.showError(context, message: 'برای چاپ برچسب واحدهای یونیک، دسترسی مشاهده انبار لازم است.');
      return;
    }
    final t = AppLocalizations.of(context);
    try {
      final state = _tableKey.currentState as dynamic;
      final items = (state?.getSelectedItems() as List<dynamic>?) ?? const <dynamic>[];
      if (items.isEmpty) {
        SnackBarHelper.showError(context, message: t.noRowsSelectedError);
        return;
      }
      final uniqueRows = <Map<String, dynamic>>[];
      for (final row in items) {
        if (row is Map<String, dynamic> && row['inventory_mode']?.toString() == 'unique') {
          uniqueRows.add(row);
        }
      }
      if (uniqueRows.isEmpty) {
        SnackBarHelper.showError(context, message: 'در انتخاب شما کالای یونیکی وجود ندارد.');
        return;
      }
      if (!mounted) return;
      final ws = WarehouseService();
      final whList = await ws.listWarehouses(businessId: widget.businessId);
      final whMap = <int, String>{
        for (final Warehouse w in whList)
          if (w.id != null) w.id!: w.name,
      };
      final labels = <ProductLabelPrintItem>[];
      for (final row in uniqueRows) {
        final rawId = row['id'];
        final productId = rawId is int
            ? rawId
            : (rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? ''));
        if (productId == null) continue;
        final name = row['name']?.toString() ?? '';
        final code = row['code']?.toString() ?? '';
        final res = await ws.searchProductInstances(
          businessId: widget.businessId,
          productId: productId,
          allStatuses: true,
        );
        final instList = res['items'] as List<dynamic>? ?? const [];
        for (final e in instList) {
          final m = Map<String, dynamic>.from(e as Map);
          final widRaw = m['warehouse_id'];
          final wId = widRaw is int ? widRaw : int.tryParse(widRaw?.toString() ?? '');
          final wLine = wId != null ? 'انبار: ${whMap[wId] ?? '#$wId'}' : 'انبار: -';
          final serial = m['serial_number']?.toString() ?? '';
          final bcRaw = m['barcode']?.toString();
          labels.add(
            ProductLabelPrintItem(
              productName: name,
              productCode: code,
              serialNumber: serial,
              instanceBarcode: (bcRaw != null && bcRaw.isNotEmpty) ? bcRaw : null,
              warehouseLabel: wLine,
              status: _instanceStatusFa(m['status']?.toString()),
            ),
          );
        }
      }
      if (!mounted) return;
      if (labels.isEmpty) {
        SnackBarHelper.showError(
          context,
          message: 'برای کالاهای یونیک انتخاب‌شده، واحدی ثبت نشده است.',
        );
        return;
      }
      await ProductLabelPrintDialog.show(context, items: labels);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.error}: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _bulkPrintGeneralBarcodeLabels() async {
    final t = AppLocalizations.of(context);
    try {
      final state = _tableKey.currentState as dynamic;
      final items = (state?.getSelectedItems() as List<dynamic>?) ?? const <dynamic>[];
      if (items.isEmpty) {
        SnackBarHelper.showError(context, message: t.noRowsSelectedError);
        return;
      }
      final labels = <ProductLabelPrintItem>[];
      for (final row in items) {
        if (row is! Map<String, dynamic>) continue;
        final name = row['name']?.toString() ?? '';
        final code = row['code']?.toString() ?? '';
        final raw = row['general_barcodes']?.toString();
        final tokens = parseGeneralBarcodeTokens(raw);
        for (final tok in tokens) {
          labels.add(
            ProductLabelPrintItem(
              productName: name,
              productCode: code,
              serialNumber: '',
              instanceBarcode: tok,
            ),
          );
        }
      }
      if (!mounted) return;
      if (labels.isEmpty) {
        SnackBarHelper.showError(context, message: t.generalBarcodeLabelsNoneSelected);
        return;
      }
      await ProductLabelPrintDialog.show(
        context,
        items: labels,
        initialShowSerialLine: false,
        dialogTitle: t.generalBarcodeLabelsTitle,
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.error}: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  String _resolveDateField(Map<String, dynamic> product, String key) {
    final formattedKey = '${key}_formatted';
    final rawKey = '${key}_raw';
    
    final formatted = product[formattedKey];
    if (formatted is Map && formatted['formatted'] != null && formatted['formatted'].toString().isNotEmpty) {
      return formatted['formatted'].toString();
    }
    final base = product[key];
    if (base is String && base.isNotEmpty) return base;
    final raw = product[rawKey];
    if (raw is String && raw.isNotEmpty) return raw;
    return '-';
  }
  
  Widget _buildSectionCard(
    ThemeData theme,
    String title,
    Widget child, {
    BuildContext? layoutContext,
    List<Widget>? footer,
  }) {
    final isMobile = layoutContext != null && ResponsiveHelper.isMobile(layoutContext);
    final outer = isMobile ? 12.0 : 16.0;
    final titleSpacing = isMobile ? 8.0 : 12.0;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(outer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: titleSpacing),
            child,
            if (footer != null) ...footer,
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoGrid(ThemeData theme, List<_InfoTileData> items, BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: ResponsiveHelper.getGridMaxCrossAxisExtent(
          context,
          mobile: 168,
          tablet: 260,
          desktop: 300,
        ),
        mainAxisSpacing: isMobile ? 8 : 12,
        crossAxisSpacing: isMobile ? 8 : 12,
        childAspectRatio: isMobile ? 3.25 : 2.15,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final tilePad = isMobile ? 8.0 : 12.0;
        final iconSize = isMobile ? 16.0 : 18.0;
        final valueStyle = isMobile
            ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)
            : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
        return Container(
          padding: EdgeInsets.all(tilePad),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.icon, size: iconSize, color: theme.colorScheme.primary),
                  SizedBox(width: isMobile ? 6 : 8),
                  Expanded(
                    child: Text(
                      item.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: isMobile ? 12 : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 4 : 8),
              Text(
                item.value.isEmpty ? '-' : item.value,
                style: valueStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildHeaderChip(
    ThemeData theme, {
    required String label,
    IconData? icon,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor ?? theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
  
  Widget _buildGeneralBarcodesWrap(ThemeData theme, Map<String, dynamic> product) {
    final tokens = parseGeneralBarcodeTokens(product['general_barcodes']?.toString());
    if (tokens.isEmpty) {
      return Text('-', style: theme.textTheme.bodyMedium);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final code in tokens)
          Chip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(code, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _buildProductDialogHeader({
    required BuildContext context,
    required AppLocalizations t,
    required String title,
    required String code,
    required String serviceType,
    required String trackingLabel,
    required String barcode,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${t.code}: $code',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (serviceType.isNotEmpty && serviceType != '-')
                _buildHeaderChip(
                  theme,
                  label: '${t.category}: $serviceType',
                  icon: Icons.category_outlined,
                ),
              _buildHeaderChip(
                theme,
                label: trackingLabel,
                icon: Icons.inventory_2_outlined,
              ),
              if (barcode.isNotEmpty && barcode != '-')
                _buildHeaderChip(
                  theme,
                  label: barcode,
                  icon: Icons.qr_code,
                ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildProductOverviewTab({
    required BuildContext dialogContext,
    required Map<String, dynamic> product,
    required String? fullImageUrl,
    required String code,
    required String category,
    required String description,
    required String trackingLabel,
    required String serviceType,
    required String barcode,
    required AppLocalizations t,
  }) {
    final theme = Theme.of(dialogContext);
    final generalItems = [
      _InfoTileData(label: t.code, value: code, icon: Icons.confirmation_number_outlined),
      _InfoTileData(label: t.service, value: serviceType, icon: Icons.category_outlined),
      _InfoTileData(label: t.category, value: category, icon: Icons.layers_outlined),
      _InfoTileData(label: t.barcode, value: barcode, icon: Icons.qr_code),
      _InfoTileData(label: t.createdAt, value: _resolveDateField(product, 'created_at'), icon: Icons.calendar_today_outlined),
      _InfoTileData(label: t.updatedAt, value: _resolveDateField(product, 'updated_at'), icon: Icons.update),
    ];
    
    final pricingItems = [
      _InfoTileData(label: t.salesPrice, value: _formatNumber(product['base_sales_price']), icon: Icons.price_change),
      _InfoTileData(label: t.purchasePrice, value: _formatNumber(product['base_purchase_price']), icon: Icons.shopping_bag_outlined),
      _InfoTileData(label: t.salesTaxRate, value: _formatPercent(product['sales_tax_rate']), icon: Icons.percent),
      _InfoTileData(label: t.purchaseTaxRate, value: _formatPercent(product['purchase_tax_rate']), icon: Icons.percent_outlined),
      _InfoTileData(label: t.taxCode, value: _stringValue(product['tax_code']), icon: Icons.receipt_long),
    ];
    
    // Format default warehouse name
    String defaultWarehouseDisplay = '-';
    final warehouseName = product['default_warehouse_name'] as String?;
    final warehouseCode = product['default_warehouse_code'] as String?;
    if (warehouseName != null && warehouseName.isNotEmpty) {
      if (warehouseCode != null && warehouseCode.isNotEmpty) {
        defaultWarehouseDisplay = '$warehouseCode - $warehouseName';
      } else {
        defaultWarehouseDisplay = warehouseName;
      }
    }
    
    final inventoryItems = [
      _InfoTileData(label: t.inventoryControl, value: trackingLabel, icon: Icons.inventory_2_outlined),
      _InfoTileData(label: 'انبار پیش‌فرض', value: defaultWarehouseDisplay, icon: Icons.warehouse_outlined),
      _InfoTileData(label: t.reorderPoint, value: _formatNumber(product['reorder_point']), icon: Icons.low_priority),
      _InfoTileData(label: t.minOrderQty, value: _formatNumber(product['min_order_qty']), icon: Icons.numbers),
    ];
    
    final overviewCompact = ResponsiveHelper.isMobile(dialogContext);
    final sectionGap = overviewCompact ? 12.0 : 16.0;
    final imageGap = overviewCompact ? 12.0 : 16.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(overviewCompact ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = ResponsiveHelper.isMobile(context);
              final generalFooter = <Widget>[
                SizedBox(height: overviewCompact ? 10 : 12),
                Text(
                  t.productGeneralBarcodes,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGeneralBarcodesWrap(theme, product),
              ];
              if (isMobile) {
                // موبایل: Column layout
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fullImageUrl != null) ...[
                      _buildProductImagePreview(dialogContext, fullImageUrl, t.imageNotAvailable),
                      SizedBox(height: imageGap),
                    ],
                    _buildSectionCard(
                      theme,
                      t.generalInformation,
                      _buildInfoGrid(theme, generalItems, dialogContext),
                      layoutContext: dialogContext,
                      footer: generalFooter,
                    ),
                    SizedBox(height: sectionGap),
                    _buildSectionCard(
                      theme,
                      t.pricing,
                      _buildInfoGrid(theme, pricingItems, dialogContext),
                      layoutContext: dialogContext,
                    ),
                    SizedBox(height: sectionGap),
                    _buildSectionCard(
                      theme,
                      t.inventory,
                      _buildInfoGrid(theme, inventoryItems, dialogContext),
                      layoutContext: dialogContext,
                    ),
                  ],
                );
              }
              // دسکتاپ/تبلت: Row layout
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (fullImageUrl != null) ...[
                    _buildProductImagePreview(dialogContext, fullImageUrl, t.imageNotAvailable),
                    const SizedBox(width: 20),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionCard(
                          theme,
                          t.generalInformation,
                          _buildInfoGrid(theme, generalItems, dialogContext),
                          layoutContext: dialogContext,
                          footer: generalFooter,
                        ),
                        SizedBox(height: sectionGap),
                        _buildSectionCard(
                          theme,
                          t.pricing,
                          _buildInfoGrid(theme, pricingItems, dialogContext),
                          layoutContext: dialogContext,
                        ),
                        SizedBox(height: sectionGap),
                        _buildSectionCard(
                          theme,
                          t.inventory,
                          _buildInfoGrid(theme, inventoryItems, dialogContext),
                          layoutContext: dialogContext,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: sectionGap),
          _buildSectionCard(
            theme,
            t.description,
            Text(
              description.isEmpty ? '-' : description,
              style: theme.textTheme.bodyMedium,
            ),
            layoutContext: dialogContext,
          ),
        ],
      ),
    );
  }
  
  Widget _buildProductImagePreview(BuildContext context, String imageUrl, String fallbackLabel) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    return SizedBox(
      width: isMobile ? double.infinity : 240,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: AspectRatio(
          aspectRatio: 1,
          child: FutureBuilder<List<int>>(
            future: _loadImageWithAuth(imageUrl),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Container(
                  color: theme.colorScheme.surfaceVariant,
                  alignment: Alignment.center,
                  child: Text(fallbackLabel, textAlign: TextAlign.center),
                );
              }
              return InkWell(
                onTap: () => _showImageDialog(context, imageUrl),
                child: Image.memory(
                  Uint8List.fromList(snapshot.data!),
                  fit: BoxFit.cover,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
  
  Future<void> _attachProductFile({
    required BuildContext dialogContext,
    required Map<String, dynamic> product,
    required AttachedFilesWidgetKey refreshKey,
    required void Function(bool uploading) onUploadingChanged,
  }) async {
    final productId = product['id'];
    if (productId == null) {
      if (mounted) {
        SnackBarHelper.showError(dialogContext, message: 'برای الصاق فایل، ابتدا کالا باید ذخیره شود');
      }
      return;
    }
    
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    
    final file = result.files.first;
    if (file.bytes == null) return;
    
    onUploadingChanged(true);
    
    try {
      await _storageService.uploadFile(
        businessId: widget.businessId,
        fileBytes: file.bytes!,
        filename: file.name,
        moduleContext: _productModuleContext,
        contextId: productId.toString(),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(dialogContext, message: 'فایل با موفقیت الصاق شد');
      refreshKey.refresh();
    } on DioException catch (e) {
      if (!mounted) return;
      await _handleProductFileUploadError(dialogContext, e);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        dialogContext,
        message: 'خطا در آپلود فایل: ${ErrorExtractor.extractErrorMessage(
          e,
          AppLocalizations.of(dialogContext),
        )}',
      );
    } finally {
      onUploadingChanged(false);
    }
  }
  
  Future<void> _handleProductFileUploadError(BuildContext context, DioException e) async {
    final response = e.response;
    if (response != null && response.data is Map) {
      final data = Map<String, dynamic>.from(response.data as Map);
      final error = data['error'];
      if (error is Map && error['code'] == 'STORAGE_LIMIT_EXCEEDED') {
        await _showStorageLimitDialog(context, Map<String, dynamic>.from(error));
        return;
      }
      String message = 'خطا در آپلود فایل';
      if (data['message'] is String) {
        message = data['message'] as String;
      } else if (error is Map && error['message'] is String) {
        message = error['message'] as String;
      }
      SnackBarHelper.showError(context, message: message);
      return;
    }
    
    SnackBarHelper.showError(
      context,
      message: ErrorExtractor.extractErrorMessage(e, AppLocalizations.of(context)),
    );
  }
  
  Future<void> _showStorageLimitDialog(BuildContext context, Map<String, dynamic> error) async {
    final totalLimit = (error['total_limit_gb'] as num?)?.toDouble() ?? 0.0;
    final currentUsage = (error['current_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final available = (error['available_gb'] as num?)?.toDouble() ?? 0.0;
    final overUsage = (error['over_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final required = (error['required_gb'] as num?)?.toDouble() ?? 0.0;
    
    await showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'محدودیت ذخیره‌سازی',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error['message'] as String? ?? 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStorageInfoRow(theme, 'محدودیت کل', '${totalLimit.toStringAsFixed(3)} GB'),
                      _buildStorageInfoRow(theme, 'استفاده شده', '${currentUsage.toStringAsFixed(3)} GB'),
                      _buildStorageInfoRow(theme, 'فضای باقی‌مانده', '${available.toStringAsFixed(3)} GB'),
                      const Divider(height: 24),
                      _buildStorageInfoRow(theme, 'حجم مورد نیاز', '${required.toStringAsFixed(3)} GB', highlight: true),
                      _buildStorageInfoRow(theme, 'کمبود فضا', '${overUsage.toStringAsFixed(3)} GB', highlight: true, isError: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'برای آپلود فایل، پلن ذخیره‌سازی را ارتقا دهید یا فایل کوچکتری انتخاب کنید.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('متوجه شدم'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                ctx.go('/business/${widget.businessId}/storage-files');
              },
              icon: const Icon(Icons.storage_outlined),
              label: const Text('مدیریت ذخیره‌سازی'),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildStorageInfoRow(ThemeData theme, String label, String value, {bool highlight = false, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: isError
                  ? Colors.red
                  : highlight
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildProductStockTab({
    required BuildContext dialogContext,
    required int? productId,
    required bool trackInventory,
    required AppLocalizations t,
  }) {
    return _ProductStockTabWidget(
      businessId: widget.businessId,
      productId: productId,
      trackInventory: trackInventory,
      t: t,
    );
  }

  Future<void> _showProductDetailsDialog(Map<String, dynamic> product) async {
    final t = AppLocalizations.of(context);
    // در صورت وجود thumbnail، می‌توان از آن برای پیش‌نمایش استفاده کرد؛ در غیر این صورت تصویر اصلی
    final fullImageUrl = _buildFullImageUrl(
      (product['image_url'] ?? product['thumbnail_url']) as String?,
    );
    final attachmentsKey = AttachedFilesWidgetKey();
    bool uploadingFile = false;
    
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final theme = Theme.of(dialogContext);
            final title = _stringValue(product['name'], fallback: t.productName);
            final code = _stringValue(product['code']);
            final description = _stringValue(product['description']);
            final category = _stringValue(product['category_name']);
            final tracking = product['track_inventory'] == true ? t.yes : t.no;
            final serviceType = _stringValue(product['item_type']);
            final barcode = _stringValue(product['barcode']);
            final productId = product['id'];
            final parsedProductId = productId is int
                ? productId
                : (productId is num ? productId.toInt() : int.tryParse(productId?.toString() ?? ''));
            final tabRules = _ProductDetailsTabRules.resolve(
              product: product,
              parsedProductId: parsedProductId,
              authStore: widget.authStore,
            );

            Widget buildDocumentsTab() {
              final canUpload = widget.authStore.canWriteSection('products');
              if (productId == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'برای الصاق فایل، ابتدا کالا باید ذخیره شود.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'فایل‌ها و مستندات مرتبط با کالا',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: AttachedFilesWidget(
                        refreshKey: attachmentsKey,
                        businessId: widget.businessId,
                        moduleContext: _productModuleContext,
                        contextId: productId.toString(),
                        allowDelete: canUpload,
                      ),
                    ),
                    if (canUpload) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton.icon(
                          onPressed: uploadingFile
                              ? null
                              : () => _attachProductFile(
                                    dialogContext: dialogContext,
                                    product: product,
                                    refreshKey: attachmentsKey,
                                    onUploadingChanged: (value) {
                                      setDialogState(() => uploadingFile = value);
                                    },
                                  ),
                          icon: uploadingFile
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file),
                          label: const Text('افزودن فایل'),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }

            Widget buildCommercialNoAccessTab() {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t.productCommercialPricingNoAccessHint,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            
            final isMobileDialog = ResponsiveHelper.isMobile(dialogContext);
            return Dialog(
              insetPadding: ResponsiveHelper.getDialogPadding(dialogContext),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: DefaultTabController(
                length: tabRules.dialogTabCount,
                child: ConstrainedBox(
                  constraints: ResponsiveHelper.getDialogConstraints(dialogContext),
                  child: Column(
                    children: [
                      _buildProductDialogHeader(
                        context: dialogContext,
                        t: t,
                        title: title,
                        code: code,
                        serviceType: serviceType,
                        trackingLabel: tracking,
                        barcode: barcode,
                      ),
                      Material(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TabBar(
                              labelColor: theme.colorScheme.primary,
                              indicatorColor: theme.colorScheme.primary,
                              isScrollable: isMobileDialog,
                              tabs: [
                                Tab(
                                  icon: const Icon(Icons.info_outline),
                                  text: t.productGeneralInfo,
                                ),
                                if (tabRules.showInstancesTab)
                                  const Tab(
                                    icon: Icon(Icons.qr_code_2_outlined),
                                    text: 'سریال و بارکد',
                                  ),
                                Tab(
                                  icon: const Icon(Icons.warehouse_outlined),
                                  text: t.productStock,
                                ),
                                if (tabRules.showCommercialTab)
                                  Tab(
                                    icon: const Icon(Icons.show_chart_outlined),
                                    text: t.productCommercialPricing,
                                  ),
                                Tab(
                                  icon: const Icon(Icons.attach_file),
                                  text: t.documents,
                                ),
                              ],
                            ),
                            Divider(height: 1, color: theme.dividerColor),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildProductOverviewTab(
                              dialogContext: dialogContext,
                              product: product,
                              fullImageUrl: fullImageUrl,
                              code: code,
                              category: category,
                              description: description,
                              trackingLabel: tracking,
                              serviceType: serviceType,
                              barcode: barcode,
                              t: t,
                            ),
                            if (tabRules.showInstancesTab)
                              ProductUniqueInstancesTab(
                                businessId: widget.businessId,
                                productId: parsedProductId!,
                                product: product,
                              ),
                            _buildProductStockTab(
                              dialogContext: dialogContext,
                              productId: productId,
                              trackInventory: product['track_inventory'] == true,
                              t: t,
                            ),
                            if (tabRules.showCommercialTab)
                              tabRules.canReadCommercialInsights
                                  ? ProductCommercialInsightsTab(
                                      businessId: widget.businessId,
                                      productId: parsedProductId!,
                                    )
                                  : buildCommercialNoAccessTab(),
                            buildDocumentsTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  /// نمایش دیالوگ تصویر
  void _showImageDialog(BuildContext context, String imageUrl) {
    final isMobile = ResponsiveHelper.isMobile(context);
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(20),
        child: Stack(
          children: [
            Center(
              child: FutureBuilder<List<int>>(
                future: _loadImageWithAuth(imageUrl),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const CircularProgressIndicator(),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            'خطا در بارگذاری تصویر',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    );
                  }
                  return Container(
                    constraints: BoxConstraints(
                      maxWidth: isMobile ? double.infinity : MediaQuery.of(context).size.width * 0.9,
                      maxHeight: isMobile ? double.infinity : MediaQuery.of(context).size.height * 0.9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        Uint8List.fromList(snapshot.data!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// دانلود تصویر با استفاده از Dio (با headerهای authentication)
  Future<List<int>> _loadImageWithAuth(String url) async {
    // استفاده از cache برای جلوگیری از دانلود مجدد
    final cached = _imageCache.get(url);
    if (cached != null) {
      return cached;
    }

    try {
      // تشخیص اینکه آیا URL کامل است یا نسبی
      final isFullUrl = url.startsWith('http://') || url.startsWith('https://');
      
      // ساخت Dio instance
      final dio = Dio(BaseOptions(
        baseUrl: isFullUrl ? '' : AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), ''),
        headers: {
          'Content-Type': 'application/json',
        },
      ));
      
      // اضافه کردن interceptor برای headerهای authentication
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          // اضافه کردن headerهای authentication از AuthStore
          final apiKey = widget.authStore.apiKey;
          if (apiKey != null && apiKey.isNotEmpty) {
            options.headers['Authorization'] = 'ApiKey $apiKey';
          }
          final deviceId = widget.authStore.deviceId;
          if (deviceId.isNotEmpty) {
            options.headers['X-Device-Id'] = deviceId;
          }
          final currentBusiness = widget.authStore.currentBusiness;
          if (currentBusiness != null) {
            options.headers['X-Business-ID'] = currentBusiness.id.toString();
          }
          // اضافه کردن business_id از URL اگر موجود باشد
          final urlToCheck = isFullUrl ? url : (options.baseUrl + url);
          if (urlToCheck.contains('/business/')) {
            final match = RegExp(r'/business/(\d+)').firstMatch(urlToCheck);
            if (match != null) {
              options.headers['X-Business-ID'] = match.group(1);
            }
          }
          handler.next(options);
        },
      ));
      
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );
      final data = response.data ?? <int>[];
      final bytes = Uint8List.fromList(data);
      if (bytes.isNotEmpty) {
        _imageCache.put(url, bytes);
      }
      return bytes;
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('products')) {
      return Scaffold(
        body: Center(child: Text(t.noProductsReadAccess)),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProductListCategoryFilterBar(
            businessId: widget.businessId,
            categories: _categoryTree,
            loading: _categoriesLoading,
            selectedCategoryId: _quickCategoryFilterId,
            onCategoryChanged: _onQuickCategoryFilterChanged,
          ),
          const Divider(height: 1),
          Expanded(
            child: DataTableWidget<Map<String, dynamic>>(
              key: _tableKey,
              config: DataTableConfig<Map<String, dynamic>>(
                endpoint: '/api/v1/products/business/${widget.businessId}/search',
          title: t.products,
          excelEndpoint: '/api/v1/products/business/${widget.businessId}/price-report/export/excel',
          pdfEndpoint: '/api/v1/products/business/${widget.businessId}/price-report/export/pdf',
          showExportButtons: false,
          businessId: widget.businessId,
          reportModuleKey: 'products',
          reportSubtype: 'list',
          showBackButton: true,
          onBack: () {
            if (!mounted) return;
            if (context.canPop()) {
              context.pop();
            }
          },
          showTableIcon: false,
          showRowNumbers: true,
          enableRowSelection: true,
          enableMultiRowSelection: true,
          columns: [
            CustomColumn(
              'image',
              'عکس',
              width: ColumnWidth.small,
              sortable: false,
              searchable: false,
              builder: (item, index) {
                // در لیست، در صورت وجود thumbnail از آن استفاده می‌کنیم؛ در غیر این صورت از تصویر اصلی
                final rawUrl = (item['thumbnail_url'] ?? item['image_url']) as String?;
                final fullUrl = _buildFullImageUrl(rawUrl);
                if (fullUrl == null) {
                  return const Center(child: SizedBox.shrink());
                }
                // استفاده از Builder برای دسترسی به context
                return Builder(
                  builder: (builderContext) {
                    // استفاده از FutureBuilder برای دانلود تصویر با Dio (با headerهای authentication)
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: GestureDetector(
                          onTap: () => _showImageDialog(builderContext, fullUrl),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: FutureBuilder<List<int>>(
                              future: _loadImageWithAuth(fullUrl),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  );
                                }
                                if (snapshot.hasError || !snapshot.hasData) {
                                  return const SizedBox.shrink();
                                }
                                return Image.memory(
                                  Uint8List.fromList(snapshot.data!),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            TextColumn('code', t.code, width: ColumnWidth.small),
            TextColumn('name', t.title, width: ColumnWidth.large),
            TextColumn(
              'category_name',
              t.category,
              width: ColumnWidth.medium,
              filterType: ColumnFilterType.categoryTree,
            ),
            TextColumn('item_type', t.service, width: ColumnWidth.small),
            TextColumn(
              'general_barcodes',
              t.productGeneralBarcodes,
              width: ColumnWidth.medium,
              formatter: (row) {
                final tokens = parseGeneralBarcodeTokens(row['general_barcodes']?.toString());
                if (tokens.isEmpty) return '-';
                return tokens.join('، ');
              },
            ),
            NumberColumn(
              'base_sales_price',
              t.salesPrice,
              width: ColumnWidth.medium,
              decimalPlaces: 0,
              formatter: (row) => formatWithThousands(row['base_sales_price'], decimalPlaces: 0),
            ),
            NumberColumn(
              'base_purchase_price',
              t.purchasePrice,
              width: ColumnWidth.medium,
              decimalPlaces: 0,
              formatter: (row) => formatWithThousands(row['base_purchase_price'], decimalPlaces: 0),
            ),
            // Inventory
            TextColumn(
              'track_inventory',
              t.inventoryControl,
              width: ColumnWidth.small,
              formatter: (row) => (row['track_inventory'] == true) ? t.yes : t.no,
            ),
            TextColumn(
              'default_warehouse_name',
              'انبار پیش‌فرض',
              width: ColumnWidth.medium,
              formatter: (row) {
                final warehouseName = row['default_warehouse_name'] as String?;
                final warehouseCode = row['default_warehouse_code'] as String?;
                if (warehouseName == null || warehouseName.isEmpty) {
                  return '-';
                }
                if (warehouseCode != null && warehouseCode.isNotEmpty) {
                  return '$warehouseCode - $warehouseName';
                }
                return warehouseName;
              },
            ),
            // موجودی انبارداری (فیزیکی)
            NumberColumn(
              'inventory_stock_warehouse',
              'موجودی انبارداری',
              width: ColumnWidth.medium,
              decimalPlaces: 0,
              sortable: false,
              formatter: (row) {
                if (row['track_inventory'] != true) {
                  return '-';
                }
                // پشتیبانی از نام‌های قدیمی برای سازگاری
                final stock = row['inventory_stock_warehouse'] ?? row['inventory_stock_physical'];
                // اگر null است و track_inventory true است، یعنی موجودی محاسبه نشده (مثلاً خطا) - "-" نمایش بده
                // اگر 0 است، "0" نمایش بده
                if (stock == null) {
                  return '-';
                }
                // تبدیل به عدد برای اطمینان از نمایش صحیح
                final stockNum = (stock is num) ? stock : (double.tryParse(stock.toString()) ?? 0.0);
                return formatWithThousands(stockNum, decimalPlaces: 0);
              },
            ),
            // موجودی حسابداری (مالی)
            NumberColumn(
              'inventory_stock_accounting',
              'موجودی حسابداری',
              width: ColumnWidth.medium,
              decimalPlaces: 0,
              sortable: false,
              formatter: (row) {
                if (row['track_inventory'] != true) {
                  return '-';
                }
                // پشتیبانی از نام‌های قدیمی برای سازگاری
                final stock = row['inventory_stock_accounting'] ?? row['inventory_stock_financial'];
                // اگر null است و track_inventory true است، یعنی موجودی محاسبه نشده (مثلاً خطا) - "-" نمایش بده
                // اگر 0 است، "0" نمایش بده
                if (stock == null) {
                  return '-';
                }
                // تبدیل به عدد برای اطمینان از نمایش صحیح
                final stockNum = (stock is num) ? stock : (double.tryParse(stock.toString()) ?? 0.0);
                return formatWithThousands(stockNum, decimalPlaces: 0);
              },
            ),
            // شارژ انبار
            CustomColumn(
              'warehouse_recharge',
              'نیاز به شارژ انبار',
              width: ColumnWidth.small,
              sortable: false,
              searchable: false,
              builder: (item, index) {
                final trackInventory = item['track_inventory'] == true;
                if (!trackInventory) {
                  return const Center(child: Text('-'));
                }
                
                // استفاده از موجودی حسابداری (با پشتیبانی از نام قدیمی)
                final stockFinancial = item['inventory_stock_accounting'] ?? item['inventory_stock_financial'];
                final reorderPoint = item['reorder_point'];
                
                // اگر موجودی حسابداری یا نقطه سفارش مجدد null باشد، ضربدر نمایش بده
                if (stockFinancial == null || reorderPoint == null) {
                  return const Center(
                    child: Icon(
                      Icons.close,
                      color: Colors.red,
                      size: 20,
                    ),
                  );
                }
                
                final stock = (stockFinancial is num) ? stockFinancial.toDouble() : 0.0;
                final reorder = (reorderPoint is num) ? reorderPoint.toDouble() : 0.0;
                
                // اگر موجودی حسابداری کمتر از نقطه سفارش مجدد باشد، تیک بزن
                if (stock < reorder) {
                  return const Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                  );
                } else {
                  return const Center(
                    child: Icon(
                      Icons.close,
                      color: Colors.red,
                      size: 20,
                    ),
                  );
                }
              },
            ),
            NumberColumn('reorder_point', t.reorderPoint, width: ColumnWidth.small, decimalPlaces: 0),
            NumberColumn('min_order_qty', t.minOrderQty, width: ColumnWidth.small, decimalPlaces: 0),
            // Taxes
            NumberColumn('sales_tax_rate', t.salesTaxRate, width: ColumnWidth.small, decimalPlaces: 2),
            NumberColumn('purchase_tax_rate', t.purchaseTaxRate, width: ColumnWidth.small, decimalPlaces: 2),
            TextColumn('tax_code', t.taxCode, width: ColumnWidth.small),
            // Show human-friendly date; keep sorting by actual `created_at`
            TextColumn(
              'created_at',
              t.createdAt,
              width: ColumnWidth.medium,
              formatter: (row) {
                // First try to get date_only from formatted object
                final dynamic caf = row['created_at_formatted'];
                if (caf is Map) {
                  final dateOnly = caf['date_only'];
                  if (dateOnly != null && dateOnly.toString().isNotEmpty) {
                    return dateOnly.toString();
                  }
                }
                // Fallback to other fields using DateFormatters
                if (caf != null) {
                  return DateFormatters.formatServerDateOnly(caf);
                }
                final dynamic ca = row['created_at'];
                if (ca != null) {
                  return DateFormatters.formatServerDateOnly(ca);
                }
                final dynamic car = row['created_at_raw'];
                if (car != null) {
                  return DateFormatters.formatServerDateOnly(car);
                }
                return '-';
              },
            ),
            // Last update, display pretty while disabling unsupported server-side sorting
            TextColumn(
              'updated_at',
              t.updatedAt,
              width: ColumnWidth.medium,
              sortable: false,
              formatter: (row) {
                // First try to get date_only from formatted object
                final dynamic uaf = row['updated_at_formatted'];
                if (uaf is Map) {
                  final dateOnly = uaf['date_only'];
                  if (dateOnly != null && dateOnly.toString().isNotEmpty) {
                    return dateOnly.toString();
                  }
                }
                // Fallback to other fields using DateFormatters
                if (uaf != null) {
                  return DateFormatters.formatServerDateOnly(uaf);
                }
                final dynamic ua = row['updated_at'];
                if (ua != null) {
                  return DateFormatters.formatServerDateOnly(ua);
                }
                final dynamic uar = row['updated_at_raw'];
                if (uar != null) {
                  return DateFormatters.formatServerDateOnly(uar);
                }
                return '-';
              },
            ),
            ActionColumn('actions', t.actions, actions: [
              DataTableAction(
                icon: Icons.edit,
                label: t.edit,
                onTap: (row) async {
                  await showDialog<Object?>(
                    context: context,
                    builder: (ctx) => ProductFormDialog(
                      businessId: widget.businessId,
                      authStore: widget.authStore,
                      product: row,
                      onSuccess: () {
                        try {
                          ( _tableKey.currentState as dynamic)?.refresh();
                        } catch (_) {}
                      },
                    ),
                  );
                },
              ),
              if (widget.authStore.canWriteSection('products'))
                DataTableAction(
                  icon: Icons.copy_outlined,
                  label: t.duplicateProduct,
                  onTap: (row) async {
                    final rawId = row['id'];
                    final productId = rawId is int
                        ? rawId
                        : (rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? ''));
                    if (productId == null) {
                      if (!context.mounted) return;
                      SnackBarHelper.showError(
                        context,
                        message: '${AppLocalizations.of(context).error}: شناسه کالا نامعتبر است',
                      );
                      return;
                    }
                    await showDialog<Object?>(
                      context: context,
                      builder: (ctx) => ProductFormDialog(
                        businessId: widget.businessId,
                        authStore: widget.authStore,
                        cloneSourceProductId: productId,
                        onSuccess: () {
                          try {
                            (_tableKey.currentState as dynamic)?.refresh();
                          } catch (_) {}
                        },
                      ),
                    );
                  },
                ),
              DataTableAction(
                icon: Icons.delete_outline,
                label: AppLocalizations.of(context).delete,
                isDestructive: true,
                onTap: (row) async {
                  final t = AppLocalizations.of(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t.deleteProducts),
                      content: Text(t.deleteConfirm('"${row['name'] ?? row['code'] ?? '#'}"')),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
                        FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.delete)),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  final rawId = row['id'];
                  final productId = rawId is int
                      ? rawId
                      : (rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? ''));
                  if (productId == null) {
                    if (!context.mounted) return;
                    SnackBarHelper.showError(context, message: '${t.error}: شناسه کالا نامعتبر است');
                    return;
                  }
                  try {
                    final api = ApiClient();
                    await api.delete<Map<String, dynamic>>(
                      '/products/business/${widget.businessId}/$productId',
                    );
                    if (!context.mounted) return;
                    SnackBarHelper.show(context, message: t.productDeletedSuccessfully);
                    try { ( _tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
                  } catch (e) {
                    if (!context.mounted) return;
                    SnackBarHelper.showError(
                      context,
                      message: ErrorExtractor.extractErrorMessage(e, t),
                    );
                  }
                },
              ),
            ]),
          ],
          searchFields: const ['code', 'name', 'description', 'general_barcodes'],
          filterFields: const ['item_type', 'category_id'],
          defaultPageSize: 20,
          customHeaderActions: [
            if (widget.authStore.canDeleteSection('products'))
              Tooltip(
                message: AppLocalizations.of(context).deleteProducts,
                child: IconButton(
                  onPressed: () async {
                    final t = AppLocalizations.of(context);
                    // Collect selected row IDs via DataTableWidget public API
                    try {
                      // Access current table state to read selected rows and items
                      final state = _tableKey.currentState as dynamic;
                      final items = (state?.getSelectedItems() as List<dynamic>?) ?? const <dynamic>[];
                      if (items.isEmpty) {
                        SnackBarHelper.showError(context, message: t.noRowsSelectedError);
                        return;
                      }
                      final ids = <int>[];
                      for (final row in items) {
                        if (row is Map<String, dynamic>) {
                          final rawId = row['id'];
                          final id = rawId is int
                              ? rawId
                              : (rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? ''));
                          if (id != null) ids.add(id);
                        }
                      }
                      if (ids.isEmpty) return;
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(t.deleteProducts),
                          content: Text(t.deleteConfirm('${ids.length}')),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
                            FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.delete)),
                          ],
                        ),
                      );
                      if (confirm != true) return;

                      final api = ApiClient();
                      await api.post<Map<String, dynamic>>(
                        '/products/business/${widget.businessId}/bulk-delete',
                        data: { 'ids': ids },
                      );
                      try { ( _tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
                      if (!context.mounted) return;
                      SnackBarHelper.show(context, message: t.productsDeletedSuccessfully);
                    } catch (e) {
                      if (!context.mounted) return;
                      SnackBarHelper.showError(
                        context,
                        message: ErrorExtractor.extractErrorMessage(e, t),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ),
            if (widget.authStore.hasBusinessPermission('inventory', 'read'))
              Tooltip(
                message: 'چاپ برچسب کالاهای یونیک انتخاب‌شده',
                child: IconButton(
                  onPressed: _bulkPrintUniqueProductLabels,
                  icon: const Icon(Icons.qr_code_2_outlined),
                ),
              ),
            if (widget.authStore.hasBusinessPermission('products', 'view'))
              Tooltip(
                message: AppLocalizations.of(context).printGeneralBarcodeLabels,
                child: IconButton(
                  onPressed: _bulkPrintGeneralBarcodeLabels,
                  icon: const Icon(Icons.label_outline),
                ),
              ),
            if (widget.authStore.hasBusinessPermission('products', 'edit'))
              Tooltip(
                message: t.bulkDefaultWarehouseAction,
                child: IconButton(
                  onPressed: () async {
                    final t = AppLocalizations.of(context);
                    try {
                      final state = _tableKey.currentState as dynamic;
                      final items = (state?.getSelectedItems() as List<dynamic>?) ?? const <dynamic>[];
                      if (items.isEmpty) {
                        SnackBarHelper.showError(context, message: t.noRowsSelectedError);
                        return;
                      }
                      final ids = <int>[];
                      for (final row in items) {
                        if (row is Map<String, dynamic>) {
                          final id = row['id'];
                          if (id is int) ids.add(id);
                        }
                      }
                      if (ids.isEmpty) return;

                      await showDialog<bool>(
                        context: context,
                        builder: (ctx) => BulkDefaultWarehouseDialog(
                          businessId: widget.businessId,
                          selectedProductIds: ids,
                          onSuccess: () {
                            try {
                              (_tableKey.currentState as dynamic)?.refresh();
                            } catch (_) {}
                          },
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      SnackBarHelper.showError(
        context,
        message: '${t.error}: ${ErrorExtractor.forContext(e, context)}',
      );
                    }
                  },
                  icon: const Icon(Icons.warehouse_outlined),
                ),
              ),
            Tooltip(
              message: t.importFromExcel,
              child: IconButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => ProductImportDialog(
                      businessId: widget.businessId,
                    ),
                  );
                  if (ok == true) {
                    try {
                      ( _tableKey.currentState as dynamic)?.refresh();
                    } catch (_) {}
                  }
                },
                icon: const Icon(Icons.upload_file),
              ),
            ),
            Tooltip(
              message: t.bulkPriceUpdateTitle,
              child: IconButton(
                onPressed: () async {
                  await showDialog<bool>(
                    context: context,
                    builder: (ctx) => BulkPriceUpdateDialog(
                      businessId: widget.businessId,
                      onSuccess: () {
                        try {
                          ( _tableKey.currentState as dynamic)?.refresh();
                        } catch (_) {}
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.auto_graph),
              ),
            ),
            if (widget.authStore.hasBusinessPermission('products', 'view'))
              Tooltip(
                message: t.bulkProductPricesSheetTitle,
                child: IconButton(
                  onPressed: () {
                    context.push('/business/${widget.businessId}/products/bulk-prices-sheet');
                  },
                  icon: const Icon(Icons.table_chart_outlined),
                ),
              ),
            if (widget.authStore.hasBusinessPermission('products', 'export'))
              Tooltip(
                message: 'گزارش قیمت کالا — خروجی PDF و اکسل (جدا از خروجی سادهٔ جدول)',
                child: IconButton(
                  onPressed: _showProductPriceReportExportDialog,
                  icon: const Icon(Icons.request_quote_outlined),
                ),
              ),
            Tooltip(
              message: t.addProduct,
              child: IconButton(
                onPressed: () async {
                  await showDialog<Object?>(
                    context: context,
                    builder: (ctx) => ProductFormDialog(
                      businessId: widget.businessId,
                      authStore: widget.authStore,
                      onSuccess: () {
                        try {
                          ( _tableKey.currentState as dynamic)?.refresh();
                        } catch (_) {}
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.add),
              ),
            ),
            Tooltip(
              message: t.managePriceLists,
              child: IconButton(
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t.managePriceLists),
                      content: SizedBox(
                        width: 700,
                        height: 480,
                        child: PriceListsPage(
                          businessId: widget.businessId,
                          authStore: widget.authStore,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(AppLocalizations.of(ctx).close),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.list_alt),
              ),
            ),
          ],
                additionalParams: {
                  'include_inventory': true,
                },
                onRowTap: (item) => _showProductDetailsDialog(item),
                expandBodyHeightToFitRows: true,
                onAllFiltersCleared: () {
                  if (!mounted) return;
                  unawaited(ListFilterPreferencesService.clear(ListFilterPageIds.products, widget.businessId));
                  setState(() => _quickCategoryFilterId = null);
                  try {
                    (_tableKey.currentState as dynamic)?.applyCategoryIdFilter(<int>[]);
                  } catch (_) {}
                },
              ),
              fromJson: (json) => json,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPriceReportExportDialog extends StatefulWidget {
  const _ProductPriceReportExportDialog({
    required this.businessId,
    required this.authStore,
    required this.tableKey,
    required this.initialReportMode,
    required this.initialPriceListIds,
    this.initialLimit,
    this.onSettingsApplied,
  });

  final int businessId;
  final AuthStore authStore;
  final GlobalKey tableKey;
  final String initialReportMode;
  final List<int> initialPriceListIds;
  final int? initialLimit;
  final void Function({
    required String mode,
    required List<int> priceListIds,
    int? maxItems,
  })? onSettingsApplied;

  @override
  State<_ProductPriceReportExportDialog> createState() => _ProductPriceReportExportDialogState();
}

class _ProductPriceReportExportDialogState extends State<_ProductPriceReportExportDialog> {
  final PriceListService _priceListService = PriceListService();
  final ReportTemplateService _templateService = ReportTemplateService(ApiClient());

  late String _reportMode;
  late Set<int> _selectedListIds;
  late TextEditingController _limitController;

  List<Map<String, dynamic>> _priceListRows = [];
  bool _listsLoading = false;

  List<Map<String, dynamic>> _templates = [];
  bool _templatesLoading = false;
  int? _pdfTemplateId;

  bool _selectedRowsOnly = false;
  bool _exporting = false;

  static const int _bulkTake = 10000;

  @override
  void initState() {
    super.initState();
    _reportMode = widget.initialReportMode;
    _selectedListIds = widget.initialPriceListIds.toSet();
    _limitController = TextEditingController(
      text: widget.initialLimit?.toString() ?? '',
    );
    _loadPriceLists();
    _loadPdfTemplates();
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _loadPriceLists() async {
    setState(() {
      _listsLoading = true;
    });
    try {
      final res = await _priceListService.listPriceLists(
        businessId: widget.businessId,
        page: 1,
        limit: 500,
      );
      final raw = res['items'];
      final parsed = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _priceListRows = parsed;
          _listsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _priceListRows = [];
          _listsLoading = false;
        });
      }
    }
  }

  Future<void> _loadPdfTemplates() async {
    setState(() => _templatesLoading = true);
    try {
      final list = await _templateService.listTemplates(
        businessId: widget.businessId,
        moduleKey: 'products',
        subtype: 'list',
        status: 'published',
      );
      if (!mounted) return;
      setState(() {
        _templates = list;
        _templatesLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _templates = [];
          _templatesLoading = false;
        });
      }
    }
  }

  int? _parsedLimit() {
    final raw = _limitController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  void _persist() {
    final sorted = _selectedListIds.toList()..sort();
    widget.onSettingsApplied?.call(
      mode: _reportMode,
      priceListIds: sorted,
      maxItems: _parsedLimit(),
    );
  }

  bool _needsPriceLists() =>
      _reportMode == 'price_lists_only' || _reportMode == 'base_plus_price_lists';

  bool _validate() {
    final t = AppLocalizations.of(context);
    if (_reportMode == 'price_lists_only' && _selectedListIds.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: 'برای این نوع گزارش، حداقل یک لیست قیمت انتخاب کنید.',
      );
      return false;
    }
    if (_selectedRowsOnly) {
      try {
        final st = widget.tableKey.currentState as dynamic;
        final sel = st?.getSelectedItems() as List<dynamic>? ?? [];
        if (sel.isEmpty) {
          SnackBarHelper.showError(context, message: t.noRowsSelectedError);
          return false;
        }
      } catch (_) {
        SnackBarHelper.showError(context, message: t.noRowsSelectedError);
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _mergedExportParams() {
    final merged = <String, dynamic>{
      'report_mode': _reportMode,
      'price_list_ids': _selectedListIds.toList()..sort(),
    };
    final lim = _parsedLimit();
    if (lim != null) merged['limit'] = lim;
    if (!_selectedRowsOnly) {
      merged['take'] = _bulkTake;
      merged['skip'] = 0;
    }
    return merged;
  }

  Future<void> _export(String format) async {
    final t = AppLocalizations.of(context);
    if (!widget.authStore.hasBusinessPermission('products', 'export')) {
      SnackBarHelper.showError(context, message: t.noPermission);
      return;
    }
    if (!_validate()) return;
    _persist();
    final st = widget.tableKey.currentState as dynamic;
    if (st == null) {
      SnackBarHelper.showError(context, message: t.error);
      return;
    }

    setState(() => _exporting = true);
    try {
      final ok = await (st.exportWithMergedBodyParams(
        format: format,
        selectedOnly: _selectedRowsOnly,
        mergedBodyParams: _mergedExportParams(),
        pdfTemplateId: format == 'pdf' ? _pdfTemplateId : null,
      )) as bool;
      if (ok && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.request_quote_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('گزارش قیمت کالا — خروجی PDF و اکسل')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('نوع گزارش', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _reportMode,
                    decoration: InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                        value: 'base_only',
                        child: Text('فقط قیمت‌های پایه خرید/فروش'),
                      ),
                      DropdownMenuItem(
                        value: 'price_lists_only',
                        child: Text('فقط لیست‌های قیمت'),
                      ),
                      DropdownMenuItem(
                        value: 'base_plus_price_lists',
                        child: Text('قیمت پایه به‌همراه لیست‌های قیمت'),
                      ),
                    ],
                    onChanged: _exporting
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _reportMode = v);
                          },
                  ),
                  const SizedBox(height: 16),
                  if (_needsPriceLists()) ...[
                    Text('لیست‌های قیمت', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (_listsLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_priceListRows.isEmpty)
                      Text(
                        'لیست قیمتی ثبت نشده است.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final row in _priceListRows)
                              Builder(builder: (_) {
                                final dynamic rawId = row['id'];
                                final id = rawId is int
                                    ? rawId
                                    : (rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? -1);
                                if (id < 0) return const SizedBox.shrink();
                                final nm = '${row['name'] ?? ''}'.trim();
                                final name = nm.isEmpty ? 'لیست #$id' : nm;
                                return CheckboxListTile(
                                  dense: true,
                                  title: Text(name),
                                  value: _selectedListIds.contains(id),
                                  onChanged: _exporting
                                      ? null
                                      : (chk) {
                                          setState(() {
                                            if (chk == true) {
                                              _selectedListIds.add(id);
                                            } else {
                                              _selectedListIds.remove(id);
                                            }
                                          });
                                        },
                                );
                              }),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                  Text('محدودهٔ خروجی', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  RadioListTile<bool>(
                    title: const Text('همهٔ ردیف‌های مطابق با فیلتر فعلی (تا سقف بارگذاری)'),
                    value: false,
                    groupValue: _selectedRowsOnly,
                    onChanged: _exporting
                        ? null
                        : (_) => setState(() => _selectedRowsOnly = false),
                  ),
                  RadioListTile<bool>(
                    title: const Text('فقط ردیف‌های انتخاب‌شده در جدول'),
                    value: true,
                    groupValue: _selectedRowsOnly,
                    onChanged: _exporting
                        ? null
                        : (_) => setState(() => _selectedRowsOnly = true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _limitController,
                    enabled: !_exporting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'حداکثر تعداد ردیف در گزارش (اختیاری، حداکثر ۱۰٬۰۰۰)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('قالب PDF', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_templatesLoading)
                    const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
                  DropdownButtonFormField<int?>(
                    value: _pdfTemplateId,
                    decoration: InputDecoration(border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('پیش‌فرض سیستم'),
                      ),
                      for (final tpl in _templates)
                        DropdownMenuItem<int?>(
                          value: (tpl['id'] as num).toInt(),
                          child: Text(tpl['name']?.toString() ?? '${tpl['id']}'),
                        ),
                    ],
                    onChanged: _exporting
                        ? null
                        : (v) => setState(() => _pdfTemplateId = v),
                  ),
                  if (!_templatesLoading && _templates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'قالب انتشار‌یافته‌ای برای این نوع نیست؛ PDF با قالب پیش‌فرض سرور ساخته می‌شود.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                ],
              ),
            ),
            if (_exporting)
              Positioned.fill(
                child: Container(
                  color: theme.colorScheme.surface.withValues(alpha: 0.65),
                  child: const Center(
                    child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _exporting ? null : () => Navigator.of(context).pop(),
          child: Text(t.close),
        ),
        OutlinedButton.icon(
          onPressed: _exporting ? null : () => _export('excel'),
          icon: Icon(Icons.table_chart_outlined),
          label: Text('اکسل'),
        ),
        FilledButton.icon(
          onPressed: _exporting ? null : () => _export('pdf'),
          icon: Icon(Icons.picture_as_pdf_outlined),
          label: Text('PDF'),
        ),
      ],
    );
  }
}

class _ProductStockTabWidget extends StatefulWidget {
  final int businessId;
  final int? productId;
  final bool trackInventory;
  final AppLocalizations t;

  const _ProductStockTabWidget({
    required this.businessId,
    required this.productId,
    required this.trackInventory,
    required this.t,
  });

  @override
  State<_ProductStockTabWidget> createState() => _ProductStockTabWidgetState();
}

class _ProductStockTabWidgetState extends State<_ProductStockTabWidget> {
  final WarehouseService _warehouseService = WarehouseService();
  bool _stockLoading = false;
  List<dynamic> _stockItems = [];
  DateTime? _stockAsOfDate = DateTime.now();
  bool _includeZeroStock = false;
  double _totalStock = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.productId != null && widget.trackInventory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadProductStock();
      });
    }
  }

  Future<void> _loadProductStock() async {
    if (widget.productId == null || !widget.trackInventory) return;

    setState(() {
      _stockLoading = true;
    });

    try {
      final query = {
        'product_ids': [widget.productId],
        'as_of_date': _stockAsOfDate?.toIso8601String().split('T')[0] ??
            DateTime.now().toIso8601String().split('T')[0],
        'include_zero': _includeZeroStock,
      };

      final res = await _warehouseService.getStockReport(
        businessId: widget.businessId,
        query: query,
      );

      final items = List<dynamic>.from(res['items'] ?? []);
      final total = items.fold<double>(
        0.0,
        (sum, item) => sum + ((item['quantity'] as num?)?.toDouble() ?? 0.0),
      );

      if (mounted) {
        setState(() {
          _stockItems = items;
          _totalStock = total;
          _stockLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stockLoading = false;
        });
        SnackBarHelper.showError(
        context,
        message: 'خطا در بارگذاری موجودی: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If product doesn't track inventory
    if (!widget.trackInventory) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                widget.t.inventoryNotTracked,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // If product ID is null
    if (widget.productId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'برای نمایش موجودی، ابتدا کالا باید ذخیره شود.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with title and refresh button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.t.productStockInWarehouses,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: _stockLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _stockLoading ? null : _loadProductStock,
                tooltip: widget.t.refreshStock,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filters
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          decoration: InputDecoration(
                            labelText: widget.t.stockReportDate,
                            border: const OutlineInputBorder(),
                            suffixIcon: const Icon(Icons.calendar_today),
                          ),
                          readOnly: true,
                          controller: TextEditingController(
                            text: _stockAsOfDate != null
                                ? HesabixDateUtils.formatForDisplay(
                                    _stockAsOfDate,
                                    ApiClient.getCalendarController()?.isJalali ?? true,
                                  )
                                : '',
                          ),
                          onTap: () async {
                            final date = await showAdaptiveDatePicker(
                              context: context,
                              calendarController: ApiClient.getCalendarController(),
                              initialDate: _stockAsOfDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (date != null) {
                              setState(() {
                                _stockAsOfDate = date;
                              });
                              _loadProductStock();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      CheckboxListTile(
                        title: Text(widget.t.showZeroStock),
                        value: _includeZeroStock,
                        onChanged: (value) {
                          setState(() {
                            _includeZeroStock = value ?? false;
                          });
                          _loadProductStock();
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Total stock summary
          if (_stockItems.isNotEmpty)
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: theme.colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.t.totalStock,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      formatWithThousands(_totalStock, decimalPlaces: 2),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_stockItems.isNotEmpty) const SizedBox(height: 16),

          // Stock table
          Expanded(
            child: _stockLoading
                ? const Center(child: CircularProgressIndicator())
                : _stockItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warehouse_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.t.noStockRecorded,
                              style: theme.textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              DataColumn(
                                label: Text(
                                  widget.t.warehouseCode,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  widget.t.warehouseName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  widget.t.stockQuantity,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                numeric: true,
                              ),
                              DataColumn(
                                label: Text(
                                  'واحد',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            rows: _stockItems.map<DataRow>((item) {
                              final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
                              final isNegative = quantity < 0;
                              final isLow = quantity > 0 && quantity < 10;

                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      item['warehouse_code']?.toString() ?? '-',
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      item['warehouse_name']?.toString() ?? '-',
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      formatWithThousands(quantity, decimalPlaces: 2),
                                      style: TextStyle(
                                        color: isNegative
                                            ? Colors.red
                                            : isLow
                                                ? Colors.orange
                                                : null,
                                        fontWeight: isNegative || isLow
                                            ? FontWeight.w600
                                            : null,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      item['unit']?.toString() ?? '-',
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}


