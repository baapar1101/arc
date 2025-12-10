import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/category_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../utils/snackbar_helper.dart';


class CategoryPickerField extends FormField<int?> {
  CategoryPickerField({
    super.key,
    required this.businessId,
    required List<Map<String, dynamic>> categoriesTree,
    required ValueChanged<int?> onChanged,
    super.initialValue,
    String? label,
    super.validator,
    this.authStore,
    this.onCategoriesUpdated,
  }) : super(
          builder: (state) {
            final context = state.context;
            final t = AppLocalizations.of(context);
            final selectedLabel = _selectedCategoryBreadcrumb(
              categoriesTree,
              state.value,
            );
            return InkWell(
              onTap: () async {
                final picked = await showDialog<int?>(
                  context: context,
                  builder: (ctx) => _CategoryPickerDialog(
                    businessId: businessId,
                    categoriesTree: categoriesTree,
                    initialCategoryId: state.value,
                    authStore: authStore,
                    onCategoriesUpdated: onCategoriesUpdated,
                  ),
                );
                if (picked != null) {
                  state.didChange(picked);
                  onChanged(picked);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label ?? t.categories,
                  errorText: state.errorText,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.expand_more),
                ),
                child: _BreadcrumbChips(label: selectedLabel ?? 'انتخاب'),
              ),
            );
          },
        );
  final int businessId;
  final AuthStore? authStore;
  final ValueChanged<List<Map<String, dynamic>>>? onCategoriesUpdated;
}

class _BreadcrumbChips extends StatelessWidget {
  final String label;

  const _BreadcrumbChips({required this.label});

  @override
  Widget build(BuildContext context) {
    final parts = label.split(' / ').where((e) => e.trim().isNotEmpty).toList();
    if (parts.isEmpty) {
      return Text('انتخاب');
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: parts
          .map((p) => Chip(
                label: Text(p),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ))
          .toList(),
    );
  }
}

String? _selectedCategoryBreadcrumb(List<Map<String, dynamic>> tree, int? id) {
  if (id == null) return null;
  final path = _findPathById(tree, id);
  if (path.isEmpty) return null;
  return path.map((e) => (e['label'] ?? e['title'] ?? '').toString()).join(' / ');
}

List<Map<String, dynamic>> _findPathById(List<Map<String, dynamic>> nodes, int id) {
  for (final n in nodes) {
    final current = Map<String, dynamic>.from(n);
    if ((current['id'] as num?)?.toInt() == id) {
      return [current];
    }
    final children = (current['children'] as List?)?.cast<dynamic>()
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? const <Map<String, dynamic>>[];
    final sub = _findPathById(children, id);
    if (sub.isNotEmpty) {
      return [current, ...sub];
    }
  }
  return const <Map<String, dynamic>>[];
}

class _CategoryPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categoriesTree;
  final int? initialCategoryId;
  final int businessId;
  final AuthStore? authStore;
  final ValueChanged<List<Map<String, dynamic>>>? onCategoriesUpdated;

  const _CategoryPickerDialog({
    required this.categoriesTree,
    required this.initialCategoryId,
    required this.businessId,
    this.authStore,
    this.onCategoriesUpdated,
  });

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  String _query = '';
  int? _selectedId;
  bool _loading = false;
  List<Map<String, dynamic>> _serverResults = const <Map<String, dynamic>>[];
  late final CategoryService _service;
  Timer? _debounce;
  List<Map<String, dynamic>> _currentTree = const <Map<String, dynamic>>[];

  bool get _canAdd => widget.authStore?.hasBusinessPermission('categories', 'add') ?? false;
  bool get _canEdit => widget.authStore?.hasBusinessPermission('categories', 'edit') ?? false;
  bool get _canDelete => widget.authStore?.hasBusinessPermission('categories', 'delete') ?? false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialCategoryId;
    _service = CategoryService(ApiClient());
    _currentTree = widget.categoriesTree;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final useServer = _query.trim().length >= 3 || _countNodes(_currentTree) > 500;
    final filteredTree = useServer
        ? _resultsToTree(_serverResults)
        : (_query.isEmpty ? _currentTree : _filterTree(_currentTree, _query));
    return AlertDialog(
      title: Row(
        children: [
          Text(t.categories),
          const Spacer(),
          if (_canAdd)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: t.addCategory,
              onPressed: () => _showAddCategoryDialog(context, null),
            ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.search,
              ),
              onChanged: (v) {
                final q = v.trim();
                setState(() => _query = q);
                _scheduleServerSearch(q);
              },
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _CategoryList(
                tree: filteredTree,
                selectedId: _selectedId,
                onSelect: (id) => setState(() => _selectedId = id),
                canAdd: _canAdd,
                canEdit: _canEdit,
                canDelete: _canDelete,
                onAdd: (parentId) => _showAddCategoryDialog(context, parentId),
                onEdit: (categoryId) => _showEditCategoryDialog(context, categoryId),
                onDelete: (categoryId) => _showDeleteCategoryDialog(context, categoryId),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selectedId),
          child: const Text('انتخاب'),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _filterTree(List<Map<String, dynamic>> nodes, String q) {
    if (q.isEmpty) return nodes;
    final query = q.toLowerCase();
    List<Map<String, dynamic>> result = [];
    for (final n in nodes) {
      final current = Map<String, dynamic>.from(n);
      final label = (current['label'] ?? current['title'] ?? '').toString();
      final children = (current['children'] as List?)?.cast<dynamic>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ?? const <Map<String, dynamic>>[];
      final filteredChildren = _filterTree(children, q);
      final matches = label.toLowerCase().contains(query);
      if (matches || filteredChildren.isNotEmpty) {
        current['children'] = filteredChildren;
        result.add(current);
      }
    }
    return result;
  }

  void _scheduleServerSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _serverResults = const <Map<String, dynamic>>[]);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _performServerSearch(q));
  }

  Future<void> _performServerSearch(String q) async {
    setState(() => _loading = true);
    try {
      final items = await _service.search(businessId: widget.businessId, query: q.trim(), limit: 100);
      if (!mounted) return;
      setState(() => _serverResults = items);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _countNodes(List<Map<String, dynamic>> nodes) {
    int c = 0;
    for (final n in nodes) {
      c += 1;
      final children = (n['children'] as List?)?.cast<dynamic>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ?? const <Map<String, dynamic>>[];
      c += _countNodes(children);
    }
    return c;
  }

  List<Map<String, dynamic>> _resultsToTree(List<Map<String, dynamic>> items) {
    // Items already contain 'path' breadcrumb; we flatten to a pseudo-tree with only matching leaves under their ancestors
    final Map<int, Map<String, dynamic>> byId = {};
    final List<Map<String, dynamic>> roots = [];
    for (final it in items) {
      final path = (it['path'] as List?)?.cast<dynamic>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ?? const <Map<String, dynamic>>[];
      Map<String, dynamic>? parent;
      for (final node in path) {
        final nid = (node['id'] as num?)?.toInt();
        if (nid == null) continue;
        var existing = byId[nid];
        if (existing == null) {
          existing = {
            'id': nid,
            'label': (node['title'] ?? '').toString(),
            'children': <Map<String, dynamic>>[],
          };
          byId[nid] = existing;
          if (parent == null) {
            roots.add(existing);
          } else {
            (parent['children'] as List).add(existing);
          }
        }
        parent = existing;
      }
    }
    return roots;
  }

  Future<void> _refreshCategories() async {
    try {
      final items = await _service.getTree(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _currentTree = items;
        });
        widget.onCategoriesUpdated?.call(items);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا در به‌روزرسانی لیست: $e');
      }
    }
  }

  Future<void> _showAddCategoryDialog(BuildContext context, int? parentId) async {
    final t = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final labelCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.addCategory),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: labelCtrl,
                  decoration: InputDecoration(
                    labelText: t.categoryName,
                    hintText: t.categoryNameHint,
                    prefixIcon: const Icon(Icons.category_outlined),
                  ),
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return t.categoryNameRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات',
                    hintText: 'توضیحات اختیاری',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, {
                  'label': labelCtrl.text.trim(),
                  'description': descriptionCtrl.text.trim().isEmpty ? null : descriptionCtrl.text.trim(),
                });
              }
            },
            child: Text(t.addCategory),
          ),
        ],
      ),
    );

    if (result == null) return;

    final label = result['label'] as String?;
    if (label == null || label.isEmpty) return;
    final description = result['description'] as String?;

    try {
      await _service.create(
        businessId: widget.businessId,
        parentId: parentId,
        type: 'global',
        label: label,
        description: description,
      );
      await _refreshCategories();
      if (mounted) {
        SnackBarHelper.show(context, message: '${t.addCategory} با موفقیت انجام شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
    }
  }

  Future<void> _showEditCategoryDialog(BuildContext context, int categoryId) async {
    final t = AppLocalizations.of(context);
    final category = _findCategoryById(_currentTree, categoryId);
    if (category == null) return;

    final formKey = GlobalKey<FormState>();
    final labelCtrl = TextEditingController(text: (category['label'] ?? category['title'] ?? '').toString());
    final descriptionCtrl = TextEditingController(text: (category['description'] as String?) ?? '');
    
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.updateCategory),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: labelCtrl,
                  decoration: InputDecoration(
                    labelText: t.categoryName,
                    hintText: t.categoryNameHint,
                    prefixIcon: const Icon(Icons.category_outlined),
                  ),
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return t.categoryNameRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات',
                    hintText: 'توضیحات اختیاری',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, {
                  'label': labelCtrl.text.trim(),
                  'description': descriptionCtrl.text.trim().isEmpty ? null : descriptionCtrl.text.trim(),
                });
              }
            },
            child: Text(t.updateCategory),
          ),
        ],
      ),
    );

    if (result == null) return;

    final label = result['label'] as String?;
    if (label == null || label.isEmpty) return;
    final description = result['description'] as String?;

    try {
      await _service.update(
        businessId: widget.businessId,
        categoryId: categoryId,
        type: 'global',
        label: label,
        description: description,
      );
      await _refreshCategories();
      if (mounted) {
        SnackBarHelper.show(context, message: '${t.updateCategory} با موفقیت انجام شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
    }
  }

  Future<void> _showDeleteCategoryDialog(BuildContext context, int categoryId) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteCategory),
        content: Text(t.deleteCategoryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.delete),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _service.delete(businessId: widget.businessId, categoryId: categoryId);
      await _refreshCategories();
      if (_selectedId == categoryId) {
        setState(() => _selectedId = null);
      }
      if (mounted) {
        SnackBarHelper.show(context, message: t.deleteCategorySuccess);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: $e');
      }
    }
  }

  Map<String, dynamic>? _findCategoryById(List<Map<String, dynamic>> nodes, int id) {
    for (final n in nodes) {
      final current = Map<String, dynamic>.from(n);
      if ((current['id'] as num?)?.toInt() == id) {
        return current;
      }
      final children = (current['children'] as List?)?.cast<dynamic>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ?? const <Map<String, dynamic>>[];
      final found = _findCategoryById(children, id);
      if (found != null) return found;
    }
    return null;
  }
}

class _CategoryList extends StatelessWidget {
  final List<Map<String, dynamic>> tree;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final ValueChanged<int?>? onAdd;
  final ValueChanged<int>? onEdit;
  final ValueChanged<int>? onDelete;

  const _CategoryList({
    required this.tree,
    required this.selectedId,
    required this.onSelect,
    this.canAdd = false,
    this.canEdit = false,
    this.canDelete = false,
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: tree.map((n) => _buildNode(context, n, 0)).toList(),
    );
  }

  Widget _buildNode(BuildContext context, Map<String, dynamic> node, int depth) {
    final id = (node['id'] as num?)?.toInt();
    final label = (node['label'] ?? node['title'] ?? '').toString();
    final children = (node['children'] as List?)?.cast<dynamic>()
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? const <Map<String, dynamic>>[];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth, end: 8),
          dense: true,
          leading: Radio<int?> (
            value: id,
            groupValue: selectedId,
            onChanged: (_) => onSelect(id),
          ),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onSelect(id),
          trailing: (canAdd || canEdit || canDelete) && id != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canAdd)
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        tooltip: 'افزودن زیردسته',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => onAdd?.call(id),
                      ),
                    if (canEdit)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: 'ویرایش',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => onEdit?.call(id),
                      ),
                    if (canDelete)
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                        tooltip: 'حذف',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => onDelete?.call(id),
                      ),
                  ],
                )
              : null,
        ),
        if (children.isNotEmpty)
          ...children.map((c) => _buildNode(context, c, depth + 1)),
      ],
    );
  }
}


