import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../widgets/product/bulk_price_update_dialog.dart';
import '../../widgets/product/product_import_dialog.dart';
import '../../core/api_client.dart';
import '../../config/app_config.dart';
import '../../core/auth_store.dart';
import 'price_lists_page.dart';
import '../../utils/number_formatters.dart';

class ProductsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ProductsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final GlobalKey _tableKey = GlobalKey();
  
  /// نمایش دیالوگ تصویر
  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
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
                      maxWidth: MediaQuery.of(context).size.width * 0.9,
                      maxHeight: MediaQuery.of(context).size.height * 0.9,
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
      return response.data ?? [];
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
      body: DataTableWidget<Map<String, dynamic>>(
        key: _tableKey,
        config: DataTableConfig<Map<String, dynamic>>(
          endpoint: '/api/v1/products/business/${widget.businessId}/search',
          title: t.products,
          excelEndpoint: '/api/v1/products/business/${widget.businessId}/export/excel',
          pdfEndpoint: '/api/v1/products/business/${widget.businessId}/export/pdf',
          businessId: widget.businessId,
          reportModuleKey: 'products',
          reportSubtype: 'list',
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
                final imageUrl = item['image_url'] as String?;
                if (imageUrl == null || imageUrl.isEmpty) {
                  return const Center(child: SizedBox.shrink());
                }
                // ساخت URL کامل
                String fullUrl = imageUrl;
                if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
                  // اگر URL نسبی است، base URL را اضافه می‌کنیم
                  final baseUrl = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
                  fullUrl = '$baseUrl${imageUrl.startsWith('/') ? imageUrl : '/$imageUrl'}';
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
            TextColumn('item_type', t.service, width: ColumnWidth.small),
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
                final dynamic caf = row['created_at_formatted'];
                if (caf is Map && caf['formatted'] != null && caf['formatted'].toString().isNotEmpty) {
                  return caf['formatted'].toString();
                }
                final dynamic ca = row['created_at'];
                if (ca is String && ca.isNotEmpty) return ca;
                final dynamic car = row['created_at_raw'];
                if (car is String && car.isNotEmpty) return car;
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
                final dynamic uaf = row['updated_at_formatted'];
                if (uaf is Map && uaf['formatted'] != null && uaf['formatted'].toString().isNotEmpty) {
                  return uaf['formatted'].toString();
                }
                final dynamic ua = row['updated_at'];
                if (ua is String && ua.isNotEmpty) return ua;
                final dynamic uar = row['updated_at_raw'];
                if (uar is String && uar.isNotEmpty) return uar;
                return '-';
              },
            ),
            ActionColumn('actions', t.actions, actions: [
              DataTableAction(
                icon: Icons.edit,
                label: t.edit,
                onTap: (row) async {
                  await showDialog<bool>(
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
                  try {
                    final api = ApiClient();
                    await api.delete<Map<String, dynamic>>(
                      '/products/business/${widget.businessId}/${row['id']}',
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.productDeletedSuccessfully)));
                    try { ( _tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
                  }
                },
              ),
            ]),
          ],
          searchFields: const ['code', 'name', 'description'],
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
                      final selectedIndices = (state?.getSelectedRowIndices() as List<int>?) ?? const <int>[];
                      final items = (state?.getSelectedItems() as List<dynamic>?) ?? const <dynamic>[];
                      if (selectedIndices.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.noRowsSelectedError)));
                        return;
                      }
                      final ids = <int>[];
                      for (final i in selectedIndices) {
                        if (i >= 0 && i < items.length) {
                          final row = items[i] as Map<String, dynamic>;
                          final id = row['id'];
                          if (id is int) ids.add(id);
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.productsDeletedSuccessfully)));
                    } catch (e) {
                      if (!context.mounted) return;
                      final t = AppLocalizations.of(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
                    }
                  },
                  icon: const Icon(Icons.delete_sweep_outlined),
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
            Tooltip(
              message: t.addProduct,
              child: IconButton(
                onPressed: () async {
                  await showDialog<bool>(
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
        ),
        fromJson: (json) => json,
      ),
    );
  }
}


