import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import '../../services/category_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';

class CategoryTreeDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CategoryTreeDialog({super.key, required this.businessId, required this.authStore});

  @override
  State<CategoryTreeDialog> createState() => _CategoryTreeDialogState();
}

class _CategoryTreeDialogState extends State<CategoryTreeDialog> {
  late final CategoryService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tree = const <Map<String, dynamic>>[];
  // TreeController دیگر استفاده نمی‌شود

  @override
  void initState() {
    super.initState();
    _service = CategoryService(ApiClient());
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.getTree(businessId: widget.businessId);
      setState(() {
        _tree = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  

  bool get _canAdd => widget.authStore.hasBusinessPermission('categories', 'add');
  bool get _canEdit => widget.authStore.hasBusinessPermission('categories', 'edit');
  bool get _canDelete => widget.authStore.hasBusinessPermission('categories', 'delete');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.category,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  t.categoriesDialogTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                if (_canAdd)
                  FilledButton.icon(
                    onPressed: () => _showEditDialog(isRoot: true),
                    icon: const Icon(Icons.add),
                    label: Text(t.addRootCategory),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 16),

            // Content
            Expanded(child: _buildBody(t)),
          ],
        ),
      ),
    );
  }


  // تب‌ها حذف شده‌اند

  Widget _buildBody(AppLocalizations t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          child: TreeView(
            nodes: _buildTreeNodes(_tree, t),
            indent: 24.0,
          ),
        ),
      ),
    );
  }

  List<TreeNode> _buildTreeNodes(List<Map<String, dynamic>> items, AppLocalizations t) {
    return items.map((m) {
      final id = m['id'] as int?;
      final label = (m['label'] ?? m['title'] ?? m['name'] ?? '').toString();
      final children = (m['children'] as List?)?.cast<dynamic>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ?? const <Map<String, dynamic>>[];

      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canAdd)
            IconButton(
              tooltip: t.addChildCategory,
              icon: const Icon(Icons.subdirectory_arrow_right),
              onPressed: () => _showEditDialog(parentId: id),
            ),
          if (_canEdit)
            IconButton(
              tooltip: t.renameCategory,
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditDialog(categoryId: id, initialLabel: label),
            ),
          if (_canDelete)
            IconButton(
              tooltip: t.deleteCategory,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(id),
            ),
        ],
      );

      return TreeNode(
        content: Row(
          children: [
            Expanded(child: Text(label)),
            actions,
          ],
        ),
        children: _buildTreeNodes(children, t),
      );
    }).toList();
  }

  // _buildNodeTile حذف شد؛ از TreeView استفاده می‌کنیم

  Future<void> _confirmDelete(int? id) async {
    if (id == null) return;
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteCategory),
        content: Text(t.deleteCategoryConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok != true) return;
    await _service.delete(businessId: widget.businessId, categoryId: id);
    await _fetch();
  }

  Future<void> _showEditDialog({
    bool isRoot = false,
    int? parentId,
    int? categoryId,
    String? initialLabel,
  }) async {
    final t = AppLocalizations.of(context);
    final labelCtrl = TextEditingController(text: initialLabel ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(categoryId == null ? t.createCategory : t.updateCategory),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Label')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(categoryId == null ? t.createCategory : t.updateCategory),
          )
        ],
      ),
    );
    if (ok != true) return;
    if (categoryId == null) {
      await _service.create(
        businessId: widget.businessId,
        parentId: isRoot ? null : parentId,
        type: 'global',
        label: labelCtrl.text.trim(),
      );
    } else {
      await _service.update(
        businessId: widget.businessId,
        categoryId: categoryId,
        type: 'global',
        label: labelCtrl.text.trim(),
      );
    }
    await _fetch();
  }
}


