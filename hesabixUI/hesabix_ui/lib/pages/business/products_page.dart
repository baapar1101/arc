import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../core/auth_store.dart';

class ProductsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ProductsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final GlobalKey _tableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('products')) {
      return Scaffold(
        body: Center(child: Text('دسترسی مشاهده کالا و خدمات را ندارید')),
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
          columns: [
            TextColumn('code', t.code, width: ColumnWidth.small),
            TextColumn('name', t.title, width: ColumnWidth.large),
            TextColumn('item_type', t.service, width: ColumnWidth.small),
            NumberColumn('base_sales_price', 'قیمت فروش', width: ColumnWidth.medium, decimalPlaces: 2),
            NumberColumn('base_purchase_price', 'قیمت خرید', width: ColumnWidth.medium, decimalPlaces: 2),
            // Inventory
            TextColumn(
              'track_inventory',
              'کنترل موجودی',
              width: ColumnWidth.small,
              formatter: (row) => (row['track_inventory'] == true) ? 'بله' : 'خیر',
            ),
            NumberColumn('reorder_point', 'نقطه سفارش', width: ColumnWidth.small, decimalPlaces: 0),
            NumberColumn('min_order_qty', 'کمینه سفارش', width: ColumnWidth.small, decimalPlaces: 0),
            // Taxes
            NumberColumn('sales_tax_rate', 'مالیات فروش %', width: ColumnWidth.small, decimalPlaces: 2),
            NumberColumn('purchase_tax_rate', 'مالیات خرید %', width: ColumnWidth.small, decimalPlaces: 2),
            TextColumn('tax_code', 'کُد مالیاتی', width: ColumnWidth.small),
            TextColumn('created_at_formatted', t.createdAt, width: ColumnWidth.medium),
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
            ]),
          ],
          searchFields: const ['code', 'name', 'description'],
          filterFields: const ['item_type', 'category_id'],
          defaultPageSize: 20,
          customHeaderActions: [
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
          ],
        ),
        fromJson: (json) => json,
      ),
    );
  }
}


