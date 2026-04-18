import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/bom_models.dart';
import '../../services/bom_service.dart';
import '../../services/product_service.dart';
import '../invoice/product_combobox_widget.dart';
import '../invoice/warehouse_combobox_widget.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';

class BomEditorDialog extends StatefulWidget {
  final int businessId;
  final ProductBOM bom;

  const BomEditorDialog({super.key, required this.businessId, required this.bom});

  @override
  State<BomEditorDialog> createState() => _BomEditorDialogState();
}

class _BomEditorDialogState extends State<BomEditorDialog> with SingleTickerProviderStateMixin {
  late final BomService _service;
  late final ProductService _productService;
  final _formKey = GlobalKey<FormState>();

  // Header fields
  late TextEditingController _nameController;
  late TextEditingController _versionController;
  bool _isDefault = false;
  final TextEditingController _yieldController = TextEditingController();
  final TextEditingController _wastageController = TextEditingController();

  // Lines
  late List<BomItem> _items;
  late List<BomOutput> _outputs;
  late List<BomOperation> _operations;
  late List<Map<String, dynamic>?> _itemSelectedProducts;
  late List<Map<String, dynamic>?> _outputSelectedProducts;

  // Controllers for items
  final Map<int, TextEditingController> _itemQtyControllers = {};
  final Map<int, TextEditingController> _itemUomControllers = {};
  final Map<int, TextEditingController> _itemWastageControllers = {};
  final Map<int, TextEditingController> _itemSubstituteControllers = {};

  // Controllers for outputs
  final Map<int, TextEditingController> _outputRatioControllers = {};
  final Map<int, TextEditingController> _outputUomControllers = {};

  // Controllers for operations
  final Map<int, TextEditingController> _operationNameControllers = {};
  final Map<int, TextEditingController> _operationFixedControllers = {};
  final Map<int, TextEditingController> _operationPerUnitControllers = {};
  final Map<int, TextEditingController> _operationUomControllers = {};
  final Map<int, TextEditingController> _operationWorkCenterControllers = {};

  bool _saving = false;
  late TabController _tabController;
  int _itemsListKey = 0;
  int _outputsListKey = 0;
  int _operationsListKey = 0;

  @override
  void initState() {
    super.initState();
    _service = BomService();
    _productService = ProductService();
    _nameController = TextEditingController(text: widget.bom.name);
    _versionController = TextEditingController(text: widget.bom.version);
    _isDefault = widget.bom.isDefault;
    _yieldController.text = widget.bom.yieldPercent?.toString() ?? '';
    _wastageController.text = widget.bom.wastagePercent?.toString() ?? '';

    _items = List<BomItem>.from(widget.bom.items);
    _outputs = List<BomOutput>.from(widget.bom.outputs);
    _operations = List<BomOperation>.from(widget.bom.operations);
    _itemSelectedProducts = List<Map<String, dynamic>?>.filled(_items.length, null);
    _outputSelectedProducts = List<Map<String, dynamic>?>.filled(_outputs.length, null);
    _tabController = TabController(length: 3, vsync: this);
    
    // Initialize controllers for existing items
    _initializeItemControllers();
    _initializeOutputControllers();
    _initializeOperationControllers();
  }

  void _initializeItemControllers() {
    for (var i = 0; i < _items.length; i++) {
      _itemQtyControllers[i] = TextEditingController(text: _items[i].qtyPer.toString());
      _itemUomControllers[i] = TextEditingController(text: _items[i].uom ?? '');
      _itemWastageControllers[i] = TextEditingController(text: _items[i].wastagePercent?.toString() ?? '');
      _itemSubstituteControllers[i] = TextEditingController(text: _items[i].substituteGroup ?? '');
    }
  }

  void _initializeOutputControllers() {
    for (var i = 0; i < _outputs.length; i++) {
      _outputRatioControllers[i] = TextEditingController(text: _outputs[i].ratio.toString());
      _outputUomControllers[i] = TextEditingController(text: _outputs[i].uom ?? '');
    }
  }

  void _initializeOperationControllers() {
    for (var i = 0; i < _operations.length; i++) {
      _operationNameControllers[i] = TextEditingController(text: _operations[i].operationName);
      _operationFixedControllers[i] = TextEditingController(text: _operations[i].costFixed?.toString() ?? '');
      _operationPerUnitControllers[i] = TextEditingController(text: _operations[i].costPerUnit?.toString() ?? '');
      _operationUomControllers[i] = TextEditingController(text: _operations[i].costUom ?? '');
      _operationWorkCenterControllers[i] = TextEditingController(text: _operations[i].workCenter ?? '');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _versionController.dispose();
    _yieldController.dispose();
    _wastageController.dispose();
    _tabController.dispose();
    
    // Dispose all item controllers
    for (var controller in _itemQtyControllers.values) controller.dispose();
    for (var controller in _itemUomControllers.values) controller.dispose();
    for (var controller in _itemWastageControllers.values) controller.dispose();
    for (var controller in _itemSubstituteControllers.values) controller.dispose();
    
    // Dispose all output controllers
    for (var controller in _outputRatioControllers.values) controller.dispose();
    for (var controller in _outputUomControllers.values) controller.dispose();
    
    // Dispose all operation controllers
    for (var controller in _operationNameControllers.values) controller.dispose();
    for (var controller in _operationFixedControllers.values) controller.dispose();
    for (var controller in _operationPerUnitControllers.values) controller.dispose();
    for (var controller in _operationUomControllers.values) controller.dispose();
    for (var controller in _operationWorkCenterControllers.values) controller.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final isTablet = ResponsiveHelper.isTablet(context);
    
    return Dialog(
      insetPadding: ResponsiveHelper.getDialogPadding(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMobile ? 0 : 16),
      ),
      child: Container(
        constraints: ResponsiveHelper.getDialogConstraints(context),
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            _buildTabs(),
            Expanded(child: _buildTabViews()),
            const Divider(height: 1),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gradient header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune,
                color: theme.colorScheme.onPrimary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ویرایش فرمول تولید',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.bom.isDefault) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: 14,
                              color: theme.colorScheme.onPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'پیش‌فرض',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // Form fields
        Padding(
          padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResponsiveHelper.isMobile(context)
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: !_saving,
                            decoration: InputDecoration(
                              labelText: 'عنوان',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              prefixIcon: const Icon(Icons.title),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'لطفاً عنوان فرمول را وارد کنید';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
                          TextFormField(
                            controller: _versionController,
                            enabled: !_saving,
                            decoration: InputDecoration(
                              labelText: 'نسخه',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              prefixIcon: const Icon(Icons.tag),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'لطفاً نسخه را وارد کنید';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
                          Container(
                            padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isDefault
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                                width: _isDefault ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isDefault ? Icons.star : Icons.star_border,
                                  color: _isDefault
                                      ? Colors.orange
                                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text('پیش‌فرض'),
                                const SizedBox(width: 8),
                                Switch(
                                  value: _isDefault,
                                  onChanged: (v) => setState(() => _isDefault = v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nameController,
                              enabled: !_saving,
                              decoration: InputDecoration(
                                labelText: 'عنوان',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                prefixIcon: const Icon(Icons.title),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'لطفاً عنوان فرمول را وارد کنید';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
                          Expanded(
                            child: TextFormField(
                              controller: _versionController,
                              enabled: !_saving,
                              decoration: InputDecoration(
                                labelText: 'نسخه',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                prefixIcon: const Icon(Icons.tag),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'لطفاً نسخه را وارد کنید';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
                          Container(
                            padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isDefault
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                                width: _isDefault ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isDefault ? Icons.star : Icons.star_border,
                                  color: _isDefault
                                      ? Colors.orange
                                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text('پیش‌فرض'),
                                const SizedBox(width: 8),
                                Switch(
                                  value: _isDefault,
                                  onChanged: (v) => setState(() => _isDefault = v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
                ResponsiveHelper.isMobile(context)
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Tooltip(
                            message: 'درصد بازده کل فرمول تولید (0-100). این مقدار در محاسبه مقدار مواد اولیه مورد نیاز استفاده می‌شود.',
                            child: TextFormField(
                              controller: _yieldController,
                              enabled: !_saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                const EnglishDigitsFormatter(),
                                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                              ],
                              decoration: InputDecoration(
                                labelText: 'بازده کل (%)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                prefixIcon: const Icon(Icons.trending_up),
                              ),
                              validator: (value) {
                                if (value != null && value.trim().isNotEmpty) {
                                  final yield = double.tryParse(value.replaceAll(',', '.'));
                                  if (yield == null) {
                                    return 'مقدار نامعتبر';
                                  }
                                  if (yield < 0 || yield > 100) {
                                    return 'باید بین 0 تا 100 باشد';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
                          Tooltip(
                            message: 'درصد پرت کل فرمول تولید (0-100). این مقدار در محاسبه مقدار مواد اولیه مورد نیاز استفاده می‌شود.',
                            child: TextFormField(
                              controller: _wastageController,
                              enabled: !_saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                const EnglishDigitsFormatter(),
                                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                              ],
                              decoration: InputDecoration(
                                labelText: 'پرت کل (%)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                prefixIcon: const Icon(Icons.trending_down),
                              ),
                              validator: (value) {
                                if (value != null && value.trim().isNotEmpty) {
                                  final wastage = double.tryParse(value.replaceAll(',', '.'));
                                  if (wastage == null) {
                                    return 'مقدار نامعتبر';
                                  }
                                  if (wastage < 0 || wastage > 100) {
                                    return 'باید بین 0 تا 100 باشد';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: 'درصد بازده کل فرمول تولید (0-100). این مقدار در محاسبه مقدار مواد اولیه مورد نیاز استفاده می‌شود.',
                              child: TextFormField(
                                controller: _yieldController,
                                enabled: !_saving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  const EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'بازده کل (%)',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  prefixIcon: const Icon(Icons.trending_up),
                                ),
                                validator: (value) {
                                  if (value != null && value.trim().isNotEmpty) {
                                    final yield = double.tryParse(value.replaceAll(',', '.'));
                                    if (yield == null) {
                                      return 'مقدار نامعتبر';
                                    }
                                    if (yield < 0 || yield > 100) {
                                      return 'باید بین 0 تا 100 باشد';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
                          Expanded(
                            child: Tooltip(
                              message: 'درصد پرت کل فرمول تولید (0-100). این مقدار در محاسبه مقدار مواد اولیه مورد نیاز استفاده می‌شود.',
                              child: TextFormField(
                                controller: _wastageController,
                                enabled: !_saving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  const EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'پرت کل (%)',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  prefixIcon: const Icon(Icons.trending_down),
                                ),
                                validator: (value) {
                                  if (value != null && value.trim().isNotEmpty) {
                                    final wastage = double.tryParse(value.replaceAll(',', '.'));
                                    if (wastage == null) {
                                      return 'مقدار نامعتبر';
                                    }
                                    if (wastage < 0 || wastage > 100) {
                                      return 'باید بین 0 تا 100 باشد';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      tabs: [
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('مواد اولیه'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_items.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('خروجی‌ها'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_outputs.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('عملیات'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_operations.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabViews() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildItemsEditor(),
        _buildOutputsEditor(),
        _buildOperationsEditor(),
      ],
    );
  }

  void _addItemController(int index, BomItem item) {
    _itemQtyControllers[index] = TextEditingController(text: item.qtyPer.toString());
    _itemUomControllers[index] = TextEditingController(text: item.uom ?? '');
    _itemWastageControllers[index] = TextEditingController(text: item.wastagePercent?.toString() ?? '');
    _itemSubstituteControllers[index] = TextEditingController(text: item.substituteGroup ?? '');
  }

  void _removeItemController(int index) {
    _itemQtyControllers[index]?.dispose();
    _itemUomControllers[index]?.dispose();
    _itemWastageControllers[index]?.dispose();
    _itemSubstituteControllers[index]?.dispose();
    _itemQtyControllers.remove(index);
    _itemUomControllers.remove(index);
    _itemWastageControllers.remove(index);
    _itemSubstituteControllers.remove(index);
    
    // Reindex remaining controllers
    _reindexControllers(_itemQtyControllers, index);
    _reindexControllers(_itemUomControllers, index);
    _reindexControllers(_itemWastageControllers, index);
    _reindexControllers(_itemSubstituteControllers, index);
  }

  void _reindexControllers(Map<int, TextEditingController> controllers, int removedIndex) {
    if (removedIndex < 0 || controllers.isEmpty) {
      return; // index نامعتبر است یا لیست خالی است
    }
    
    // بررسی اینکه آیا index در محدوده معتبر است
    final maxKey = controllers.keys.isEmpty ? -1 : controllers.keys.reduce((a, b) => a > b ? a : b);
    if (removedIndex > maxKey) {
      return; // index خارج از محدوده است
    }
    
    final keys = controllers.keys.toList()..sort();
    final newMap = <int, TextEditingController>{};
    
    for (var oldKey in keys) {
      if (oldKey < removedIndex) {
        // کلیدهای قبل از index حذف شده بدون تغییر باقی می‌مانند
        newMap[oldKey] = controllers[oldKey]!;
      } else if (oldKey > removedIndex) {
        // کلیدهای بعد از index حذف شده باید یک واحد کاهش یابند
        newMap[oldKey - 1] = controllers[oldKey]!;
      }
      // oldKey == removedIndex را نادیده می‌گیریم (قبلاً dispose شده)
    }
    
    controllers.clear();
    controllers.addAll(newMap);
  }

  /// به‌روزرسانی line_no برای همه items
  List<BomItem> _updateItemsLineNos() {
    return _items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      if (item.lineNo != i + 1) {
        return BomItem(
          lineNo: i + 1,
          componentProductId: item.componentProductId,
          qtyPer: item.qtyPer,
          uom: item.uom,
          wastagePercent: item.wastagePercent,
          isOptional: item.isOptional,
          substituteGroup: item.substituteGroup,
          suggestedWarehouseId: item.suggestedWarehouseId,
        );
      }
      return item;
    }).toList();
  }

  /// به‌روزرسانی line_no برای همه outputs
  List<BomOutput> _updateOutputsLineNos() {
    return _outputs.asMap().entries.map((entry) {
      final i = entry.key;
      final output = entry.value;
      if (output.lineNo != i + 1) {
        return BomOutput(
          lineNo: i + 1,
          outputProductId: output.outputProductId,
          ratio: output.ratio,
          uom: output.uom,
          outputProductName: output.outputProductName,
          outputProductCode: output.outputProductCode,
        );
      }
      return output;
    }).toList();
  }

  /// به‌روزرسانی line_no برای همه operations
  List<BomOperation> _updateOperationsLineNos() {
    return _operations.asMap().entries.map((entry) {
      final i = entry.key;
      final op = entry.value;
      if (op.lineNo != i + 1) {
        return BomOperation(
          lineNo: i + 1,
          operationName: op.operationName,
          costFixed: op.costFixed,
          costPerUnit: op.costPerUnit,
          costUom: op.costUom,
          workCenter: op.workCenter,
        );
      }
      return op;
    }).toList();
  }

  void _addOutputController(int index, BomOutput output) {
    _outputRatioControllers[index] = TextEditingController(text: output.ratio.toString());
    _outputUomControllers[index] = TextEditingController(text: output.uom ?? '');
  }

  void _removeOutputController(int index) {
    _outputRatioControllers[index]?.dispose();
    _outputUomControllers[index]?.dispose();
    _outputRatioControllers.remove(index);
    _outputUomControllers.remove(index);
    _reindexControllers(_outputRatioControllers, index);
    _reindexControllers(_outputUomControllers, index);
  }

  void _addOperationController(int index, BomOperation operation) {
    _operationNameControllers[index] = TextEditingController(text: operation.operationName);
    _operationFixedControllers[index] = TextEditingController(text: operation.costFixed?.toString() ?? '');
    _operationPerUnitControllers[index] = TextEditingController(text: operation.costPerUnit?.toString() ?? '');
    _operationUomControllers[index] = TextEditingController(text: operation.costUom ?? '');
    _operationWorkCenterControllers[index] = TextEditingController(text: operation.workCenter ?? '');
  }

  void _removeOperationController(int index) {
    _operationNameControllers[index]?.dispose();
    _operationFixedControllers[index]?.dispose();
    _operationPerUnitControllers[index]?.dispose();
    _operationUomControllers[index]?.dispose();
    _operationWorkCenterControllers[index]?.dispose();
    _operationNameControllers.remove(index);
    _operationFixedControllers.remove(index);
    _operationPerUnitControllers.remove(index);
    _operationUomControllers.remove(index);
    _operationWorkCenterControllers.remove(index);
    _reindexControllers(_operationNameControllers, index);
    _reindexControllers(_operationFixedControllers, index);
    _reindexControllers(_operationPerUnitControllers, index);
    _reindexControllers(_operationUomControllers, index);
    _reindexControllers(_operationWorkCenterControllers, index);
  }

  Widget _buildItemsEditor() {
    final isMobile = ResponsiveHelper.isMobile(context);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
          child: Column(
            children: [
              if (!isMobile) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        final newIndex = _items.length;
                        final newLineNo = _items.isEmpty ? 1 : (_items.length + 1);
                        final newItem = BomItem(lineNo: newLineNo, componentProductId: -1, qtyPer: 1);
                        
                        // افزودن به لیست‌ها
                        _items = [..._items, newItem];
                        _itemSelectedProducts = [..._itemSelectedProducts, null];
                        
                        // افزودن کنترلرها بعد از افزودن به لیست
                        _addItemController(newIndex, newItem);
                        
                        // به‌روزرسانی key برای rebuild ListView
                        _itemsListKey++;
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن سطر مواد'),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
              ],
              Expanded(
                child: _items.isEmpty
                    ? _buildEmptyState(
                        context,
                        icon: Icons.inventory_2,
                        title: 'هیچ ماده اولیه‌ای تعریف نشده',
                        message: isMobile 
                            ? 'برای افزودن مواد اولیه، روی دکمه + در پایین صفحه کلیک کنید.'
                            : 'برای افزودن مواد اولیه مورد نیاز برای تولید، روی دکمه "افزودن سطر مواد" کلیک کنید.',
                      )
                    : ListView.separated(
                        key: ValueKey('items_list_$_itemsListKey'),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
                        itemBuilder: (context, index) {
                      final it = _items[index];
                      final actualLineNo = index + 1;
                      
                      // Debug log
                      debugPrint('BOM Editor: Building item at index $index, lineNo: ${it.lineNo}, actualLineNo: $actualLineNo, controllers keys: ${_itemQtyControllers.keys.toList()}');
                      
                      // Ensure controllers exist
                      if (!_itemQtyControllers.containsKey(index)) {
                        debugPrint('BOM Editor: Creating controllers for index $index');
                        _addItemController(index, it);
                      }
                      
                      final qtyCtrl = _itemQtyControllers[index]!;
                      final uomCtrl = _itemUomControllers[index]!;
                      final wastCtrl = _itemWastageControllers[index]!;
                      final substCtrl = _itemSubstituteControllers[index]!;
                      
                      final isValid = it.componentProductId > 0 && it.qtyPer > 0;
                      final isMobile = ResponsiveHelper.isMobile(context);
                      
                      Widget rowContent = isMobile
                          ? _buildMobileItemCard(context, index, it, actualLineNo, qtyCtrl, uomCtrl, wastCtrl, substCtrl, isValid)
                          : _buildDesktopItemRow(context, index, it, actualLineNo, qtyCtrl, uomCtrl, wastCtrl, substCtrl, isValid);
                      
                      return Dismissible(
                        key: ValueKey('item_$index'),
                        direction: isMobile ? DismissDirection.endToStart : DismissDirection.horizontal,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white, size: 32),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('تأیید حذف'),
                              content: const Text('آیا از حذف این سطر اطمینان دارید؟'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('انصراف'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('حذف'),
                                ),
                              ],
                            ),
                          ) ?? false;
                        },
                        onDismissed: (direction) {
                          setState(() {
                            _itemQtyControllers[index]?.dispose();
                            _itemUomControllers[index]?.dispose();
                            _itemWastageControllers[index]?.dispose();
                            _itemSubstituteControllers[index]?.dispose();
                            _itemQtyControllers.remove(index);
                            _itemUomControllers.remove(index);
                            _itemWastageControllers.remove(index);
                            _itemSubstituteControllers.remove(index);
                            _items.removeAt(index);
                            _itemSelectedProducts.removeAt(index);
                            _reindexControllers(_itemQtyControllers, index);
                            _reindexControllers(_itemUomControllers, index);
                            _reindexControllers(_itemWastageControllers, index);
                            _reindexControllers(_itemSubstituteControllers, index);
                            _itemsListKey++;
                          });
                        },
                        child: rowContent,
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
        if (isMobile)
          Positioned(
            bottom: ResponsiveHelper.getPadding(context),
            right: ResponsiveHelper.getPadding(context),
            child: FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  final newIndex = _items.length;
                  final newLineNo = _items.isEmpty ? 1 : (_items.length + 1);
                  final newItem = BomItem(lineNo: newLineNo, componentProductId: -1, qtyPer: 1);
                  
                  _items = [..._items, newItem];
                  _itemSelectedProducts = [..._itemSelectedProducts, null];
                  _addItemController(newIndex, newItem);
                  _itemsListKey++;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('افزودن'),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileItemCard(BuildContext context, int index, BomItem it, int actualLineNo,
      TextEditingController qtyCtrl, TextEditingController uomCtrl, 
      TextEditingController wastCtrl, TextEditingController substCtrl, bool isValid) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.all(ResponsiveHelper.getGridSpacing(context)),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isValid 
            ? BorderSide.none 
            : BorderSide(color: Colors.red.shade300, width: 2),
      ),
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (!isValid) ...[
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'ردیف $actualLineNo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _itemQtyControllers[index]?.dispose();
                      _itemUomControllers[index]?.dispose();
                      _itemWastageControllers[index]?.dispose();
                      _itemSubstituteControllers[index]?.dispose();
                      _itemQtyControllers.remove(index);
                      _itemUomControllers.remove(index);
                      _itemWastageControllers.remove(index);
                      _itemSubstituteControllers.remove(index);
                      _items.removeAt(index);
                      _itemSelectedProducts.removeAt(index);
                      _reindexControllers(_itemQtyControllers, index);
                      _reindexControllers(_itemUomControllers, index);
                      _reindexControllers(_itemWastageControllers, index);
                      _reindexControllers(_itemSubstituteControllers, index);
                      _itemsListKey++;
                    });
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            ProductComboboxWidget(
              businessId: widget.businessId,
              selectedProduct: _itemSelectedProducts[index],
              label: 'کالا',
              hintText: 'جست‌وجوی کالا',
              onChanged: (product) {
                setState(() {
                  _itemSelectedProducts[index] = product;
                  if (product != null) {
                    final pid = product['id'] as int?;
                    if (pid != null) {
                      if (pid == widget.bom.productId) {
                        SnackBarHelper.showError(
                          context,
                          message: 'کالا نمی‌تواند برای خودش به عنوان ماده اولیه استفاده شود',
                        );
                        _itemSelectedProducts[index] = null;
                        _updateItem(index, componentProductId: -1);
                        return;
                      }
                      final mainUnit = product['main_unit']?.toString();
                      final currentUom = _items[index].uom;
                      final newUom = (currentUom == null || currentUom.isEmpty) && mainUnit != null && mainUnit.isNotEmpty
                          ? mainUnit
                          : currentUom;
                      _updateItem(index, componentProductId: pid, uom: newUom);
                    } else {
                      _updateItem(index, componentProductId: -1);
                    }
                  } else {
                    _updateItem(index, componentProductId: -1);
                  }
                });
              },
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'مقدار',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _updateItem(index, qtyPer: double.tryParse(v)),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
                Expanded(
                  child: _buildUnitDropdown(
                    index,
                    _itemSelectedProducts[index],
                    uomCtrl,
                    (v) => _updateItem(index, uom: v),
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            TextField(
              controller: wastCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'پرت (%)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _updateItem(index, wastagePercent: double.tryParse(v)),
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            TextField(
              controller: substCtrl,
              decoration: const InputDecoration(
                labelText: 'گروه جایگزین',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _updateItem(index, substituteGroup: v.isEmpty ? null : v),
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            WarehouseComboboxWidget(
              businessId: widget.businessId,
              selectedWarehouseId: it.suggestedWarehouseId,
              label: 'انبار پیشنهادی',
              hintText: 'انتخاب انبار',
              onChanged: (warehouseId) => _updateItem(index, suggestedWarehouseId: warehouseId),
              selectDefaultWhenUnset: true,
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            Row(
              children: [
                Checkbox(
                  value: it.isOptional,
                  onChanged: (v) => _updateItem(index, isOptional: v ?? false),
                ),
                const Text('اختیاری'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopItemRow(BuildContext context, int index, BomItem it, int actualLineNo,
      TextEditingController qtyCtrl, TextEditingController uomCtrl, 
      TextEditingController wastCtrl, TextEditingController substCtrl, bool isValid) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
      child: Row(
        children: [
          // ستون 1: Warning icon (اگر نامعتبر)
          if (!isValid) ...[
            Tooltip(
              message: 'این سطر نامعتبر است: کالا باید انتخاب شود و مقدار باید بزرگ‌تر از صفر باشد',
              child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
            ),
            SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          ],
          // ستون 2: شماره ردیف
          SizedBox(
            width: 60,
            child: Tooltip(
              message: 'شماره ردیف به صورت خودکار تنظیم می‌شود',
              child: Text('ردیف $actualLineNo'),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 3: کالا
          Expanded(
            flex: 2,
            child: ProductComboboxWidget(
              businessId: widget.businessId,
              selectedProduct: _itemSelectedProducts[index],
              label: 'کالا',
              hintText: 'جست‌وجوی کالا',
              onChanged: (product) {
                setState(() {
                  _itemSelectedProducts[index] = product;
                  if (product != null) {
                    final pid = product['id'] as int?;
                    if (pid != null) {
                      // بررسی وابستگی چرخه‌ای
                      if (pid == widget.bom.productId) {
                        SnackBarHelper.showError(
                          context,
                          message: 'کالا نمی‌تواند برای خودش به عنوان ماده اولیه استفاده شود',
                        );
                        _itemSelectedProducts[index] = null;
                        _updateItem(index, componentProductId: -1);
                        return;
                      }
                      final mainUnit = product['main_unit']?.toString();
                      final currentUom = _items[index].uom;
                      final newUom = (currentUom == null || currentUom.isEmpty) && mainUnit != null && mainUnit.isNotEmpty
                          ? mainUnit
                          : currentUom;
                      _updateItem(index, componentProductId: pid, uom: newUom);
                    } else {
                      _updateItem(index, componentProductId: -1);
                    }
                  } else {
                    _updateItem(index, componentProductId: -1);
                  }
                });
              },
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 4: مقدار
          Expanded(
            child: Tooltip(
              message: 'مقدار این کالا برای تولید 1 واحد محصول نهایی',
              child: TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'مقدار',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateItem(index, qtyPer: double.tryParse(v)),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 5: واحد
          Expanded(
            child: _buildUnitDropdown(
              index,
              _itemSelectedProducts[index],
              uomCtrl,
              (v) => _updateItem(index, uom: v),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 6: پرت %
          Expanded(
            child: Tooltip(
              message: 'درصد پرت این کالا در فرآیند تولید (0-100)',
              child: TextField(
                controller: wastCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'پرت (%)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateItem(index, wastagePercent: double.tryParse(v)),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 7: گروه جایگزین
          Expanded(
            child: Tooltip(
              message: 'گروه جایگزین: کالاهای با گروه یکسان می‌توانند جایگزین یکدیگر شوند',
              child: TextField(
                controller: substCtrl,
                decoration: const InputDecoration(
                  labelText: 'گروه جایگزین',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateItem(index, substituteGroup: v.isEmpty ? null : v),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 8: انبار پیشنهادی
          Expanded(
            child: Tooltip(
              message: 'انبار پیشنهادی برای برداشت این ماده اولیه در سند تولید',
              child: WarehouseComboboxWidget(
                businessId: widget.businessId,
                selectedWarehouseId: it.suggestedWarehouseId,
                label: 'انبار پیشنهادی',
                hintText: 'انتخاب انبار',
                onChanged: (warehouseId) => _updateItem(index, suggestedWarehouseId: warehouseId),
                selectDefaultWhenUnset: true,
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 9: اختیاری
          Tooltip(
            message: 'اگر فعال باشد، این ماده اولیه اختیاری است و می‌تواند در تولید استفاده نشود',
            child: Checkbox(
              value: it.isOptional,
              onChanged: (v) => _updateItem(index, isOptional: v ?? false),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 10: دکمه حذف
          IconButton(
            onPressed: () {
              setState(() {
                _itemQtyControllers[index]?.dispose();
                _itemUomControllers[index]?.dispose();
                _itemWastageControllers[index]?.dispose();
                _itemSubstituteControllers[index]?.dispose();
                _itemQtyControllers.remove(index);
                _itemUomControllers.remove(index);
                _itemWastageControllers.remove(index);
                _itemSubstituteControllers.remove(index);
                _items.removeAt(index);
                _itemSelectedProducts.removeAt(index);
                _reindexControllers(_itemQtyControllers, index);
                _reindexControllers(_itemUomControllers, index);
                _reindexControllers(_itemWastageControllers, index);
                _reindexControllers(_itemSubstituteControllers, index);
                _itemsListKey++;
              });
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: 'حذف سطر',
          ),
        ],
      ),
    );
  }

  Widget _buildOutputsEditor() {
    final isMobile = ResponsiveHelper.isMobile(context);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
          child: Column(
            children: [
              if (!isMobile) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        final newIndex = _outputs.length;
                        final newLineNo = _outputs.isEmpty ? 1 : (_outputs.length + 1);
                        final newOutput = BomOutput(lineNo: newLineNo, outputProductId: -1, ratio: 1);
                        _outputs = [..._outputs, newOutput];
                        _outputSelectedProducts = [..._outputSelectedProducts, null];
                        _addOutputController(newIndex, newOutput);
                        _outputsListKey++;
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن سطر خروجی'),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
              ],
              Expanded(
                child: _outputs.isEmpty
                    ? _buildEmptyState(
                        context,
                        icon: Icons.output,
                        title: 'هیچ محصول خروجی‌ای تعریف نشده',
                        message: isMobile 
                            ? 'برای افزودن محصول خروجی، روی دکمه + در پایین صفحه کلیک کنید.'
                            : 'برای افزودن محصولات خروجی تولید، روی دکمه "افزودن سطر خروجی" کلیک کنید.',
                      )
                    : ListView.separated(
                        key: ValueKey('outputs_list_$_outputsListKey'),
                        itemCount: _outputs.length,
                        separatorBuilder: (context, index) => SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
                        itemBuilder: (context, index) {
                          final ot = _outputs[index];
                          final actualLineNo = index + 1;
                          
                          // Ensure controllers exist
                          if (!_outputRatioControllers.containsKey(index)) {
                            _addOutputController(index, ot);
                          }
                          
                          final ratioCtrl = _outputRatioControllers[index]!;
                          final uomCtrl = _outputUomControllers[index]!;
                          final isValid = ot.outputProductId > 0 && ot.ratio > 0;
                          
                          Widget rowContent = isMobile
                              ? _buildMobileOutputCard(context, index, ot, actualLineNo, ratioCtrl, uomCtrl, isValid)
                              : _buildDesktopOutputRow(context, index, ot, actualLineNo, ratioCtrl, uomCtrl, isValid);
                          
                          return Dismissible(
                            key: ValueKey('output_$index'),
                            direction: isMobile ? DismissDirection.endToStart : DismissDirection.horizontal,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.delete, color: Colors.white, size: 32),
                            ),
                            confirmDismiss: (direction) async {
                              return await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('تأیید حذف'),
                                  content: const Text('آیا از حذف این سطر اطمینان دارید؟'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('انصراف'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('حذف'),
                                    ),
                                  ],
                                ),
                              ) ?? false;
                            },
                            onDismissed: (direction) {
                              setState(() {
                                _outputRatioControllers[index]?.dispose();
                                _outputUomControllers[index]?.dispose();
                                _outputRatioControllers.remove(index);
                                _outputUomControllers.remove(index);
                                _outputs.removeAt(index);
                                _outputSelectedProducts.removeAt(index);
                                _reindexControllers(_outputRatioControllers, index);
                                _reindexControllers(_outputUomControllers, index);
                                _outputsListKey++;
                              });
                            },
                            child: rowContent,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        if (isMobile)
          Positioned(
            bottom: ResponsiveHelper.getPadding(context),
            right: ResponsiveHelper.getPadding(context),
            child: FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  final newIndex = _outputs.length;
                  final newLineNo = _outputs.isEmpty ? 1 : (_outputs.length + 1);
                  final newOutput = BomOutput(lineNo: newLineNo, outputProductId: -1, ratio: 1);
                  _outputs = [..._outputs, newOutput];
                  _outputSelectedProducts = [..._outputSelectedProducts, null];
                  _addOutputController(newIndex, newOutput);
                  _outputsListKey++;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('افزودن'),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileOutputCard(BuildContext context, int index, BomOutput ot, int actualLineNo,
      TextEditingController ratioCtrl, TextEditingController uomCtrl, bool isValid) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.all(ResponsiveHelper.getGridSpacing(context)),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isValid 
            ? BorderSide.none 
            : BorderSide(color: Colors.red.shade300, width: 2),
      ),
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (!isValid) ...[
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'ردیف $actualLineNo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _outputRatioControllers[index]?.dispose();
                      _outputUomControllers[index]?.dispose();
                      _outputRatioControllers.remove(index);
                      _outputUomControllers.remove(index);
                      _outputs.removeAt(index);
                      _outputSelectedProducts.removeAt(index);
                      _reindexControllers(_outputRatioControllers, index);
                      _reindexControllers(_outputUomControllers, index);
                      _outputsListKey++;
                    });
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            ProductComboboxWidget(
              businessId: widget.businessId,
              selectedProduct: _outputSelectedProducts[index],
              label: 'محصول خروجی',
              hintText: 'جست‌وجوی محصول خروجی',
              onChanged: (product) {
                setState(() {
                  _outputSelectedProducts[index] = product;
                  if (product != null) {
                    final pid = product['id'] as int?;
                    if (pid != null) {
                      final mainUnit = product['main_unit']?.toString();
                      final currentUom = _outputs[index].uom;
                      final newUom = (currentUom == null || currentUom.isEmpty) && mainUnit != null && mainUnit.isNotEmpty
                          ? mainUnit
                          : currentUom;
                      _updateOutput(index, outputProductId: pid, uom: newUom);
                    } else {
                      _updateOutput(index, outputProductId: -1);
                    }
                  } else {
                    _updateOutput(index, outputProductId: -1);
                  }
                });
              },
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ratioCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'نسبت',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _updateOutput(index, ratio: double.tryParse(v)),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
                Expanded(
                  child: _buildUnitDropdown(
                    index,
                    _outputSelectedProducts[index],
                    uomCtrl,
                    (v) => _updateOutput(index, uom: v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopOutputRow(BuildContext context, int index, BomOutput ot, int actualLineNo,
      TextEditingController ratioCtrl, TextEditingController uomCtrl, bool isValid) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
      child: Row(
        children: [
          // ستون 1: Warning icon (اگر نامعتبر)
          if (!isValid) ...[
            Tooltip(
              message: 'این سطر نامعتبر است: محصول خروجی باید انتخاب شود و نسبت باید بزرگ‌تر از صفر باشد',
              child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
            ),
            SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          ],
          // ستون 2: شماره ردیف
          SizedBox(
            width: 60,
            child: Tooltip(
              message: 'شماره ردیف به صورت خودکار تنظیم می‌شود',
              child: Text('ردیف $actualLineNo'),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 3: محصول خروجی
          Expanded(
            flex: 2,
            child: ProductComboboxWidget(
              businessId: widget.businessId,
              selectedProduct: _outputSelectedProducts[index],
              label: 'محصول خروجی',
              hintText: 'جست‌وجوی محصول خروجی',
              onChanged: (product) {
                setState(() {
                  _outputSelectedProducts[index] = product;
                  if (product != null) {
                    final pid = product['id'] as int?;
                    if (pid != null) {
                      final mainUnit = product['main_unit']?.toString();
                      final currentUom = _outputs[index].uom;
                      final newUom = (currentUom == null || currentUom.isEmpty) && mainUnit != null && mainUnit.isNotEmpty
                          ? mainUnit
                          : currentUom;
                      _updateOutput(index, outputProductId: pid, uom: newUom);
                    } else {
                      _updateOutput(index, outputProductId: -1);
                    }
                  } else {
                    _updateOutput(index, outputProductId: -1);
                  }
                });
              },
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 4: نسبت
          Expanded(
            child: Tooltip(
              message: 'نسبت خروجی این محصول به ازای هر واحد تولید',
              child: TextField(
                controller: ratioCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'نسبت',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateOutput(index, ratio: double.tryParse(v)),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 5: واحد
          Expanded(
            child: _buildUnitDropdown(
              index,
              _outputSelectedProducts[index],
              uomCtrl,
              (v) => _updateOutput(index, uom: v),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 6: دکمه حذف
          IconButton(
            onPressed: () {
              setState(() {
                _outputRatioControllers[index]?.dispose();
                _outputUomControllers[index]?.dispose();
                _outputRatioControllers.remove(index);
                _outputUomControllers.remove(index);
                _outputs.removeAt(index);
                _outputSelectedProducts.removeAt(index);
                _reindexControllers(_outputRatioControllers, index);
                _reindexControllers(_outputUomControllers, index);
                _outputsListKey++;
              });
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: 'حذف سطر',
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsEditor() {
    final isMobile = ResponsiveHelper.isMobile(context);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
          child: Column(
            children: [
              if (!isMobile) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        final newIndex = _operations.length;
                        final newLineNo = _operations.isEmpty ? 1 : (_operations.length + 1);
                        final newOperation = BomOperation(lineNo: newLineNo, operationName: '');
                        
                        _operations = [..._operations, newOperation];
                        _addOperationController(newIndex, newOperation);
                        _operationsListKey++;
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن عملیات'),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
              ],
              Expanded(
                child: _operations.isEmpty
                    ? _buildEmptyState(
                        context,
                        icon: Icons.build,
                        title: 'هیچ عملیاتی تعریف نشده',
                        message: isMobile 
                            ? 'برای افزودن عملیات، روی دکمه + در پایین صفحه کلیک کنید.'
                            : 'برای افزودن عملیات تولیدی (مثل برش، جوشکاری و ...)، روی دکمه "افزودن عملیات" کلیک کنید.',
                      )
                    : ListView.separated(
                        key: ValueKey('operations_list_$_operationsListKey'),
                        itemCount: _operations.length,
                        separatorBuilder: (context, index) => SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
                        itemBuilder: (context, index) {
                          final op = _operations[index];
                          final actualLineNo = index + 1;
                          
                          // Ensure controllers exist
                          if (!_operationNameControllers.containsKey(index)) {
                            _addOperationController(index, op);
                          }
                          
                          final nameCtrl = _operationNameControllers[index]!;
                          final fixedCtrl = _operationFixedControllers[index]!;
                          final perCtrl = _operationPerUnitControllers[index]!;
                          final uomCtrl = _operationUomControllers[index]!;
                          final wcCtrl = _operationWorkCenterControllers[index]!;
                          
                          Widget rowContent = isMobile
                              ? _buildMobileOperationCard(context, index, op, actualLineNo, nameCtrl, fixedCtrl, perCtrl, uomCtrl, wcCtrl)
                              : _buildDesktopOperationRow(context, index, op, actualLineNo, nameCtrl, fixedCtrl, perCtrl, uomCtrl, wcCtrl);
                          
                          return Dismissible(
                            key: ValueKey('operation_$index'),
                            direction: isMobile ? DismissDirection.endToStart : DismissDirection.horizontal,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.delete, color: Colors.white, size: 32),
                            ),
                            confirmDismiss: (direction) async {
                              return await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('تأیید حذف'),
                                  content: const Text('آیا از حذف این سطر اطمینان دارید؟'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('انصراف'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('حذف'),
                                    ),
                                  ],
                                ),
                              ) ?? false;
                            },
                            onDismissed: (direction) {
                              setState(() {
                                _operationNameControllers[index]?.dispose();
                                _operationFixedControllers[index]?.dispose();
                                _operationPerUnitControllers[index]?.dispose();
                                _operationUomControllers[index]?.dispose();
                                _operationWorkCenterControllers[index]?.dispose();
                                _operationNameControllers.remove(index);
                                _operationFixedControllers.remove(index);
                                _operationPerUnitControllers.remove(index);
                                _operationUomControllers.remove(index);
                                _operationWorkCenterControllers.remove(index);
                                _operations.removeAt(index);
                                _reindexControllers(_operationNameControllers, index);
                                _reindexControllers(_operationFixedControllers, index);
                                _reindexControllers(_operationPerUnitControllers, index);
                                _reindexControllers(_operationUomControllers, index);
                                _reindexControllers(_operationWorkCenterControllers, index);
                                _operationsListKey++;
                              });
                            },
                            child: rowContent,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        if (isMobile)
          Positioned(
            bottom: ResponsiveHelper.getPadding(context),
            right: ResponsiveHelper.getPadding(context),
            child: FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  final newIndex = _operations.length;
                  final newLineNo = _operations.isEmpty ? 1 : (_operations.length + 1);
                  final newOperation = BomOperation(lineNo: newLineNo, operationName: '');
                  
                  _operations = [..._operations, newOperation];
                  _addOperationController(newIndex, newOperation);
                  _operationsListKey++;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('افزودن'),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileOperationCard(BuildContext context, int index, BomOperation op, int actualLineNo,
      TextEditingController nameCtrl, TextEditingController fixedCtrl, TextEditingController perCtrl,
      TextEditingController uomCtrl, TextEditingController wcCtrl) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.all(ResponsiveHelper.getGridSpacing(context)),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ردیف $actualLineNo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _operationNameControllers[index]?.dispose();
                      _operationFixedControllers[index]?.dispose();
                      _operationPerUnitControllers[index]?.dispose();
                      _operationUomControllers[index]?.dispose();
                      _operationWorkCenterControllers[index]?.dispose();
                      _operationNameControllers.remove(index);
                      _operationFixedControllers.remove(index);
                      _operationPerUnitControllers.remove(index);
                      _operationUomControllers.remove(index);
                      _operationWorkCenterControllers.remove(index);
                      _operations.removeAt(index);
                      _reindexControllers(_operationNameControllers, index);
                      _reindexControllers(_operationFixedControllers, index);
                      _reindexControllers(_operationPerUnitControllers, index);
                      _reindexControllers(_operationUomControllers, index);
                      _reindexControllers(_operationWorkCenterControllers, index);
                      _operationsListKey++;
                    });
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'نام عملیات',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _updateOperation(index, operationName: v),
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fixedCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'هزینه ثابت',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _updateOperation(index, costFixed: double.tryParse(v)),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
                Expanded(
                  child: TextField(
                    controller: perCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'هزینه واحد',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _updateOperation(index, costPerUnit: double.tryParse(v)),
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            TextField(
              controller: uomCtrl,
              decoration: const InputDecoration(
                labelText: 'واحد هزینه',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _updateOperation(index, costUom: v.isEmpty ? null : v),
            ),
            SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
            TextField(
              controller: wcCtrl,
              decoration: const InputDecoration(
                labelText: 'ایستگاه کاری',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _updateOperation(index, workCenter: v.isEmpty ? null : v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopOperationRow(BuildContext context, int index, BomOperation op, int actualLineNo,
      TextEditingController nameCtrl, TextEditingController fixedCtrl, TextEditingController perCtrl,
      TextEditingController uomCtrl, TextEditingController wcCtrl) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
      child: Row(
        children: [
          // ستون 1: شماره ردیف
          SizedBox(
            width: 60,
            child: Tooltip(
              message: 'شماره ردیف به صورت خودکار تنظیم می‌شود',
              child: Text('ردیف $actualLineNo'),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 2: نام عملیات
          Expanded(
            flex: 2,
            child: Tooltip(
              message: 'نام عملیات تولیدی (مثال: برش، جوشکاری، رنگ‌آمیزی)',
              child: TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'نام عملیات',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateOperation(index, operationName: v),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 3: هزینه ثابت
          Expanded(
            child: Tooltip(
              message: 'هزینه ثابت عملیات (در حال حاضر در تولید سند حسابداری استفاده نمی‌شود)',
              child: TextField(
                controller: fixedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'هزینه ثابت',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateOperation(index, costFixed: double.tryParse(v)),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 4: هزینه واحد
          Expanded(
            child: Tooltip(
              message: 'هزینه به ازای هر واحد (در حال حاضر در تولید سند حسابداری استفاده نمی‌شود)',
              child: TextField(
                controller: perCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'هزینه واحد',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateOperation(index, costPerUnit: double.tryParse(v)),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 5: واحد هزینه
          Expanded(
            child: Tooltip(
              message: 'واحد هزینه (در حال حاضر در تولید سند حسابداری استفاده نمی‌شود)',
              child: TextField(
                controller: uomCtrl,
                decoration: const InputDecoration(
                  labelText: 'واحد هزینه',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateOperation(index, costUom: v.isEmpty ? null : v),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 6: ایستگاه کاری
          Expanded(
            child: Tooltip(
              message: 'ایستگاه کاری یا بخش انجام عملیات (فقط برای اطلاعات)',
              child: TextField(
                controller: wcCtrl,
                decoration: const InputDecoration(
                  labelText: 'ایستگاه کاری',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _updateOperation(index, workCenter: v.isEmpty ? null : v),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
          // ستون 7: دکمه حذف
          IconButton(
            onPressed: () {
              setState(() {
                _operationNameControllers[index]?.dispose();
                _operationFixedControllers[index]?.dispose();
                _operationPerUnitControllers[index]?.dispose();
                _operationUomControllers[index]?.dispose();
                _operationWorkCenterControllers[index]?.dispose();
                _operationNameControllers.remove(index);
                _operationFixedControllers.remove(index);
                _operationPerUnitControllers.remove(index);
                _operationUomControllers.remove(index);
                _operationWorkCenterControllers.remove(index);
                _operations.removeAt(index);
                _reindexControllers(_operationNameControllers, index);
                _reindexControllers(_operationFixedControllers, index);
                _reindexControllers(_operationPerUnitControllers, index);
                _reindexControllers(_operationUomControllers, index);
                _reindexControllers(_operationWorkCenterControllers, index);
                _operationsListKey++;
              });
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: 'حذف سطر',
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.getPadding(context)),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                        : const Icon(Icons.save),
                    label: const Text('ذخیره'),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.getGridSpacing(context)),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('انصراف'),
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('انصراف'),
                ),
                SizedBox(width: ResponsiveHelper.getGridSpacing(context)),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                      : const Icon(Icons.save),
                  label: const Text('ذخیره'),
                ),
              ],
            ),
    );
  }

  Widget _num(TextEditingController c, String label, void Function(String) onChanged, {String? Function(String?)? validator}) {
    return Expanded(
      child: TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          EnglishDigitsFormatter(),
          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorMaxLines: 2,
        ),
        validator: validator,
        onChanged: (value) {
          if (validator != null) {
            // Trigger validation on change
            validator(value);
          }
          onChanged(value);
        },
      ),
    );
  }

  Widget _numWithTooltip(TextEditingController c, String label, String tooltip, void Function(String) onChanged, {String? Function(String?)? validator, double? min, double? max}) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: TextFormField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            EnglishDigitsFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            errorMaxLines: 2,
          ),
          validator: validator ?? (value) {
            if (value == null || value.trim().isEmpty) return null;
            final num = double.tryParse(value.replaceAll(',', '.'));
            if (num == null) return 'مقدار نامعتبر';
            if (min != null && num < min) return 'حداقل مقدار: $min';
            if (max != null && num > max) return 'حداکثر مقدار: $max';
            return null;
          },
          onChanged: (value) {
            // اعتبارسنجی خودکار انجام می‌شود از طریق validator
            onChanged(value);
          },
        ),
      ),
    );
  }

  Widget _text(TextEditingController c, String label, void Function(String) onChanged) {
    return Expanded(
      child: TextField(
        controller: c,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: onChanged,
      ),
    );
  }

  Widget _textWithTooltip(TextEditingController c, String label, String tooltip, void Function(String) onChanged) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildUnitDropdown(int index, Map<String, dynamic>? selectedProduct, TextEditingController uomController, void Function(String?) onChanged) {
    // دریافت واحدهای کالای انتخاب شده
    final mainUnit = selectedProduct?['main_unit']?.toString();
    final secondaryUnit = selectedProduct?['secondary_unit']?.toString();
    final currentUom = uomController.text;
    
    // ساخت لیست واحدهای موجود
    final Set<String> units = {};
    if (mainUnit != null && mainUnit.isNotEmpty) {
      units.add(mainUnit);
    }
    if (secondaryUnit != null && secondaryUnit.isNotEmpty) {
      units.add(secondaryUnit);
    }
    
    // اگر واحد انتخاب شده موجود است اما در لیست نیست، آن را اضافه کن
    if (currentUom.isNotEmpty && !units.contains(currentUom)) {
      units.add(currentUom);
    }
    
    // تبدیل به لیست مرتب شده
    final sortedUnits = units.toList()..sort();
    
    // اگر هیچ واحدی موجود نبود، از فیلد متنی استفاده می‌کنیم
    if (sortedUnits.isEmpty) {
      // استفاده از TextField با controller
      return Expanded(
        child: TextField(
          controller: uomController,
          decoration: const InputDecoration(
            labelText: 'واحد',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => onChanged(v.isEmpty ? null : v),
        ),
      );
    }
    
    return Expanded(
      child: Tooltip(
        message: 'واحد اندازه‌گیری کالا (واحد اصلی و فرعی)',
        child: DropdownButtonFormField<String?>(
          value: currentUom.isEmpty ? null : currentUom,
          decoration: const InputDecoration(
            labelText: 'واحد',
            border: OutlineInputBorder(),
          ),
          items: [
            // گزینه خالی برای حذف واحد
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('بدون واحد'),
            ),
            // واحدهای موجود
            ...sortedUnits.map((unit) => DropdownMenuItem<String?>(
              value: unit,
              child: Text(unit),
            )),
          ],
          onChanged: (v) {
            uomController.text = v ?? '';
            onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required IconData icon, required String title, required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateItem(int index, {int? lineNo, int? componentProductId, double? qtyPer, String? uom, double? wastagePercent, String? substituteGroup, bool? isOptional, int? suggestedWarehouseId}) {
    if (index >= _items.length) {
      return;
    }
    final current = _items[index];
    setState(() {
      _items[index] = BomItem(
        lineNo: lineNo ?? current.lineNo,
        componentProductId: componentProductId != null ? componentProductId : current.componentProductId,
        qtyPer: qtyPer ?? current.qtyPer,
        uom: uom ?? current.uom,
        wastagePercent: wastagePercent ?? current.wastagePercent,
        isOptional: isOptional ?? current.isOptional,
        substituteGroup: substituteGroup ?? current.substituteGroup,
        suggestedWarehouseId: suggestedWarehouseId ?? current.suggestedWarehouseId,
      );
    });
  }

  void _updateOutput(int index, {int? lineNo, int? outputProductId, double? ratio, String? uom}) {
    if (index >= _outputs.length) {
      return;
    }
    final current = _outputs[index];
    setState(() {
      _outputs[index] = BomOutput(
        lineNo: lineNo ?? current.lineNo,
        outputProductId: outputProductId != null ? outputProductId : current.outputProductId,
        ratio: ratio ?? current.ratio,
        uom: uom ?? current.uom,
        outputProductName: current.outputProductName,
        outputProductCode: current.outputProductCode,
      );
    });
  }

  void _updateOperation(int index, {int? lineNo, String? operationName, double? costFixed, double? costPerUnit, String? costUom, String? workCenter}) {
    if (index >= _operations.length) {
      return;
    }
    final current = _operations[index];
    setState(() {
      _operations[index] = BomOperation(
        lineNo: lineNo ?? current.lineNo,
        operationName: operationName ?? current.operationName,
        costFixed: costFixed ?? current.costFixed,
        costPerUnit: costPerUnit ?? current.costPerUnit,
        costUom: costUom ?? current.costUom,
        workCenter: workCenter ?? current.workCenter,
      );
    });
  }

  bool _validateBeforeSave() {
    // اعتبارسنجی نسخه و نام
    if (_versionController.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'نسخه نمی‌تواند خالی باشد');
      return false;
    }
    if (_nameController.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'عنوان نمی‌تواند خالی باشد');
      return false;
    }

    // اعتبارسنجی yield_percent و wastage_percent
    if (_yieldController.text.trim().isNotEmpty) {
      final yield = double.tryParse(_yieldController.text.replaceAll(',', '.'));
      if (yield == null || yield < 0 || yield > 100) {
        SnackBarHelper.show(context, message: 'درصد بازده باید بین 0 تا 100 باشد');
        return false;
      }
    }
    if (_wastageController.text.trim().isNotEmpty) {
      final wastage = double.tryParse(_wastageController.text.replaceAll(',', '.'));
      if (wastage == null || wastage < 0 || wastage > 100) {
        SnackBarHelper.show(context, message: 'درصد پرت باید بین 0 تا 100 باشد');
        return false;
      }
    }

    // اعتبارسنجی اقلام مواد اولیه
    // فقط سطرهایی که کالا انتخاب شده‌اند را بررسی می‌کنیم (سطرهای ناقص نادیده گرفته می‌شوند)
    final validItems = _items.where((item) => item.componentProductId > 0).toList();
    
    // به‌روزرسانی خودکار line_no قبل از اعتبارسنجی (فقط برای سطرهای معتبر)
    for (var i = 0; i < validItems.length; i++) {
      final originalIndex = _items.indexOf(validItems[i]);
      if (originalIndex >= 0 && validItems[i].lineNo != i + 1) {
        _updateItem(originalIndex, lineNo: i + 1);
        validItems[i] = _items[originalIndex];
      }
    }
    
    for (var i = 0; i < validItems.length; i++) {
      final item = validItems[i];
      
      // بررسی qty_per مثبت
      if (item.qtyPer <= 0) {
        final originalIndex = _items.indexOf(item);
        SnackBarHelper.show(context, message: 'مقدار برای تولید در ردیف ${originalIndex + 1} باید بزرگ‌تر از صفر باشد');
        return false;
      }
      
      // بررسی wastage_percent در محدوده 0-100
      if (item.wastagePercent != null && (item.wastagePercent! < 0 || item.wastagePercent! > 100)) {
        final originalIndex = _items.indexOf(item);
        SnackBarHelper.show(context, message: 'درصد پرت در ردیف ${originalIndex + 1} باید بین 0 تا 100 باشد');
        return false;
      }
    }

    // اعتبارسنجی خروجی‌ها
    // فقط سطرهایی که محصول خروجی انتخاب شده‌اند را بررسی می‌کنیم (سطرهای ناقص نادیده گرفته می‌شوند)
    final validOutputs = _outputs.where((output) => output.outputProductId > 0).toList();
    
    // به‌روزرسانی خودکار line_no قبل از اعتبارسنجی (فقط برای سطرهای معتبر)
    for (var i = 0; i < validOutputs.length; i++) {
      final originalIndex = _outputs.indexOf(validOutputs[i]);
      if (originalIndex >= 0 && validOutputs[i].lineNo != i + 1) {
        _updateOutput(originalIndex, lineNo: i + 1);
        validOutputs[i] = _outputs[originalIndex];
      }
    }
    
    for (var i = 0; i < validOutputs.length; i++) {
      final output = validOutputs[i];
      
      // بررسی ratio مثبت
      if (output.ratio <= 0) {
        final originalIndex = _outputs.indexOf(output);
        SnackBarHelper.show(context, message: 'نسبت خروجی در ردیف ${originalIndex + 1} باید بزرگ‌تر از صفر باشد');
        return false;
      }
    }

    // اعتبارسنجی عملیات
    final operationLineNos = <int>{};
    for (var i = 0; i < _operations.length; i++) {
      final op = _operations[i];
      
      // بررسی نام عملیات خالی نباشد
      if (op.operationName.trim().isEmpty) {
        SnackBarHelper.show(context, message: 'نام عملیات در ردیف ${i + 1} نمی‌تواند خالی باشد');
        return false;
      }
      
      // بررسی هزینه‌های منفی
      if (op.costFixed != null && op.costFixed! < 0) {
        SnackBarHelper.show(context, message: 'هزینه ثابت در ردیف ${i + 1} نمی‌تواند منفی باشد');
        return false;
      }
      if (op.costPerUnit != null && op.costPerUnit! < 0) {
        SnackBarHelper.show(context, message: 'هزینه واحد در ردیف ${i + 1} نمی‌تواند منفی باشد');
        return false;
      }
      
      // بررسی line_no تکراری
      if (operationLineNos.contains(op.lineNo)) {
        SnackBarHelper.show(context, message: 'شماره ردیف ${op.lineNo} در عملیات تکراری است');
        return false;
      }
      operationLineNos.add(op.lineNo);
    }

    return true;
  }

  Future<bool> _showProductIdMissingDialog(String productName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('هشدار: کالای فرمول در خروجی‌ها نیست'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'کالای این فرمول تولید ("$productName") در لیست خروجی‌های فرمول تعریف نشده است.',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'توصیه می‌شود:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• کالای فرمول باید در خروجی‌های فرمول تعریف شود',
                      style: TextStyle(fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• این کار باعث می‌شود فرمول تولید به درستی کار کند',
                      style: TextStyle(fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• در فاکتور تولید، این کالا به عنوان خروجی شناسایی می‌شود',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'آیا می‌خواهید کالای فرمول به صورت خودکار به خروجی‌ها اضافه شود؟',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('خیر، ادامه بدون اضافه کردن'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('بله، اضافه کن'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _addProductIdToOutputs() async {
    // بررسی اینکه product_id در outputs نباشد
    final productIdInOutputs = _outputs.any(
      (output) => output.outputProductId == widget.bom.productId,
    );
    
    if (productIdInOutputs) {
      return; // قبلاً اضافه شده است
    }

    // دریافت اطلاعات محصول برای نمایش نام و واحد
    String productName = 'کالا #${widget.bom.productId}';
    String? mainUnit;
    
    try {
      final productData = await _productService.getProduct(
        businessId: widget.businessId,
        productId: widget.bom.productId,
      );
      productName = productData['name']?.toString() ?? productName;
      mainUnit = productData['main_unit']?.toString();
    } catch (e) {
      // در صورت خطا، از نام پیش‌فرض استفاده می‌کنیم
      debugPrint('خطا در دریافت اطلاعات محصول: $e');
    }

    // نمایش دیالوگ تایید
    final shouldAdd = await _showProductIdMissingDialog(productName);
    
    if (shouldAdd && mounted) {
      // اضافه کردن product_id به outputs
      setState(() {
        final newIndex = _outputs.length;
        final newLineNo = _outputs.isEmpty 
            ? 1 
            : (_outputs.map((o) => o.lineNo).reduce((a, b) => a > b ? a : b) + 1);
        
        final newOutput = BomOutput(
          lineNo: newLineNo,
          outputProductId: widget.bom.productId,
          ratio: 1.0, // نسبت پیش‌فرض 1
          uom: mainUnit,
        );
        
        _outputs = [..._outputs, newOutput];
        _outputSelectedProducts = [..._outputSelectedProducts, null];
        _addOutputController(newIndex, newOutput);
        _outputsListKey++;
        
        // نمایش پیام موفقیت
        SnackBarHelper.showSuccess(
          context,
          message: 'کالای فرمول ("$productName") به خروجی‌ها اضافه شد',
        );
      });
    }
  }

  Future<void> _save() async {
    // اعتبارسنجی فرم
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (!_validateBeforeSave()) {
      return;
    }

    // بررسی اینکه product_id فرمول در خروجی‌ها باشد
    final productIdInOutputs = _outputs.any(
      (output) => output.outputProductId == widget.bom.productId,
    );
    
    if (!productIdInOutputs) {
      // نمایش دیالوگ و اضافه کردن در صورت تایید
      await _addProductIdToOutputs();
      
      // بررسی مجدد بعد از اضافه کردن (اگر کاربر تایید کرد)
      final productIdStillMissing = !_outputs.any(
        (output) => output.outputProductId == widget.bom.productId,
      );
      
      if (productIdStillMissing) {
        // کاربر تایید نکرده است، اما ادامه می‌دهیم (هشدار داده شده)
        // می‌توانیم یک هشدار دیگر نمایش دهیم یا ادامه دهیم
      }
    }

    setState(() => _saving = true);
    try {
      // فیلتر کردن آیتم‌هایی که componentProductId معتبر دارند
      final validItems = _items.where((item) => item.componentProductId > 0).toList();
      final validOutputs = _outputs.where((output) => output.outputProductId > 0).toList();
      // فیلتر کردن عملیات با نام خالی
      final validOperations = _operations.where((op) => op.operationName.trim().isNotEmpty).toList();
      
      final payload = <String, dynamic>{
        'version': _versionController.text.trim(),
        'name': _nameController.text.trim(),
        'is_default': _isDefault,
        'yield_percent': _yieldController.text.trim().isEmpty ? null : double.tryParse(_yieldController.text.replaceAll(',', '.')),
        'wastage_percent': _wastageController.text.trim().isEmpty ? null : double.tryParse(_wastageController.text.replaceAll(',', '.')),
        'items': validItems.map((e) => e.toJson()).toList(),
        'outputs': validOutputs.map((e) => e.toJson()).toList(),
        'operations': validOperations.map((e) => e.toJson()).toList(),
      };
      final updated = await _service.update(
        businessId: widget.businessId,
        bomId: widget.bom.id!,
        payload: payload,
      );
      if (!mounted) return;
      Navigator.of(context).pop<ProductBOM>(updated);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در ذخیره: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}


