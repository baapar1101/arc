import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/category_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import 'category_picker_field.dart';

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
  final Set<int> _expandedNodes = <int>{};

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
                    label: Text(t.addCategory),
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
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: _buildTreeNodes(_tree, t, 0),
      ),
    );
  }

  List<Widget> _buildTreeNodes(List<Map<String, dynamic>> items, AppLocalizations t, int level) {
    final List<Widget> widgets = [];
    
    for (final item in items) {
      final id = item['id'] as int?;
      final label = (item['label'] ?? item['title'] ?? item['name'] ?? '').toString();
      final description = (item['description'] as String?);
      final children = (item['children'] as List?)?.cast<dynamic>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const <Map<String, dynamic>>[];
      final isExpanded = id != null && _expandedNodes.contains(id);
      final hasChildren = children.isNotEmpty;

      widgets.add(
        _CategoryTreeNodeWidget(
          id: id,
          label: label,
          description: description,
          level: level,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          canAdd: _canAdd,
          canEdit: _canEdit,
          canDelete: _canDelete,
          onToggleExpand: hasChildren ? () {
            setState(() {
              if (isExpanded) {
                _expandedNodes.remove(id);
              } else {
                _expandedNodes.add(id!);
              }
            });
          } : null,
          onAddChild: _canAdd ? () => _showEditDialog(parentId: id) : null,
          onEdit: _canEdit ? () {
            final sortOrder = (item['sort_order'] as num?)?.toInt();
            final currentParentId = (item['parent_id'] as num?)?.toInt();
            _showEditDialog(
              categoryId: id,
              initialLabel: label,
              initialDescription: description,
              initialSortOrder: sortOrder,
              initialParentId: currentParentId,
            );
          } : null,
          onDelete: _canDelete ? () => _confirmDelete(id) : null,
          t: t,
        ),
      );
      
      if (isExpanded && hasChildren) {
        widgets.addAll(_buildTreeNodes(children, t, level + 1));
      }
    }
    
    return widgets;
  }

  /// فیلتر کردن درخت برای حذف یک دسته‌بندی و تمام فرزندانش
  List<Map<String, dynamic>> _filterTreeExcludingCategory(
    List<Map<String, dynamic>> tree,
    int excludeId,
  ) {
    List<Map<String, dynamic>> result = [];
    for (final node in tree) {
      final id = (node['id'] as num?)?.toInt();
      if (id == excludeId) {
        // این نود و تمام فرزندانش را حذف می‌کنیم
        continue;
      }
      final children = (node['children'] as List?)?.cast<dynamic>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const <Map<String, dynamic>>[];
      final filteredChildren = _filterTreeExcludingCategory(children, excludeId);
      final newNode = Map<String, dynamic>.from(node);
      newNode['children'] = filteredChildren;
      result.add(newNode);
    }
    return result;
  }

  /// باز کردن مسیر تا یک نود خاص
  void _expandToNode(int targetId) {
    bool findAndExpand(List<Map<String, dynamic>> nodes, int targetId, List<int> path) {
      for (final node in nodes) {
        final id = node['id'] as int?;
        if (id == null) continue;
        
        final currentPath = [...path, id];
        
        if (id == targetId) {
          // پیدا شد - باز کردن تمام مسیر
          setState(() {
            for (final pathId in currentPath) {
              _expandedNodes.add(pathId);
            }
          });
          return true;
        }
        
        final children = (node['children'] as List?)?.cast<dynamic>()
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? const <Map<String, dynamic>>[];
        
        if (children.isNotEmpty) {
          if (findAndExpand(children, targetId, currentPath)) {
            // باز کردن نود فعلی چون در مسیر است
            setState(() {
              _expandedNodes.add(id);
            });
            return true;
          }
        }
      }
      return false;
    }
    
    findAndExpand(_tree, targetId, []);
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
    String? initialDescription,
    int? initialSortOrder,
    int? initialParentId,
  }) async {
    final t = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final labelCtrl = TextEditingController(text: initialLabel ?? '');
    final descriptionCtrl = TextEditingController(text: initialDescription ?? '');
    final sortOrderCtrl = TextEditingController(text: (initialSortOrder ?? 0).toString());
    int? selectedParentId = categoryId != null ? (initialParentId) : (isRoot ? null : parentId);
    
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                  Row(
                    children: [
                      Icon(
                        categoryId == null ? Icons.add_circle_outline : Icons.edit_outlined,
                        color: Theme.of(ctx).primaryColor,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          categoryId == null ? t.createCategory : t.updateCategory,
                          style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        icon: const Icon(Icons.close),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Category Name Field
                  TextFormField(
                    controller: labelCtrl,
                    decoration: InputDecoration(
                      labelText: t.categoryName,
                      hintText: t.categoryNameHint,
                      prefixIcon: const Icon(Icons.category_outlined),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surface,
                    ),
                    textInputAction: TextInputAction.next,
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return t.categoryNameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Description Field
                  TextFormField(
                    controller: descriptionCtrl,
                    decoration: InputDecoration(
                      labelText: 'توضیحات',
                      hintText: 'توضیحات اختیاری دسته‌بندی',
                      prefixIcon: const Icon(Icons.description_outlined),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surface,
                    ),
                    maxLines: 3,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  
                  // Sort Order Field (only for edit mode)
                  if (categoryId != null)
                    TextFormField(
                      controller: sortOrderCtrl,
                      decoration: InputDecoration(
                        labelText: 'ترتیب نمایش',
                        hintText: 'عدد ترتیب نمایش (کمتر = بالاتر)',
                        prefixIcon: const Icon(Icons.sort),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Theme.of(ctx).colorScheme.surface,
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'ترتیب نمایش الزامی است';
                        }
                        final intValue = int.tryParse(value.trim());
                        if (intValue == null) {
                          return 'لطفاً یک عدد معتبر وارد کنید';
                        }
                        return null;
                      },
                    ),
                  if (categoryId != null) const SizedBox(height: 16),
                  
                  // Parent Selection Field (only for edit mode)
                  if (categoryId != null)
                    CategoryPickerField(
                      businessId: widget.businessId,
                      categoriesTree: _filterTreeExcludingCategory(_tree, categoryId),
                      initialValue: selectedParentId,
                      onChanged: (value) {
                        selectedParentId = value;
                      },
                      label: 'والد (دسته‌بندی مادر)',
                    ),
                  if (categoryId != null) const SizedBox(height: 24),
                  
                  const SizedBox(height: 24),
                  
                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: Text(t.cancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            final sortOrder = categoryId != null ? int.tryParse(sortOrderCtrl.text.trim()) : null;
                            Navigator.pop(ctx, {
                              'label': labelCtrl.text.trim(),
                              'description': descriptionCtrl.text.trim().isEmpty ? null : descriptionCtrl.text.trim(),
                              'sort_order': sortOrder,
                              'parent_id': categoryId != null ? selectedParentId : null,
                            });
                          }
                        },
                        icon: Icon(categoryId == null ? Icons.add : Icons.save),
                        label: Text(categoryId == null ? t.createCategory : t.updateCategory),
                      ),
                    ],
                  ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    
    if (result == null) return;
    
    final label = result['label'] as String?;
    if (label == null || label.isEmpty) return;
    final description = result['description'] as String?;
    final sortOrder = result['sort_order'] as int?;
    final newParentId = result['parent_id'] as int?;
    
    int? newCategoryId;
    try {
      if (categoryId == null) {
        final createResult = await _service.create(
          businessId: widget.businessId,
          parentId: isRoot ? null : parentId,
          type: 'global',
          label: label,
          description: description,
        );
        newCategoryId = createResult['id'] as int?;
      } else {
        await _service.update(
          businessId: widget.businessId,
          categoryId: categoryId,
          type: 'global',
          label: label,
          description: description,
          sortOrder: sortOrder,
          parentId: newParentId,
        );
      }
      await _fetch();
      
      // اگر آیتم جدید اضافه شده، مسیر تا آن را باز کن
      if (newCategoryId != null) {
        // کمی تأخیر برای اطمینان از اینکه درخت به‌روزرسانی شده
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _expandToNode(newCategoryId!);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.operationFailed),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

/// ویجت نمایش یک نود دسته‌بندی در درخت
class _CategoryTreeNodeWidget extends StatelessWidget {
  final int? id;
  final String label;
  final String? description;
  final int level;
  final bool isExpanded;
  final bool hasChildren;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onAddChild;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final AppLocalizations t;

  const _CategoryTreeNodeWidget({
    required this.id,
    required this.label,
    this.description,
    required this.level,
    required this.isExpanded,
    required this.hasChildren,
    required this.canAdd,
    required this.canEdit,
    required this.canDelete,
    this.onToggleExpand,
    this.onAddChild,
    this.onEdit,
    this.onDelete,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = level * 24.0;
    final lineColor = theme.colorScheme.outline.withValues(alpha: 0.3);
    
    return Stack(
      children: [
        // خطوط اتصال درخت
        if (level > 0)
          Positioned(
            right: indent - 12,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1,
              color: lineColor,
            ),
          ),
        InkWell(
          onTap: onToggleExpand,
          child: Container(
            padding: EdgeInsets.only(
              right: indent + 12,
              left: 12,
              top: 8,
              bottom: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                right: level > 0
                    ? BorderSide(
                        color: lineColor,
                        width: 1,
                      )
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                // آیکون باز/بسته کردن
                SizedBox(
                  width: 24,
                  child: hasChildren
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 20,
                          onPressed: onToggleExpand,
                          icon: Icon(
                            isExpanded ? Icons.expand_more : Icons.chevron_left,
                            color: theme.colorScheme.onSurface,
                          ),
                        )
                      : const SizedBox(width: 24),
                ),
                
                const SizedBox(width: 8),
                
                // آیکون دسته‌بندی
                Icon(
                  hasChildren ? Icons.folder : Icons.category,
                  size: 20,
                  color: hasChildren
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                
                const SizedBox(width: 12),
                
                // نام دسته‌بندی و توضیحات
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: hasChildren ? FontWeight.w600 : FontWeight.normal,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (description != null && description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // دکمه‌های عملیات
                if (canAdd)
                  IconButton(
                    tooltip: t.addChildCategory,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: onAddChild,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (canEdit)
                  IconButton(
                    tooltip: t.renameCategory,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (canDelete)
                  IconButton(
                    tooltip: t.deleteCategory,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: theme.colorScheme.error,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

