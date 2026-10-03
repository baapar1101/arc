import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../models/product_bundle.dart';
import '../../services/product_bundle_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../widgets/product/product_bundle_form_dialog.dart';

class ProductBundlesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ProductBundlesPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<ProductBundlesPage> createState() => _ProductBundlesPageState();
}

class _ProductBundlesPageState extends State<ProductBundlesPage> {
  final ProductBundleService _service = ProductBundleService();
  final GlobalKey _tableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.hasBusinessPermission('products', 'view')) {
      return const AccessDeniedPage();
    }
    return Scaffold(
      body: SingleChildScrollView(
        child: DataTableWidget<ProductBundle>(
          key: _tableKey,
          config: _config(),
          fromJson: ProductBundle.fromJson,
        ),
      ),
    );
  }

  DataTableConfig<ProductBundle> _config() {
    return DataTableConfig<ProductBundle>(
      endpoint: '/api/v1/product-bundles/business/${widget.businessId}/search',
      businessId: widget.businessId,
      title: 'باندل‌های کالا',
      showBackButton: true,
      onBack: () {
        if (context.canPop()) context.pop();
      },
      showTableIcon: false,
      columns: [
        TextColumn(
          'name',
          'نام باندل',
          width: ColumnWidth.large,
          formatter: (item) => item.name,
        ),
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.extraLarge,
          formatter: (item) => item.description?.trim().isNotEmpty == true
              ? item.description
              : '—',
        ),
        NumberColumn(
          'items_count',
          'تعداد اقلام',
          formatter: (item) => item.itemsCount.toString(),
        ),
        TextColumn(
          'is_active',
          'وضعیت',
          sortable: true,
          searchable: false,
          formatter: (item) => item.isActive ? 'فعال' : 'غیرفعال',
        ),
        DateColumn(
          'updated_at',
          'آخرین تغییر',
          formatter: (item) => item.updatedAtDisplay ?? '—',
        ),
        ActionColumn(
          'actions',
          'عملیات',
          actions: [
            DataTableAction(
              icon: Icons.edit_outlined,
              label: 'ویرایش',
              enabled: (_) =>
                  widget.authStore.hasBusinessPermission('products', 'edit'),
              onTap: (item) => _edit(item as ProductBundle),
            ),
            DataTableAction(
              icon: Icons.delete_outline,
              label: 'حذف',
              isDestructive: true,
              enabled: (_) =>
                  widget.authStore.hasBusinessPermission('products', 'delete'),
              onTap: (item) => _delete(item as ProductBundle),
            ),
          ],
        ),
      ],
      searchFields: const ['name', 'description'],
      filterFields: const ['is_active'],
      defaultPageSize: 20,
      expandBodyHeightToFitRows: true,
      customHeaderActions: [
        PermissionButton(
          section: 'products',
          action: 'add',
          authStore: widget.authStore,
          child: Tooltip(
            message: 'باندل جدید',
            child: IconButton(onPressed: _create, icon: const Icon(Icons.add)),
          ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final changed = await showProductBundleFormDialog(
      context: context,
      businessId: widget.businessId,
      authStore: widget.authStore,
    );
    if (changed == true) {
      _refresh();
      if (mounted) SnackBarHelper.show(context, message: 'باندل ساخته شد.');
    }
  }

  Future<void> _edit(ProductBundle row) async {
    try {
      final bundle = await _service.getOne(
        businessId: widget.businessId,
        bundleId: row.id,
      );
      if (!mounted) return;
      final changed = await showProductBundleFormDialog(
        context: context,
        businessId: widget.businessId,
        authStore: widget.authStore,
        bundle: bundle,
      );
      if (changed == true) {
        _refresh();
        if (mounted) SnackBarHelper.show(context, message: 'باندل ویرایش شد.');
      }
    } catch (error) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(error, context),
          isError: true,
        );
      }
    }
  }

  Future<void> _delete(ProductBundle row) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف باندل'),
        content: Text(
          'باندل «${row.name}» حذف شود؟ این کار روی فاکتورهای قبلی اثری ندارد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.delete(businessId: widget.businessId, bundleId: row.id);
      _refresh();
      if (mounted) SnackBarHelper.show(context, message: 'باندل حذف شد.');
    } catch (error) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(error, context),
          isError: true,
        );
      }
    }
  }

  void _refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _tableKey.currentState;
      if (mounted && state != null) {
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
      }
    });
  }
}
