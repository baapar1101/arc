import 'package:flutter/material.dart';
import '../../../services/bom_service.dart';
import '../../../models/bom_models.dart';
import '../../product/bom_editor_dialog.dart';
import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/calendar_controller.dart';
import '../../document/document_form_dialog.dart';
import '../../document/document_line_editor.dart';
import '../../../services/account_service.dart';
import '../../../models/account_model.dart';
import '../production_settings_dialog.dart';
import '../../../services/production_settings_service.dart';

class ProductBomSection extends StatefulWidget {
  final int businessId;
  final int? productId;

  const ProductBomSection({super.key, required this.businessId, required this.productId});

  @override
  State<ProductBomSection> createState() => _ProductBomSectionState();
}

class _ProductBomSectionState extends State<ProductBomSection> {
  final BomService _service = BomService();
  bool _loading = true;
  String? _error;
  List<ProductBOM> _items = const <ProductBOM>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.productId == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final items = await _service.list(businessId: widget.businessId, productId: widget.productId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.productId == null) {
      return _buildDisabledState();
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('فرمول‌های تولید', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Tooltip(
              message: 'تنظیمات تولید',
              child: IconButton(
                onPressed: () async {
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => ProductionSettingsDialog(businessId: widget.businessId),
                  );
                },
                icon: const Icon(Icons.settings_suggest_outlined),
              ),
            ),
            FilledButton.icon(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add),
              label: const Text('افزودن فرمول'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _items.isEmpty
              ? const Center(child: Text('هنوز فرمولی تعریف نشده است'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final bom = _items[idx];
                    return ListTile(
                      leading: Icon(bom.isDefault ? Icons.star : Icons.blur_on, color: bom.isDefault ? Colors.orange : null),
                      title: Text('${bom.name} (v${bom.version})'),
                      subtitle: Text('وضعیت: ${bom.status} | بازده: ${bom.yieldPercent ?? 0}٪ | پرت: ${bom.wastagePercent ?? 0}٪'),
                      trailing: Wrap(spacing: 8, children: [
                        IconButton(
                          tooltip: 'انفجار فرمول',
                          icon: const Icon(Icons.auto_awesome),
                          onPressed: () => _explode(bom),
                        ),
                        IconButton(
                          tooltip: 'ویرایش جزئیات',
                          icon: const Icon(Icons.tune),
                          onPressed: () => _openEditor(bom),
                        ),
                        IconButton(
                          tooltip: 'ویرایش',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showEditDialog(bom),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(bom),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDisabledState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('برای مدیریت فرمول تولید، ابتدا کالا را ذخیره کنید.'),
    );
  }

  Future<void> _explode(ProductBOM bom) async {
    try {
      // دریافت مقدار تولید از کاربر
      final qtyController = TextEditingController(text: '1');
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('انفجار فرمول')
          ,
          content: TextField(
            controller: qtyController,
            decoration: const InputDecoration(labelText: 'مقدار تولید', hintText: 'مثلاً 10'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ادامه')),
          ],
        ),
      );
      if (ok != true) return;
      final qty = double.tryParse(qtyController.text.replaceAll(',', '.')) ?? 1;

      final result = await _service.explode(
        businessId: widget.businessId,
        bomId: bom.id,
        quantity: qty,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('خروجی انفجار فرمول (برای ${qty.toString()} واحد)'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('مواد موردنیاز:'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  child: ListView.builder(
                    itemCount: result.items.length,
                    itemBuilder: (ctx, i) {
                      final it = result.items[i];
                      final name = it.componentProductName ?? '#${it.componentProductId}';
                      final unit = it.uom ?? it.componentProductMainUnit ?? '';
                      final mainUnit = it.mainUnit ?? it.componentProductMainUnit ?? '';
                      final showConv = it.requiredQtyMainUnit != null && (unit != mainUnit) && mainUnit.isNotEmpty;
                      final convText = showConv ? ' (≈ ${it.requiredQtyMainUnit} $mainUnit)' : '';
                      return Text('- $name × ${it.requiredQty} ${unit.isEmpty ? '' : unit}$convText');
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text('خروجی‌ها:'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    itemCount: result.outputs.length,
                    itemBuilder: (ctx, i) {
                      final ot = result.outputs[i];
                      final name = ot.outputProductName ?? '#${ot.outputProductId}';
                      final mainUnit = ot.mainUnit;
                      final showConv = ot.ratioMainUnit != null && mainUnit != null && (ot.uom ?? '') != mainUnit;
                      final convText = showConv ? ' (≈ ${ot.ratioMainUnit} $mainUnit)' : '';
                      return Text('- $name: ${ot.ratio} ${ot.uom ?? ''}$convText');
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('بستن')),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final draft = await _service.produceDraft(
                    businessId: widget.businessId,
                    bomId: bom.id,
                    quantity: qty,
                  );
                  if (!mounted) return;
                      Navigator.of(context).pop();
                      // یافتن حساب‌های پیش‌فرض
                      final accountService = AccountService(client: ApiClient());
                      final prodSettings = ProductionSettingsService();
                      final (savedInvCode, savedWipCode) = await prodSettings.getDefaultAccounts(widget.businessId);
                      Future<Account?> _getAccountByCode(String code) async {
                        try {
                          final res = await accountService.searchAccounts(businessId: widget.businessId, searchQuery: code, limit: 10);
                          final items = (res['items'] as List<dynamic>? ?? const <dynamic>[])
                              .map((e) => Account.fromJson(Map<String, dynamic>.from(e as Map)))
                              .toList();
                          // جستجوی دقیق بر اساس کد
                          final exact = items.where((a) => a.code == code).toList();
                          if (exact.isNotEmpty) return exact.first;
                          return items.isNotEmpty ? items.first : null;
                        } catch (_) {
                          return null;
                        }
                      }

                      final inventoryAccount = await _getAccountByCode((savedInvCode ?? '10102'));
                      final wipAccount = await _getAccountByCode((savedWipCode ?? '10106'));

                      // ساخت خطوط اولیه از پیش‌نویس برای فرم سند
                      final lines = <DocumentLineEdit>[];
                      final draftLines = (draft['lines'] as List?) ?? const <dynamic>[];
                      for (final raw in draftLines) {
                        final m = Map<String, dynamic>.from(raw as Map);
                        final isConsumption = (m['description']?.toString() ?? '').contains('مصرف');
                        final Account? defaultAccount = isConsumption
                            ? inventoryAccount
                            : (wipAccount ?? inventoryAccount);
                        lines.add(
                          DocumentLineEdit(
                            account: defaultAccount,
                            detail: {
                              if (m['product_id'] != null) 'product_id': m['product_id'],
                            },
                            quantity: m['quantity'] is num ? (m['quantity'] as num).toDouble() : double.tryParse(m['quantity']?.toString() ?? ''),
                            debit: 0,
                            credit: 0,
                            description: m['description']?.toString(),
                          ),
                        );
                      }

                      // بارگذاری کنترلر تقویم (در صورت عدم وجود)
                      final calendarController = await CalendarController.load();

                      // باز کردن فرم سند با مقداردهی اولیه
                      await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => DocumentFormDialog(
                          businessId: widget.businessId,
                          calendarController: calendarController,
                          authStore: AuthStore(),
                          apiClient: ApiClient(),
                          fiscalYearId: null,
                          currencyId: null,
                          initialLines: lines,
                          initialDescription: draft['description']?.toString(),
                        ),
                      );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در ایجاد پیش‌نویس: $e')));
                }
              },
              icon: const Icon(Icons.playlist_add),
              label: const Text('ایجاد پیش‌نویس سند تولید'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  Future<void> _showCreateDialog() async {
    final controller = TextEditingController();
    final nameController = TextEditingController();
    bool isDefault = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('افزودن فرمول تولید'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'عنوان')), 
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'نسخه (مثلاً v1)')),
            const SizedBox(height: 8),
            StatefulBuilder(builder: (ctx, setSt) {
              return CheckboxListTile(
                value: isDefault,
                onChanged: (v) => setSt(() => isDefault = v ?? false),
                title: const Text('به عنوان پیش‌فرض تنظیم شود'),
                controlAffinity: ListTileControlAffinity.leading,
              );
            })
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final created = await _service.create(
        businessId: widget.businessId,
        payload: {
          'product_id': widget.productId,
          'version': controller.text.trim().isEmpty ? 'v1' : controller.text.trim(),
          'name': nameController.text.trim().isEmpty ? 'BOM' : nameController.text.trim(),
          'is_default': isDefault,
          'items': <Map<String, dynamic>>[],
          'outputs': <Map<String, dynamic>>[],
          'operations': <Map<String, dynamic>>[],
        },
      );
      if (!mounted) return;
      setState(() {
        _items = [created, ..._items];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  Future<void> _showEditDialog(ProductBOM bom) async {
    final controller = TextEditingController(text: bom.version);
    final nameController = TextEditingController(text: bom.name);
    bool isDefault = bom.isDefault;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ویرایش فرمول تولید'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'عنوان')), 
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'نسخه')), 
            const SizedBox(height: 8),
            StatefulBuilder(builder: (ctx, setSt) {
              return CheckboxListTile(
                value: isDefault,
                onChanged: (v) => setSt(() => isDefault = v ?? false),
                title: const Text('پیش‌فرض'),
                controlAffinity: ListTileControlAffinity.leading,
              );
            })
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final updated = await _service.update(
        businessId: widget.businessId,
        bomId: bom.id!,
        payload: {
          'version': controller.text.trim(),
          'name': nameController.text.trim(),
          'is_default': isDefault,
        },
      );
      if (!mounted) return;
      setState(() {
        _items = _items.map((e) => e.id == updated.id ? updated : e).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  Future<void> _openEditor(ProductBOM bom) async {
    final updated = await showDialog<ProductBOM>(
      context: context,
      builder: (_) => BomEditorDialog(businessId: widget.businessId, bom: bom),
    );
    if (updated != null && mounted) {
      setState(() {
        _items = _items.map((e) => e.id == updated.id ? updated : e).toList();
      });
    }
  }

  Future<void> _delete(ProductBOM bom) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف فرمول'),
        content: Text('آیا از حذف «${bom.name}» مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(businessId: widget.businessId, bomId: bom.id!);
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != bom.id).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }
}




