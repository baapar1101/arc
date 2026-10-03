import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../models/product_bundle.dart';
import '../../services/product_bundle_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../invoice/product_combobox_widget.dart';

Future<bool?> showProductBundleFormDialog({
  required BuildContext context,
  required int businessId,
  required AuthStore authStore,
  ProductBundle? bundle,
}) {
  return showGlassDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProductBundleFormDialog(
      businessId: businessId,
      authStore: authStore,
      bundle: bundle,
    ),
  );
}

class _BundleDraftItem {
  final Map<String, dynamic> product;
  final TextEditingController quantityController;

  _BundleDraftItem({required this.product, required num quantity})
    : quantityController = TextEditingController(
        text: _formatQuantity(quantity),
      );

  int get productId => _asInt(product['id']) ?? 0;

  void dispose() => quantityController.dispose();
}

class _ProductBundleFormDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final ProductBundle? bundle;

  const _ProductBundleFormDialog({
    required this.businessId,
    required this.authStore,
    this.bundle,
  });

  @override
  State<_ProductBundleFormDialog> createState() =>
      _ProductBundleFormDialogState();
}

class _ProductBundleFormDialogState extends State<_ProductBundleFormDialog> {
  final ProductBundleService _service = ProductBundleService();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late bool _isActive;
  late final List<_BundleDraftItem> _items;
  bool _saving = false;
  int _pickerRevision = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.bundle?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.bundle?.description ?? '',
    );
    _isActive = widget.bundle?.isActive ?? true;
    _items = (widget.bundle?.items ?? const <ProductBundleItem>[])
        .map(
          (item) =>
              _BundleDraftItem(product: item.product, quantity: item.quantity),
        )
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addProduct(Map<String, dynamic>? product) {
    if (product == null) return;
    final productId = _asInt(product['id']);
    if (productId == null) return;
    if (_items.any((item) => item.productId == productId)) {
      SnackBarHelper.show(
        context,
        message: 'این کالا قبلاً به باندل اضافه شده است.',
      );
      setState(() => _pickerRevision++);
      return;
    }
    setState(() {
      _items.add(_BundleDraftItem(product: product, quantity: 1));
      _pickerRevision++;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      SnackBarHelper.show(context, message: 'نام باندل را وارد کنید.');
      return;
    }
    if (_items.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'حداقل یک کالا به باندل اضافه کنید.',
      );
      return;
    }
    final requestItems = <Map<String, dynamic>>[];
    for (final item in _items) {
      final quantity = num.tryParse(
        toEnglishDigits(item.quantityController.text.trim()),
      );
      if (quantity == null || quantity <= 0) {
        SnackBarHelper.show(
          context,
          message: 'تعداد همهٔ کالاها باید بیشتر از صفر باشد.',
        );
        return;
      }
      requestItems.add({'product_id': item.productId, 'quantity': quantity});
    }

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'name': name,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'is_active': _isActive,
        'items': requestItems,
      };
      if (widget.bundle == null) {
        await _service.create(businessId: widget.businessId, payload: payload);
      } else {
        await _service.update(
          businessId: widget.businessId,
          bundleId: widget.bundle!.id,
          payload: payload,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(error, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.bundle == null ? 'باندل جدید' : 'ویرایش باندل'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: 'نام باندل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'توضیحات (اختیاری)',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('فعال'),
                subtitle: const Text(
                  'فقط باندل فعال را می‌توان به فاکتور افزود.',
                ),
                value: _isActive,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _isActive = value),
              ),
              const Divider(height: 28),
              Text('کالاهای باندل', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              ProductComboboxWidget(
                key: ValueKey(_pickerRevision),
                businessId: widget.businessId,
                authStore: widget.authStore,
                productsOnly: true,
                label: 'افزودن کالا',
                hintText: 'کالا را جست‌وجو و انتخاب کنید',
                onChanged: _addProduct,
              ),
              const SizedBox(height: 14),
              if (_items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'هنوز کالایی اضافه نشده است.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ..._items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final code = item.product['code']?.toString() ?? '';
                  final name = item.product['name']?.toString() ?? '';
                  final unit = item.product['main_unit']?.toString() ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              code.isEmpty ? name : '$code - $name',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: item.quantityController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: const [EnglishDigitsFormatter()],
                              decoration: InputDecoration(
                                labelText: unit.isEmpty
                                    ? 'تعداد'
                                    : 'تعداد ($unit)',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'حذف از باندل',
                            onPressed: _saving
                                ? null
                                : () {
                                    setState(() => _items.removeAt(index));
                                    item.dispose();
                                  },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('ذخیره'),
        ),
      ],
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _formatQuantity(num value) {
  if (value.remainder(1) == 0) return value.toInt().toString();
  return value.toString();
}
