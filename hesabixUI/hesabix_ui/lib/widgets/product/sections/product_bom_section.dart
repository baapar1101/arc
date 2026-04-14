import 'package:flutter/material.dart';
import '../../../services/bom_service.dart';
import '../../../models/bom_models.dart';
import '../../product/bom_editor_dialog.dart';
import '../production_settings_dialog.dart';
import '../../../../utils/snackbar_helper.dart';

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
        // کارت راهنمای استفاده از فرمول در فاکتور تولید
        if (_items.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'راهنمای استفاده از فرمول تولید',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'برای استفاده از این فرمول‌ها در تولید، به بخش "فاکتور تولید" بروید و از دکمه "انفجار فرمول" استفاده کنید. این روش از نظر حسابداری اصولی‌تر است.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _items.isEmpty
              ? const Center(child: Text('هنوز فرمولی تعریف نشده است'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, separatorIndex) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final bom = _items[idx];
                    final itemsCount = bom.items.length;
                    final outputsCount = bom.outputs.length;
                    final operationsCount = bom.operations.length;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: bom.isDefault 
                                ? Colors.orange.withValues(alpha: 0.2)
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            bom.isDefault ? Icons.star : Icons.blur_on,
                            color: bom.isDefault ? Colors.orange : Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 24,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                bom.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (bom.isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star, size: 14, color: Colors.orange.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      'پیش‌فرض',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Chip(
                                  label: Text('v${bom.version}'),
                                  labelStyle: Theme.of(context).textTheme.bodySmall,
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 8),
                                Chip(
                                  label: Text(_getStatusText(bom.status)),
                                  labelStyle: Theme.of(context).textTheme.bodySmall,
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: _getStatusColor(bom.status).withValues(alpha: 0.2),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                if (bom.yieldPercent != null)
                                  _buildInfoChip(
                                    context,
                                    Icons.trending_up,
                                    'بازده: ${bom.yieldPercent}٪',
                                  ),
                                if (bom.wastagePercent != null)
                                  _buildInfoChip(
                                    context,
                                    Icons.trending_down,
                                    'پرت: ${bom.wastagePercent}٪',
                                  ),
                                _buildInfoChip(
                                  context,
                                  Icons.inventory_2,
                                  'مواد: $itemsCount',
                                ),
                                _buildInfoChip(
                                  context,
                                  Icons.output,
                                  'خروجی: $outputsCount',
                                ),
                                if (operationsCount > 0)
                                  _buildInfoChip(
                                    context,
                                    Icons.build,
                                    'عملیات: $operationsCount',
                                  ),
                              ],
                            ),
                            if (bom.createdAt != null || bom.updatedAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _getDateInfo(bom),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Wrap(spacing: 4, children: [
                          IconButton(
                            tooltip: 'ویرایش جزئیات (مواد، خروجی‌ها، عملیات)',
                            icon: const Icon(Icons.tune),
                            onPressed: () => _openEditor(bom),
                          ),
                          IconButton(
                            tooltip: 'ویرایش اطلاعات کلی (نام، نسخه، پیش‌فرض)',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showEditDialog(bom),
                          ),
                          IconButton(
                            tooltip: 'حذف فرمول',
                            icon: const Icon(Icons.delete_outline),
                            color: Colors.red.shade700,
                            onPressed: () => _delete(bom),
                          ),
                        ]),
                        isThreeLine: true,
                      ),
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

  Widget _buildInfoChip(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'پیش‌نویس';
      case 'approved':
        return 'تایید شده';
      case 'archived':
        return 'بایگانی';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'approved':
        return Colors.green;
      case 'archived':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  String _getDateInfo(ProductBOM bom) {
    final parts = <String>[];
    if (bom.createdAt != null) {
      final created = bom.createdAt!;
      parts.add('ایجاد: ${created.year}/${created.month}/${created.day}');
    }
    if (bom.updatedAt != null && bom.updatedAt != bom.createdAt) {
      final updated = bom.updatedAt!;
      parts.add('ویرایش: ${updated.year}/${updated.month}/${updated.day}');
    }
    return parts.join(' | ');
  }


  Future<void> _showCreateDialog() async {
    final result = await showDialog<ProductBOM>(
      context: context,
      builder: (_) => _CreateBomDialog(
        businessId: widget.businessId,
        productId: widget.productId!,
        service: _service,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _items = [result, ..._items];
      });
    }
  }

  Future<void> _showEditDialog(ProductBOM bom) async {
    final result = await showDialog<ProductBOM>(
      context: context,
      builder: (_) => _EditBomDialog(
        businessId: widget.businessId,
        bom: bom,
        service: _service,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _items = _items.map((e) => e.id == result.id ? result : e).toList();
      });
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
    final itemsCount = bom.items.length;
    final outputsCount = bom.outputs.length;
    final operationsCount = bom.operations.length;
    
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Expanded(child: Text('حذف فرمول تولید')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'آیا از حذف فرمول «${bom.name} (v${bom.version})» مطمئن هستید؟',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'این فرمول شامل:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (itemsCount > 0)
                    Row(
                      children: [
                        Icon(Icons.inventory_2, size: 16, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Text('$itemsCount ماده اولیه', style: TextStyle(color: Colors.red.shade700)),
                      ],
                    ),
                  if (outputsCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.output, size: 16, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Text('$outputsCount محصول خروجی', style: TextStyle(color: Colors.red.shade700)),
                      ],
                    ),
                  ],
                  if (operationsCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.build, size: 16, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Text('$operationsCount عملیات', style: TextStyle(color: Colors.red.shade700)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'این عمل قابل بازگشت نیست.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('حذف'),
          ),
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
      if (mounted) {
        SnackBarHelper.show(context, message: 'فرمول با موفقیت حذف شد');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در حذف فرمول: $e');
    }
  }
}

class _CreateBomDialog extends StatefulWidget {
  final int businessId;
  final int productId;
  final BomService service;

  const _CreateBomDialog({
    required this.businessId,
    required this.productId,
    required this.service,
  });

  @override
  State<_CreateBomDialog> createState() => _CreateBomDialogState();
}

class _CreateBomDialogState extends State<_CreateBomDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _versionController;
  late final TextEditingController _nameController;
  bool _isDefault = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _versionController = TextEditingController();
    _nameController = TextEditingController();
    
    // Track changes
    _versionController.addListener(_onFieldChanged);
    _nameController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!mounted) return;
    final hasChanges = _versionController.text.trim().isNotEmpty ||
        _nameController.text.trim().isNotEmpty ||
        _isDefault;
    if (hasChanges != _hasChanges) {
      setState(() {
        _hasChanges = hasChanges;
      });
    }
  }

  @override
  void dispose() {
    _versionController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final created = await widget.service.create(
        businessId: widget.businessId,
        payload: {
          'product_id': widget.productId,
          'version': _versionController.text.trim(),
          'name': _nameController.text.trim(),
          'is_default': _isDefault,
          'items': <Map<String, dynamic>>[],
          'outputs': <Map<String, dynamic>>[],
          'operations': <Map<String, dynamic>>[],
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop<ProductBOM>(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'خطا در ایجاد فرمول: $e';
      });
    }
  }

  Future<bool> _handleClose() async {
    if (!_hasChanges || _isLoading) {
      return true;
    }
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تغییرات ذخیره نشده'),
        content: const Text('آیا می‌خواهید بدون ذخیره تغییرات خارج شوید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('بازگشت'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    return shouldClose ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return WillPopScope(
      onWillPop: () async {
        if (_isLoading) return false;
        return await _handleClose();
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: theme.colorScheme.onPrimary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'افزودن فرمول تولید',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isLoading ? null : () async {
                        if (await _handleClose()) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.close),
                      color: theme.colorScheme.onPrimary,
                    ),
                  ],
                ),
              ),
              // Form content
              Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title field
                      TextFormField(
                        controller: _nameController,
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          labelText: 'عنوان فرمول',
                          hintText: 'مثال: فرمول اصلی تولید',
                          prefixIcon: const Icon(Icons.title),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'لطفاً عنوان فرمول را وارد کنید';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Version field
                      TextFormField(
                        controller: _versionController,
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          labelText: 'نسخه',
                          hintText: 'مثال: v1, v2.0, 2024',
                          prefixIcon: const Icon(Icons.tag),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          helperText: 'نسخه فرمول تولید را مشخص کنید',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'لطفاً نسخه را وارد کنید';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Default checkbox with better styling
                      Container(
                        padding: const EdgeInsets.all(16),
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
                          children: [
                            Icon(
                              _isDefault ? Icons.star : Icons.star_border,
                              color: _isDefault
                                  ? Colors.orange
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تنظیم به عنوان پیش‌فرض',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'این فرمول به صورت پیش‌فرض برای تولید استفاده می‌شود',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isDefault,
                              onChanged: _isLoading
                                  ? null
                                  : (v) => setState(() => _isDefault = v),
                            ),
                          ],
                        ),
                      ),
                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              if (await _handleClose()) {
                                Navigator.of(context).pop();
                              }
                            },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('انصراف'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _handleSave,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isLoading ? 'در حال ایجاد...' : 'ذخیره'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
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

class _EditBomDialog extends StatefulWidget {
  final int businessId;
  final ProductBOM bom;
  final BomService service;

  const _EditBomDialog({
    required this.businessId,
    required this.bom,
    required this.service,
  });

  @override
  State<_EditBomDialog> createState() => _EditBomDialogState();
}

class _EditBomDialogState extends State<_EditBomDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _versionController;
  late final TextEditingController _nameController;
  late bool _isDefault;
  late String _status;
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _versionController = TextEditingController(text: widget.bom.version);
    _nameController = TextEditingController(text: widget.bom.name);
    _isDefault = widget.bom.isDefault;
    _status = widget.bom.status;
    
    // Track changes
    _versionController.addListener(_onFieldChanged);
    _nameController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!mounted) return;
    final hasChanges = _versionController.text.trim() != widget.bom.version ||
        _nameController.text.trim() != widget.bom.name ||
        _isDefault != widget.bom.isDefault ||
        _status != widget.bom.status;
    if (hasChanges != _hasChanges) {
      setState(() {
        _hasChanges = hasChanges;
      });
    }
  }

  @override
  void dispose() {
    _versionController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final updated = await widget.service.update(
        businessId: widget.businessId,
        bomId: widget.bom.id!,
        payload: {
          'version': _versionController.text.trim(),
          'name': _nameController.text.trim(),
          'is_default': _isDefault,
          'status': _status,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'خطا در ذخیره تغییرات: $e';
      });
    }
  }

  Future<bool> _handleClose() async {
    if (!_hasChanges || _isLoading) {
      return true;
    }
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تغییرات ذخیره نشده'),
        content: const Text('آیا می‌خواهید بدون ذخیره تغییرات خارج شوید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('بازگشت'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    return shouldClose ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return WillPopScope(
      onWillPop: () async {
        if (_isLoading) return false;
        return await _handleClose();
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
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
                            style: theme.textTheme.headlineSmall?.copyWith(
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
                    IconButton(
                      onPressed: _isLoading ? null : () async {
                        if (await _handleClose()) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.close),
                      color: theme.colorScheme.onPrimary,
                    ),
                  ],
                ),
              ),
              // Form content
              Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title field
                      TextFormField(
                        controller: _nameController,
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          labelText: 'عنوان فرمول',
                          hintText: 'مثال: فرمول اصلی تولید',
                          prefixIcon: const Icon(Icons.title),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'لطفاً عنوان فرمول را وارد کنید';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Version field
                      TextFormField(
                        controller: _versionController,
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          labelText: 'نسخه',
                          hintText: 'مثال: v1, v2.0, 2024',
                          prefixIcon: const Icon(Icons.tag),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          helperText: 'نسخه فرمول تولید را مشخص کنید',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'لطفاً نسخه را وارد کنید';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Status field
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration: InputDecoration(
                          labelText: 'وضعیت',
                          prefixIcon: const Icon(Icons.info_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'draft',
                            child: Text('پیش‌نویس'),
                          ),
                          DropdownMenuItem(
                            value: 'approved',
                            child: Text('تایید شده'),
                          ),
                          DropdownMenuItem(
                            value: 'archived',
                            child: Text('بایگانی'),
                          ),
                        ],
                        onChanged: _isLoading ? null : (value) {
                          if (value != null) {
                            setState(() {
                              _status = value;
                              _onFieldChanged();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Default checkbox with better styling
                      Container(
                        padding: const EdgeInsets.all(16),
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
                          children: [
                            Icon(
                              _isDefault ? Icons.star : Icons.star_border,
                              color: _isDefault
                                  ? Colors.orange
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تنظیم به عنوان پیش‌فرض',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'این فرمول به صورت پیش‌فرض برای تولید استفاده می‌شود',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isDefault,
                              onChanged: _isLoading
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _isDefault = v;
                                        _onFieldChanged();
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),
                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              if (await _handleClose()) {
                                Navigator.of(context).pop();
                              }
                            },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('انصراف'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _handleSave,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isLoading ? 'در حال ذخیره...' : 'ذخیره'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
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

