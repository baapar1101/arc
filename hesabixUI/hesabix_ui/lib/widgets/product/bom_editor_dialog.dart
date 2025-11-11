import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/bom_models.dart';
import '../../services/bom_service.dart';
import '../invoice/product_combobox_widget.dart';
import '../../utils/number_normalizer.dart';

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
              const SizedBox(width: 12),
              Expanded(
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
                  _items = [
                    ..._items,
                    BomItem(lineNo: (_items.isEmpty ? 1 : (_items.last.lineNo + 1)), componentProductId: 0, qtyPer: 1),
                  ];
                  _itemSelectedProducts = [..._itemSelectedProducts, null];
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
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final it = _items[i];
                final lineCtrl = TextEditingController(text: it.lineNo.toString());
                final qtyCtrl = TextEditingController(text: it.qtyPer.toString());
                final uomCtrl = TextEditingController(text: it.uom ?? '');
                final wastCtrl = TextEditingController(text: it.wastagePercent?.toString() ?? '');
                final substCtrl = TextEditingController(text: it.substituteGroup ?? '');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _num(lineCtrl, 'ردیف', (v) => _updateItem(i, lineNo: int.tryParse(v))),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ProductComboboxWidget(
                          businessId: widget.businessId,
                          selectedProduct: _itemSelectedProducts[i],
                          label: 'کالا',
                          hintText: 'جست‌وجوی کالا',
                          onChanged: (p) {
                            setState(() {
                              _itemSelectedProducts[i] = p;
                              final pid = p == null ? null : (p['id'] as int?);
                              if (pid != null) {
                                _updateItem(i, componentProductId: pid);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _num(qtyCtrl, 'مقدار برای 1 واحد', (v) => _updateItem(i, qtyPer: double.tryParse(v))),
                      const SizedBox(width: 8),
                      _text(uomCtrl, 'واحد', (v) => _updateItem(i, uom: v.isEmpty ? null : v)),
                      const SizedBox(width: 8),
                      _num(wastCtrl, 'پرت (%)', (v) => _updateItem(i, wastagePercent: double.tryParse(v))),
                      const SizedBox(width: 8),
                      _text(substCtrl, 'گروه جایگزین', (v) => _updateItem(i, substituteGroup: v.isEmpty ? null : v)),
                      IconButton(onPressed: () => setState(() { _items.removeAt(i); _itemSelectedProducts.removeAt(i); }), icon: const Icon(Icons.delete_outline)),
                    ],
                  ),
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
                  _outputs = [
                    ..._outputs,
                    BomOutput(lineNo: (_outputs.isEmpty ? 1 : (_outputs.last.lineNo + 1)), outputProductId: 0, ratio: 1),
                  ];
                  _outputSelectedProducts = [..._outputSelectedProducts, null];
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
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final ot = _outputs[i];
                final lineCtrl = TextEditingController(text: ot.lineNo.toString());
                final ratioCtrl = TextEditingController(text: ot.ratio.toString());
                final uomCtrl = TextEditingController(text: ot.uom ?? '');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _num(lineCtrl, 'ردیف', (v) => _updateOutput(i, lineNo: int.tryParse(v))),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ProductComboboxWidget(
                          businessId: widget.businessId,
                          selectedProduct: _outputSelectedProducts[i],
                          label: 'محصول خروجی',
                          hintText: 'جست‌وجوی محصول خروجی',
                          onChanged: (p) {
                            setState(() {
                              _outputSelectedProducts[i] = p;
                              final pid = p == null ? null : (p['id'] as int?);
                              if (pid != null) {
                                _updateOutput(i, outputProductId: pid);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _num(ratioCtrl, 'نسبت', (v) => _updateOutput(i, ratio: double.tryParse(v))),
                      const SizedBox(width: 8),
                      _text(uomCtrl, 'واحد', (v) => _updateOutput(i, uom: v.isEmpty ? null : v)),
                      IconButton(onPressed: () => setState(() { _outputs.removeAt(i); _outputSelectedProducts.removeAt(i); }), icon: const Icon(Icons.delete_outline)),
                    ],
                  ),
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
                  _operations = [
                    ..._operations,
                    const BomOperation(lineNo: 1, operationName: ''),
                  ];
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
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final op = _operations[i];
                final lineCtrl = TextEditingController(text: op.lineNo.toString());
                final nameCtrl = TextEditingController(text: op.operationName);
                final fixedCtrl = TextEditingController(text: op.costFixed?.toString() ?? '');
                final perCtrl = TextEditingController(text: op.costPerUnit?.toString() ?? '');
                final uomCtrl = TextEditingController(text: op.costUom ?? '');
                final wcCtrl = TextEditingController(text: op.workCenter ?? '');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _num(lineCtrl, 'ردیف', (v) => _updateOperation(i, lineNo: int.tryParse(v))),
                      const SizedBox(width: 8),
                      _text(nameCtrl, 'نام عملیات', (v) => _updateOperation(i, operationName: v)),
                      const SizedBox(width: 8),
                      _num(fixedCtrl, 'هزینه ثابت', (v) => _updateOperation(i, costFixed: double.tryParse(v))),
                      const SizedBox(width: 8),
                      _num(perCtrl, 'هزینه واحد', (v) => _updateOperation(i, costPerUnit: double.tryParse(v))),
                      const SizedBox(width: 8),
                      _text(uomCtrl, 'واحد هزینه', (v) => _updateOperation(i, costUom: v.isEmpty ? null : v)),
                      const SizedBox(width: 8),
                      _text(wcCtrl, 'ایستگاه کاری', (v) => _updateOperation(i, workCenter: v.isEmpty ? null : v)),
                      IconButton(onPressed: () => setState(() => _operations.removeAt(i)), icon: const Icon(Icons.delete_outline)),
                    ],
                  ),
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

  Widget _text(TextEditingController c, String label, void Function(String) onChanged) {
    return Expanded(
      child: TextField(
        controller: c,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: onChanged,
      ),
    );
  }

  void _updateItem(int index, {int? lineNo, int? componentProductId, double? qtyPer, String? uom, double? wastagePercent, String? substituteGroup}) {
    final current = _items[index];
    setState(() {
      _items[index] = BomItem(
        lineNo: lineNo ?? current.lineNo,
        componentProductId: componentProductId ?? current.componentProductId,
        qtyPer: qtyPer ?? current.qtyPer,
        uom: uom ?? current.uom,
        wastagePercent: wastagePercent ?? current.wastagePercent,
        isOptional: current.isOptional,
        substituteGroup: substituteGroup ?? current.substituteGroup,
        suggestedWarehouseId: current.suggestedWarehouseId,
      );
    });
  }

  void _updateOutput(int index, {int? lineNo, int? outputProductId, double? ratio, String? uom}) {
    final current = _outputs[index];
    setState(() {
      _outputs[index] = BomOutput(
        lineNo: lineNo ?? current.lineNo,
        outputProductId: outputProductId ?? current.outputProductId,
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'version': _versionController.text.trim(),
        'name': _nameController.text.trim(),
        'is_default': _isDefault,
        'yield_percent': _yieldController.text.trim().isEmpty ? null : double.tryParse(_yieldController.text.replaceAll(',', '.')),
        'wastage_percent': _wastageController.text.trim().isEmpty ? null : double.tryParse(_wastageController.text.replaceAll(',', '.')),
        'items': _items.map((e) => e.toJson()).toList(),
        'outputs': _outputs.map((e) => e.toJson()).toList(),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در ذخیره: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}


