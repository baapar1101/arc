import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../controllers/product_form_controller.dart';
import 'sections/product_basic_info_section.dart';
import 'sections/product_pricing_inventory_section.dart';
import 'sections/product_tax_section.dart';
import 'sections/product_bom_section.dart';
import '../../utils/snackbar_helper.dart';

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
    _initializeForm();
  }

  Future<void> _initializeForm() async {
    await _controller.initializeWithProduct(widget.product);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(widget.product == null ? Icons.add : Icons.edit),
              const SizedBox(width: 8),
              Text(widget.product == null ? t.addProduct : t.edit),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 1200 ? 1000 : 800,
            child: _controller.isLoading
                ? _buildLoadingWidget(t)
                : _buildFormContent(),
          ),
          actions: _buildActions(t),
        );
      },
    );
  }

  Widget _buildLoadingWidget(AppLocalizations t) {
    return SizedBox(
      height: 300,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildFormContent() {
    return DefaultTabController(
      length: 4,
      child: SizedBox(
        height: MediaQuery.of(context).size.height > 800 ? 700 : 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTabBar(),
            const SizedBox(height: 12),
            Expanded(
              child: Form(
                key: _formKey,
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
      ),
    );
  }

  Widget _buildTabBar() {
    final t = AppLocalizations.of(context);
    return TabBar(
      isScrollable: true,
      tabs: [
        Tab(text: t.productGeneralInfo),
        Tab(text: t.pricingAndInventory),
        Tab(text: t.tax),
        const Tab(text: 'فرمول تولید'),
      ],
    );
  }

  Widget _buildBasicInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ProductTaxSection(
        formData: _controller.formData,
        onChanged: _controller.updateFormData,
        taxTypes: _controller.taxTypes,
        taxUnits: _controller.taxUnits,
      ),
    );
  }

  Widget _buildBomTab() {
    final productId = widget.product != null ? widget.product!['id'] as int? : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _controller.errorMessage!,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(AppLocalizations t) {
    return [
      TextButton(
        onPressed: _controller.isLoading ? null : () => Navigator.of(context).pop(),
        child: Text(t.cancel),
      ),
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
    ];
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
      widget.onSuccess?.call();
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
