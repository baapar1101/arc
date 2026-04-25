import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/warranty_service.dart';
import '../../services/product_service.dart';
import '../../models/product_model.dart';
import '../../models/warranty_models.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class GenerateWarrantyCodesDialog extends StatefulWidget {
  final int businessId;
  final WarrantyService warrantyService;

  const GenerateWarrantyCodesDialog({
    super.key,
    required this.businessId,
    required this.warrantyService,
  });

  @override
  State<GenerateWarrantyCodesDialog> createState() => _GenerateWarrantyCodesDialogState();
}

class _GenerateWarrantyCodesDialogState extends State<GenerateWarrantyCodesDialog> {
  final _formKey = GlobalKey<FormState>();
  final ProductService _productService = ProductService();
  bool _loading = false;
  bool _loadingProducts = false;
  List<Product> _products = [];
  Product? _selectedProduct;
  int _quantity = 1;
  int _warrantyDurationDays = 365;
  String _codeFormat = 'random';
  String? _codePrefix;
  String _serialFormat = 'random';
  int? _serialLength;
  List<String> _customCodes = [];
  List<String> _customSerials = [];
  final TextEditingController _customCodesController = TextEditingController();
  final TextEditingController _customSerialsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _customCodesController.dispose();
    _customSerialsController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final productsData = await _productService.searchProducts(
        businessId: widget.businessId,
        limit: 1000,
      );
      if (mounted) {
        setState(() {
          _products = productsData.map((json) => Product.fromJson(json)).toList();
          _loadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingProducts = false);
        SnackBarHelper.showError(
        context,
        message:
            'خطا در بارگذاری کالاها: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    }
  }

  Future<void> _generateCodes() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      SnackBarHelper.showError(context, message: 'لطفاً کالا را انتخاب کنید');
      return;
    }

    setState(() => _loading = true);
    try {
      final codes = await widget.warrantyService.generateCodes(
        widget.businessId,
        _selectedProduct!.id!,
        _quantity,
        _warrantyDurationDays,
        serialFormat: _serialFormat == 'custom' ? 'custom' : null,
        customSerials: _customSerials.isNotEmpty ? _customSerials : null,
        codeFormat: _codeFormat == 'custom' ? 'custom' : null,
        customCodes: _customCodes.isNotEmpty ? _customCodes : null,
      );

      if (mounted) {
        Navigator.of(context).pop(codes);
        SnackBarHelper.showSuccess(context, message: '${codes.length} کد گارانتی با موفقیت تولید شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message:
            'خطا در تولید کدهای گارانتی: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, color: colorScheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.generateWarrantyCodes,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colorScheme.onPrimaryContainer),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<Product>(
                        decoration: InputDecoration(
                          labelText: t.warrantyProduct,
                          border: const OutlineInputBorder(),
                        ),
                        value: _selectedProduct,
                        items: _products.map((product) {
                          return DropdownMenuItem(
                            value: product,
                            child: Text(product.displayName),
                          );
                        }).toList(),
                        onChanged: _loadingProducts
                            ? null
                            : (value) => setState(() => _selectedProduct = value),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: t.warrantyQuantity,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        initialValue: _quantity.toString(),
                        onChanged: (value) => _quantity = int.tryParse(value) ?? 1,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'تعداد الزامی است';
                          }
                          final qty = int.tryParse(value);
                          if (qty == null || qty < 1) {
                            return 'تعداد باید بیشتر از 0 باشد';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: t.warrantyDurationDays,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        initialValue: _warrantyDurationDays.toString(),
                        onChanged: (value) =>
                            _warrantyDurationDays = int.tryParse(value) ?? 365,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'مدت گارانتی الزامی است';
                          }
                          final days = int.tryParse(value);
                          if (days == null || days < 1) {
                            return 'مدت گارانتی باید بیشتر از 0 باشد';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        t.warrantyCodeFormat,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'random', label: Text(t.warrantyRandom)),
                          ButtonSegment(value: 'sequential', label: Text(t.warrantySequential)),
                          ButtonSegment(value: 'custom', label: Text(t.warrantyCustom)),
                        ],
                        selected: {_codeFormat},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() => _codeFormat = newSelection.first);
                        },
                      ),
                      if (_codeFormat == 'custom') ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customCodesController,
                          decoration: InputDecoration(
                            labelText: t.warrantyCustomCodes,
                            border: const OutlineInputBorder(),
                            helperText: 'کدها را با کاما جدا کنید',
                          ),
                          maxLines: 3,
                          onChanged: (value) {
                            _customCodes = value
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();
                          },
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        t.warrantySerialFormat,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'random', label: Text(t.warrantyRandom)),
                          ButtonSegment(value: 'custom', label: Text(t.warrantyCustom)),
                        ],
                        selected: {_serialFormat},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() => _serialFormat = newSelection.first);
                        },
                      ),
                      if (_serialFormat == 'random') ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          decoration: InputDecoration(
                            labelText: t.warrantySerialLength,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          initialValue: _serialLength?.toString(),
                          onChanged: (value) => _serialLength = int.tryParse(value),
                        ),
                      ],
                      if (_serialFormat == 'custom') ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customSerialsController,
                          decoration: InputDecoration(
                            labelText: t.warrantyCustomSerials,
                            border: const OutlineInputBorder(),
                            helperText: 'سریال‌ها را با کاما جدا کنید',
                          ),
                          maxLines: 3,
                          onChanged: (value) {
                            _customSerials = value
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _loading ? null : () => Navigator.of(context).pop(),
                      child: const Text('انصراف'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _loading ? null : _generateCodes,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('تولید'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

