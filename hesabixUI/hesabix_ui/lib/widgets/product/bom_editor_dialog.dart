import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/bom_models.dart';
import '../../services/bom_service.dart';
import '../invoice/product_combobox_widget.dart';
import '../invoice/warehouse_combobox_widget.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';

class BomEditorDialog extends StatefulWidget {
  final int businessId;
  final ProductBOM bom;

  const BomEditorDialog({super.key, required this.businessId, required this.bom});

  @override
  State<BomEditorDialog> createState() => _BomEditorDialogState();
}

class _BomEditorDialogState extends State<BomEditorDialog> with SingleTickerProviderStateMixin {
  late final BomService _service;

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

  bool _saving = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _service = BomService();
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _versionController.dispose();
    _yieldController.dispose();
    _wastageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 700,
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ویرایش فرمول تولید', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'عنوان', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _versionController,
                  decoration: const InputDecoration(labelText: 'نسخه', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              CheckboxListTile(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v ?? false),
                title: const Text('پیش‌فرض'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: 'درصد بازده کل فرمول تولید (0-100). این مقدار در محاسبه مقدار مواد اولیه مورد نیاز استفاده می‌شود.',
                  child: TextField(
                    controller: _yieldController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      const EnglishDigitsFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                    ],
                    decoration: const InputDecoration(labelText: 'بازده کل (%)', border: OutlineInputBorder()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Tooltip(
                  message: 'درصد پرت کل فرمول تولید (0-100). این مقدار در محاسبه مقدار مواد اولیه مورد نیاز استفاده می‌شود.',
                  child: TextField(
                    controller: _wastageController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      const EnglishDigitsFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                    ],
                    decoration: const InputDecoration(labelText: 'پرت کل (%)', border: OutlineInputBorder()),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: 'مواد اولیه'),
        Tab(text: 'خروجی‌ها'),
        Tab(text: 'عملیات'),
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

  Widget _buildItemsEditor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () {
                setState(() {
                  final newLineNo = _items.isEmpty ? 1 : (_items.length + 1);
                  _items = [
                    ..._items,
                    BomItem(lineNo: newLineNo, componentProductId: -1, qtyPer: 1),
                  ];
                  _itemSelectedProducts = [..._itemSelectedProducts, null];
                  // به‌روزرسانی line_no همه سطرها
                  for (var i = 0; i < _items.length; i++) {
                    if (_items[i].lineNo != i + 1) {
                      _items[i] = BomItem(
                        lineNo: i + 1,
                        componentProductId: _items[i].componentProductId,
                        qtyPer: _items[i].qtyPer,
                        uom: _items[i].uom,
                        wastagePercent: _items[i].wastagePercent,
                        isOptional: _items[i].isOptional,
                        substituteGroup: _items[i].substituteGroup,
                        suggestedWarehouseId: _items[i].suggestedWarehouseId,
                      );
                    }
                  }
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('افزودن سطر مواد'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (separatorContext, separatorIndex) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final it = _items[index];
                final actualLineNo = index + 1;
                return StatefulBuilder(
                  builder: (context, setStateLocal) {
                    final qtyCtrl = TextEditingController(text: it.qtyPer.toString());
                    final uomCtrl = TextEditingController(text: it.uom ?? '');
                    final wastCtrl = TextEditingController(text: it.wastagePercent?.toString() ?? '');
                    final substCtrl = TextEditingController(text: it.substituteGroup ?? '');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: 'شماره ردیف به صورت خودکار تنظیم می‌شود',
                                  child: TextField(
                                    controller: TextEditingController(text: actualLineNo.toString()),
                                    enabled: false,
                                    decoration: const InputDecoration(
                                      labelText: 'ردیف',
                                      border: OutlineInputBorder(),
                                      filled: true,
                                    ),
                                  ),
                                ),
                              ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Tooltip(
                              message: 'کالای مصرفی که در تولید استفاده می‌شود',
                              child: ProductComboboxWidget(
                                businessId: widget.businessId,
                                selectedProduct: _itemSelectedProducts[index],
                                label: 'کالا',
                                hintText: 'جست‌وجوی کالا',
                                onChanged: (product) {
                                  setState(() {
                                    _itemSelectedProducts[index] = product;
                                    final pid = product == null ? null : (product['id'] as int?);
                                    if (pid != null) {
                                      _updateItem(index, componentProductId: pid);
                                    }
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _numWithTooltip(
                            qtyCtrl,
                            'مقدار برای 1 واحد',
                            'مقدار این کالا برای تولید 1 واحد محصول نهایی',
                            (v) => _updateItem(index, qtyPer: double.tryParse(v)),
                          ),
                          const SizedBox(width: 8),
                          _textWithTooltip(
                            uomCtrl,
                            'واحد',
                            'واحد اندازه‌گیری کالا',
                            (v) => _updateItem(index, uom: v.isEmpty ? null : v),
                          ),
                          const SizedBox(width: 8),
                          _numWithTooltip(
                            wastCtrl,
                            'پرت (%)',
                            'درصد پرت این کالا در فرآیند تولید (0-100)',
                            (v) => _updateItem(index, wastagePercent: double.tryParse(v)),
                          ),
                          const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _items.removeAt(index);
                                    _itemSelectedProducts.removeAt(index);
                                    // به‌روزرسانی line_no سطرهای باقی‌مانده
                                    for (var i = 0; i < _items.length; i++) {
                                      if (_items[i].lineNo != i + 1) {
                                        _items[i] = BomItem(
                                          lineNo: i + 1,
                                          componentProductId: _items[i].componentProductId,
                                          qtyPer: _items[i].qtyPer,
                                          uom: _items[i].uom,
                                          wastagePercent: _items[i].wastagePercent,
                                          isOptional: _items[i].isOptional,
                                          substituteGroup: _items[i].substituteGroup,
                                          suggestedWarehouseId: _items[i].suggestedWarehouseId,
                                        );
                                      }
                                    }
                                  });
                                },
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'حذف سطر',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: 'گروه جایگزین: کالاهای با گروه یکسان می‌توانند جایگزین یکدیگر شوند',
                                  child: _text(substCtrl, 'گروه جایگزین', (v) => _updateItem(index, substituteGroup: v.isEmpty ? null : v)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Tooltip(
                                  message: 'انبار پیشنهادی برای برداشت این ماده اولیه در سند تولید',
                                  child: WarehouseComboboxWidget(
                                    businessId: widget.businessId,
                                    selectedWarehouseId: it.suggestedWarehouseId,
                                    label: 'انبار پیشنهادی',
                                    hintText: 'انتخاب انبار',
                                    onChanged: (warehouseId) => _updateItem(index, suggestedWarehouseId: warehouseId),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: 'اگر فعال باشد، این ماده اولیه اختیاری است و می‌تواند در تولید استفاده نشود',
                                child: CheckboxListTile(
                                  value: it.isOptional,
                                  onChanged: (v) => _updateItem(index, isOptional: v ?? false),
                                  title: const Text('اختیاری'),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputsEditor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () {
                setState(() {
                  final newLineNo = _outputs.isEmpty ? 1 : (_outputs.length + 1);
                  _outputs = [
                    ..._outputs,
                    BomOutput(lineNo: newLineNo, outputProductId: -1, ratio: 1),
                  ];
                  _outputSelectedProducts = [..._outputSelectedProducts, null];
                  // به‌روزرسانی line_no همه سطرها
                  for (var i = 0; i < _outputs.length; i++) {
                    if (_outputs[i].lineNo != i + 1) {
                      _outputs[i] = BomOutput(
                        lineNo: i + 1,
                        outputProductId: _outputs[i].outputProductId,
                        ratio: _outputs[i].ratio,
                        uom: _outputs[i].uom,
                        outputProductName: _outputs[i].outputProductName,
                        outputProductCode: _outputs[i].outputProductCode,
                      );
                    }
                  }
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('افزودن سطر خروجی'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: _outputs.length,
              separatorBuilder: (separatorContext, separatorIndex) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final ot = _outputs[index];
                final actualLineNo = index + 1;
                return StatefulBuilder(
                  builder: (context, setStateLocal) {
                    final ratioCtrl = TextEditingController(text: ot.ratio.toString());
                    final uomCtrl = TextEditingController(text: ot.uom ?? '');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: 'شماره ردیف به صورت خودکار تنظیم می‌شود',
                              child: TextField(
                                controller: TextEditingController(text: actualLineNo.toString()),
                                enabled: false,
                                decoration: const InputDecoration(
                                  labelText: 'ردیف',
                                  border: OutlineInputBorder(),
                                  filled: true,
                                ),
                              ),
                            ),
                          ),
                      const SizedBox(width: 8),
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
                              final pid = product == null ? null : (product['id'] as int?);
                              if (pid != null) {
                                _updateOutput(index, outputProductId: pid);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _numWithTooltip(
                        ratioCtrl,
                        'نسبت',
                        'نسبت خروجی این محصول به ازای هر واحد تولید',
                        (v) => _updateOutput(index, ratio: double.tryParse(v)),
                      ),
                      const SizedBox(width: 8),
                      _textWithTooltip(
                        uomCtrl,
                        'واحد',
                        'واحد اندازه‌گیری محصول خروجی',
                        (v) => _updateOutput(index, uom: v.isEmpty ? null : v),
                      ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _outputs.removeAt(index);
                                _outputSelectedProducts.removeAt(index);
                                // به‌روزرسانی line_no سطرهای باقی‌مانده
                                for (var i = 0; i < _outputs.length; i++) {
                                  if (_outputs[i].lineNo != i + 1) {
                                    _outputs[i] = BomOutput(
                                      lineNo: i + 1,
                                      outputProductId: _outputs[i].outputProductId,
                                      ratio: _outputs[i].ratio,
                                      uom: _outputs[i].uom,
                                      outputProductName: _outputs[i].outputProductName,
                                      outputProductCode: _outputs[i].outputProductCode,
                                    );
                                  }
                                }
                              });
                            },
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'حذف سطر',
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsEditor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () {
                setState(() {
                  final newLineNo = _operations.isEmpty ? 1 : (_operations.length + 1);
                  _operations = [
                    ..._operations,
                    BomOperation(lineNo: newLineNo, operationName: ''),
                  ];
                  // به‌روزرسانی line_no همه سطرها
                  for (var i = 0; i < _operations.length; i++) {
                    if (_operations[i].lineNo != i + 1) {
                      _operations[i] = BomOperation(
                        lineNo: i + 1,
                        operationName: _operations[i].operationName,
                        costFixed: _operations[i].costFixed,
                        costPerUnit: _operations[i].costPerUnit,
                        costUom: _operations[i].costUom,
                        workCenter: _operations[i].workCenter,
                      );
                    }
                  }
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('افزودن عملیات'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: _operations.length,
              separatorBuilder: (separatorContext, separatorIndex) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final op = _operations[index];
                final actualLineNo = index + 1;
                return StatefulBuilder(
                  builder: (context, setStateLocal) {
                    final nameCtrl = TextEditingController(text: op.operationName);
                    final fixedCtrl = TextEditingController(text: op.costFixed?.toString() ?? '');
                    final perCtrl = TextEditingController(text: op.costPerUnit?.toString() ?? '');
                    final uomCtrl = TextEditingController(text: op.costUom ?? '');
                    final wcCtrl = TextEditingController(text: op.workCenter ?? '');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: 'شماره ردیف به صورت خودکار تنظیم می‌شود',
                              child: TextField(
                                controller: TextEditingController(text: actualLineNo.toString()),
                                enabled: false,
                                decoration: const InputDecoration(
                                  labelText: 'ردیف',
                                  border: OutlineInputBorder(),
                                  filled: true,
                                ),
                              ),
                            ),
                          ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Tooltip(
                          message: 'نام عملیات تولیدی (مثال: برش، جوشکاری، رنگ‌آمیزی)',
                          child: _text(nameCtrl, 'نام عملیات', (v) => _updateOperation(index, operationName: v)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: 'هزینه ثابت عملیات (در حال حاضر در تولید سند حسابداری استفاده نمی‌شود)',
                          child: _num(fixedCtrl, 'هزینه ثابت', (v) => _updateOperation(index, costFixed: double.tryParse(v))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: 'هزینه به ازای هر واحد (در حال حاضر در تولید سند حسابداری استفاده نمی‌شود)',
                          child: _num(perCtrl, 'هزینه واحد', (v) => _updateOperation(index, costPerUnit: double.tryParse(v))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: 'واحد هزینه (در حال حاضر در تولید سند حسابداری استفاده نمی‌شود)',
                          child: _text(uomCtrl, 'واحد هزینه', (v) => _updateOperation(index, costUom: v.isEmpty ? null : v)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: 'ایستگاه کاری یا بخش انجام عملیات (فقط برای اطلاعات)',
                          child: _text(wcCtrl, 'ایستگاه کاری', (v) => _updateOperation(index, workCenter: v.isEmpty ? null : v)),
                        ),
                      ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _operations.removeAt(index);
                                // به‌روزرسانی line_no سطرهای باقی‌مانده
                                for (var i = 0; i < _operations.length; i++) {
                                  if (_operations[i].lineNo != i + 1) {
                                    _operations[i] = BomOperation(
                                      lineNo: i + 1,
                                      operationName: _operations[i].operationName,
                                      costFixed: _operations[i].costFixed,
                                      costPerUnit: _operations[i].costPerUnit,
                                      costUom: _operations[i].costUom,
                                      workCenter: _operations[i].workCenter,
                                    );
                                  }
                                }
                              });
                            },
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'حذف سطر',
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
            label: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Widget _num(TextEditingController c, String label, void Function(String) onChanged) {
    return Expanded(
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          EnglishDigitsFormatter(),
          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
        ],
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: onChanged,
      ),
    );
  }

  Widget _numWithTooltip(TextEditingController c, String label, String tooltip, void Function(String) onChanged) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            EnglishDigitsFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
          ],
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          onChanged: onChanged,
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

  void _updateItem(int index, {int? lineNo, int? componentProductId, double? qtyPer, String? uom, double? wastagePercent, String? substituteGroup, bool? isOptional, int? suggestedWarehouseId}) {
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نسخه نمی‌تواند خالی باشد')));
      return false;
    }
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان نمی‌تواند خالی باشد')));
      return false;
    }

    // اعتبارسنجی yield_percent و wastage_percent
    if (_yieldController.text.trim().isNotEmpty) {
      final yield = double.tryParse(_yieldController.text.replaceAll(',', '.'));
      if (yield == null || yield < 0 || yield > 100) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درصد بازده باید بین 0 تا 100 باشد')));
        return false;
      }
    }
    if (_wastageController.text.trim().isNotEmpty) {
      final wastage = double.tryParse(_wastageController.text.replaceAll(',', '.'));
      if (wastage == null || wastage < 0 || wastage > 100) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درصد پرت باید بین 0 تا 100 باشد')));
        return false;
      }
    }

    // اعتبارسنجی اقلام مواد اولیه
    // به‌روزرسانی خودکار line_no قبل از اعتبارسنجی
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].lineNo != i + 1) {
        _updateItem(i, lineNo: i + 1);
      }
    }
    
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      
      // بررسی component_product_id انتخاب شده
      if (item.componentProductId <= 0) {
        SnackBarHelper.show(context, message: 'لطفاً کالای مواد اولیه در ردیف ${i + 1} را انتخاب کنید');
        return false;
      }
      
      // بررسی qty_per مثبت
      if (item.qtyPer <= 0) {
        SnackBarHelper.show(context, message: 'مقدار برای تولید در ردیف ${i + 1} باید بزرگ‌تر از صفر باشد');
        return false;
      }
      
      // بررسی wastage_percent در محدوده 0-100
      if (item.wastagePercent != null && (item.wastagePercent! < 0 || item.wastagePercent! > 100)) {
        SnackBarHelper.show(context, message: 'درصد پرت در ردیف ${i + 1} باید بین 0 تا 100 باشد');
        return false;
      }
    }

    // اعتبارسنجی خروجی‌ها
    // به‌روزرسانی خودکار line_no قبل از اعتبارسنجی
    for (var i = 0; i < _outputs.length; i++) {
      if (_outputs[i].lineNo != i + 1) {
        _updateOutput(i, lineNo: i + 1);
      }
    }
    
    for (var i = 0; i < _outputs.length; i++) {
      final output = _outputs[i];
      
      // بررسی output_product_id انتخاب شده
      if (output.outputProductId <= 0) {
        SnackBarHelper.show(context, message: 'لطفاً محصول خروجی در ردیف ${i + 1} را انتخاب کنید');
        return false;
      }
      
      // بررسی ratio مثبت
      if (output.ratio <= 0) {
        SnackBarHelper.show(context, message: 'نسبت خروجی در ردیف ${i + 1} باید بزرگ‌تر از صفر باشد');
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

  Future<void> _save() async {
    if (!_validateBeforeSave()) {
      return;
    }

    setState(() => _saving = true);
    try {
      // فیلتر کردن آیتم‌هایی که componentProductId معتبر دارند
      final validItems = _items.where((item) => item.componentProductId > 0).toList();
      final validOutputs = _outputs.where((output) => output.outputProductId > 0).toList();
      
      final payload = <String, dynamic>{
        'version': _versionController.text.trim(),
        'name': _nameController.text.trim(),
        'is_default': _isDefault,
        'yield_percent': _yieldController.text.trim().isEmpty ? null : double.tryParse(_yieldController.text.replaceAll(',', '.')),
        'wastage_percent': _wastageController.text.trim().isEmpty ? null : double.tryParse(_wastageController.text.replaceAll(',', '.')),
        'items': validItems.map((e) => e.toJson()).toList(),
        'outputs': validOutputs.map((e) => e.toJson()).toList(),
        'operations': _operations.map((e) => e.toJson()).toList(),
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


