import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import 'package:go_router/go_router.dart';
import 'price_list_items_page.dart';
import '../../core/auth_store.dart';

class PriceListsPage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;

  const PriceListsPage({super.key, required this.businessId, required this.authStore});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      body: DataTableWidget<Map<String, dynamic>>(
        config: DataTableConfig<Map<String, dynamic>>(
          endpoint: '/api/v1/price-lists/business/$businessId/search',
          title: t.priceLists,
          columns: [
            TextColumn('name', t.title, width: ColumnWidth.large),
            TextColumn('currency_id', 'ارز', width: ColumnWidth.small),
            TextColumn('default_unit_id', 'واحد پیش‌فرض', width: ColumnWidth.small),
            TextColumn('created_at_formatted', t.createdAt, width: ColumnWidth.medium),
          ],
          searchFields: const ['name'],
          filterFields: const [],
          defaultPageSize: 20,
          onRowDoubleTap: (row) {
            final id = row['id'] as int?;
            if (id != null) {
              context.go('/business/$businessId/price-lists/$id/items');
            }
          },
        ),
        fromJson: (json) => json,
      ),
    );
  }
}


