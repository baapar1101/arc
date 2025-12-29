import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../controllers/product_form_controller.dart';
import 'sections/product_basic_info_section.dart';
import 'sections/product_pricing_inventory_section.dart';
import 'sections/product_tax_section.dart';
import 'sections/product_bom_section.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';

class ProductFormDialog extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic>? product;
  final VoidCallback? onSuccess;
  final AuthStore authStore;

  const ProductFormDialog({
    super.key,
    required this.businessId,
    required this.authStore,
    this.product,
    this.onSuccess,
  });

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final ProductFormController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProductFormController(businessId: widget.businessId);
    // استفاده از unawaited برای جلوگیری از warning
    _initializeForm();
  }

  Future<void> _initializeForm() async {
    if (mounted) {
      await _controller.initializeWithProduct(widget.product);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);
    final dialogConstraints = ResponsiveHelper.getDialogConstraints(context);
    
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        return Dialog(
          insetPadding: ResponsiveHelper.getDialogPadding(context),
          child: Container(
            constraints: dialogConstraints,
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                if (isMobile)
                  AppBar(
                    title: Text(widget.product == null ? t.addProduct : t.edit),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    automaticallyImplyLeading: false,
                  )
                else
                  Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            widget.product == null ? Icons.add : Icons.edit,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.product == null ? t.addProduct : t.edit,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const Divider(),
                    ],
                  ),
                SizedBox(height: isMobile ? 8 : 16),
                // Content
                Expanded(
                  child: _controller.isLoading
                      ? _buildLoadingWidget(t)
                      : _buildFormContent(),
                ),
                // Actions
                const Divider(),
                SizedBox(height: isMobile ? 8 : 16),
                _buildActions(t, isMobile),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingWidget(AppLocalizations t) {
    return SizedBox(
      height: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'در حال بارگذاری اطلاعات...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormContent() {
    final isMobile = ResponsiveHelper.isMobile(context);
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabBar(),
          SizedBox(height: isMobile ? 8 : 12),
          Expanded(
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: TabBarView(
                children: [
                  _buildBasicInfoTab(),
                  _buildPricingInventoryTab(),
                  _buildTaxTab(),
                  _buildBomTab(),
                ],
              ),
            ),
          ),
          if (_controller.errorMessage != null) _buildErrorMessage(),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    return TabBar(
      isScrollable: isMobile,
      tabs: [
        Tab(text: t.productGeneralInfo),
        Tab(text: t.pricingAndInventory),
        Tab(text: t.tax),
        const Tab(text: 'فرمول تولید'),
      ],
    );
  }

  Widget _buildBasicInfoTab() {
    final isMobile = ResponsiveHelper.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
      child: ProductBasicInfoSection(
        businessId: widget.businessId,
        formData: _controller.formData,
        onChanged: _controller.updateFormData,
        categories: _controller.categories,
        attributes: _controller.attributes,
        controller: _controller,
        authStore: widget.authStore,
      ),
    );
  }

  Widget _buildPricingInventoryTab() {
    final isMobile = ResponsiveHelper.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
      child: ProductPricingInventorySection(
        businessId: widget.businessId,
        formData: _controller.formData,
        onChanged: _controller.updateFormData,
        priceLists: _controller.priceLists,
        currencies: _controller.currencies,
        warehouses: _controller.warehouses,
        draftPriceItems: _controller.draftPriceItems,
        onAddOrUpdatePriceItem: (item) {
          _controller.addOrUpdateDraftPriceItem(item);
          _controller.updateFormData(_controller.formData);
        },
        onDeletePriceItem: (item) {
          _controller.removeDraftPriceItem(item);
          _controller.updateFormData(_controller.formData);
        },
        controller: _controller,
        productId: widget.product?['id'] as int?,
      ),
    );
  }

  Widget _buildTaxTab() {
    final isMobile = ResponsiveHelper.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
      child: ProductTaxSection(
        formData: _controller.formData,
        onChanged: _controller.updateFormData,
        taxTypes: _controller.taxTypes,
        taxUnits: _controller.taxUnits,
      ),
    );
  }

  Widget _buildBomTab() {
    final isMobile = ResponsiveHelper.isMobile(context);
    final productId = widget.product != null ? widget.product!['id'] as int? : null;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 8),
      child: ProductBomSection(
        businessId: widget.businessId,
        productId: productId,
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'خطا',
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _controller.errorMessage!,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Colors.red.shade600,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              _controller.updateFormData(_controller.formData);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActions(AppLocalizations t, bool isMobile) {
    if (isMobile) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _controller.isLoading ? null : _handleSubmit,
              child: _controller.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.save),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _controller.isLoading 
                  ? null 
                  : () {
                      _controller.resetForm();
                      if (mounted) {
                        Navigator.of(context).pop(false);
                      }
                    },
              child: Text(t.cancel),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _controller.isLoading 
              ? null 
              : () {
                  _controller.resetForm();
                  if (mounted) {
                    Navigator.of(context).pop(false);
                  }
                },
          child: Text(t.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _controller.isLoading ? null : _handleSubmit,
          child: _controller.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.save),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    final t = AppLocalizations.of(context);
    if (!_controller.validateForm(_formKey)) {
      return;
    }

    bool success;
    int? createdProductId;
    if (widget.product != null) {
      final productId = widget.product!['id'] as int;
      success = await _controller.updateProduct(productId);
    } else {
      success = await _controller.submitForm();
      createdProductId = _controller.lastCreatedProductId;
    }

    if (success && mounted) {
      // نمایش پیام موفقیت
      SnackBarHelper.show(
        context,
        message: widget.product != null 
            ? 'کالا/خدمت با موفقیت ویرایش شد' 
            : 'کالا/خدمت با موفقیت ایجاد شد',
      );
      // پاک کردن فرم
      _controller.resetForm();
      // فراخوانی callback
      widget.onSuccess?.call();
      // بستن دیالوگ
      Navigator.of(context).pop(createdProductId ?? true);
    } else if (mounted) {
      SnackBarHelper.showError(
        context,
        message: _controller.errorMessage ?? t.error,
        action: SnackBarAction(
          label: t.retry,
          textColor: Colors.white,
          onPressed: _handleSubmit,
        ),
      );
    }
  }
}
