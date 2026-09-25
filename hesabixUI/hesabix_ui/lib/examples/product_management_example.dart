import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../widgets/product/product_form_dialog.dart';

class ProductManagementExample extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;

  const ProductManagementExample({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت کالاها'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddProductDialog(context),
            tooltip: t.addProduct,
          ),
        ],
      ),
      body: ListView(
        children: [
          // Example product list items
          _buildProductListItem(
            context,
            id: 1,
            name: 'کالای نمونه ۱',
            code: 'P001',
            price: 100000,
            onEdit: () => _showEditProductDialog(context, 1),
          ),
          _buildProductListItem(
            context,
            id: 2,
            name: 'کالای نمونه ۲',
            code: 'P002',
            price: 250000,
            onEdit: () => _showEditProductDialog(context, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildProductListItem(
    BuildContext context, {
    required int id,
    required String name,
    required String code,
    required int price,
    required VoidCallback onEdit,
  }) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.inventory),
        ),
        title: Text(name),
        subtitle: Text('کد: $code - قیمت: ${price.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        )} تومان'),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: const Row(
                children: [
                  Icon(Icons.edit),
                  SizedBox(width: 8),
                  Text('ویرایش'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: const Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('حذف', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'edit') {
              onEdit();
            } else if (value == 'delete') {
              _showDeleteConfirmation(context, id, name);
            }
          },
        ),
        onTap: onEdit,
      ),
    );
  }

  void _showAddProductDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProductFormDialog(
        businessId: businessId,
        authStore: authStore,
        onSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('کالا با موفقیت اضافه شد'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  void _showEditProductDialog(BuildContext context, int productId) {
    // In a real app, you would fetch the product data from your service
    final productData = {
      'id': productId,
      'name': 'کالای نمونه $productId',
      'code': 'P00$productId',
      'item_type': 'کالا',
      'description': 'توضیحات کالای نمونه $productId',
      'base_sales_price': productId == 1 ? 100000 : 250000,
      'track_inventory': true,
      'is_sales_taxable': false,
      'is_purchase_taxable': false,
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProductFormDialog(
        businessId: businessId,
        authStore: authStore,
        product: productData,
        onSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('کالا با موفقیت به‌روزرسانی شد'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, int productId, String productName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('آیا از حذف "$productName" اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // In a real app, you would call your delete service here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('کالا با موفقیت حذف شد'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}
